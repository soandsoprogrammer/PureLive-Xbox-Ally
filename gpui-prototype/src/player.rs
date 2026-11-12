use crate::{compat::Source, playback::AudioSettings};
use std::{
    collections::BTreeMap,
    ffi::{CStr, CString, c_char, c_int, c_void},
    path::Path,
    ptr::{NonNull, null},
};

type Create = unsafe extern "C" fn() -> *mut c_void;
type Initialize = unsafe extern "C" fn(*mut c_void) -> c_int;
type Destroy = unsafe extern "C" fn(*mut c_void);
type SetOption = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char) -> c_int;
type SetNode = unsafe extern "C" fn(*mut c_void, *const c_char, c_int, *const c_void) -> c_int;
type Command = unsafe extern "C" fn(*mut c_void, *const *const c_char) -> c_int;
type CommandRet = unsafe extern "C" fn(*mut c_void, *const *const c_char, *mut Node) -> c_int;
type FreeNode = unsafe extern "C" fn(*mut Node);
type Property = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_void);
type WaitEvent = unsafe extern "C" fn(*mut c_void, f64) -> *const Event;

const EVENT_NONE: c_int = 0;
const EVENT_END_FILE: c_int = 7;
const END_FILE_EOF: c_int = 0;
const END_FILE_ERROR: c_int = 4;
const FORMAT_STRING: c_int = 1;
const FORMAT_INT64: c_int = 4;
const FORMAT_NODE: c_int = 6;
const FORMAT_NODE_ARRAY: c_int = 7;
const FORMAT_NODE_MAP: c_int = 8;

#[repr(C)]
union NodeData {
    ptr: *const c_void,
    integer: i64,
}

#[repr(C)]
struct Node {
    data: NodeData,
    format: c_int,
}

#[repr(C)]
struct NodeList {
    count: c_int,
    values: *const Node,
    keys: *const *const c_char,
}

#[repr(C)]
struct Event {
    id: c_int,
    error: c_int,
    reply_userdata: u64,
    data: *const c_void,
}

#[repr(C)]
struct EndFile {
    reason: c_int,
    error: c_int,
    playlist_entry_id: i64,
}

pub enum PlaybackEnd {
    Error(c_int),
    Eof,
}

struct SourceOptions {
    headers: BTreeMap<String, String>,
    proxy: String,
    relayed: bool,
    rtp: bool,
}

impl SourceOptions {
    fn new(source: &Source) -> Self {
        Self {
            headers: source.headers.clone(),
            proxy: source.proxy.clone(),
            relayed: source.lease.is_some(),
            rtp: source.url.starts_with("rtp:"),
        }
    }

    fn can_reload(&self, source: &Source) -> bool {
        // A relay owns the stream until mpv finishes closing it asynchronously.
        !self.relayed
            && source.lease.is_none()
            && self.rtp == source.url.starts_with("rtp:")
            && self.proxy == source.proxy
            && self.headers == source.headers
    }
}

pub struct Player {
    handle: NonNull<c_void>,
    destroy: Destroy,
    command: Command,
    command_ret: CommandRet,
    free_node: FreeNode,
    property: Property,
    free: Free,
    wait_event: WaitEvent,
    source_options: SourceOptions,
    first_entry_id: Option<i64>,
    _library: libloading::Library,
}

