use crate::{compat::Source, playback::AudioSettings};
use std::{
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
type Property = unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_char;
type Free = unsafe extern "C" fn(*mut c_void);
type WaitEvent = unsafe extern "C" fn(*mut c_void, f64) -> *const Event;

const EVENT_NONE: c_int = 0;
const EVENT_END_FILE: c_int = 7;
const END_FILE_ERROR: c_int = 4;
const FORMAT_STRING: c_int = 1;
const FORMAT_NODE: c_int = 6;
const FORMAT_NODE_ARRAY: c_int = 7;

#[repr(C)]
struct Node {
    data: *const c_void,
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
}

pub struct Player {
    handle: NonNull<c_void>,
    destroy: Destroy,
    command: Command,
    property: Property,
    free: Free,
    wait_event: WaitEvent,
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
            let property = *library
                .get::<Property>(b"mpv_get_property_string\0")
                .map_err(symbol_error)?;
            let free = *library.get::<Free>(b"mpv_free\0").map_err(symbol_error)?;
            let wait_event = *library
                .get::<WaitEvent>(b"mpv_wait_event\0")
                .map_err(symbol_error)?;
            let handle = NonNull::new(create()).ok_or("无法创建 libmpv 播放器")?;
            let player = Self {
                handle,
                destroy,
                command,
                property,
                free,
                wait_event,
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
            if !source.proxy.is_empty() || source.lease.is_some() {
                let proxy = CString::new(source.proxy.as_str()).map_err(|_| "代理地址无效")?;
                let status = option(handle.as_ptr(), c"http-proxy".as_ptr(), proxy.as_ptr());
                if status < 0 {
                    return Err(format!("libmpv 设置播放代理失败 ({status})"));
                }
            }
            if source.lease.is_some() {
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
            if source.url.starts_with("rtp:") {
                let status = option(
                    handle.as_ptr(),
                    c"demuxer-lavf-format".as_ptr(),
                    c"mpegts".as_ptr(),
                );
                if status < 0 {
                    return Err(format!("libmpv 配置 RTP 播放失败 ({status})"));
                }
            }
            if !source.headers.is_empty() {
                let headers = source
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
                        data: text.as_ptr().cast(),
                        format: FORMAT_STRING,
                    })
                    .collect();
                let list = NodeList {
                    count: nodes.len() as c_int,
                    values: nodes.as_ptr(),
                    keys: null(),
                };
                let node = Node {
                    data: (&raw const list).cast(),
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
            let source = CString::new(source.url.as_str()).map_err(|_| "播放地址含有无效字符")?;
            let args = [c"loadfile".as_ptr(), source.as_ptr(), null()];
            let status = (player.command)(handle.as_ptr(), args.as_ptr());
            if status < 0 {
                return Err(format!("libmpv 打开播放源失败 ({status})"));
            }
            Ok(player)
        }
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

    pub fn chat_overlay(&self, text: &str) -> bool {
        if text.is_empty() {
            return self.run(&[c"osd-overlay", c"1", c"none", c""]) >= 0;
        }
        CString::new(text).is_ok_and(|text| {
            self.run(&[c"osd-overlay", c"1", c"ass-events", &text, c"1280", c"720"]) >= 0
        })
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

    pub fn playback_error(&mut self) -> Option<c_int> {
        // mpv retains event memory until the next wait. Read the reason immediately.
        unsafe {
            loop {
                let event = (self.wait_event)(self.handle.as_ptr(), 0.0).as_ref()?;
                if event.id == EVENT_NONE {
                    return None;
                }
                if event.id == EVENT_END_FILE {
                    if let Some(end) = event.data.cast::<EndFile>().as_ref() {
                        if end.reason == END_FILE_ERROR {
                            return Some(end.error);
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
