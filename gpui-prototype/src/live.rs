use std::{collections::BTreeMap, fs, path::Path, time::Duration};

use crate::compat::{self, Source};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use url::Url;

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
    #[serde(default)]
    pub live: bool,
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
            platform: bilibili(),
            headers: BTreeMap::new(),
        }
    }

    pub fn same_channel(&self, other: &Self) -> bool {
        self.platform == other.platform && self.id == other.id
    }
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
    let config = ureq::Agent::config_builder().timeout_global(Some(Duration::from_secs(12)));
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
    let result = compat::resolve(directory, room, cookie, selection);
    if result.is_err()
        && room.platform == "bilibili"
        && selection.quality.is_none()
        && selection.line.is_none()
    {
        if let Ok(url) = resolve_bili(room, cookie) {
            return Ok(Source {
                url,
                headers: BTreeMap::from([("referer".into(), "https://live.bilibili.com/".into())]),
                playback: compat::Playback {
                    chat: true,
                    super_chat: true,
                    super_chat_board: true,
                    ..compat::Playback::default()
                },
                ..Source::default()
            });
        }
    }
    result
}

fn resolve_bili(room: &Room, cookie: Option<&str>) -> Result<String, String> {
    let result = request(
        "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
        &[
            ("room_id", &room.id),
            ("protocol", "0,1"),
            ("format", "0,1,2"),
            ("codec", "0"),
            ("qn", "150"),
            ("platform", "web"),
            ("ptype", "8"),
        ],
        cookie,
    )?;
    stream_url(&result).ok_or_else(|| "直播间当前没有可用的游客播放线路".into())
}

fn stream_url(result: &Value) -> Option<String> {
    let streams = result["data"]["playurl_info"]["playurl"]["stream"].as_array()?;
    for stream in streams {
        for format in stream["format"].as_array().into_iter().flatten() {
            for codec in format["codec"].as_array().into_iter().flatten() {
                let Some(base) = codec["base_url"].as_str() else {
                    continue;
                };
                for line in codec["url_info"].as_array().into_iter().flatten() {
                    let (Some(host), Some(extra)) = (line["host"].as_str(), line["extra"].as_str())
                    else {
                        continue;
                    };
                    let url = format!("{host}{base}{extra}");
                    if Url::parse(&url)
                        .is_ok_and(|parsed| matches!(parsed.scheme(), "http" | "https"))
                    {
                        return Some(url);
                    }
                }
            }
        }
    }
    None
}

pub fn load(path: &Path) -> Vec<Room> {
    fs::read(path)
        .ok()
        .and_then(|data| serde_json::from_slice(&data).ok())
        .unwrap_or_default()
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
    fn recognizes_only_bilibili_room_links() {
        assert_eq!(
            room_id("https://live.bilibili.com/123?from=test"),
            Some(123)
        );
        assert_eq!(room_id("123"), Some(123));
        assert_eq!(room_id("https://live.bilibili.com.example.com/123"), None);
    }

    #[test]
    fn joins_playback_line_without_losing_query() {
        let result = serde_json::json!({"data":{"playurl_info":{"playurl":{"stream":[{"format":[{"codec":[
            {"base_url":"/room.flv","url_info":[{"host":"https://cdn.example.com","extra":"?token=abc&x=1"}]}
        ]}]}]}}}});
        assert_eq!(
            stream_url(&result).as_deref(),
            Some("https://cdn.example.com/room.flv?token=abc&x=1")
        );
    }
}
