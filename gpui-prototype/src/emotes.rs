use std::{
    collections::{BTreeMap, HashSet, VecDeque},
    io::Cursor,
    sync::{Arc, OnceLock},
    time::Duration,
};

use serde::Deserialize;
use unicode_width::UnicodeWidthStr;

const MAX_IMAGES_PER_MESSAGE: usize = 3;
const MAX_CACHE_ENTRIES: usize = 80;
const MAX_PENDING: usize = 4;
const IMAGE_SIDE: u32 = 48;
pub const EMOTE_WIDTH: i32 = 32;

type Index = BTreeMap<String, [usize; 2]>;

struct Catalog {
    index: OnceLock<Index>,
    manifest: &'static str,
    images: &'static [u8],
}

impl Catalog {
    const fn new(manifest: &'static str, images: &'static [u8]) -> Self {
        Self {
            index: OnceLock::new(),
            manifest,
            images,
        }
    }

    fn find(&self, text: &str) -> Option<(&str, &[u8])> {
        let index = self
            .index
            .get_or_init(|| serde_json::from_str(self.manifest).expect("embedded emoticon index"));
        let code = if text.starts_with('[') {
            let end = text.bytes().take(144).position(|byte| byte == b']')?;
            index.get_key_value(&text[..=end])
        } else if text.starts_with("/{") {
            index
                .range("/{".to_owned()..)
                .take_while(|(code, _)| code.starts_with("/{"))
                .filter(|(code, _)| text.starts_with(code.as_str()))
                .max_by_key(|(code, _)| code.len())
        } else {
            None
        };
        let (code, [start, length]) = code?;
        self.images
            .get(*start..start.checked_add(*length)?)
            .map(|bytes| (code.as_str(), bytes))
    }
}

fn catalog(platform: &str) -> Option<&'static Catalog> {
    static BILIBILI: Catalog = Catalog::new(
        include_str!("../assets/emotes/bilibili.json"),
        include_bytes!("../assets/emotes/bilibili.bin"),
    );
    static DOUYIN: Catalog = Catalog::new(
        include_str!("../assets/emotes/douyin.json"),
        include_bytes!("../assets/emotes/douyin.bin"),
    );
    static DOUYU: Catalog = Catalog::new(
        include_str!("../assets/emotes/douyu.json"),
        include_bytes!("../assets/emotes/douyu.bin"),
    );
    static HUYA: Catalog = Catalog::new(
        include_str!("../assets/emotes/huya.json"),
        include_bytes!("../assets/emotes/huya.bin"),
    );
    match platform {
        "bilibili" => Some(&BILIBILI),
        "douyin" => Some(&DOUYIN),
        "douyu" => Some(&DOUYU),
        "huya" => Some(&HUYA),
        _ => None,
    }
}

#[derive(Deserialize)]
pub struct RemoteEmote {
    pub code: String,
    pub url: String,
}

#[derive(Clone, PartialEq, Eq, Hash)]
pub enum Source {
    Local(&'static [u8]),
    Remote(String),
}

pub enum Segment {
    Text(String),
    Picture { source: Source, alt: String },
}

impl Segment {
    pub fn width(&self) -> i32 {
        match self {
            Self::Text(text) => UnicodeWidthStr::width(text.as_str()) as i32 * 15,
            Self::Picture { alt, .. } => {
                (EMOTE_WIDTH + 4).max(UnicodeWidthStr::width(alt.as_str()) as i32 * 15)
            }
        }
    }
}

pub fn segments(platform: &str, text: &str, remote: &[RemoteEmote]) -> Vec<Segment> {
    let text: String = text
        .chars()
        .filter(|ch| !ch.is_control())
        .take(90)
        .collect();
    let catalog = catalog(platform);
    let mut result = Vec::new();
    let mut plain_start = 0;
    let mut cursor = 0;
    let mut count = 0;
    while cursor < text.len() && count < MAX_IMAGES_PER_MESSAGE {
        let remaining = &text[cursor..];
        let local = catalog
            .and_then(|catalog| catalog.find(remaining))
            .map(|(code, bytes)| (code, Source::Local(bytes)));
        let remote = remote
            .iter()
            .take(12)
            .filter(|item| !item.code.is_empty() && remaining.starts_with(&item.code))
            .filter_map(|item| {
                trusted_url(platform, &item.url)
                    .map(|url| (item.code.as_str(), Source::Remote(url)))
            })
            .max_by_key(|(code, _)| code.len());
        let matched = match (local, remote) {
            (Some(local), Some(remote)) if remote.0.len() > local.0.len() => Some(remote),
            (Some(local), _) => Some(local),
            (None, remote) => remote,
        };
        if let Some((code, source)) = matched {
            if plain_start < cursor {
                result.push(Segment::Text(text[plain_start..cursor].to_owned()));
            }
            let alt = if code.starts_with("[表情") {
                "[表情]"
            } else {
                code
            }
            .to_owned();
            result.push(Segment::Picture { source, alt });
            cursor += code.len();
            plain_start = cursor;
            count += 1;
        } else {
            cursor += remaining.chars().next().expect("nonempty text").len_utf8();
        }
    }
    if plain_start < text.len() {
        result.push(Segment::Text(text[plain_start..].to_owned()));
    }
    result
}

fn trusted_url(platform: &str, value: &str) -> Option<String> {
    if value.len() > 2048 {
        return None;
    }
    let url = url::Url::parse(value).ok()?;
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
    {
        return None;
    }
    let host = url.host_str()?;
    let domains: &[&str] = match platform {
        "bilibili" => &["hdslb.com", "bilibili.com"],
        "douyin" => &[
            "douyinpic.com",
            "douyincdn.com",
            "byteimg.com",
            "bytecdn.cn",
        ],
        _ => return None,
    };
    domains
        .iter()
        .any(|domain| {
            host == *domain
                || host
                    .strip_suffix(domain)
                    .is_some_and(|prefix| prefix.ends_with('.'))
        })
        .then(|| url.into())
}

pub struct Bitmap {
    pub pixels: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

#[derive(Default)]
pub struct Cache {
    ready: VecDeque<(Source, Option<Arc<Bitmap>>)>,
    pending: HashSet<Source>,
}

impl Cache {
    pub fn get(&self, source: &Source) -> Option<&Arc<Bitmap>> {
        self.ready
            .iter()
            .find(|(key, _)| key == source)
            .and_then(|(_, bitmap)| bitmap.as_ref())
    }

