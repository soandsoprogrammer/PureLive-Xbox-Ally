use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Read, Write},
    path::Path,
    process::{Child, ChildStdout, Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use serde::Deserialize;

use crate::live::{Room, RoomKey, RoomStatus};

#[derive(Default)]
pub struct Source {
    pub url: String,
    pub headers: BTreeMap<String, String>,
    pub proxy: String,
    pub lease: Option<Bridge>,
    pub playback: Playback,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Choice {
    pub id: String,
    pub label: String,
}

#[derive(Default, Deserialize)]
#[serde(default)]
pub struct Playback {
    pub qualities: Vec<Choice>,
    pub quality: Option<String>,
    pub quality_label: Option<String>,
    pub lines: Vec<Choice>,
    pub line: Option<String>,
    pub chat: bool,
    pub super_chat: bool,
    pub super_chat_board: bool,
}

#[derive(Clone, Default)]
pub struct Selection {
    pub quality: Option<String>,
    pub line: Option<String>,
}

#[derive(Deserialize)]
pub struct ChatEvent {
    pub text: Option<String>,
    pub state: Option<String>,
    pub error: Option<String>,
    pub super_chat: Option<SuperChat>,
    #[serde(default)]
    pub emotes: Vec<crate::emotes::RemoteEmote>,
}

#[derive(Clone, Deserialize)]
pub struct SuperChat {
    pub id: String,
    pub user: String,
    pub text: String,
    pub price: String,
    pub time: String,
    pub start: i64,
    pub end: i64,
    pub estimated: bool,
    pub picture: bool,
}

impl SuperChat {
    pub fn same_event(&self, other: &Self) -> bool {
        if !self.id.is_empty() || !other.id.is_empty() {
            return self.id == other.id;
        }
        self.user == other.user
            && self.text == other.text
            && self.price == other.price
            && self.picture == other.picture
            && (self.start == other.start
                || ((self.estimated || other.estimated)
                    && self.start < other.end
                    && other.start < self.end))
    }
}

pub struct Chat {
    pub events: async_channel::Receiver<ChatEvent>,
    text_enabled: Arc<AtomicBool>,
    _child: Bridge,
}

impl Chat {
    pub fn set_text_enabled(&self, enabled: bool) {
        self.text_enabled.store(enabled, Ordering::Relaxed);
    }
}

pub struct Bridge(Option<Child>);

impl Drop for Bridge {
    fn drop(&mut self) {
        let Some(mut child) = self.0.take() else {
            return;
        };
        drop(child.stdin.take());
        // Closing stdin releases the relay. Reap off the UI thread and bound
        // cleanup if a stalled network connection keeps the helper alive.
        thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            while Instant::now() < deadline {
                match child.try_wait() {
                    Ok(Some(_)) => return,
                    Ok(None) => thread::sleep(Duration::from_millis(40)),
                    Err(_) => break,
                }
            }
            let _ = child.kill();
            let _ = child.wait();
        });
    }
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct Reply {
    error: Option<String>,
    rooms: Vec<Room>,
    room_statuses: Vec<RoomStatus>,
    url: String,
    headers: BTreeMap<String, String>,
    proxy: String,
    lease: bool,
    playback: Playback,
    super_chats: Vec<SuperChat>,
}

fn launch(directory: &Path, message: serde_json::Value) -> Result<(ChildStdout, Bridge), String> {
    let mut command = Command::new(directory.join(format!(
        "purelive-platforms{}",
        std::env::consts::EXE_SUFFIX
    )));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000);
    }
    let child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| "找不到直播平台兼容组件，请完整解压便携包".to_owned())?;
    let mut guard = Bridge(Some(child));
    let child = guard.0.as_mut().expect("new child");
    let input = child.stdin.as_mut().ok_or("无法打开平台组件输入")?;
    writeln!(input, "{message}").map_err(|_| "平台组件输入失败")?;
    let stdout = child.stdout.take().ok_or("无法读取平台组件输出")?;
    Ok((stdout, guard))
}

fn request(directory: &Path, message: serde_json::Value) -> Result<(Reply, Bridge), String> {
    let (stdout, guard) = launch(directory, message)?;
    let mut output = String::new();
    BufReader::new(stdout.take(2 * 1024 * 1024))
        .read_line(&mut output)
        .map_err(|_| "平台组件响应中断")?;
    let reply: Reply = serde_json::from_str(&output).map_err(|_| "平台组件响应无效")?;
    if let Some(error) = reply.error {
        return Err(error);
    }
    Ok((reply, guard))
}

pub fn find(
    directory: &Path,
    platform: &str,
    query: &str,
    cookie: Option<&str>,
) -> Result<Vec<Room>, String> {
    let (reply, _) = request(
        directory,
        serde_json::json!({
            "action": "find", "platform": platform, "query": query, "account_cookie": cookie,
        }),
    )?;
    Ok(reply.rooms)
}

pub fn room_statuses(
    directory: &Path,
    rooms: &[RoomKey],
    cookies: &BTreeMap<String, String>,
) -> Result<Vec<RoomStatus>, String> {
    let (reply, _) = request(
        directory,
        serde_json::json!({
            "action": "status", "rooms": rooms, "account_cookies": cookies,
        }),
    )?;
    Ok(reply.room_statuses)
}

pub fn resolve(
    directory: &Path,
    room: &Room,
    cookie: Option<&str>,
    selection: &Selection,
) -> Result<Source, String> {
    let (reply, guard) = request(
        directory,
        serde_json::json!({
            "action": "play", "platform": room.platform, "query": room.id, "account_cookie": cookie,
            "quality": selection.quality, "line": selection.line,
        }),
    )?;
    if reply.url.is_empty() {
        return Err("平台没有返回可用线路".into());
    }
    Ok(Source {
        url: reply.url,
        headers: reply.headers,
        proxy: reply.proxy,
        lease: reply.lease.then_some(guard),
        playback: reply.playback,
    })
}

pub fn chat(
    directory: &Path,
    room: &Room,
    cookie: Option<&str>,
    text_enabled: bool,
) -> Result<Chat, String> {
    let (stdout, child) = launch(
        directory,
        serde_json::json!({
            "action": "chat", "platform": room.platform, "query": room.id, "account_cookie": cookie,
        }),
    )?;
    let (sender, events) = async_channel::bounded(32);
    let text_enabled = Arc::new(AtomicBool::new(text_enabled));
    let receive_text = text_enabled.clone();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if let Ok(event) = serde_json::from_str::<ChatEvent>(&line) {
                if event.state.is_some() || event.error.is_some() || event.super_chat.is_some() {
                    // State and SC must still arrive if regular chat fills the queue.
                    if sender.send_blocking(event).is_err() {
                        break;
                    }
                } else if event.text.is_some()
                    && receive_text.load(Ordering::Relaxed)
                    && let Err(async_channel::TrySendError::Closed(_)) = sender.try_send(event)
                {
                    break;
                }
            }
        }
    });
    Ok(Chat {
        events,
        text_enabled,
        _child: child,
    })
}

pub fn super_chats(
    directory: &Path,
    room: &Room,
    cookie: Option<&str>,
) -> Result<Vec<SuperChat>, String> {
    let (reply, _) = request(
        directory,
        serde_json::json!({
            "action": "super_chat", "platform": room.platform, "query": room.id, "account_cookie": cookie,
        }),
    )?;
    Ok(reply.super_chats)
}
