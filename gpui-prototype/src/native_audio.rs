use crate::Result;
use std::{mem::size_of_val, ptr};
use symphonia_core::audio::{AudioBufferRef, SampleBuffer};
use windows::Win32::{
    Media::Audio::*,
    System::Com::{CLSCTX_INPROC_SERVER, CoCreateInstance},
};

#[derive(Default)]
pub struct Audio {
    endpoint: Option<Endpoint>,
    samples: Option<SampleBuffer<f32>>,
}

struct Endpoint {
    client: IAudioClient,
    render: IAudioRenderClient,
    format: (u32, u32),
    capacity: u32,
    running: bool,
}

impl Endpoint {
    fn open(rate: u32, channels: u32) -> Result<Self> {
        unsafe {
            let devices: IMMDeviceEnumerator =
                CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_INPROC_SERVER)?;
            let device = devices.GetDefaultAudioEndpoint(eRender, eMultimedia)?;
            let client: IAudioClient = device.Activate(CLSCTX_INPROC_SERVER, None)?;
            let align = u16::try_from(channels * 4)?;
            let wave = WAVEFORMATEX {
                wFormatTag: 3,
                nChannels: u16::try_from(channels)?,
                nSamplesPerSec: rate,
                nAvgBytesPerSec: rate * u32::from(align),
                nBlockAlign: align,
                wBitsPerSample: 32,
                cbSize: 0,
            };
            client.Initialize(
                AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                2_000_000,
                0,
                &wave,
                None,
            )?;
            Ok(Self {
                capacity: client.GetBufferSize()?,
                render: client.GetService()?,
                client,
                format: (rate, channels),
                running: false,
            })
        }
    }

    fn set_running(&mut self, running: bool) -> Result<()> {
        if self.running != running {
            unsafe {
                if running {
                    self.client.Start()?;
                } else {
                    self.client.Stop()?;
                }
            }
            self.running = running;
        }
        Ok(())
    }
}

impl Drop for Endpoint {
    fn drop(&mut self) {
        let _ = self.set_running(false);
    }
}

impl Audio {
    pub fn frame(
        &mut self,
        decoded: AudioBufferRef<'_>,
        video_ready: bool,
        gain: f32,
    ) -> Result<()> {
        let spec = *decoded.spec();
        let channels = spec.channels.count();
        let format = (spec.rate, channels as u32);
        if self
            .endpoint
            .as_ref()
            .is_none_or(|endpoint| endpoint.format != format)
        {
            self.endpoint = Some(Endpoint::open(format.0, format.1)?);
            self.samples = None;
        }
        let endpoint = self.endpoint.as_mut().ok_or("missing audio endpoint")?;
        let capacity = decoded.capacity() * channels;
        let samples = self
            .samples
            .get_or_insert_with(|| SampleBuffer::new(decoded.capacity() as u64, spec));
        if samples.capacity() < capacity {
            *samples = SampleBuffer::new(decoded.capacity() as u64, spec);
        }
        samples.copy_interleaved_ref(decoded);
        let pcm = samples.samples_mut();
        if gain != 1.0 {
            pcm.iter_mut().for_each(|sample| *sample *= gain);
        }
        unsafe {
            let available = endpoint
                .capacity
                .saturating_sub(endpoint.client.GetCurrentPadding()?);
            let frames = ((pcm.len() / channels) as u32).min(available);
            if frames > 0 {
                let target = endpoint.render.GetBuffer(frames)?;
                let written = &pcm[..frames as usize * channels];
                ptr::copy_nonoverlapping(
                    written.as_ptr().cast::<u8>(),
                    target,
                    size_of_val(written),
                );
                endpoint.render.ReleaseBuffer(frames, 0)?;
            }
        }
        if video_ready {
            endpoint.set_running(true)?;
        }
        Ok(())
    }

    pub fn set_paused(&mut self, paused: bool) {
        if let Some(endpoint) = &mut self.endpoint {
            let _ = endpoint.set_running(!paused);
        }
    }
}
