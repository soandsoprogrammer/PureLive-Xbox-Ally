use crate::{Result, hardware_player::Input, live_flv::LiveFlv};
use oxideav_core::{Error, MediaType, RuntimeContext, TimeBase};
use oxideav_h264::avcc::AvcDecoderConfigurationRecord;
use oxideav_h264::nal::AvccSplitter;
use std::{
    collections::VecDeque,
    io::{BufRead, BufReader, Cursor, Read, Seek, SeekFrom, Write},
    net::{TcpListener, TcpStream},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering::Relaxed},
    },
    thread,
    time::Duration,
};

pub struct Relay {
    pub url: String,
    state: Arc<State>,
}

#[derive(Default)]
struct State {
    stop: AtomicBool,
    data: Mutex<Playlist>,
}

#[derive(Default)]
struct Playlist {
    sequence: u64,
    chunks: VecDeque<(f64, Arc<Vec<u8>>)>,
    end: bool,
    failed: bool,
}

impl Relay {
    pub fn start(input: Input) -> Result<Self> {
        let listener = TcpListener::bind(("127.0.0.1", 0))?;
        listener.set_nonblocking(true)?;
        let url = format!("http://{}/live.m3u8", listener.local_addr()?);
        let state = Arc::new(State::default());
        let reader = state.clone();
        thread::spawn(move || {
            let result = remux(input, &reader);
            let mut list = reader.data.lock().unwrap();
            list.failed = result.is_err();
            list.end = true;
        });
        let server = state.clone();
        thread::spawn(move || {
            while !server.stop.load(Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let _ = serve(stream, &server);
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(15))
                    }
                    Err(_) => break,
                }
            }
        });
        Ok(Self { url, state })
    }

    pub fn ready(&self) -> bool {
        !self.state.data.lock().unwrap().chunks.is_empty()
    }
    pub fn failed(&self) -> bool {
        self.state.data.lock().unwrap().failed
    }
}

impl Drop for Relay {
    fn drop(&mut self) {
        self.state.stop.store(true, Relaxed);
    }
}

fn serve(mut stream: TcpStream, state: &State) -> std::io::Result<()> {
    let timeout = Some(Duration::from_secs(1));
    stream.set_read_timeout(timeout)?;
    stream.set_write_timeout(timeout)?;
    let mut line = String::new();
    BufReader::new((&mut stream).take(1024)).read_line(&mut line)?;
    let mut parts = line.split_whitespace();
    let head = parts.next() == Some("HEAD");
    let path = parts.next().unwrap_or("");
    let list = state.data.lock().unwrap();
    let (kind, body) = if path == "/live.m3u8" {
        let target = list
            .chunks
            .iter()
            .map(|(seconds, _)| seconds.ceil() as u32)
            .max()
            .unwrap_or(6)
            .max(6);
        let mut manifest = format!(
            "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:{target}\n#EXT-X-MEDIA-SEQUENCE:{}\n",
            list.sequence
        );
        for (index, (duration, _)) in list.chunks.iter().enumerate() {
            manifest.push_str(&format!(
                "#EXTINF:{duration:.3},\n/{}.ts\n",
                list.sequence + index as u64
            ));
        }
        if list.end {
            manifest.push_str("#EXT-X-ENDLIST\n");
        }
        (
            "application/vnd.apple.mpegurl",
            Some(Arc::new(manifest.into_bytes())),
        )
    } else {
        let chunk = path
            .strip_prefix('/')
            .and_then(|name| name.strip_suffix(".ts"))
            .and_then(|name| name.parse::<u64>().ok())
            .and_then(|sequence| sequence.checked_sub(list.sequence))
            .and_then(|index| list.chunks.get(index as usize))
            .map(|(_, bytes)| bytes.clone());
        ("video/mp2t", chunk)
    };
    drop(list);
    if let Some(body) = body {
        write!(
            stream,
            "HTTP/1.1 200 OK\r\nContent-Type: {kind}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
            body.len()
        )?;
        if !head {
            stream.write_all(&body)?;
        }
    } else {
        stream.write_all(
            b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        )?;
    }
    Ok(())
}

#[derive(Clone, Default)]
struct Buffer(Arc<Mutex<Cursor<Vec<u8>>>>);

