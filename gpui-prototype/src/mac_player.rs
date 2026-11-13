use crate::{
    Result,
    compat::Source,
    emotes::Bitmap,
    mac_flv::Relay,
    native_danmaku::{Lane, Part},
    playback::AudioSettings,
};
use objc2::{MainThreadMarker, rc::Retained, runtime::AnyObject};
use objc2_app_kit::{NSFont, NSFontAttributeName, NSStringDrawing, NSView};
use objc2_av_foundation::{AVPlayer, AVPlayerItem, AVPlayerLayer, AVURLAsset};
use objc2_core_foundation::{CFData, CFString};
use objc2_core_graphics::{
    CGBitmapInfo, CGColorRenderingIntent, CGColorSpace, CGDataProvider, CGImage,
};
use objc2_foundation::{NSDictionary, NSPoint, NSRect, NSSize, NSString, NSURL};
use objc2_quartz_core::{CALayer, CATextLayer, CATransaction};
use std::{
    cell::{Cell, RefCell},
    ffi::CStr,
    sync::Arc,
    time::{Duration, Instant},
};

const DANMAKU_SPEED: f64 = 120.0;
const DANMAKU_FONT: &str = "PingFangSC-Medium";
const DANMAKU_FONT_SIZE: f64 = 20.0;
const DANMAKU_TEXT_HEIGHT: f64 = 29.0;
const DANMAKU_ROW_HEIGHT: f64 = 30.0;
const DANMAKU_TOP: f64 = 12.0;
const DANMAKU_GAP: f64 = 40.0;

pub struct Input {
    pub url: String,
    headers: std::collections::BTreeMap<String, String>,
    proxy: String,
}

impl Input {
    pub fn from_source(source: &Source) -> Self {
        Self {
            url: source.url.clone(),
            headers: source.headers.clone(),
            proxy: source.proxy.clone(),
        }
    }

    pub fn agent(&self) -> Result<ureq::Agent> {
        let proxy = (!self.proxy.is_empty())
            .then(|| ureq::Proxy::new(&self.proxy))
            .transpose()?;
        let timeout = Some(std::time::Duration::from_secs(7));
        Ok(ureq::Agent::config_builder()
            .proxy(proxy)
            .timeout_connect(timeout)
            .timeout_recv_response(timeout)
            .timeout_per_read(timeout)
            .build()
            .into())
    }

    pub fn request(
        &self,
        agent: &ureq::Agent,
        target: &str,
    ) -> ureq::RequestBuilder<ureq::typestate::WithoutBody> {
        let mut request = agent.get(target);
        for (key, value) in &self.headers {
            request = request.header(key.as_str(), value.as_str());
        }
        request
    }
}

pub enum End {
    Eof,
    Failed(String),
}

pub struct HardwarePlayer {
    view: Retained<NSView>,
    player: Retained<AVPlayer>,
    video: Retained<AVPlayerLayer>,
    overlay: Retained<CALayer>,
    relay: Option<Relay>,
    lanes: RefCell<Vec<VisualLane>>,
    paused: Cell<bool>,
    ready: Cell<bool>,
    volume: Cell<u8>,
    muted: Cell<bool>,
    drawn: Cell<(bool, bool)>,
    bounds: Cell<NSRect>,
    danmaku_font: Retained<NSFont>,
}

struct VisualLane {
    lane: Lane,
    parts: Vec<(f32, Part, Retained<CALayer>)>,
}