impl Player {
    pub fn start(
        directory: &Path,
        window: usize,
        source: &Source,
        vsync: bool,
        paused: bool,
        audio: AudioSettings,
    ) -> Result<Self, String> {
        // Use the bundled DLL beside the executable. Retain it until the mpv handle is destroyed.
        let library = unsafe { libloading::Library::new(directory.join("libmpv-2.dll")) }
            .map_err(|err| format!("无法加载 libmpv-2.dll：{err}"))?;
        // The function signatures match mpv/client.h from the bundled libmpv.
        unsafe {
            let create = *library
                .get::<Create>(b"mpv_create\0")
                .map_err(symbol_error)?;
            let init = *library
                .get::<Initialize>(b"mpv_initialize\0")
                .map_err(symbol_error)?;
            let option = *library
                .get::<SetOption>(b"mpv_set_option_string\0")
                .map_err(symbol_error)?;
            let destroy = *library
                .get::<Destroy>(b"mpv_terminate_destroy\0")
                .map_err(symbol_error)?;
            let command = *library
                .get::<Command>(b"mpv_command\0")
                .map_err(symbol_error)?;
            let command_ret = *library
                .get::<CommandRet>(b"mpv_command_ret\0")
                .map_err(symbol_error)?;
            let free_node = *library
                .get::<FreeNode>(b"mpv_free_node_contents\0")
                .map_err(symbol_error)?;
            let property = *library
                .get::<Property>(b"mpv_get_property_string\0")
                .map_err(symbol_error)?;
            let free = *library.get::<Free>(b"mpv_free\0").map_err(symbol_error)?;
            let wait_event = *library
                .get::<WaitEvent>(b"mpv_wait_event\0")
                .map_err(symbol_error)?;
            let handle = NonNull::new(create()).ok_or("无法创建 libmpv 播放器")?;
            let mut player = Self {
                handle,
                destroy,
                command,
                command_ret,
                free_node,
                property,
                free,
                wait_event,
                source_options: SourceOptions::new(source),
                first_entry_id: None,
                _library: library,
            };
            let window = CString::new(window.to_string()).expect("numeric HWND");
            let volume = CString::new(audio.volume.to_string()).expect("numeric volume");
            let options = [
                (c"config", c"no"),
                (c"wid", &window),
                (c"vo", c"gpu"),
                (c"gpu-api", c"d3d11"),
                (c"gpu-context", c"d3d11"),
                (c"d3d11-sync-interval", if vsync { c"1" } else { c"0" }),
                (c"hwdec", c"auto-safe"),
                (c"pause", if paused { c"yes" } else { c"no" }),
                (c"volume", &volume),
                (c"mute", if audio.muted { c"yes" } else { c"no" }),
            ];
            for (key, value) in options {
                let status = option(handle.as_ptr(), key.as_ptr(), value.as_ptr());
                if status < 0 {
                    return Err(format!(
                        "libmpv 设置 {} 失败 ({status})",
                        key.to_string_lossy()
                    ));
                }
            }
            let source_options = &player.source_options;
            if !source_options.proxy.is_empty() || source_options.relayed {
                let proxy =
                    CString::new(source_options.proxy.as_str()).map_err(|_| "代理地址无效")?;
                let status = option(handle.as_ptr(), c"http-proxy".as_ptr(), proxy.as_ptr());
                if status < 0 {
                    return Err(format!("libmpv 设置播放代理失败 ({status})"));
                }
            }
            if source_options.relayed {
                // The loopback relay rewrites HLS resource paths. Let FFmpeg
                // probe their types while keeping its network protocol list narrow.
                let settings = c"allowed_extensions=ALL,allowed_segment_extensions=ALL,extension_picky=0,protocol_whitelist=[http,https,httpproxy,tcp,tls,crypto]";
                let status = option(
                    handle.as_ptr(),
                    c"demuxer-lavf-o".as_ptr(),
                    settings.as_ptr(),
                );
                if status < 0 {
                    return Err(format!("libmpv 配置播放中继失败 ({status})"));
                }
            }
            if source_options.rtp {
                let status = option(
                    handle.as_ptr(),
                    c"demuxer-lavf-format".as_ptr(),
                    c"mpegts".as_ptr(),
                );
                if status < 0 {
                    return Err(format!("libmpv 配置 RTP 播放失败 ({status})"));
                }
            }
            if !source_options.headers.is_empty() {
                let headers = source_options
                    .headers
                    .iter()
                    .filter(|(key, value)| {
                        !key.contains(['\r', '\n', ':']) && !value.contains(['\r', '\n'])
                    })
                    .map(|(key, value)| CString::new(format!("{key}: {value}")))
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|_| "播放请求头无效")?;
                let nodes: Vec<_> = headers
                    .iter()
                    .map(|text| Node {
                        data: NodeData {
                            ptr: text.as_ptr().cast(),
                        },
                        format: FORMAT_STRING,
                    })
                    .collect();
                let list = NodeList {
                    count: nodes.len() as c_int,
                    values: nodes.as_ptr(),
                    keys: null(),
                };
                let node = Node {
                    data: NodeData {
                        ptr: (&raw const list).cast(),
                    },
                    format: FORMAT_NODE_ARRAY,
                };
                let set_node = *player
                    ._library
                    .get::<SetNode>(b"mpv_set_option\0")
                    .map_err(symbol_error)?;
                let status = set_node(
                    handle.as_ptr(),
                    c"http-header-fields".as_ptr(),
                    FORMAT_NODE,
                    (&raw const node).cast(),
                );
                if status < 0 {
                    return Err(format!("libmpv 设置播放请求头失败 ({status})"));
                }
            }
            let status = init(handle.as_ptr());
            if status < 0 {
                return Err(format!("libmpv 初始化失败 ({status})"));
            }
            player.load(&source.url)?;
            Ok(player)
        }
    }

    pub fn try_reload(&mut self, source: &Source) -> bool {
        // Older mpv builds may omit the playlist entry ID in the command result.
        self.first_entry_id.is_some()
            && self.source_options.can_reload(source)
            && self.load(&source.url).is_ok()
    }

    fn load(&mut self, url: &str) -> Result<(), String> {
        let url = CString::new(url).map_err(|_| "播放地址含有无效字符")?;
        let args = [
            c"loadfile".as_ptr(),
            url.as_ptr(),
            c"replace".as_ptr(),
            null(),
        ];
        let mut result = Node {
            data: NodeData { ptr: null() },
            format: 0,
        };
        unsafe {
            let status = (self.command_ret)(self.handle.as_ptr(), args.as_ptr(), &mut result);
            if status < 0 {
                return Err(format!("libmpv 打开播放源失败 ({status})"));
            }
            self.first_entry_id = None;
            if result.format == FORMAT_NODE_MAP {
                let entries = &*result.data.ptr.cast::<NodeList>();
                for index in 0..entries.count as usize {
                    let value = &*entries.values.add(index);
                    if value.format == FORMAT_INT64
                        && CStr::from_ptr(*entries.keys.add(index)) == c"playlist_entry_id"
                    {
                        self.first_entry_id = Some(value.data.integer);
                        break;
                    }
                }
            }
            (self.free_node)(&mut result);
        }
        Ok(())
    }

    pub fn property(&self, name: &CStr) -> Option<String> {
        // mpv owns the allocation until mpv_free. Copy the value before freeing it.
        unsafe {
            let value = NonNull::new((self.property)(self.handle.as_ptr(), name.as_ptr()))?;
            let text = CStr::from_ptr(value.as_ptr())
                .to_string_lossy()
                .into_owned();
            (self.free)(value.as_ptr().cast());
            Some(text)
        }
    }

    fn run(&self, args: &[&CStr]) -> c_int {
        let args: Vec<_> = args
            .iter()
            .map(|arg| arg.as_ptr())
            .chain([null()])
            .collect();
        unsafe { (self.command)(self.handle.as_ptr(), args.as_ptr()) }
    }

    pub fn set_paused(&self, paused: bool) -> Result<(), String> {
        let status = self.run(&[c"set", c"pause", if paused { c"yes" } else { c"no" }]);
        if status < 0 {
            return Err(format!("切换播放状态失败（mpv {status}）"));
        }
        Ok(())
    }

    pub fn set_volume(&self, volume: u8) -> Result<(), String> {
        let volume = CString::new(volume.to_string()).expect("numeric volume");
        self.set_audio_property(c"volume", &volume)
    }

    pub fn set_muted(&self, muted: bool) -> Result<(), String> {
        self.set_audio_property(c"mute", if muted { c"yes" } else { c"no" })
    }

    fn set_audio_property(&self, name: &CStr, value: &CStr) -> Result<(), String> {
        let status = self.run(&[c"set", name, value]);
        if status < 0 {
            return Err(format!("设置音量失败（mpv {status}）"));
        }
        Ok(())
    }

    /// Draws [text] (ASS events) over the video as overlay [id], rasterised at [size]
    /// pixels; the overlay is only then scaled with the video, so passing the video's
    /// own size keeps the text sharp instead of upscaling it from 720p.
    pub fn chat_overlay(&self, id: u32, text: &str, size: (u32, u32)) -> bool {
        let id = CString::new(id.to_string()).expect("numeric overlay id");
        if text.is_empty() {
            return self.run(&[c"osd-overlay", &id, c"none", c""]) >= 0;
        }
        let Ok(text) = CString::new(text) else {
            return false;
        };
        let width = CString::new(size.0.to_string()).expect("numeric OSD width");
        let height = CString::new(size.1.to_string()).expect("numeric OSD height");
        self.run(&[c"osd-overlay", &id, c"ass-events", &text, &width, &height]) >= 0
    }

    /// Shows a short centred message over the video (mpv `show-text`), used for
    /// "3/6 神棍老师" after switching rooms with the bumpers.
    pub fn show_text(&self, text: &str, duration_ms: u32) -> bool {
        let Ok(text) = CString::new(text) else {
            return false;
        };
        let duration = CString::new(duration_ms.to_string()).expect("numeric duration");
        self.run(&[c"show-text", &text, &duration]) >= 0
    }

    pub fn osd_size(&self) -> Option<(f32, f32)> {
        let width = self.property(c"osd-width")?.parse::<u32>().ok()?;
        let height = self.property(c"osd-height")?.parse::<u32>().ok()?;
        (width > 0 && height > 0).then_some((width as f32, height as f32))
    }

    pub fn emote_overlay(
        &self,
        id: u8,
        position: (i32, i32),
        size: (u32, u32),
        bitmap: &crate::emotes::Bitmap,
    ) -> bool {
        let stride = bitmap.width as usize * 4;
        if id >= 64 || stride * bitmap.height as usize != bitmap.pixels.len() {
            return false;
        }
        // The bundled mpv copies the validated BGRA slice before this synchronous call returns.
        let args = [
            id.to_string(),
            position.0.to_string(),
            position.1.to_string(),
            format!("&{}", bitmap.pixels.as_ptr() as usize),
            "0".into(),
            "bgra".into(),
            bitmap.width.to_string(),
            bitmap.height.to_string(),
            stride.to_string(),
            size.0.to_string(),
            size.1.to_string(),
        ]
        .map(|arg| CString::new(arg).expect("overlay argument"));
        let mut command = [c"overlay-add"; 12];
        for (slot, arg) in command[1..].iter_mut().zip(&args) {
            *slot = arg;
        }
        self.run(&command) >= 0
    }

    pub fn remove_emote(&self, id: u8) {
        let id = CString::new(id.to_string()).expect("numeric overlay id");
        self.run(&[c"overlay-remove", &id]);
    }

    pub fn stats(&self) -> String {
        let hardware = self
            .property(c"hwdec-current")
            .unwrap_or_else(|| "—".into());
        let dropped = self
            .property(c"frame-drop-count")
            .unwrap_or_else(|| "—".into());
        let time = self.property(c"time-pos").unwrap_or_else(|| "—".into());
        format!("硬解 {hardware}    掉帧 {dropped}    进度 {time} s")
    }

    pub fn playback_end(&mut self, track_eof: bool) -> Option<PlaybackEnd> {
        // mpv retains event memory until the next wait. Read the reason immediately.
        unsafe {
            loop {
                let event = (self.wait_event)(self.handle.as_ptr(), 0.0).as_ref()?;
                if event.id == EVENT_NONE {
                    return None;
                }
                if event.id == EVENT_END_FILE {
                    if let Some(end) = event.data.cast::<EndFile>().as_ref() {
                        // A replacement can leave end events for the previous source queued.
                        if self
                            .first_entry_id
                            .is_none_or(|id| end.playlist_entry_id >= id)
                        {
                            match end.reason {
                                END_FILE_ERROR => return Some(PlaybackEnd::Error(end.error)),
                                END_FILE_EOF if track_eof => return Some(PlaybackEnd::Eof),
                                _ => {}
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn display_stats(&self) -> String {
        [
            c"container-fps",
            c"display-fps",
            c"estimated-display-fps",
            c"decoder-frame-drop-count",
        ]
        .into_iter()
        .map(|key| {
            format!(
                "{}={}",
                key.to_string_lossy(),
                self.property(key).unwrap_or_else(|| "—".into())
            )
        })
        .collect::<Vec<_>>()
        .join(" ")
    }
}

fn symbol_error(err: libloading::Error) -> String {
    format!("libmpv 接口加载失败：{err}")
}

impl Drop for Player {
    fn drop(&mut self) {
        // Terminate video output before the owner destroys the native surface.
        unsafe { (self.destroy)(self.handle.as_ptr()) };
    }
}
