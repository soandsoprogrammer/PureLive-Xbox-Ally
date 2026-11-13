use crate::Result;
use oxideav_core::{CodecParameters, Packet};
use oxideav_h264::{avcc::AvcDecoderConfigurationRecord, nal::AvccSplitter};
use std::{ffi::c_void, mem::ManuallyDrop, ptr};
use windows::{
    Win32::{
        Foundation::HMODULE,
        Graphics::{Direct3D::D3D_DRIVER_TYPE_HARDWARE, Direct3D11::*},
        Media::MediaFoundation::*,
        System::{Com::*, Variant::VARIANT},
    },
    core::Interface,
};

pub struct Runtime;

impl Runtime {
    pub fn new() -> Result<Self> {
        unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok()? };
        if let Err(error) = unsafe { MFStartup(MF_VERSION, MFSTARTUP_FULL) } {
            unsafe { CoUninitialize() };
            return Err(error.into());
        }
        Ok(Self)
    }
}

impl Drop for Runtime {
    fn drop(&mut self) {
        unsafe {
            let _ = MFShutdown();
            CoUninitialize();
        }
    }
}

pub struct Device {
    pub device: ID3D11Device,
    pub context: ID3D11DeviceContext,
    manager: IMFDXGIDeviceManager,
}

impl Device {
    pub fn new() -> Result<Self> {
        let (mut device, mut context) = (None, None);
        unsafe {
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )?;
            let device = device.ok_or("D3D11 returned no device")?;
            let context: ID3D11DeviceContext = context.ok_or("D3D11 returned no context")?;
            let _ = context
                .cast::<ID3D11Multithread>()?
                .SetMultithreadProtected(true);
            let mut token = 0;
            let mut manager = None;
            MFCreateDXGIDeviceManager(&mut token, &mut manager)?;
            let manager = manager.ok_or("Media Foundation returned no DXGI device manager")?;
            manager.ResetDevice(&device, token)?;
            Ok(Self {
                device,
                context,
                manager,
            })
        }
    }
}

pub struct Frame {
    pub texture: ID3D11Texture2D,
    pub subresource: u32,
    pub width: u32,
    pub height: u32,
    pub pts: Option<i64>,
    _sample: IMFSample,
}

pub struct Decoder {
    mft: IMFTransform,
    sequence_header: Vec<u8>,
    nal_length: u8,
    access_unit: Vec<u8>,
    size: (u32, u32),
    needs_header: bool,
    annex_b: bool,
}