impl HardwarePlayer {
    pub fn start(window: usize, input: Input, paused: bool, audio: AudioSettings) -> Result<Self> {
        let marker = MainThreadMarker::new().ok_or("无法在后台线程创建播放器")?;
        let view = unsafe { Retained::retain(window as *mut NSView) }.ok_or("缺少播放区域")?;
        let parsed = url::Url::parse(&input.url).map_err(|_| "无效的播放地址")?;
        let flv = parsed.path().to_ascii_lowercase().ends_with(".flv");
        let headers = if flv {
            None
        } else {
            Some(input.headers.clone())
        };
        let relay = if flv {
            Some(Relay::start(input)?)
        } else {
            None
        };
        let url = relay
            .as_ref()
            .map_or(parsed.as_str(), |relay| relay.url.as_str());
        let url = NSURL::URLWithString(&NSString::from_str(url)).ok_or("无效的播放地址")?;
        let player = unsafe {
            if let Some(headers) = headers.filter(|headers| !headers.is_empty()) {
                let names: Vec<_> = headers
                    .keys()
                    .map(|name| NSString::from_str(name))
                    .collect();
                let values: Vec<_> = headers
                    .values()
                    .map(|value| NSString::from_str(value))
                    .collect();
                let names: Vec<_> = names.iter().map(|value| &**value).collect();
                let values: Vec<_> = values.iter().map(|value| &**value).collect();
                let fields = NSDictionary::from_slices(&names, &values);
                let options = NSDictionary::from_slices(
                    &[&*NSString::from_str("AVURLAssetHTTPHeaderFieldsKey")],
                    &[&*fields as &AnyObject],
                );
                let asset = AVURLAsset::URLAssetWithURL_options(&url, Some(&options));
                let item = AVPlayerItem::playerItemWithAsset(&asset, marker);
                AVPlayer::playerWithPlayerItem(Some(&item), marker)
            } else if relay.is_some() {
                AVPlayer::playerWithPlayerItem(None, marker)
            } else {
                AVPlayer::playerWithURL(&url, marker)
            }
        };
        let layer = view.layer().ok_or("无法创建 macOS 视频图层")?;
        let bounds = view.bounds();
        let video = unsafe { AVPlayerLayer::playerLayerWithPlayer(Some(&player)) };
        video.setFrame(bounds);
        layer.addSublayer(&video);
        let overlay = CALayer::layer();
        overlay.setFrame(bounds);
        overlay.setMasksToBounds(true);
        overlay.setZPosition(1.0);
        layer.addSublayer(&overlay);
        let this = Self {
            view,
            player,
            video,
            overlay,
            ready: Cell::new(relay.is_none()),
            relay,
            lanes: RefCell::new(Vec::new()),
            paused: Cell::new(paused),
            volume: Cell::new(audio.volume),
            muted: Cell::new(audio.muted),
            drawn: Cell::new((false, false)),
            bounds: Cell::new(bounds),
            danmaku_font: NSFont::fontWithName_size(
                &NSString::from_str(DANMAKU_FONT),
                DANMAKU_FONT_SIZE,
            )
            .unwrap_or_else(|| NSFont::systemFontOfSize(DANMAKU_FONT_SIZE)),
        };
        this.set_volume(audio.volume);
        this.set_muted(audio.muted);
        this.set_paused(paused);
        Ok(this)
    }

    pub fn set_paused(&self, paused: bool) {
        self.paused.set(paused);
        unsafe {
            if paused {
                self.player.pause();
            } else if self.ready.get() {
                self.player.play();
            }
        }
    }

    pub fn set_volume(&self, volume: u8) {
        self.volume.set(volume);
        unsafe { self.player.setVolume(f32::from(volume) / 100.0) };
    }

    pub fn set_muted(&self, muted: bool) {
        self.muted.set(muted);
        unsafe { self.player.setMuted(muted) };
    }

    pub fn take_end(&self) -> Option<End> {
        if self.bounds.get() != self.view.bounds() {
            self.paint();
        }
        if let Some(relay) = &self.relay {
            if relay.failed() && !relay.ready() {
                return Some(End::Failed("无法读取 FLV 直播".into()));
            }
            if !self.ready.get() && relay.ready() {
                let url = NSURL::URLWithString(&NSString::from_str(&relay.url))?;
                let marker = MainThreadMarker::new()?;
                unsafe {
                    let item = AVPlayerItem::playerItemWithURL(&url, marker);
                    self.player.replaceCurrentItemWithPlayerItem(Some(&item));
                }
                self.ready.set(true);
                self.set_paused(self.paused.get());
            }
        }
        unsafe {
            let item = self.player.currentItem()?;
            if let Some(error) = item.error().or_else(|| self.player.error()) {
                return Some(End::Failed(format!("AVFoundation {}", error.code())));
            }
            let duration = item.duration().seconds();
            let position = self.player.currentTime().seconds();
            if duration.is_finite() && duration > 0.0 && position >= duration - 0.08 {
                return Some(End::Eof);
            }
        }
        None
    }

