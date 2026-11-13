use crate::{Result, hardware_player::Input};
use m3u8_rs::{ByteRange, KeyMethod, Playlist};
use std::{collections::VecDeque, io::Read, thread, time::Duration};
use ureq::ResponseExt;
use url::Url;

pub struct Hls<'a> {
    input: &'a Input,
    agent: ureq::Agent,
    url: Url,
    pending: VecDeque<Segment>,
    next: Option<u64>,
    ended: bool,
    interval: Duration,
    init: Option<(Url, Option<ByteRange>, Vec<u8>)>,
}

struct Segment {
    url: Url,
    range: Option<ByteRange>,
    init: Option<(Url, Option<ByteRange>)>,
}

impl<'a> Hls<'a> {
    pub fn open(input: &'a Input) -> Result<Self> {
        Ok(Self {
            input,
            agent: input.agent()?,
            url: Url::parse(&input.url)?,
            pending: VecDeque::new(),
            next: None,
            ended: false,
            interval: Duration::from_millis(500),
            init: None,
        })
    }

    pub fn next(&mut self, stopped: impl Fn() -> bool) -> Result<Option<(bool, Vec<u8>)>> {
        while self.pending.is_empty() && !self.ended && !stopped() {
            self.reload()?;
            if self.pending.is_empty() && !self.ended {
                for _ in 0..(self.interval.as_millis() / 100) {
                    if stopped() {
                        return Ok(None);
                    }
                    thread::sleep(Duration::from_millis(100));
                }
            }
        }
        let Some(segment) = self.pending.pop_front().filter(|_| !stopped()) else {
            return Ok(None);
        };
        let mut data = Vec::new();
        if let Some((url, range)) = &segment.init {
            if self
                .init
                .as_ref()
                .is_none_or(|(old_url, old_range, _)| old_url != url || old_range != range)
            {
                let bytes = self.fetch(url, range.as_ref(), 4 * 1024 * 1024)?;
                self.init = Some((url.clone(), range.clone(), bytes));
            }
            if let Some((_, _, bytes)) = &self.init {
                data.extend_from_slice(bytes);
            }
        }
        data.extend(self.fetch(&segment.url, segment.range.as_ref(), 32 * 1024 * 1024)?);
        Ok(Some((segment.init.is_some(), data)))
    }

    fn reload(&mut self) -> Result<()> {
        for _ in 0..4 {
            let response = self.input.request(&self.agent, self.url.as_str()).call()?;
            self.url = Url::parse(&response.get_uri().to_string())?;
            let bytes = read_limited(response.into_body().into_reader(), 1024 * 1024)?;
            match m3u8_rs::parse_playlist_res(&bytes).map_err(|_| "无效的 HLS 播放列表")? {
                Playlist::MasterPlaylist(master) => {
                    let variant = master
                        .variants
                        .iter()
                        .filter(|item| !item.is_i_frame && item.audio.is_none())
                        .filter(|item| {
                            item.codecs.as_deref().is_none_or(|codecs| {
                                codecs.contains("avc1") || codecs.contains("avc3")
                            })
                        })
                        .max_by_key(|item| item.bandwidth)
                        .ok_or("HLS 没有可用的 H.264 音视频线路")?;
                    self.url = self.url.join(&variant.uri)?;
                }
                Playlist::MediaPlaylist(list) => {
                    let start = self.next.unwrap_or_else(|| {
                        list.media_sequence
                            + if list.end_list {
                                0
                            } else {
                                list.segments.len().saturating_sub(3) as u64
                            }
                    });
                    self.ended = list.end_list;
                    self.interval = Duration::from_millis(
                        (list.target_duration.saturating_mul(500)).clamp(250, 2000),
                    );
                    let mut range_end = None;
                    let mut init = None;
                    for (index, segment) in list.segments.into_iter().enumerate() {
                        let seq = list.media_sequence + index as u64;
                        let range = segment.byte_range.map(|mut range| {
                            let offset = range.offset.or(range_end).unwrap_or(0);
                            range.offset = Some(offset);
                            range_end = offset.checked_add(range.length);
                            range
                        });
                        if range.is_none() {
                            range_end = None;
                        }
                        if let Some(map) = segment.map {
                            init = Some((self.url.join(&map.uri)?, map.byte_range));
                        }
                        if seq < start {
                            continue;
                        }
                        if segment.key.is_some_and(|key| key.method != KeyMethod::None) {
                            return Err("当前 HLS 线路使用加密分段".into());
                        }
                        self.pending.push_back(Segment {
                            url: self.url.join(&segment.uri)?,
                            range,
                            init: init.clone(),
                        });
                        self.next = Some(seq.saturating_add(1));
                    }
                    return Ok(());
                }
            }
        }
        Err("HLS 主列表跳转过多".into())
    }

    fn fetch(&self, url: &Url, range: Option<&ByteRange>, limit: u64) -> Result<Vec<u8>> {
        let mut request = self.input.request(&self.agent, url.as_str());
        if let Some(range) = range {
            let start = range.offset.unwrap_or(0);
            let end = start
                .checked_add(range.length.checked_sub(1).ok_or("无效的 HLS 字节范围")?)
                .ok_or("无效的 HLS 字节范围")?;
            request = request.header("Range", format!("bytes={start}-{end}"));
        }
        let response = request.call()?;
        if range.is_some() && response.status().as_u16() != 206 {
            return Err("HLS 服务器未接受字节范围".into());
        }
        read_limited(response.into_body().into_reader(), limit)
    }
}

fn read_limited(input: impl Read, limit: u64) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    input.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err("HLS 分段超出大小限制".into());
    }
    Ok(bytes)
}
