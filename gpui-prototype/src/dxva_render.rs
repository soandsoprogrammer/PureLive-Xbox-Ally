use crate::{
    Result, dxva,
    native_danmaku::{Drawn, Lane, Overlay},
};
use std::{mem::ManuallyDrop, time::Instant};
use windows::{
    Win32::{
        Foundation::{HWND, RECT},
        Graphics::{
            Direct2D::Common::D2D_RECT_F,
            Direct3D11::*,
            Dxgi::{Common::*, *},
        },
        UI::WindowsAndMessaging::GetClientRect,
    },
    core::Interface,
};

pub struct Renderer {
    swap_chain: IDXGISwapChain1,
    video_device: ID3D11VideoDevice,
    context: ID3D11VideoContext1,
    processor: Option<Processor>,
    window: HWND,
    output_size: (u32, u32),
}

struct Processor {
    size: (u32, u32),
    enumerator: ID3D11VideoProcessorEnumerator,
    converter: ID3D11VideoProcessor,
    output: ID3D11VideoProcessorOutputView,
    viewport: D2D_RECT_F,
    overlay: Option<Overlay>,
}

impl Renderer {
    pub fn new(window: HWND, gpu: &dxva::Device) -> Result<Self> {
        unsafe {
            let adapter = gpu.device.cast::<IDXGIDevice>()?.GetAdapter()?;
            let factory: IDXGIFactory2 = adapter.GetParent()?;
            let description = DXGI_SWAP_CHAIN_DESC1 {
                Format: DXGI_FORMAT_B8G8R8A8_UNORM,
                SampleDesc: DXGI_SAMPLE_DESC {
                    Count: 1,
                    Quality: 0,
                },
                BufferUsage: DXGI_USAGE_RENDER_TARGET_OUTPUT,
                BufferCount: 2,
                SwapEffect: DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
                Scaling: DXGI_SCALING_STRETCH,
                AlphaMode: DXGI_ALPHA_MODE_IGNORE,
                ..Default::default()
            };
            let swap_chain =
                factory.CreateSwapChainForHwnd(&gpu.device, window, &description, None, None)?;
            factory.MakeWindowAssociation(window, DXGI_MWA_NO_ALT_ENTER)?;
            let back_buffer: ID3D11Texture2D = swap_chain.GetBuffer(0)?;
            let mut desc = D3D11_TEXTURE2D_DESC::default();
            back_buffer.GetDesc(&mut desc);
            Ok(Self {
                swap_chain,
                video_device: gpu.device.cast()?,
                context: gpu.context.cast()?,
                processor: None,
                window,
                output_size: (desc.Width, desc.Height),
            })
        }
    }

    pub fn frame(&mut self, frame: &dxva::Frame, lanes: &[Lane]) -> Result<Drawn> {
        let mut client = RECT::default();
        unsafe {
            GetClientRect(self.window, &mut client)?;
        }
        let output_size = (client.right.max(1) as u32, client.bottom.max(1) as u32);
        if output_size != self.output_size {
            self.processor = None;
            unsafe {
                self.swap_chain.ResizeBuffers(
                    0,
                    output_size.0,
                    output_size.1,
                    DXGI_FORMAT_UNKNOWN,
                    DXGI_SWAP_CHAIN_FLAG(0),
                )?;
            }
            self.output_size = output_size;
        }
        let size = (frame.width, frame.height);
        if self
            .processor
            .as_ref()
            .is_none_or(|processor| processor.size != size)
        {
            self.processor = Some(self.processor(size)?);
        }
        let processor = self
            .processor
            .as_mut()
            .ok_or("missing D3D11 video processor")?;
        let description = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC {
            ViewDimension: D3D11_VPIV_DIMENSION_TEXTURE2D,
            Anonymous: D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC_0 {
                Texture2D: D3D11_TEX2D_VPIV {
                    MipSlice: 0,
                    ArraySlice: frame.subresource,
                },
            },
            ..Default::default()
        };
        let mut drawn = Drawn::default();
        unsafe {
            let mut input = None;
            self.video_device.CreateVideoProcessorInputView(
                &frame.texture,
                &processor.enumerator,
                &description,
                Some(&mut input),
            )?;
            let mut stream = D3D11_VIDEO_PROCESSOR_STREAM {
                Enable: true.into(),
                pInputSurface: ManuallyDrop::new(input),
                ..Default::default()
            };
            let result = self.context.VideoProcessorBlt(
                &processor.converter,
                &processor.output,
                0,
                std::slice::from_ref(&stream),
            );
            ManuallyDrop::drop(&mut stream.pInputSurface);
            result?;
            if !lanes.is_empty() {
                let viewport = processor.viewport;
                if processor.overlay.is_none() {
                    let buffer: IDXGISurface = self.swap_chain.GetBuffer(0)?;
                    processor.overlay = Some(Overlay::new(
                        &buffer,
                        ((viewport.right - viewport.left) / 1280.0).max(0.1),
                    )?);
                }
                if let Some(overlay) = &mut processor.overlay {
                    drawn = overlay.draw(lanes, viewport, Instant::now())?;
                }
            }
            self.swap_chain.Present(0, DXGI_PRESENT(0)).ok()?;
        }
        Ok(drawn)
    }

