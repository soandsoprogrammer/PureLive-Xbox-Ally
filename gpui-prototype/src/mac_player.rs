use crate::{
    Result,
    compat::Source,
    emotes::Bitmap,
    mac_flv::Relay,
    native_danmaku::{Lane, Part},
    playback::AudioSettings,
};
use objc2::{MainThreadMarker, rc::Retained, runtime::AnyObject};
use objc2_app_kit::NSView;
use objc2_av_foundation::{AVPlayer, AVPlayerItem, AVPlayerLayer, AVURLAsset};
use objc2_core_foundation::CFData;
use objc2_core_graphics::{
    CGBitmapInfo, CGColorRenderingIntent, CGColorSpace, CGDataProvider, CGImage,
};
use objc2_foundation::{NSDictionary, NSPoint, NSRect, NSSize, NSString, NSURL};
use objc2_quartz_core::{CALayer, CATextLayer, CATransaction};
use std::{
    cell::{Cell, RefCell},
    ffi::CStr,
    sync::Arc,
    time::Instant,
};

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
}

struct VisualLane {
    lane: Lane,
    parts: Vec<(f32, Retained<CALayer>)>,
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
        let video = unsafe { AVPlayerLayer::playerLayerWithPlayer(Some(&player)) };
        video.setFrame(view.bounds());
        layer.addSublayer(&video);
        let overlay = CALayer::layer();
        overlay.setFrame(view.bounds());
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
        self.paint();
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
        let mut visuals = self.lanes.borrow_mut();
        for lane in visuals.drain(..) {
            for (_, layer) in lane.parts {
                layer.removeFromSuperlayer();
            }
        }
        for lane in lanes {
            let parts = lane
                .parts
                .iter()
                .filter_map(|(x, part)| {
                    let layer = match part {
                        Part::Text(text) => {
                            let layer = CATextLayer::layer();
                            let text = NSString::from_str(&String::from_utf16_lossy(text));
                            unsafe { layer.setString(Some(&text)) };
                            layer.setFontSize(24.0);
                            layer.setContentsScale(
                                self.view
                                    .window()
                                    .map_or(1.0, |window| window.backingScaleFactor()),
                            );
                            layer.setShadowOpacity(0.9);
                            layer.setShadowRadius(2.0);
                            Retained::into_super(layer)
                        }
                        Part::Image(bitmap) => self.image(bitmap)?,
                    };
                    self.overlay.addSublayer(&layer);
                    Some((*x, layer))
                })
                .collect();
            visuals.push(VisualLane { lane, parts });
        }
        drop(visuals);
        self.paint();
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

    pub fn paint(&self) {
        CATransaction::begin();
        CATransaction::setDisableActions(true);
        let bounds = self.view.bounds();
        self.video.setFrame(bounds);
        self.overlay.setFrame(bounds);
        let scale = (bounds.size.width / 1280.0).max(0.1);
        let now = Instant::now();
        let (mut text_drawn, mut image_drawn) = self.drawn.get();
        for visual in &*self.lanes.borrow() {
            let elapsed = now.saturating_duration_since(visual.lane.started);
            let progress = (elapsed.as_secs_f64() / visual.lane.duration.as_secs_f64()).min(1.0);
            let x = 1280.0 - progress * (1280.0 + f64::from(visual.lane.width));
            for ((offset, layer), (_, part)) in visual.parts.iter().zip(&visual.lane.parts) {
                let (width, height) = match part {
                    Part::Text(_) => {
                        text_drawn |= progress < 1.0;
                        (1024.0, 40.0)
                    }
                    Part::Image(bitmap) => {
                        image_drawn |= progress < 1.0;
                        let ratio = 32.0 / f64::from(bitmap.width.max(bitmap.height));
                        (
                            f64::from(bitmap.width) * ratio,
                            f64::from(bitmap.height) * ratio,
                        )
                    }
                };
                layer.setHidden(progress >= 1.0);
                layer.setFrame(NSRect::new(
                    NSPoint::new(
                        (x + f64::from(*offset)) * scale,
                        bounds.size.height - (f64::from(visual.lane.y) + height) * scale,
                    ),
                    NSSize::new(width * scale, height * scale),
                ));
            }
        }
        self.drawn.set((text_drawn, image_drawn));
        CATransaction::commit();
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

impl Drop for HardwarePlayer {
    fn drop(&mut self) {
        self.set_paused(true);
        self.overlay.removeFromSuperlayer();
        self.video.removeFromSuperlayer();
    }
}