impl Decoder {
    pub fn new(device: &Device, params: &CodecParameters, annex_b: bool) -> Result<Self> {
        if params.codec_id.as_str() != "h264" {
            return Err("Windows hardware experiment supports H.264 video".into());
        }
        let config = AvcDecoderConfigurationRecord::parse(&params.extradata)?;
        let mut sequence_header = Vec::new();
        for nal in config.sps.iter().chain(&config.pps).chain(&config.sps_ext) {
            append_nal(&mut sequence_header, nal);
        }
        unsafe {
            let mft: IMFTransform =
                CoCreateInstance(&CMSH264DecoderMFT, None, CLSCTX_INPROC_SERVER)?;
            if mft.GetAttributes()?.GetUINT32(&MF_SA_D3D11_AWARE)? == 0 {
                return Err("Windows H.264 decoder does not support D3D11".into());
            }
            if let Ok(api) = mft.cast::<ICodecAPI>() {
                let _ = api.SetValue(&CODECAPI_AVDecVideoAcceleration_H264, &VARIANT::from(true));
            }
            mft.ProcessMessage(
                MFT_MESSAGE_SET_D3D_MANAGER,
                device.manager.as_raw() as usize,
            )?;
            let media = MFCreateMediaType()?;
            media.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video)?;
            media.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_H264)?;
            media.SetUINT32(
                &MF_MT_INTERLACE_MODE,
                MFVideoInterlace_MixedInterlaceOrProgressive.0 as u32,
            )?;
            if let (Some(width), Some(height)) = (params.width, params.height) {
                media.SetUINT64(
                    &MF_MT_FRAME_SIZE,
                    (u64::from(width) << 32) | u64::from(height),
                )?;
            }
            media.SetBlob(&MF_MT_MPEG_SEQUENCE_HEADER, &sequence_header)?;
            mft.SetInputType(0, &media, 0)?;
            let mut decoder = Self {
                mft,
                sequence_header,
                nal_length: config.length_size,
                access_unit: Vec::new(),
                size: (0, 0),
                needs_header: true,
                annex_b,
            };
            decoder.output_type()?;
            decoder
                .mft
                .ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0)?;
            decoder
                .mft
                .ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0)?;
            Ok(decoder)
        }
    }

    fn output_type(&mut self) -> Result<()> {
        unsafe {
            for index in 0.. {
                let media = self.mft.GetOutputAvailableType(0, index)?;
                if media.GetGUID(&MF_MT_SUBTYPE)? != MFVideoFormat_NV12 {
                    continue;
                }
                self.mft.SetOutputType(0, &media, 0)?;
                self.size = media
                    .GetUINT64(&MF_MT_FRAME_SIZE)
                    .map_or((0, 0), |size| ((size >> 32) as u32, size as u32));
                let flags = self.mft.GetOutputStreamInfo(0)?.dwFlags;
                let provides =
                    MFT_OUTPUT_STREAM_PROVIDES_SAMPLES.0 | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES.0;
                if flags & provides as u32 == 0 {
                    return Err("H.264 decoder did not offer GPU-allocated samples".into());
                }
                return Ok(());
            }
        }
        unreachable!()
    }

    pub fn send(&mut self, packet: &Packet) -> Result<()> {
        self.access_unit.clear();
        if self.needs_header || packet.flags.keyframe {
            self.access_unit.extend_from_slice(&self.sequence_header);
        }
        if self.annex_b {
            self.access_unit.extend_from_slice(&packet.data);
        } else {
            for nal in AvccSplitter::new(&packet.data, self.nal_length)? {
                append_nal(&mut self.access_unit, nal?);
            }
        }
        self.needs_header = false;
        let length = u32::try_from(self.access_unit.len())?;
        unsafe {
            let buffer = MFCreateMemoryBuffer(length)?;
            let mut data = ptr::null_mut();
            buffer.Lock(&mut data, None, None)?;
            ptr::copy_nonoverlapping(self.access_unit.as_ptr(), data, self.access_unit.len());
            buffer.Unlock()?;
            buffer.SetCurrentLength(length)?;
            let sample = MFCreateSample()?;
            sample.AddBuffer(&buffer)?;
            if let Some(pts) = packet.pts {
                sample.SetSampleTime(timestamp(pts, packet.time_base)?)?;
            }
            if let Some(dts) = packet.dts {
                let dts = timestamp(dts, packet.time_base)?;
                if let Ok(dts) = u64::try_from(dts) {
                    sample.SetUINT64(&MFSampleExtension_DecodeTimestamp, dts)?;
                }
            }
            if packet.flags.keyframe {
                sample.SetUINT32(&MFSampleExtension_CleanPoint, 1)?;
            }
            self.mft.ProcessInput(0, &sample, 0)?;
        }
        Ok(())
    }

    pub fn receive(&mut self) -> Result<Option<Frame>> {
        loop {
            let mut data = MFT_OUTPUT_DATA_BUFFER::default();
            let mut status = 0;
            unsafe {
                let result =
                    self.mft
                        .ProcessOutput(0, std::slice::from_mut(&mut data), &mut status);
                let sample = ManuallyDrop::take(&mut data.pSample);
                drop(ManuallyDrop::take(&mut data.pEvents));
                match result {
                    Err(error) if error.code() == MF_E_TRANSFORM_NEED_MORE_INPUT => {
                        return Ok(None);
                    }
                    Err(error) if error.code() == MF_E_TRANSFORM_STREAM_CHANGE => {
                        self.output_type()?;
                        continue;
                    }
                    Err(error) => return Err(error.into()),
                    Ok(()) => {}
                }
                let Some(sample) = sample else { continue };
                let buffer = sample
                    .GetBufferByIndex(0)?
                    .cast::<IMFDXGIBuffer>()
                    .map_err(|_| "H.264 decoder returned a CPU buffer instead of a GPU surface")?;
                let mut texture: *mut c_void = ptr::null_mut();
                buffer.GetResource(&ID3D11Texture2D::IID, &mut texture)?;
                let texture = ID3D11Texture2D::from_raw(texture);
                let mut desc = D3D11_TEXTURE2D_DESC::default();
                texture.GetDesc(&mut desc);
                let (width, height) = self.size;
                return Ok(Some(Frame {
                    texture,
                    subresource: buffer.GetSubresourceIndex()?,
                    width: if width == 0 {
                        desc.Width
                    } else {
                        width.min(desc.Width)
                    },
                    height: if height == 0 {
                        desc.Height
                    } else {
                        height.min(desc.Height)
                    },
                    pts: sample.GetSampleTime().ok(),
                    _sample: sample,
                }));
            }
        }
    }

    pub fn finish(&self) -> Result<()> {
        unsafe {
            self.mft
                .ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0)?;
            self.mft.ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0)?;
        }
        Ok(())
    }
}

fn append_nal(output: &mut Vec<u8>, nal: &[u8]) {
    output.extend_from_slice(&[0, 0, 0, 1]);
    output.extend_from_slice(nal);
}

fn timestamp(value: i64, base: oxideav_core::TimeBase) -> Result<i64> {
    Ok(i64::try_from(
        i128::from(value) * i128::from(base.num()) * 10_000_000 / i128::from(base.den()),
    )?)
}