    fn processor(&self, size: (u32, u32)) -> Result<Processor> {
        let (width, height) = size;
        unsafe {
            let back_buffer: ID3D11Texture2D = self.swap_chain.GetBuffer(0)?;
            let mut desc = D3D11_TEXTURE2D_DESC::default();
            back_buffer.GetDesc(&mut desc);
            let description = D3D11_VIDEO_PROCESSOR_CONTENT_DESC {
                InputFrameFormat: D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE,
                InputFrameRate: DXGI_RATIONAL {
                    Numerator: 60,
                    Denominator: 1,
                },
                InputWidth: width,
                InputHeight: height,
                OutputFrameRate: DXGI_RATIONAL {
                    Numerator: 60,
                    Denominator: 1,
                },
                OutputWidth: desc.Width,
                OutputHeight: desc.Height,
                Usage: D3D11_VIDEO_USAGE_PLAYBACK_NORMAL,
            };
            let enumerator = self
                .video_device
                .CreateVideoProcessorEnumerator(&description)?;
            let converter = self.video_device.CreateVideoProcessor(&enumerator, 0)?;
            let mut output = None;
            let view = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC {
                ViewDimension: D3D11_VPOV_DIMENSION_TEXTURE2D,
                ..Default::default()
            };
            self.video_device.CreateVideoProcessorOutputView(
                &back_buffer,
                &enumerator,
                &view,
                Some(&mut output),
            )?;
            self.context
                .VideoProcessorSetStreamAutoProcessingMode(&converter, 0, false);
            let source = RECT {
                left: 0,
                top: 0,
                right: width as i32,
                bottom: height as i32,
            };
            let scale = (f64::from(desc.Width) / f64::from(width))
                .min(f64::from(desc.Height) / f64::from(height));
            let out_width = (f64::from(width) * scale).round() as i32;
            let out_height = (f64::from(height) * scale).round() as i32;
            let left = (desc.Width as i32 - out_width) / 2;
            let top = (desc.Height as i32 - out_height) / 2;
            let destination = RECT {
                left,
                top,
                right: left + out_width,
                bottom: top + out_height,
            };
            self.context
                .VideoProcessorSetStreamSourceRect(&converter, 0, true, Some(&source));
            self.context
                .VideoProcessorSetStreamDestRect(&converter, 0, true, Some(&destination));
            let color = if height >= 720 {
                DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709
            } else {
                DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P601
            };
            self.context
                .VideoProcessorSetStreamColorSpace1(&converter, 0, color);
            self.context.VideoProcessorSetOutputColorSpace1(
                &converter,
                DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709,
            );
            Ok(Processor {
                size,
                enumerator,
                converter,
                output: output.ok_or("D3D11 returned no processor output view")?,
                viewport: D2D_RECT_F {
                    left: left as f32,
                    top: top as f32,
                    right: (left + out_width) as f32,
                    bottom: (top + out_height) as f32,
                },
                overlay: None,
            })
        }
    }
}
