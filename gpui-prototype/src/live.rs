use std::{collections::BTreeMap, fs, path::Path, time::Duration};

use crate::compat::{self, Source};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use url::Url;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BroadcastStatus {
    #[default]
    Unknown,
    Live,
    Offline,
    Replay,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FollowFilter {
    #[default]
    Live,
    All,
    Offline,
}

impl FollowFilter {
    pub const TABS: [Self; 3] = [Self::Live, Self::All, Self::Offline];

    pub fn label(self) -> &'static str {
        match self {
            Self::Live => "已开播",
            Self::All => "全部",
            Self::Offline => "未开播",
        }
    }

    pub fn includes(self, status: BroadcastStatus) -> bool {
        match self {
            Self::Live => status == BroadcastStatus::Live,
            Self::All => true,
            Self::Offline => matches!(status, BroadcastStatus::Offline | BroadcastStatus::Replay),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct RoomKey {
    pub platform: String,
    pub id: String,
}

#[derive(Deserialize)]
pub struct RoomStatus {
    #[serde(flatten)]
    pub key: RoomKey,
    pub status: BroadcastStatus,
    #[serde(default)]
    pub cover: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Room {
    #[serde(deserialize_with = "room_key")]
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub nick: String,
    #[serde(default)]
    pub watching: String,
    #[serde(default, skip_serializing)]
    pub live: bool,
    #[serde(default, skip_serializing)]
    pub broadcast: Option<BroadcastStatus>,
    #[serde(default = "bilibili")]
    pub platform: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub headers: BTreeMap<String, String>,
}

fn bilibili() -> String {
    "bilibili".into()
}

fn room_key<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Id {
        Text(String),
        Number(u64),
    }
    Ok(match Id::deserialize(deserializer)? {
        Id::Text(id) => id,
        Id::Number(id) => id.to_string(),
    })
}

impl Room {
    pub fn bili(id: u64, title: String) -> Self {
        Self {
            id: id.to_string(),
            title,
            cover: String::new(),
            nick: String::new(),
            watching: String::new(),
            live: false,
            broadcast: None,
            platform: bilibili(),
            headers: BTreeMap::new(),
        }
    }

    pub fn same_channel(&self, other: &Self) -> bool {
        self.platform == other.platform && self.id == other.id
    }

    pub fn key(&self) -> RoomKey {
        RoomKey {
            platform: self.platform.clone(),
            id: self.id.clone(),
        }
    }

    pub fn broadcast_status(&self) -> BroadcastStatus {
        self.broadcast.unwrap_or(if self.live {
            BroadcastStatus::Live
        } else {
            BroadcastStatus::Unknown
        })
    }

    pub fn update_broadcast_status(&mut self, status: BroadcastStatus) -> bool {
        if status == BroadcastStatus::Unknown {
            return false;
        }
        let changed = self.broadcast_status() != status;
        self.broadcast = Some(status);
        changed
    }

    pub fn update_room_status(&mut self, status: &RoomStatus) -> bool {
        let mut changed = self.update_broadcast_status(status.status);
        if status.status != BroadcastStatus::Unknown
            && let Some(cover) = status.cover.as_ref().filter(|cover| !cover.is_empty())
            && self.cover != *cover
        {
            self.cover = cover.clone();
            changed = true;
        }
        changed
    }

    pub fn is_playback_candidate(&self, include_unknown: bool) -> bool {
        match self.broadcast_status() {
            BroadcastStatus::Live => true,
            BroadcastStatus::Unknown => include_unknown,
            BroadcastStatus::Offline | BroadcastStatus::Replay => false,
        }
    }
}

/// Follow the displayed order, wrapping at either end and skipping known
/// unavailable rooms. Popular lists may omit live status, unlike checked follows.
pub fn next_room_index(
    rooms: &[Room],
    current: &RoomKey,
    forward: bool,
    include_unknown: bool,
) -> Option<usize> {
    if rooms.is_empty() {
        return None;
    }
    let matches_current = |room: &Room| room.platform == current.platform && room.id == current.id;
    let position = rooms.iter().position(matches_current);
    let start = position.unwrap_or(if forward { rooms.len() - 1 } else { 0 });
    (1..=rooms.len())
        .map(|step| {
            if forward {
                (start + step) % rooms.len()
            } else {
                (start + rooms.len() - step) % rooms.len()
            }
        })
        .find(|&index| {
            !matches_current(&rooms[index])
                && rooms[index].is_playback_candidate(include_unknown)
        })
}

#[derive(Deserialize)]
pub struct Platform {
    pub id: String,
    pub name: String,
}

pub fn platforms() -> Vec<Platform> {
    #[derive(Deserialize)]
    struct Catalog {
        sites: Vec<Platform>,
    }
    serde_json::from_str::<Catalog>(include_str!("platforms.json"))
        .expect("bundled platform catalog")
        .sites
}

fn request(endpoint: &str, params: &[(&str, &str)], cookie: Option<&str>) -> Result<Value, String> {
    let url = Url::parse_with_params(endpoint, params).map_err(|_| "直播接口地址无效")?;
    // Bilibili APIs use the same direct route as the native media downloader.
    // An inherited development-tool proxy may be unavailable or blocked by Bilibili.
    let config = ureq::Agent::config_builder()
        .proxy(None)
        .timeout_global(Some(Duration::from_secs(12)));
    let config = if cookie.is_some() {
        config.max_redirects(0)
    } else {
        config
    };
    let agent: ureq::Agent = config.build().into();
    let req = agent
        .get(url.as_str())
        .header("Referer", "https://live.bilibili.com/")
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PureLive/0.1",
        );
    let req = if let Some(cookie) = cookie {
        req.header("Cookie", cookie)
    } else {
        req
    };
    let result: Value = req
        .call()
        .map_err(|err| match err {
            ureq::Error::StatusCode(412) if endpoint.contains("/search/") => {
                "关键词搜索被平台限制（HTTP 412），可输入直播间链接或房间号".into()
            }
            ureq::Error::StatusCode(code) => format!("哔哩哔哩接口返回 HTTP {code}"),
            _ => "连接哔哩哔哩失败，请检查网络".into(),
        })?
        .body_mut()
        .read_json()
        .map_err(|_| "哔哩哔哩接口响应格式有误")?;
    match result["code"].as_i64() {
        Some(0) => Ok(result),
        Some(code) => Err(format!("哔哩哔哩接口返回 {code}")),
        None => Err("哔哩哔哩接口响应缺少状态".into()),
    }
}

pub fn account_name(cookie: &str) -> Result<String, String> {
    let response = request(
        "https://api.bilibili.com/x/web-interface/nav",
        &[],
        Some(cookie),
    )?;
    let data = &response["data"];
    if data["isLogin"].as_bool() != Some(true) {
        return Err("B 站还没有确认登录，请在网页完成登录后重试".into());
    }
    data["uname"]
        .as_str()
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| "未取得账号名称".into())
}

pub fn find(
    directory: &Path,
    platform: &str,
    input: &str,
    cookie: Option<&str>,
) -> Result<Vec<Room>, String> {
    let text = input.trim();
    if platform != "iptv" {
        let native_bili = (platform == "bilibili"
            && !text.contains("://")
            && !text.starts_with('@')
            && !text.is_empty())
            || (text.contains("://") && room_id(text).is_some());
        if native_bili {
            let cookie = if platform == "bilibili" { cookie } else { None };
            return find_bili(text, cookie).or_else(|error| {
                if error.contains("HTTP 412") {
                    compat::find(directory, "bilibili", text, cookie).map_err(|_| error)
                } else {
                    Err(error)
                }
            });
        }
    }
    compat::find(directory, platform, text, cookie)
}

fn find_bili(input: &str, cookie: Option<&str>) -> Result<Vec<Room>, String> {
    let input = input.trim();
    if let Some(id) = room_id(input) {
        let result = request(
            "https://api.live.bilibili.com/room/v1/Room/get_info",
            &[("room_id", &id.to_string())],
            cookie,
        )?;
        let data = &result["data"];
        let mut room = Room::bili(
            data["room_id"].as_u64().filter(|id| *id != 0).unwrap_or(id),
            data["title"].as_str().unwrap_or("哔哩哔哩直播间").into(),
        );
        room.cover = data["user_cover"]
            .as_str()
            .filter(|value| !value.is_empty())
            .or_else(|| data["keyframe"].as_str())
            .unwrap_or_default()
            .into();
        room.live = data["live_status"].as_u64() == Some(1);
        return Ok(vec![room]);
    }
    if input.is_empty() {
        return Err("输入关键词、房间号或 B 站直播间链接".into());
    }
    if input.contains("://") {
        return Err("请输入 B 站直播间链接。直播流直链可用 --stream 播放。".into());
    }
    let result = request(
        "https://api.bilibili.com/x/web-interface/search/type",
        &[("search_type", "live"), ("keyword", input), ("page", "1")],
        cookie,
    )?;
    let data = &result["data"]["result"];
    let entries = data["live_room"].as_array().or_else(|| data.as_array());
    Ok(entries
        .into_iter()
        .flatten()
        .filter_map(|row| {
            let id = row["roomid"]
                .as_u64()
                .or_else(|| row["roomid"].as_str()?.parse().ok())?;
            let title = row["title"]
                .as_str()?
                .replace("<em class=\"keyword\">", "")
                .replace("</em>", "");
            let mut room = Room::bili(id, title);
            room.cover = row["user_cover"]
                .as_str()
                .filter(|value| !value.is_empty())
                .or_else(|| row["cover"].as_str())
                .unwrap_or_default()
                .into();
            room.nick = row["uname"].as_str().unwrap_or_default().into();
            room.live = row["live_status"].as_u64() == Some(1);
            Some(room)
        })
        .take(20)
        .collect())
}

fn room_id(input: &str) -> Option<u64> {
    if let Ok(id) = input.parse::<u64>() {
        return (id > 0).then_some(id);
    }
    let url = Url::parse(input).ok()?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str()? != "live.bilibili.com" {
        return None;
    }
    url.path_segments()?
        .find_map(|part| part.parse::<u64>().ok().filter(|id| *id > 0))
}

pub fn resolve(
    directory: &Path,
    room: &Room,
    cookie: Option<&str>,
    selection: &compat::Selection,
) -> Result<Source, String> {
    if room.platform == "iptv" {
        if !Url::parse(&room.id).is_ok_and(|url| {
            matches!(
                url.scheme(),
                "http" | "https" | "rtmp" | "rtsp" | "rtp" | "udp" | "mms"
            )
        }) {
            return Err("IPTV 播放地址无效".into());
        }
        return Ok(Source {
            url: room.id.clone(),
            headers: room.headers.clone(),
            ..Source::default()
        });
    }
    if room.platform == "bilibili" {
        if let Ok((url, playback)) = resolve_bili(room, cookie, selection) {
            return Ok(Source {
                url,
                headers: BTreeMap::from([("referer".into(), "https://live.bilibili.com/".into())]),
                playback,
                ..Source::default()
            });
        }
    }
    compat::resolve(directory, room, cookie, selection)
}

pub struct FinishedReplay {
    id: Option<String>,
    end_ms: u64,
}

impl FinishedReplay {
    pub fn new(playback: &compat::Playback, end_ms: u64) -> Self {
        Self { id: playback.replay_id.clone(), end_ms }
    }

    fn can_play(&self, playback: &compat::Playback) -> bool {
        if self.id.is_none() || self.id != playback.replay_id {
            return true;
        }
        // One-video carousels can loop. Accept that video once the platform
        // reports a position back before its end (play_time is in whole seconds).
        playback.replay_start_ms.is_some_and(|start| {
            let tolerance = (self.end_ms / 3).min(1_000);
            (start.max(0) as u64).saturating_add(tolerance) < self.end_ms
        })
    }
}

#[cfg(test)]
#[test]
fn carousel_waits_for_a_new_video_or_a_loop() {
    let previous = compat::Playback { replay_id: Some("video/1".into()), ..Default::default() };
    let finished = FinishedReplay::new(&previous, 30_500);
    let mut source = compat::Playback {
        replay_id: previous.replay_id,
        replay_start_ms: Some(30_000),
        ..Default::default()
    };
    assert!(!finished.can_play(&source));
    source.replay_start_ms = Some(0);
    assert!(finished.can_play(&source));
    source.replay_start_ms = Some(30_000);
    source.replay_id = Some("video/2".into());
    assert!(finished.can_play(&source));
    assert!(finished.can_play(&compat::Playback::default()));
}

pub fn continue_carousel(
    directory: &Path,
    room: &Room,
    cookie: Option<&str>,
    finished: &FinishedReplay,
) -> Result<Source, String> {
    for delay in [0, 1, 2, 3] {
        if delay > 0 {
            std::thread::sleep(Duration::from_secs(delay));
        }
        // Discover the current video and its available lines again. The room
        // may also have gone live while the previous replay was playing.
        if let Ok(source) = resolve(directory, room, cookie, &compat::Selection::default())
            && finished.can_play(&source.playback)
        {
            return Ok(source);
        }
    }
    Err("暂未接到下一段回放，可刷新重试".into())
}

/// Resolve a Bilibili room ourselves so the player can offer every quality and
/// CDN line the room exposes, instead of a single hard-coded URL.
fn resolve_bili(
    room: &Room,
    cookie: Option<&str>,
    selection: &compat::Selection,
) -> Result<(String, compat::Playback), String> {
    let quality = selection
        .quality
        .as_deref()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(10_000);
    let qn = quality.to_string();
    let result = request(
        "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
        &[
            ("room_id", &room.id),
            ("protocol", "0,1"),
            ("format", "0,1,2"),
            ("codec", "0"),
            ("qn", qn.as_str()),
            ("platform", "web"),
            ("ptype", "8"),
        ],
        cookie,
    )?;
    bili_playback(&result, quality, selection)
}

fn bili_playback(
    result: &Value,
    quality: u64,
    selection: &compat::Selection,
) -> Result<(String, compat::Playback), String> {
    let play = &result["data"]["playurl_info"]["playurl"];
    let streams = play["stream"]
        .as_array()
        .ok_or_else(|| "直播间当前没有可用的播放线路".to_owned())?;
    let names: BTreeMap<String, String> = play["g_qn_desc"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            Some((
                entry["qn"].as_u64()?.to_string(),
                entry["desc"].as_str()?.to_owned(),
            ))
        })
        .collect();
    let label_for = |id: &str| {
        names.get(id).cloned().unwrap_or_else(|| match id {
            "10000" => "原画".into(),
            _ => format!("画质 {id}"),
        })
    };
    let mut qualities: Vec<compat::Choice> = Vec::new();
    let mut lines: Vec<compat::Choice> = Vec::new();
    let mut urls = Vec::new();
    for stream in streams {
        let protocol = stream["protocol_name"].as_str().unwrap_or("http_stream");
        for format in stream["format"].as_array().into_iter().flatten() {
            let name = format["format_name"].as_str().unwrap_or_default();
            for codec in format["codec"].as_array().into_iter().flatten() {
                let current = codec["current_qn"].as_u64().unwrap_or(quality);
                for qn in codec["accept_qn"].as_array().into_iter().flatten() {
                    let Some(qn) = qn.as_u64() else {
                        continue;
                    };
                    let id = qn.to_string();
                    if qualities.iter().any(|choice| choice.id == id) {
                        continue;
                    }
                    let label = label_for(&id);
                    qualities.push(compat::Choice { id, label });
                }
                for (index, info) in codec["url_info"].as_array().into_iter().flatten().enumerate()
                {
                    let (Some(host), Some(base), Some(extra)) = (
                        info["host"].as_str(),
                        codec["base_url"].as_str(),
                        info["extra"].as_str(),
                    ) else {
                        continue;
                    };
                    let video = match (protocol, name) {
                        ("http_stream", _) => "FLV".to_owned(),
                        ("http_hls", "fmp4") => "HLS fMP4".to_owned(),
                        ("http_hls", _) => "HLS TS".to_owned(),
                        _ => protocol.to_owned(),
                    };
                    let id = format!("{protocol}/{name}/{index}");
                    let label = format!("{video} 线路{}", index + 1);
                    lines.push(compat::Choice {
                        id: id.clone(),
                        label,
                    });
                    urls.push((id, format!("{host}{base}{extra}"), current));
                }
            }
        }
    }
    if urls.is_empty() {
        return Err("直播间当前没有可用的游客播放线路".into());
    }
    let chosen = selection
        .line
        .as_deref()
        .and_then(|id| urls.iter().find(|(line, _, _)| line == id))
        .or_else(|| urls.iter().find(|(line, _, _)| line.starts_with("http_stream/")))
        .unwrap_or(&urls[0]);
    let quality_id = chosen.2.to_string();
    let quality_label = label_for(&quality_id);
    if !qualities.iter().any(|choice| choice.id == quality_id) {
        qualities.push(compat::Choice {
            id: quality_id.clone(),
            label: quality_label.clone(),
        });
    }
    Ok((
        chosen.1.clone(),
        compat::Playback {
            carousel: result["data"]["live_status"] == 2 || result["data"]["live_status"] == "2",
            replay_id: None,
            replay_start_ms: None,
            qualities,
            quality: Some(quality_id),
            quality_label: Some(quality_label),
            lines,
            // Keep automatic selection distinct from the resolved playback URL.
            line: selection.line.as_ref().filter(|id| **id == chosen.0).cloned(),
            chat: true,
            super_chat: true,
            super_chat_board: true,
        },
    ))
}