    pub fn set_danmaku(&self, lanes: Vec<Lane>) {
        CATransaction::begin();
        CATransaction::setDisableActions(true);
        let mut visuals = self.lanes.borrow_mut();
        let mut previous = std::mem::take(&mut *visuals);
        visuals.reserve(lanes.len());
        for mut lane in lanes {
            let mut parts = previous
                .iter()
                .position(|visual| visual.lane.y == lane.y && visual.lane.started == lane.started)
                .map(|index| previous.swap_remove(index).parts)
                .unwrap_or_default()
                .into_iter()
                .peekable();
            let mut updated = Vec::with_capacity(lane.parts.len());
            for (offset, part) in std::mem::take(&mut lane.parts) {
                let layer = if let Some((_, _, layer)) =
                    parts.next_if(|(x, old, _)| *x == offset && same_part(old, &part))
                {
                    layer
                } else {
                    // The content at this offset changed, usually from fallback
                    // text to a loaded emote. Keep other parts of the lane.
                    if let Some((_, _, layer)) = parts.next_if(|(x, _, _)| *x == offset) {
                        layer.removeFromSuperlayer();
                    }
                    let Some(layer) = self.danmaku_layer(&part) else {
                        continue;
                    };
                    self.overlay.addSublayer(&layer);
                    layer
                };
                updated.push((offset, part, layer));
            }
            for (_, _, layer) in parts {
                layer.removeFromSuperlayer();
            }
            visuals.push(VisualLane {
                lane,
                parts: updated,
            });
        }
        for visual in previous {
            for (_, _, layer) in visual.parts {
                layer.removeFromSuperlayer();
            }
        }
        drop(visuals);
        self.position_layers();
        CATransaction::commit();
    }

    fn danmaku_layer(&self, part: &Part) -> Option<Retained<CALayer>> {
        match part {
            Part::Text(text) => {
                let layer = CATextLayer::layer();
                let text = NSString::from_str(&String::from_utf16_lossy(text));
                let font = CFString::from_str(&self.danmaku_font.fontName().to_string());
                unsafe {
                    layer.setFont(Some(&font));
                    layer.setString(Some(&text));
                }
                layer.setFontSize(DANMAKU_FONT_SIZE);
                layer.setBounds(NSRect::new(
                    NSPoint::new(0.0, 0.0),
                    NSSize::new(self.measure_danmaku_text(&text), DANMAKU_TEXT_HEIGHT),
                ));
                // Keep contrast on bright video without an offset halo below the glyphs.
                layer.setShadowOffset(NSSize::new(0.0, 0.0));
                layer.setShadowOpacity(0.7);
                layer.setShadowRadius(0.85);
                Some(Retained::into_super(layer))
            }
            Part::Image(bitmap) => self.image(bitmap),
        }
    }

    fn image(&self, bitmap: &Arc<Bitmap>) -> Option<Retained<CALayer>> {
        let data = CFData::from_bytes(&bitmap.pixels);
        let provider = CGDataProvider::with_cf_data(Some(&data))?;
        let space = CGColorSpace::new_device_rgb()?;
        let width = bitmap.width as usize;
        let height = bitmap.height as usize;
        let image = unsafe {
            CGImage::new(
                width,
                height,
                8,
                32,
                width * 4,
                Some(&space),
                CGBitmapInfo(0x2002),
                Some(&provider),
                std::ptr::null(),
                true,
                CGColorRenderingIntent::RenderingIntentDefault,
            )?
        };
        let layer = CALayer::layer();
        unsafe { layer.setContents(Some(&*(std::ptr::from_ref(&*image).cast::<AnyObject>()))) };
        Some(layer)
    }

    pub fn paint(&self) -> bool {
        CATransaction::begin();
        CATransaction::setDisableActions(true);
        let animating = self.position_layers();
        CATransaction::commit();
        animating
    }

    pub fn danmaku_segment_width(&self, segment: &crate::emotes::Segment) -> f32 {
        (match segment {
            crate::emotes::Segment::Text(text) => {
                self.measure_danmaku_text(&NSString::from_str(text))
            }
            crate::emotes::Segment::Picture { alt, .. } => self
                .measure_danmaku_text(&NSString::from_str(alt))
                .max(36.0),
        }) as f32
    }

    fn measure_danmaku_text(&self, text: &NSString) -> f64 {
        unsafe {
            let attributes = NSDictionary::from_slices(
                &[NSFontAttributeName],
                &[&*self.danmaku_font as &AnyObject],
            );
            text.sizeWithAttributes(Some(&attributes)).width.ceil() + 2.0
        }
    }

