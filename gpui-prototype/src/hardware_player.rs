use crate::{
    Result, compat::Source, dxva, dxva_render, hls::Hls, live_flv::LiveFlv, native_audio::Audio,
    native_danmaku::Lane, playback::AudioSettings,
};
use oxideav_core::{Error, MediaType, Packet, RuntimeContext, registry::container::Demuxer};
use oxideav_h264::avcc::AvcDecoderConfigurationRecord;
use std::{
    collections::BTreeMap,
    ffi::c_void,
    io::Cursor,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering::Relaxed},
        mpsc::sync_channel,
    },
    thread,
    time::{Duration, Instant},
};
use symphonia_codec_aac::AacDecoder;
use symphonia_core::{
    codecs::{CODEC_TYPE_AAC, CodecParameters, Decoder, DecoderOptions},
    formats::Packet as AudioPacket,
};
use windows::Win32::Foundation::HWND;

pub struct Input {
    pub url: String,
    pub headers: BTreeMap<String, String>,
    pub proxy: String,
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
        let timeout = Some(Duration::from_secs(7));
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
        let same_origin = url::Url::parse(target)
            .ok()
            .zip(url::Url::parse(&self.url).ok())
            .is_some_and(|(target, source)| target.origin() == source.origin());
        for (name, value) in &self.headers {
            let sensitive = matches!(
                name.to_ascii_lowercase().as_str(),
                "cookie" | "authorization" | "proxy-authorization"
            );
            if same_origin || !sensitive {
                request = request.header(name.as_str(), value.as_str());
            }
        }
        request
    }
}

pub struct HardwarePlayer {
    state: Arc<State>,
}

#[derive(Default)]
struct State {
    stopped: AtomicBool,
    paused: AtomicBool,
    muted: AtomicBool,
    volume: AtomicU8,
    frames: AtomicU64,
    audio_frames: AtomicU64,
    dropped: AtomicU64,
    position_ms: AtomicU64,
    danmaku: Mutex<Arc<Vec<Lane>>>,
    text_drawn: AtomicBool,
    emote_drawn: AtomicBool,
    end: Mutex<Option<End>>,
}

pub enum End {
    Eof,
    Failed(String),
}

impl HardwarePlayer {
    pub fn start(
        window: usize,
        source: Input,
        paused: bool,
        audio: AudioSettings,
    ) -> std::io::Result<Self> {
        let state = Arc::new(State::default());
        state.paused.store(paused, Relaxed);
        state.volume.store(audio.volume, Relaxed);
        state.muted.store(audio.muted, Relaxed);
        let worker = state.clone();
        thread::Builder::new()
            .name("purelive-d3d11".into())
            .spawn(move || {
                let result = play(window, source, &worker);
                if !worker.stopped.load(Relaxed) {
                    *worker.end.lock().unwrap() = Some(match result {
                        Ok(()) => End::Eof,
                        Err(error) => End::Failed(error.to_string()),
                    });
                }
            })?;
        Ok(Self { state })
    }

    pub fn set_paused(&self, paused: bool) {
        self.state.paused.store(paused, Relaxed);
    }
    pub fn set_volume(&self, volume: u8) {
        self.state.volume.store(volume, Relaxed);
    }
    pub fn set_muted(&self, muted: bool) {
        self.state.muted.store(muted, Relaxed);
    }
    pub fn take_end(&self) -> Option<End> {
        self.state.end.lock().unwrap().take()
    }

    pub fn set_danmaku(&self, lanes: Vec<Lane>) {
        *self.state.danmaku.lock().unwrap() = Arc::new(lanes);
    }

    pub fn danmaku_rendered(&self) -> (bool, bool) {
        (
            self.state.text_drawn.load(Relaxed),
            self.state.emote_drawn.load(Relaxed),
        )
    }

    pub fn property(&self, name: &std::ffi::CStr) -> Option<String> {
        match name.to_bytes() {
            b"time-pos" if self.state.frames.load(Relaxed) > 0 => Some(format!(
                "{:.3}",
                self.state.position_ms.load(Relaxed) as f64 / 1000.0
            )),
            b"hwdec-current" if self.state.frames.load(Relaxed) > 0 => Some("mf-d3d11".into()),
            b"frame-drop-count" => Some(self.state.dropped.load(Relaxed).to_string()),
            b"volume" => Some(self.state.volume.load(Relaxed).to_string()),
            b"mute" => Some(
                if self.state.muted.load(Relaxed) {
                    "yes"
                } else {
                    "no"
                }
                .into(),
            ),
            _ => None,
        }
    }