pub fn load(path: &Path) -> Vec<Room> {
    let mut rooms: Vec<Room> = fs::read(path)
        .ok()
        .and_then(|data| serde_json::from_slice(&data).ok())
        .unwrap_or_default();
    for room in &mut rooms {
        room.live = false;
        room.broadcast = None;
    }
    rooms
}

pub fn save(path: &Path, rooms: &[Room]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let temp = path.with_extension("tmp");
    fs::write(
        &temp,
        serde_json::to_vec_pretty(rooms).map_err(|err| err.to_string())?,
    )
    .and_then(|_| fs::rename(temp, path))
    .map_err(|err| format!("关注保存失败：{err}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn room(id: u64, status: BroadcastStatus) -> Room {
        Room {
            broadcast: Some(status),
            ..Room::bili(id, String::new())
        }
    }

    #[test]
    fn popular_room_switching_preserves_order_wraps_and_skips_unavailable_rooms() {
        let rooms = vec![
            room(1, BroadcastStatus::Live),
            room(2, BroadcastStatus::Offline),
            room(3, BroadcastStatus::Unknown),
            room(4, BroadcastStatus::Replay),
            room(5, BroadcastStatus::Live),
        ];
        assert_eq!(next_room_index(&rooms, &rooms[0].key(), true, true), Some(2));
        assert_eq!(next_room_index(&rooms, &rooms[4].key(), false, true), Some(2));
        assert_eq!(next_room_index(&rooms, &rooms[4].key(), true, true), Some(0));
        assert_eq!(next_room_index(&rooms, &rooms[0].key(), false, true), Some(4));
        // A room going offline during playback must not reset our position.
        assert_eq!(next_room_index(&rooms, &rooms[1].key(), true, true), Some(2));
        // Follow switching still requires a confirmed live status.
        assert_eq!(next_room_index(&rooms, &rooms[0].key(), true, false), Some(4));
    }

    #[test]
    fn room_switching_handles_empty_single_and_missing_current_rooms() {
        let current = room(1, BroadcastStatus::Live);
        assert_eq!(next_room_index(&[], &current.key(), true, true), None);
        assert_eq!(next_room_index(std::slice::from_ref(&current), &current.key(), true, true), None);
        let rooms = vec![current.clone(), room(2, BroadcastStatus::Replay)];
        assert_eq!(next_room_index(&rooms, &current.key(), false, true), None);
        let rooms = vec![room(2, BroadcastStatus::Live), room(3, BroadcastStatus::Live)];
        assert_eq!(next_room_index(&rooms, &current.key(), true, true), Some(0));
        assert_eq!(next_room_index(&rooms, &current.key(), false, true), Some(1));
    }

    #[test]
    fn room_switching_uses_platform_and_id_for_identity() {
        let current = room(1, BroadcastStatus::Live);
        let other = Room {
            platform: "douyu".into(),
            ..current.clone()
        };
        let rooms = vec![current.clone(), other];
        assert_eq!(next_room_index(&rooms, &current.key(), true, true), Some(1));
    }

    #[test]
    fn follow_filters_keep_unknown_rooms_in_all_and_replays_out_of_live() {
        let statuses = [
            BroadcastStatus::Live,
            BroadcastStatus::Offline,
            BroadcastStatus::Replay,
            BroadcastStatus::Unknown,
        ];
        assert_eq!(
            statuses.map(|status| FollowFilter::Live.includes(status)),
            [true, false, false, false]
        );
        assert_eq!(
            statuses.map(|status| FollowFilter::All.includes(status)),
            [true; 4]
        );
        assert_eq!(
            statuses.map(|status| FollowFilter::Offline.includes(status)),
            [false, true, true, false]
        );
    }

    #[test]
    fn existing_numeric_follows_keep_bilibili_identity() {
        let saved: Room = serde_json::from_str(r#"{"id":123,"title":"已关注"}"#).unwrap();
        assert!(saved.same_channel(&Room::bili(123, "改名".into())));
        let other = Room {
            platform: "douyu".into(),
            ..saved.clone()
        };
        assert!(!saved.same_channel(&other));
    }

    #[test]
    fn catalog_has_distinct_entries_for_the_legacy_sites_and_iptv() {
        let sites = platforms();
        let ids: std::collections::BTreeSet<_> =
            sites.iter().map(|site| site.id.as_str()).collect();
        assert_eq!(sites.len(), 35);
        assert_eq!(ids.len(), 35);
        assert!(ids.contains("iptv"));
    }

    #[test]
    fn follows_round_trip_and_replace_existing_file() {
        let folder =
            std::env::temp_dir().join(format!("purelive-follows-test-{}", std::process::id()));
        let path = folder.join("follows.json");
        let room = Room::bili(123, "直播间".into());
        save(&path, std::slice::from_ref(&room)).expect("save first follow");
        assert_eq!(load(&path), vec![room]);
        save(&path, &[]).expect("replace follows");
        assert!(load(&path).is_empty());
        fs::remove_file(path).expect("remove test file");
        fs::remove_dir(folder).expect("remove test folder");
    }

    #[test]
    fn saved_live_status_is_ignored_until_the_platform_confirms_it() {
        let folder =
            std::env::temp_dir().join(format!("purelive-status-test-{}", std::process::id()));
        let path = folder.join("follows.json");
        fs::create_dir_all(&folder).expect("create test folder");
        fs::write(
            &path,
            r#"[{"id":"42","platform":"douyin","title":"旧关注","live":true}]"#,
        )
        .expect("write legacy follow");
        let mut rooms = load(&path);
        assert_eq!(rooms[0].id, "42");
        assert_eq!(rooms[0].broadcast_status(), BroadcastStatus::Unknown);
        rooms[0].live = true;
        rooms[0].broadcast = Some(BroadcastStatus::Offline);
        assert_eq!(rooms[0].broadcast_status(), BroadcastStatus::Offline);
        save(&path, &rooms).expect("save follow");
        let persisted = fs::read_to_string(&path).expect("read follow");
        assert!(!persisted.contains("\"live\""));
        assert!(!persisted.contains("\"broadcast\""));
        fs::remove_file(path).expect("remove test file");
        fs::remove_dir(folder).expect("remove test folder");
    }

    #[test]
    fn unknown_status_keeps_last_confirmed_broadcast_status() {
        let mut followed = room(42, BroadcastStatus::Unknown);
        assert!(!followed.update_broadcast_status(BroadcastStatus::Unknown));
        assert_eq!(followed.broadcast_status(), BroadcastStatus::Unknown);
        assert!(followed.update_broadcast_status(BroadcastStatus::Live));
        assert!(!followed.update_broadcast_status(BroadcastStatus::Unknown));
        assert!(followed.is_playback_candidate(false));
        assert!(followed.update_broadcast_status(BroadcastStatus::Offline));
        assert!(!followed.update_broadcast_status(BroadcastStatus::Unknown));
        assert_eq!(followed.broadcast_status(), BroadcastStatus::Offline);
    }

    #[test]
    fn room_refresh_updates_saved_covers_and_accepts_old_status_replies() {
        let mut followed = room(42, BroadcastStatus::Live);
        followed.cover = "https://liveimg.sooplive.com/m/123".into();
        let updated: RoomStatus = serde_json::from_value(serde_json::json!({
            "platform": "bilibili", "id": "42", "status": "live",
            "cover": "https://res.sooplive.com/images/thumb/live/0004_480x270_dark.png"
        })).unwrap();
        assert!(followed.update_room_status(&updated));
        assert_eq!(followed.cover, updated.cover.as_deref().unwrap());
        let old_reply: RoomStatus = serde_json::from_value(serde_json::json!({
            "platform": "bilibili", "id": "42", "status": "live"
        })).unwrap();
        assert!(!followed.update_room_status(&old_reply));
        let failed: RoomStatus = serde_json::from_value(serde_json::json!({
            "platform": "bilibili", "id": "42", "status": "unknown", "cover": "unconfirmed"
        })).unwrap();
        assert!(!followed.update_room_status(&failed));
        assert_eq!(followed.cover, updated.cover.as_deref().unwrap());
    }

    #[test]
    fn recognizes_only_bilibili_room_links() {
        assert_eq!(
            room_id("https://live.bilibili.com/123?from=test"),
            Some(123)
        );
        assert_eq!(room_id("123"), Some(123));
        assert_eq!(room_id("https://live.bilibili.com.example.com/123"), None);
    }

    #[test]
    fn bili_playback_line_keeps_signed_query() {
        let result = serde_json::json!({"data":{"playurl_info":{"playurl":{"stream":[{"format":[{"codec":[
            {"base_url":"/room.flv","url_info":[{"host":"https://cdn.example.com","extra":"?token=abc&x=1"}]}
        ]}]}]}}}});
        assert_eq!(
            bili_playback(&result, 10_000, &compat::Selection::default())
                .expect("playback line")
                .0,
            "https://cdn.example.com/room.flv?token=abc&x=1"
        );
    }

    #[test]
    fn bili_playback_quality_follows_selected_line() {
        let result = serde_json::json!({"data":{"playurl_info":{"playurl":{
            "g_qn_desc": [{"qn":10000,"desc":"原画"},{"qn":400,"desc":"蓝光"}],
            "stream":[
                {"protocol_name":"http_stream","format":[{"format_name":"flv","codec":[
                    {"current_qn":10000,"accept_qn":[10000,400],"base_url":"/room.flv",
                     "url_info":[{"host":"https://example.test","extra":""}]}
                ]}]},
                {"protocol_name":"http_hls","format":[{"format_name":"fmp4","codec":[
                    {"current_qn":400,"accept_qn":[400],"base_url":"/room.m3u8",
                     "url_info":[{"host":"https://example.test","extra":""}]}
                ]}]}
            ]
        }}}});
        let (url, playback) = bili_playback(&result, 10_000, &compat::Selection::default()).unwrap();
        assert!(url.ends_with("room.flv"));
        assert_eq!(playback.quality.as_deref(), Some("10000"));
        assert_eq!(playback.quality_label.as_deref(), Some("原画"));
        assert_eq!(playback.line, None);

        let selected = compat::Selection {
            line: Some("http_hls/fmp4/0".into()),
            ..Default::default()
        };
        let (url, playback) = bili_playback(&result, 10_000, &selected).unwrap();
        assert!(url.ends_with("room.m3u8"));
        assert_eq!(playback.quality.as_deref(), Some("400"));
        assert_eq!(playback.quality_label.as_deref(), Some("蓝光"));
        assert_eq!(playback.line, selected.line);
    }
}
