use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Read, Write},
    os::windows::process::CommandExt,
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

fn bili_request(message: &serde_json::Value) -> bool {
    if message["platform"] == "bilibili" {
        return true;
    }
    message["action"] == "status"
        && message["rooms"].as_array().is_some_and(|rooms| {
            !rooms.is_empty() && rooms.iter().all(|room| room["platform"] == "bilibili")
        })
}

fn configure_network(command: &mut Command, message: &serde_json::Value) {
    if bili_request(message) {
        // Scope this to the Bilibili helper, preserving proxies for other sites
        // and never changing the parent process or the user's system settings.
        for key in [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy",
        ] {
            command.env_remove(key);
        }
    }
}

fn launch(directory: &Path, message: serde_json::Value) -> Result<(ChildStdout, Bridge), String> {
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let mut command = Command::new(directory.join("purelive-platforms.exe"));
    configure_network(&mut command, &message);
    let child = command
        .creation_flags(CREATE_NO_WINDOW)
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
    // A mixed batch must not force overseas sites off their configured proxy,
    // or make Bilibili inherit it. Keep successful results if either batch fails.
    let (bili, other): (Vec<_>, Vec<_>) = rooms
        .iter()
        .cloned()
        .partition(|room| room.platform == "bilibili");
    if !bili.is_empty() && !other.is_empty() {
        return thread::scope(|scope| {
            let bili = scope.spawn(|| room_statuses(directory, &bili, cookies));
            let other = room_statuses(directory, &other, cookies);
            let bili = bili.join().unwrap_or_else(|_| Err("B 站状态查询中断".into()));
            match (bili, other) {
                (Ok(mut bili), Ok(other)) => {
                    bili.extend(other);
                    Ok(bili)
                }
                (Ok(rooms), Err(_)) | (Err(_), Ok(rooms)) => Ok(rooms),
                (Err(error), Err(_)) => Err(error),
            }
        });
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn bili_network_policy_is_scoped_to_one_platform() {
        for action in ["find", "play", "chat", "super_chat"] {
            let mut command = Command::new("helper.exe");
            configure_network(&mut command, &json!({"action": action, "platform": "bilibili"}));
            assert!(command.get_envs().any(|(key, value)| key == "HTTPS_PROXY" && value.is_none()));
        }
        for platform in ["douyu", "twitch", "all", ""] {
            let mut command = Command::new("helper.exe");
            configure_network(&mut command, &json!({"action": "find", "platform": platform}));
            assert_eq!(command.get_envs().count(), 0);
        }
    }

    #[test]
    fn bili_status_routing_requires_a_nonempty_homogeneous_batch() {
        let bili = json!({"platform": "bilibili", "id": "1"});
        let twitch = json!({"platform": "twitch", "id": "channel"});
        assert!(bili_request(&json!({"action": "status", "rooms": [bili.clone()]})));
        assert!(!bili_request(&json!({"action": "status", "rooms": [bili, twitch]})));
        assert!(!bili_request(&json!({"action": "status", "rooms": []})));
    }
}