    pub fn stats(&self) -> String {
        format!(
            "硬解 mf-d3d11    掉帧 {}    进度 {} s    AAC 帧 {}",
            self.state.dropped.load(Relaxed),
            self.property(c"time-pos").unwrap_or_default(),
            self.state.audio_frames.load(Relaxed)
        )
    }
}

impl Drop for HardwarePlayer {
    fn drop(&mut self) {
        self.state.stopped.store(true, Relaxed);
    }
}

fn play(window: usize, source: Input, state: &State) -> Result<()> {
    let _runtime = dxva::Runtime::new()?;
    let mut context = RuntimeContext::new();
    oxideav_flv::register(&mut context);
    oxideav_mp4::register(&mut context);
    let url = url::Url::parse(&source.url).map_err(|_| "无效的播放地址")?;
    let is_hls = url.path().to_ascii_lowercase().ends_with(".m3u8");
    let device = dxva::Device::new()?;
    if state.stopped.load(Relaxed) {
        return Ok(());
    }
    let mut renderer = dxva_render::Renderer::new(HWND(window as *mut c_void), &device)?;
    let mut clock = Clock::default();
    let mut output = Audio::default();
    if is_hls {
        let done = AtomicBool::new(false);
        thread::scope(|scope| -> Result<()> {
            let (sender, receiver) = sync_channel(1);
            let done = &done;
            scope.spawn(move || {
                let run = || -> Result<()> {
                    let mut hls = Hls::open(&source)?;
                    while let Some(segment) =
                        hls.next(|| done.load(Relaxed) || state.stopped.load(Relaxed))?
                    {
                        if sender.send(Ok(segment)).is_err() {
                            break;
                        }
                    }
                    Ok(())
                };
                if let Err(error) = run() {
                    let _ = sender.send(Err(error.to_string()));
                }
            });
            let result = (|| -> Result<()> {
                for segment in receiver {
                    if state.stopped.load(Relaxed) {
                        break;
                    }
                    let (fragmented_mp4, data) = segment?;
                    let demux = if fragmented_mp4 {
                        context.containers.open_demuxer(
                            "mp4",
                            Box::new(Cursor::new(data)),
                            &context.codecs,
                        )?
                    } else {
                        oxideav_mpegts::demuxer::open(Box::new(Cursor::new(data)), &context.codecs)?
                    };
                    play_packets(
                        demux,
                        !fragmented_mp4,
                        &device,
                        &mut renderer,
                        &mut clock,
                        &mut output,
                        state,
                    )?;
                }
                Ok(())
            })();
            done.store(true, Relaxed);
            result
        })?;
    } else if matches!(url.scheme(), "http" | "https") {
        let demux = context.containers.open_demuxer(
            "flv",
            Box::new(LiveFlv::open(&source)?),
            &context.codecs,
        )?;
        play_packets(
            demux,
            false,
            &device,
            &mut renderer,
            &mut clock,
            &mut output,
            state,
        )?;
    } else {
        return Err("当前播放器支持 HTTP/HTTPS FLV 和 HLS 直播线路".into());
    }
    if state.frames.load(Relaxed) == 0 && !state.stopped.load(Relaxed) {
        return Err("播放源没有可用的视频帧".into());
    }
    Ok(())
}

fn play_packets(
    mut demux: Box<dyn Demuxer>,
    annex_b: bool,
    device: &dxva::Device,
    renderer: &mut dxva_render::Renderer,
    clock: &mut Clock,
    output: &mut Audio,
    state: &State,
) -> Result<()> {
    let video = demux
        .streams()
        .iter()
        .find(|stream| stream.params.media_type == MediaType::Video)
        .ok_or("播放源没有视频轨")?
        .clone();
    let audio = demux
        .streams()
        .iter()
        .find(|stream| stream.params.media_type == MediaType::Audio)
        .cloned();
    let mut aac = None;
    let mut decoder = None;
    while !state.stopped.load(Relaxed) {
        clock.wait_while_paused(state, output);
        if state.stopped.load(Relaxed) {
            break;
        }
        let mut packet = match demux.next_packet() {
            Ok(packet) => packet,
            Err(Error::Eof) => break,
            Err(error) => return Err(error.into()),
        };
        if packet.flags.header || packet.flags.discard || packet.data.is_empty() {
            continue;
        }
        if packet.stream_index == video.index {
            if decoder.is_none() {
                let mut params = video.params.clone();
                if annex_b {
                    let Ok(config) = AvcDecoderConfigurationRecord::from_annex_b(&packet.data)
                    else {
                        continue;
                    };
                    let (width, height) = config.parsed_sps()?.cropped_dimensions();
                    params.width = Some(width);
                    params.height = Some(height);
                    params.extradata = config.to_bytes()?;
                }
                decoder = Some(dxva::Decoder::new(device, &params, annex_b)?);
            }
            if let Some(decoder) = &mut decoder {
                decoder.send(&packet)?;
                while let Some(frame) = decoder.receive()? {
                    clock.present(frame, renderer, state, output)?;
                }
            }
        } else if let Some(stream) = &audio
            && packet.stream_index == stream.index
        {
            if !stream.params.codec_id.as_str().starts_with("aac") {
                continue;
            }
            let config = if annex_b {
                strip_adts(&mut packet)?
            } else {
                stream.params.extradata.clone()
            };
            if aac.is_none() {
                let mut params = CodecParameters::new();
                params
                    .for_codec(CODEC_TYPE_AAC)
                    .with_extra_data(config.into_boxed_slice());
                aac = Some(AacDecoder::try_new(&params, &DecoderOptions::default())?);
            }
            if let Some(aac) = &mut aac {
                let data = AudioPacket::new_from_boxed_slice(
                    stream.index,
                    packet.pts.unwrap_or(0).max(0) as u64,
                    0,
                    packet.data.into_boxed_slice(),
                );
                let gain = if state.muted.load(Relaxed) {
                    0.0
                } else {
                    f32::from(state.volume.load(Relaxed)) / 100.0
                };
                output.frame(aac.decode(&data)?, state.frames.load(Relaxed) > 0, gain)?;
                state.audio_frames.fetch_add(1, Relaxed);
            }
        }
    }
    if let Some(mut decoder) = decoder
        && !state.stopped.load(Relaxed)
    {
        decoder.finish()?;
        while let Some(frame) = decoder.receive()? {
            clock.present(frame, renderer, state, output)?;
        }
    }
    Ok(())
}