    pub fn begin(&mut self, source: &Source) -> bool {
        self.pending.len() < MAX_PENDING
            && !self.ready.iter().any(|(key, _)| key == source)
            && self.pending.insert(source.clone())
    }

    pub fn finish(&mut self, source: Source, bitmap: Option<Bitmap>) {
        self.pending.remove(&source);
        if self.ready.len() == MAX_CACHE_ENTRIES {
            self.ready.pop_front();
        }
        self.ready.push_back((source, bitmap.map(Arc::new)));
    }
}

pub fn load(source: &Source) -> Option<Bitmap> {
    match source {
        Source::Local(bytes) => decode(bytes),
        Source::Remote(url) => {
            static CLIENT: OnceLock<ureq::Agent> = OnceLock::new();
            let client = CLIENT.get_or_init(|| {
                ureq::Agent::config_builder()
                    .timeout_global(Some(Duration::from_secs(4)))
                    .max_redirects(0)
                    .build()
                    .into()
            });
            let bytes = client
                .get(url)
                .call()
                .ok()?
                .body_mut()
                .with_config()
                .limit(512 * 1024)
                .read_to_vec()
                .ok()?;
            decode(&bytes)
        }
    }
}

fn decode(bytes: &[u8]) -> Option<Bitmap> {
    let mut reader = image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?;
    if !matches!(
        reader.format(),
        Some(
            image::ImageFormat::Png
                | image::ImageFormat::WebP
                | image::ImageFormat::Gif
                | image::ImageFormat::Jpeg
        )
    ) {
        return None;
    }
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(512);
    limits.max_image_height = Some(512);
    limits.max_alloc = Some(4 * 1024 * 1024);
    reader.limits(limits);
    let image = reader
        .decode()
        .ok()?
        .thumbnail(IMAGE_SIDE, IMAGE_SIDE)
        .into_rgba8();
    let (width, height) = image.dimensions();
    let mut pixels = image.into_raw();
    for pixel in pixels.chunks_exact_mut(4) {
        pixel.swap(0, 2);
        let alpha = u16::from(pixel[3]);
        for channel in &mut pixel[..3] {
            *channel = ((u16::from(*channel) * alpha + 127) / 255) as u8;
        }
    }
    Some(Bitmap {
        pixels,
        width,
        height,
    })
}

#[cfg(test)]
mod tests {
    use super::{Segment, load, segments, trusted_url};

    #[test]
    fn resolves_and_decodes_the_four_platforms_and_huya_aliases() {
        for (platform, code) in [
            ("bilibili", "[dog]"),
            ("douyin", "[微笑]"),
            ("douyu", "[梗比心]"),
            ("huya", "/{66"),
        ] {
            let parts = segments(platform, &format!("前{code}后"), &[]);
            assert_eq!(parts.len(), 3, "{platform}");
            let Segment::Picture { source, .. } = &parts[1] else {
                panic!("{platform}");
            };
            let bitmap = load(source).unwrap();
            assert!(bitmap.width <= 48 && bitmap.height <= 48);
        }
        assert!(matches!(
            segments("huya", "[666]", &[])[0],
            Segment::Picture { .. }
        ));
        assert!(matches!(
            segments("bilibili", "[不存在的表情]", &[])[0],
            Segment::Text(_)
        ));
    }

    #[test]
    fn remote_emotes_accept_only_the_platforms_image_hosts() {
        assert!(trusted_url("bilibili", "https://i0.hdslb.com/bfs/live/emote.png").is_some());
        assert!(trusted_url("douyin", "https://p3.douyinpic.com/example.webp").is_some());
        assert!(trusted_url("bilibili", "https://hdslb.com.example.com/emote.png").is_none());
        assert!(trusted_url("douyin", "http://p3.douyinpic.com/example.webp").is_none());
    }
}