impl Write for Buffer {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().write(bytes)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
impl Seek for Buffer {
    fn seek(&mut self, to: SeekFrom) -> std::io::Result<u64> {
        self.0.lock().unwrap().seek(to)
    }
}

fn remux(input: Input, state: &State) -> Result<()> {
    let mut context = RuntimeContext::new();
    oxideav_flv::register(&mut context);
    let mut demux = context.containers.open_demuxer(
        "flv",
        Box::new(LiveFlv::open(&input)?),
        &context.codecs,
    )?;
    let video = demux
        .streams()
        .iter()
        .find(|track| {
            track.params.media_type == MediaType::Video && track.params.codec_id.as_str() == "h264"
        })
        .ok_or("FLV does not carry H.264")?
        .clone();
    let audio = demux
        .streams()
        .iter()
        .find(|track| {
            track.params.media_type == MediaType::Audio && track.params.codec_id.as_str() == "aac"
        })
        .cloned();
    let transport_clock = TimeBase::new(1, 90_000);
    let tracks: Vec<_> = std::iter::once(video.clone())
        .chain(audio.clone())
        .map(|mut track| {
            track.time_base = transport_clock;
            track
        })
        .collect();
    let config = AvcDecoderConfigurationRecord::parse(&video.params.extradata)?;
    let mut header = Vec::new();
    for nal in config.sps.iter().chain(&config.pps) {
        header.extend_from_slice(&[0, 0, 0, 1]);
        header.extend_from_slice(nal);
    }
    let mut start = None;
    let mut last = 0.0_f64;
    let mut segment = None;
    while !state.stop.load(Relaxed) {
        let mut packet = match demux.next_packet() {
            Ok(packet) => packet,
            Err(Error::Eof) => break,
            Err(error) => return Err(error.into()),
        };
        if packet.flags.header || packet.flags.discard || packet.data.is_empty() {
            continue;
        }
        let is_video = packet.stream_index == video.index;
        let time = packet.dts.or(packet.pts).unwrap_or(0) as f64 * packet.time_base.num() as f64
            / packet.time_base.den() as f64;
        if is_video && packet.flags.keyframe && start.is_none_or(|start| time - start >= 1.8) {
            if let Some((old, buffer)) = segment.take() {
                finish(state, old, buffer, time - start.unwrap_or(time))?;
            }
            let buffer = Buffer::default();
            let mut muxer = oxideav_mpegts::muxer::open(Box::new(buffer.clone()), &tracks)?;
            muxer.write_header()?;
            segment = Some((muxer, buffer));
            start = Some(time);
        }
        let Some((muxer, buffer)) = &mut segment else {
            continue;
        };
        if buffer.0.lock().unwrap().get_ref().len() > 32 * 1024 * 1024 {
            return Err("FLV segment exceeds size limit".into());
        }
        if is_video {
            let mut annex_b = if packet.flags.keyframe {
                header.clone()
            } else {
                Vec::new()
            };
            for nal in AvccSplitter::new(&packet.data, config.length_size)? {
                annex_b.extend_from_slice(&[0, 0, 0, 1]);
                annex_b.extend_from_slice(nal?);
            }
            packet.data = annex_b;
        } else if let Some(audio) = &audio
            && packet.stream_index == audio.index
        {
            packet.data = adts(&audio.params.extradata, &packet.data)?;
        } else {
            continue;
        }
        let source_clock = packet.time_base;
        packet.pts = packet
            .pts
            .map(|value| source_clock.rescale(value, transport_clock));
        packet.dts = packet
            .dts
            .map(|value| source_clock.rescale(value, transport_clock));
        packet.duration = packet
            .duration
            .map(|value| source_clock.rescale(value, transport_clock));
        packet.time_base = transport_clock;
        muxer.write_packet(&packet)?;
        last = last.max(time);
    }
    if let Some((muxer, buffer)) = segment {
        finish(state, muxer, buffer, last - start.unwrap_or(last) + 0.04)?;
    }
    Ok(())
}

fn finish(
    state: &State,
    mut muxer: Box<dyn oxideav_core::Muxer>,
    buffer: Buffer,
    duration: f64,
) -> Result<()> {
    muxer.write_trailer()?;
    let bytes = std::mem::take(buffer.0.lock().unwrap().get_mut());
    let mut list = state.data.lock().unwrap();
    list.chunks.push_back((duration.max(0.04), Arc::new(bytes)));
    if list.chunks.len() > 8 {
        list.chunks.pop_front();
        list.sequence += 1;
    }
    Ok(())
}

fn adts(config: &[u8], data: &[u8]) -> Result<Vec<u8>> {
    let [a, b, ..] = config else {
        return Err("missing AAC configuration".into());
    };
    let object = a >> 3;
    let rate = ((a & 7) << 1) | (b >> 7);
    let channels = (b >> 3) & 15;
    let length = data.len() + 7;
    if !(1..=4).contains(&object) || rate > 12 || channels > 7 || length > 8191 {
        return Err("unsupported AAC configuration".into());
    }
    let mut frame = Vec::with_capacity(length);
    frame.extend_from_slice(&[
        0xff,
        0xf1,
        ((object - 1) << 6) | (rate << 2) | (channels >> 2),
        (channels << 6) | (length >> 11) as u8,
        (length >> 3) as u8,
        (length as u8 & 7) << 5 | 31,
        0xfc,
    ]);
    frame.extend_from_slice(data);
    Ok(frame)
}