fn strip_adts(packet: &mut Packet) -> Result<Vec<u8>> {
    let data = &mut packet.data;
    if data.len() < 7 || data[0] != 0xff || data[1] & 0xf6 != 0xf0 {
        return Err("无效的 AAC ADTS 分帧".into());
    }
    let header = if data[1] & 1 == 0 { 9 } else { 7 };
    if data.len() <= header {
        return Err("AAC ADTS 分帧不完整".into());
    }
    let profile = (data[2] >> 6) + 1;
    let rate = (data[2] >> 2) & 15;
    let channels = ((data[2] & 1) << 2) | (data[3] >> 6);
    data.drain(..header);
    Ok(vec![
        (profile << 3) | (rate >> 1),
        (rate << 7) | (channels << 3),
    ])
}
#[derive(Default)]
struct Clock {
    anchor: Option<(i64, Instant)>,
    first_pts: Option<i64>,
}

impl Clock {
    fn wait_while_paused(&mut self, state: &State, audio: &mut Audio) {
        if state.paused.load(Relaxed) {
            audio.set_paused(true);
            let began = Instant::now();
            while state.paused.load(Relaxed) && !state.stopped.load(Relaxed) {
                thread::sleep(Duration::from_millis(10));
            }
            if let Some((_, wall)) = &mut self.anchor {
                *wall += began.elapsed();
            }
            audio.set_paused(false);
        }
    }

    fn present(
        &mut self,
        frame: dxva::Frame,
        renderer: &mut dxva_render::Renderer,
        state: &State,
        audio: &mut Audio,
    ) -> Result<()> {
        self.wait_while_paused(state, audio);
        if let Some(pts) = frame.pts {
            let first = *self.first_pts.get_or_insert(pts);
            state
                .position_ms
                .store(pts.saturating_sub(first).max(0) as u64 / 10_000, Relaxed);
            let now = Instant::now();
            let (origin, wall) = *self.anchor.get_or_insert((pts, now));
            let elapsed = Duration::from_nanos(
                (pts.saturating_sub(origin).max(0) as u64).saturating_mul(100),
            );
            let deadline = wall.checked_add(elapsed).unwrap_or(now);
            let distance = deadline
                .checked_duration_since(now)
                .unwrap_or_else(|| now.duration_since(deadline));
            if distance > Duration::from_secs(1) {
                self.anchor = Some((pts, now));
            } else if let Some(wait) = deadline.checked_duration_since(now) {
                thread::sleep(wait.min(Duration::from_millis(200)));
            } else if now.duration_since(deadline) > Duration::from_millis(80) {
                state.dropped.fetch_add(1, Relaxed);
                return Ok(());
            }
        }
        if !state.stopped.load(Relaxed) {
            let lanes = Arc::clone(&state.danmaku.lock().unwrap());
            let drawn = renderer.frame(&frame, &lanes)?;
            if drawn.text {
                state.text_drawn.store(true, Relaxed);
            }
            if drawn.emote {
                state.emote_drawn.store(true, Relaxed);
            }
            state.frames.fetch_add(1, Relaxed);
        }
        Ok(())
    }
}