    pub fn danmaku_duration(&self, message_width: f32) -> Duration {
        danmaku_duration(self.view.bounds().size.width, message_width)
    }

    pub fn danmaku_rows(&self) -> usize {
        let height = self.view.bounds().size.height;
        ((height - DANMAKU_TOP) / DANMAKU_ROW_HEIGHT).max(0.0) as usize
    }

    pub fn danmaku_spacing(&self, message_width: f32) -> Duration {
        Duration::from_secs_f64((f64::from(message_width) + DANMAKU_GAP) / DANMAKU_SPEED)
    }

    fn position_layers(&self) -> bool {
        let bounds = self.view.bounds();
        if self.bounds.replace(bounds) != bounds {
            self.video.setFrame(bounds);
            self.overlay.setFrame(bounds);
        }
        let width = bounds.size.width;
        let rows = self.danmaku_rows();
        let backing_scale = self
            .view
            .window()
            .map_or(1.0, |window| window.backingScaleFactor());
        // Fractional device pixels resample the glyph texture as it moves.
        let snap = |points: f64| (points * backing_scale).round() / backing_scale;
        let now = Instant::now();
        let (mut text_drawn, mut image_drawn) = self.drawn.get();
        let mut animating = false;
        for visual in &*self.lanes.borrow() {
            let elapsed = now.saturating_duration_since(visual.lane.started);
            let visible = elapsed < danmaku_duration(width, visual.lane.width);
            let x = width - elapsed.as_secs_f64() * DANMAKU_SPEED;
            let row_visible = visible && (visual.lane.y as usize) < rows;
            animating |= visible;
            for (offset, part, layer) in &visual.parts {
                let (width, height) = match part {
                    Part::Text(_) => {
                        text_drawn |= row_visible;
                        if layer.contentsScale() != backing_scale {
                            layer.setContentsScale(backing_scale);
                        }
                        (layer.bounds().size.width, DANMAKU_TEXT_HEIGHT)
                    }
                    Part::Image(bitmap) => {
                        image_drawn |= row_visible;
                        let ratio = 24.0 / f64::from(bitmap.width.max(bitmap.height));
                        (
                            f64::from(bitmap.width) * ratio,
                            f64::from(bitmap.height) * ratio,
                        )
                    }
                };
                layer.setHidden(!row_visible);
                layer.setFrame(NSRect::new(
                    NSPoint::new(
                        snap(x + f64::from(*offset)),
                        snap(
                            bounds.size.height
                                - DANMAKU_TOP
                                - f64::from(visual.lane.y) * DANMAKU_ROW_HEIGHT
                                - height,
                        ),
                    ),
                    NSSize::new(width, height),
                ));
            }
        }
        self.drawn.set((text_drawn, image_drawn));
        animating
    }

    pub fn danmaku_rendered(&self) -> (bool, bool) {
        self.drawn.get()
    }

    pub fn property(&self, key: &CStr) -> Option<String> {
        match key.to_bytes() {
            b"time-pos" => {
                let position = unsafe { self.player.currentTime().seconds() };
                (position.is_finite() && unsafe { self.video.isReadyForDisplay() })
                    .then(|| format!("{position:.3}"))
            }
            b"volume" => Some(self.volume.get().to_string()),
            b"mute" => Some(if self.muted.get() { "yes" } else { "no" }.into()),
            _ => None,
        }
    }

    pub fn stats(&self) -> String {
        format!(
            "AVFoundation 进度 {} s",
            self.property(c"time-pos").unwrap_or_default()
        )
    }
}

fn danmaku_duration(view_width: f64, message_width: f32) -> Duration {
    let distance = view_width + f64::from(message_width);
    Duration::from_secs_f64(distance / DANMAKU_SPEED)
}

fn same_part(left: &Part, right: &Part) -> bool {
    match (left, right) {
        (Part::Text(left), Part::Text(right)) => left == right,
        (Part::Image(left), Part::Image(right)) => Arc::ptr_eq(left, right),
        _ => false,
    }
}

impl Drop for HardwarePlayer {
    fn drop(&mut self) {
        self.set_paused(true);
        self.overlay.removeFromSuperlayer();
        self.video.removeFromSuperlayer();
    }
}
