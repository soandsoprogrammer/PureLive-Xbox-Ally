#[cfg(windows)]
use crate::Result;
use crate::emotes::Bitmap;
#[cfg(windows)]
use std::collections::VecDeque;
#[cfg(windows)]
use std::time::Duration;
use std::{sync::Arc, time::Instant};
#[cfg(windows)]
use windows::{
    Win32::Graphics::{
        Direct2D::{Common::*, *},
        DirectWrite::*,
        Dxgi::{Common::DXGI_FORMAT_B8G8R8A8_UNORM, IDXGISurface},
    },
    core::w,
};

pub struct Lane {
    pub started: Instant,
    #[cfg(windows)]
    pub duration: Duration,
    pub width: f32,
    pub y: f32,
    pub parts: Vec<(f32, Part)>,
}

pub enum Part {
    Text(Vec<u16>),
    Image(Arc<Bitmap>),
}

#[cfg(windows)]
pub struct Overlay {
    target: ID2D1RenderTarget,
    text: IDWriteTextFormat,
    white: ID2D1SolidColorBrush,
    shadow: ID2D1SolidColorBrush,
    pictures: VecDeque<(Arc<Bitmap>, ID2D1Bitmap)>,
}

#[cfg(windows)]
#[derive(Default)]
pub struct Drawn {
    pub text: bool,
    pub emote: bool,
}

#[cfg(windows)]
impl Overlay {
    pub fn new(buffer: &IDXGISurface, scale: f32) -> Result<Self> {
        unsafe {
            let factory: ID2D1Factory = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)?;
            let properties = D2D1_RENDER_TARGET_PROPERTIES {
                pixelFormat: pixel_format(D2D1_ALPHA_MODE_IGNORE),
                dpiX: 96.0,
                dpiY: 96.0,
                ..Default::default()
            };
            let target = factory.CreateDxgiSurfaceRenderTarget(buffer, &properties)?;
            target.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
            let write: IDWriteFactory = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)?;
            let text = write.CreateTextFormat(
                w!("Microsoft YaHei UI"),
                None,
                DWRITE_FONT_WEIGHT_SEMI_BOLD,
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                28.0 * scale,
                w!("zh-CN"),
            )?;
            text.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
            let white = target.CreateSolidColorBrush(
                &D2D1_COLOR_F {
                    r: 1.0,
                    g: 1.0,
                    b: 1.0,
                    a: 1.0,
                },
                None,
            )?;
            let shadow = target.CreateSolidColorBrush(
                &D2D1_COLOR_F {
                    r: 0.0,
                    g: 0.0,
                    b: 0.0,
                    a: 0.9,
                },
                None,
            )?;
            Ok(Self {
                target,
                text,
                white,
                shadow,
                pictures: VecDeque::new(),
            })
        }
    }

    pub fn draw(&mut self, lanes: &[Lane], viewport: D2D_RECT_F, now: Instant) -> Result<Drawn> {
        let scale = ((viewport.right - viewport.left) / 1280.0).max(0.1);
        let mut drawn = Drawn::default();
        unsafe {
            self.target.BeginDraw();
            self.target
                .PushAxisAlignedClip(&viewport, D2D1_ANTIALIAS_MODE_ALIASED);
        }
        let result = self.draw_lanes(lanes, viewport, now, scale, &mut drawn);
        unsafe {
            self.target.PopAxisAlignedClip();
            self.target.EndDraw(None, None)?;
        }
        result?;
        Ok(drawn)
    }

    fn draw_lanes(
        &mut self,
        lanes: &[Lane],
        viewport: D2D_RECT_F,
        now: Instant,
        scale: f32,
        drawn: &mut Drawn,
    ) -> Result<()> {
        for lane in lanes {
            let elapsed = now.saturating_duration_since(lane.started);
            if elapsed >= lane.duration {
                continue;
            }
            let progress = elapsed.as_secs_f32() / lane.duration.as_secs_f32();
            let x = 1280.0 - progress * (1280.0 + lane.width);
            let y = viewport.top + lane.y * scale;
            for (offset, part) in &lane.parts {
                let x = viewport.left + (x + offset) * scale;
                if x >= viewport.right || y >= viewport.bottom {
                    continue;
                }
                match part {
                    Part::Text(text) => {
                        self.draw_text(text, x, y, scale);
                        drawn.text = true;
                    }
                    Part::Image(source) => {
                        let side = crate::emotes::EMOTE_WIDTH as f32 * scale;
                        if x + side <= viewport.left {
                            continue;
                        }
                        let ratio = side / source.width.max(source.height) as f32;
                        let bitmap = self.picture(source)?;
                        let destination = D2D_RECT_F {
                            left: x,
                            top: y,
                            right: x + source.width as f32 * ratio,
                            bottom: y + source.height as f32 * ratio,
                        };
                        unsafe {
                            self.target.DrawBitmap(
                                &bitmap,
                                Some(&destination),
                                1.0,
                                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                                None,
                            );
                        }
                        drawn.emote = true;
                    }
                }
            }
        }
        Ok(())
    }

    fn draw_text(&self, text: &[u16], x: f32, y: f32, scale: f32) {
        let edge = scale.max(1.0);
        for (dx, dy, brush) in [
            (-edge, 0.0, &self.shadow),
            (edge, 0.0, &self.shadow),
            (0.0, -edge, &self.shadow),
            (0.0, edge, &self.shadow),
            (0.0, 0.0, &self.white),
        ] {
            let bounds = D2D_RECT_F {
                left: x + dx,
                top: y + dy,
                right: x + dx + 1280.0 * scale,
                bottom: y + dy + 39.0 * scale,
            };
            unsafe {
                self.target.DrawText(
                    text,
                    &self.text,
                    &bounds,
                    brush,
                    D2D1_DRAW_TEXT_OPTIONS_NONE,
                    DWRITE_MEASURING_MODE_NATURAL,
                );
            }
        }
    }

    fn picture(&mut self, source: &Arc<Bitmap>) -> Result<ID2D1Bitmap> {
        if let Some((_, bitmap)) = self
            .pictures
            .iter()
            .find(|(cached, _)| Arc::ptr_eq(cached, source))
        {
            return Ok(bitmap.clone());
        }
        if source.pixels.len() != (source.width * source.height * 4) as usize {
            return Err("invalid danmaku bitmap".into());
        }
        let properties = D2D1_BITMAP_PROPERTIES {
            pixelFormat: pixel_format(D2D1_ALPHA_MODE_PREMULTIPLIED),
            dpiX: 96.0,
            dpiY: 96.0,
        };
        let bitmap = unsafe {
            self.target.CreateBitmap(
                D2D_SIZE_U {
                    width: source.width,
                    height: source.height,
                },
                Some(source.pixels.as_ptr().cast()),
                source.width * 4,
                &properties,
            )?
        };
        if self.pictures.len() == 32 {
            self.pictures.pop_front();
        }
        self.pictures
            .push_back((Arc::clone(source), bitmap.clone()));
        Ok(bitmap)
    }
}

#[cfg(windows)]
fn pixel_format(alpha_mode: D2D1_ALPHA_MODE) -> D2D1_PIXEL_FORMAT {
    D2D1_PIXEL_FORMAT {
        format: DXGI_FORMAT_B8G8R8A8_UNORM,
        alphaMode: alpha_mode,
    }
}
