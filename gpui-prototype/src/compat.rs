use std::{
    collections::BTreeMap,
    io::{BufRead, BufReader, Read, Write},
    path::Path,
    process::{Child, ChildStdout, Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
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
    lease: bool,
    playback: Playback,
    super_chats: Vec<SuperChat>,
}

fn configure_network(command: &mut Command) {
    // Keep all helper connections direct without changing the parent's environment.
    for key in [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
    ] {
        command.env_remove(key);
    }
    command.env("NO_PROXY", "*").env("no_proxy", "*");
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
    configure_network(&mut command);
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
    let timeout = reply_timeout(&message);
    let (stdout, guard) = launch(directory, message)?;
    // On timeout, dropping the bridge closes stdin and reaps the helper. That
    // also releases the pipe reader even if the child never wrote a response.
    let output = read_reply(stdout, timeout)?;
    let reply: Reply = serde_json::from_str(&output).map_err(|_| "平台组件响应无效")?;
    if let Some(error) = reply.error {
        return Err(error);
    }
    Ok((reply, guard))
}

fn reply_timeout(message: &serde_json::Value) -> Duration {
    let seconds = if message["action"] == "status" {
        // The helper checks four rooms concurrently, with a five-second limit
        // per room. Allow large follow lists longer than a single-room request.
        message["rooms"]
            .as_array()
            .map_or(0, Vec::len)
            .div_ceil(4)
            .saturating_mul(5)
            .saturating_add(15)
            .clamp(40, 300)
    } else {
        40
    };
    Duration::from_secs(seconds as u64)
}

fn read_reply(reader: impl Read + Send + 'static, timeout: Duration) -> Result<String, String> {
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::Builder::new()
        .name("platform-reply".into())
        .spawn(move || {
            let mut output = String::new();
            let result = BufReader::new(reader.take(2 * 1024 * 1024))
                .read_line(&mut output)
                .map(|_| output)
                .map_err(|_| "平台组件响应中断".to_owned());
            let _ = sender.send(result);
        })
        .map_err(|_| "无法启动平台响应读取".to_owned())?;
    receiver
        .recv_timeout(timeout)
        .map_err(|error| match error {
            mpsc::RecvTimeoutError::Timeout => "平台响应超时，请重试".to_owned(),
            mpsc::RecvTimeoutError::Disconnected => "平台组件响应中断".to_owned(),
        })?
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

pub fn popular_page(
    directory: &Path,
    platform: &str,
    page: u32,
    cookie: Option<&str>,
) -> Result<Vec<Room>, String> {
    let (reply, _) = request(
        directory,
        serde_json::json!({
            "action": "find", "platform": platform, "query": "", "page": page,
            "account_cookie": cookie,
        }),
    )?;
    Ok(reply.rooms)
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

    #[test]
    fn stalled_helper_reply_times_out_instead_of_hanging() {
        struct Stalled(mpsc::Receiver<()>);
        impl Read for Stalled {
            fn read(&mut self, _: &mut [u8]) -> std::io::Result<usize> {
                let _ = self.0.recv();
                Ok(0)
            }
        }
        let (release, wait) = mpsc::channel();
        let result = read_reply(Stalled(wait), Duration::from_millis(20));
        let _ = release.send(());
        assert_eq!(result.unwrap_err(), "平台响应超时，请重试");
    }

    #[test]
    fn helper_reply_keeps_the_first_complete_line() {
        let reply = read_reply(
            std::io::Cursor::new(b"{\"rooms\":[]}\nignored"),
            Duration::from_secs(2),
        );
        assert_eq!(reply.unwrap(), "{\"rooms\":[]}\n");
    }

    #[test]
    fn status_reply_budget_scales_with_follow_count_but_is_bounded() {
        let rooms = vec![serde_json::json!({}); 80];
        assert_eq!(
            reply_timeout(&serde_json::json!({"action":"status", "rooms":rooms})),
            Duration::from_secs(115)
        );
        assert_eq!(
            reply_timeout(&serde_json::json!({"action":"play"})),
            Duration::from_secs(40)
        );
        let rooms = vec![serde_json::json!({}); 1000];
        assert_eq!(
            reply_timeout(&serde_json::json!({"action":"status", "rooms":rooms})),
            Duration::from_secs(300)
        );
    }

    #[test]
    fn network_helper_removes_proxies_and_disables_proxy_discovery() {
        let mut command = Command::new("helper.exe");
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            command.env(key, "http://127.0.0.1:9");
        }
        configure_network(&mut command);
        for expected in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            assert!(command.get_envs().any(|(key, value)| {
                key.to_string_lossy().eq_ignore_ascii_case(expected) && value.is_none()
            }));
        }
        assert!(command.get_envs().any(|(key, value)| {
            key.to_string_lossy().eq_ignore_ascii_case("NO_PROXY")
                && value == Some(std::ffi::OsStr::new("*"))
        }));
    }
}
