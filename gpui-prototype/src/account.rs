use serde::{Deserialize, Serialize};
use std::path::Path;
#[cfg(windows)]
use std::{
    fs,
    ptr::{null, null_mut},
    slice,
};
#[cfg(windows)]
use windows_sys::Win32::{
    Foundation::LocalFree,
    Security::Cryptography::{
        CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData,
    },
};

pub struct Platform {
    pub id: &'static str,
    pub name: &'static str,
    pub page: &'static str,
    pub origins: &'static [&'static str],
    pub domain: &'static str,
    signals: &'static [&'static str],
    extra: &'static [&'static str],
}

pub const PLATFORMS: &[Platform] = &[
    Platform {
        id: "bilibili",
        name: "哔哩哔哩",
        page: "https://passport.bilibili.com/login",
        origins: &["https://api.bilibili.com/"],
        domain: "bilibili.com",
        signals: &["SESSDATA"],
        extra: &["DedeUserID", "DedeUserID__ckMd5", "buvid3", "buvid4"],
    },
    Platform {
        id: "douyu",
        name: "斗鱼",
        page: "https://passport.douyu.com/h5/loginActivity",
        origins: &[
            "https://www.douyu.com/",
            "https://passport.douyu.com/",
            "https://m.douyu.com/",
        ],
        domain: "douyu.com",
        signals: &["acf_jwt_token", "acf_auth", "dy_auth"],
        extra: &[
            "acf_uid",
            "acf_username",
            "acf_nickname",
            "acf_did",
            "dy_did",
            "acf_ltkid",
        ],
    },
    Platform {
        id: "huya",
        name: "虎牙",
        page: "https://www.huya.com/",
        origins: &["https://www.huya.com/", "https://udblgn.huya.com/"],
        domain: "huya.com",
        signals: &["udb_biztoken"],
        extra: &["yyuid", "udb_uid", "udb_ver", "udb_guid", "udb_n", "udb_v"],
    },
    Platform {
        id: "douyin",
        name: "抖音",
        page: "https://live.douyin.com/",
        origins: &["https://live.douyin.com/", "https://www.douyin.com/"],
        domain: "douyin.com",
        signals: &["sessionid", "sessionid_ss"],
        extra: &[
            "ttwid",
            "msToken",
            "uid_tt",
            "uid_tt_ss",
            "sid_tt",
            "sid_guard",
            "passport_csrf_token",
            "odin_tt",
            "__ac_nonce",
            "__ac_signature",
        ],
    },
    Platform {
        id: "kuaishou",
        name: "快手",
        page: "https://passport.kuaishou.com/pc/account/login/?sid=kuaishou.live.web&callback=https%3A%2F%2Flive.kuaishou.com%2F",
        origins: &[
            "https://live.kuaishou.com/",
            "https://passport.kuaishou.com/",
            "https://id.kuaishou.com/",
        ],
        domain: "kuaishou.com",
        signals: &["kuaishou.live.web_st"],
        extra: &[
            "userId",
            "did",
            "didv",
            "kuaishou.live.web_ph",
            "kpf",
            "kpn",
        ],
    },
    Platform {
        id: "yy",
        name: "YY",
        page: "https://aq.yy.com/",
        origins: &["https://aq.yy.com/", "https://www.yy.com/"],
        domain: "yy.com",
        signals: &["udb_biztoken"],
        extra: &["yyuid", "udb_uid", "udb_ver", "udb_guid", "udb_n", "udb_v"],
    },
    Platform {
        id: "twitch",
        name: "Twitch",
        page: "https://www.twitch.tv/login",
        origins: &["https://www.twitch.tv/"],
        domain: "twitch.tv",
        signals: &["auth-token"],
        extra: &[
            "login",
            "name",
            "persistent",
            "unique_id",
            "unique_id_durable",
        ],
    },
    Platform {
        id: "soop",
        name: "SOOP",
        page: "https://login.sooplive.com/afreeca/login.php",
        origins: &[
            "https://login.sooplive.com/",
            "https://www.sooplive.com/",
            "https://login.sooplive.co.kr/",
            "https://www.sooplive.co.kr/",
        ],
        domain: "sooplive.co.kr",
        signals: &["AuthTicket"],
        extra: &["UserTicket", "UserID", "UserNick", "isLogin", "autoLogin"],
    },
];

impl Platform {
    pub fn allows(&self, value: &str) -> bool {
        url::Url::parse(value).is_ok_and(|url| {
            url.scheme() == "https"
                && url.username().is_empty()
                && url.password().is_none()
                && url.host_str().is_some_and(|host| {
                    let matches = |domain| {
                        host == domain
                            || host
                                .strip_suffix(domain)
                                .is_some_and(|prefix| prefix.ends_with('.'))
                    };
                    matches(self.domain) || (self.id == "soop" && matches("sooplive.com"))
                })
        })
    }
}

pub fn path(root: &Path, site: &str) -> std::path::PathBuf {
    root.with_file_name(format!("{site}.dpapi"))
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Account {
    pub name: String,
    pub cookie: String,
}

#[cfg(windows)]
fn dpapi(bytes: &[u8], encrypt: bool) -> std::io::Result<Vec<u8>> {
    let input = CRYPT_INTEGER_BLOB {
        cbData: bytes.len() as u32,
        pbData: bytes.as_ptr().cast_mut(),
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    // DPAPI allocates the output with LocalAlloc. Copy and free it before returning.
    unsafe {
        let ok = if encrypt {
            CryptProtectData(
                &input,
                null(),
                null(),
                null(),
                null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        } else {
            CryptUnprotectData(
                &input,
                null_mut(),
                null(),
                null(),
                null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output,
            )
        };
        if ok == 0 {
            return Err(std::io::Error::last_os_error());
        }
        let data = if output.cbData == 0 {
            Vec::new()
        } else {
            slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec()
        };
        LocalFree(output.pbData.cast());
        Ok(data)
    }
}

#[cfg(windows)]
pub fn load(path: &Path) -> Option<Account> {
    let encrypted = fs::read(path).ok()?;
    if encrypted.len() > 16 * 1024 {
        return None;
    }
    serde_json::from_slice(&dpapi(&encrypted, false).ok()?).ok()
}

#[cfg(windows)]
pub fn save(path: &Path, account: &Account) -> Result<(), String> {
    let result = (|| -> std::io::Result<()> {
        let bytes = serde_json::to_vec(account)?;
        let encrypted = dpapi(&bytes, true)?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let temp = path.with_extension("tmp");
        fs::write(&temp, encrypted)?;
        fs::rename(temp, path)
    })();
    result.map_err(|_| "无法加密保存账号登录状态".into())
}

#[cfg(windows)]
pub fn logout(path: &Path) -> Result<(), String> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err("无法清除本地登录状态".into()),
    }
}

#[cfg(target_os = "macos")]
const KEYCHAIN_SERVICE: &str = "PureLiveRust";

#[cfg(target_os = "macos")]
pub fn load(path: &Path) -> Option<Account> {
    let id = path.file_stem()?.to_str()?;
    let data = security_framework::passwords::get_generic_password(KEYCHAIN_SERVICE, id).ok()?;
    serde_json::from_slice(&data).ok()
}

#[cfg(target_os = "macos")]
pub fn save(path: &Path, account: &Account) -> Result<(), String> {
    let id = path
        .file_stem()
        .and_then(|id| id.to_str())
        .ok_or("无效的平台账号")?;
    let data = serde_json::to_vec(account).map_err(|_| "无法保存账号")?;
    security_framework::passwords::set_generic_password(KEYCHAIN_SERVICE, id, &data)
        .map_err(|_| "无法保存账号到 macOS 钥匙串".into())
}

#[cfg(target_os = "macos")]
pub fn logout(path: &Path) -> Result<(), String> {
    let id = path
        .file_stem()
        .and_then(|id| id.to_str())
        .ok_or("无效的平台账号")?;
    match security_framework::passwords::delete_generic_password(KEYCHAIN_SERVICE, id) {
        Ok(()) => Ok(()),
        Err(error) if error.code() == -25300 => Ok(()),
        Err(_) => Err("无法清除钥匙串中的账号".into()),
    }
}

pub fn cookie_header<'a>(
    site: &Platform,
    cookies: impl IntoIterator<Item = (&'a str, &'a str)>,
) -> Option<String> {
    let mut selected = std::collections::BTreeMap::new();
    for (name, value) in cookies {
        if (site.signals.contains(&name) || site.extra.contains(&name))
            && !value.is_empty()
            && !value.contains([';', '\r', '\n'])
        {
            selected.entry(name).or_insert(value);
        }
    }
    if !site.signals.iter().any(|name| selected.contains_key(name)) {
        return None;
    }
    Some(
        selected
            .into_iter()
            .map(|(name, value)| format!("{name}={value}"))
            .collect::<Vec<_>>()
            .join("; "),
    )
}

#[cfg(test)]
mod tests {
    use super::{PLATFORMS, cookie_header};

    #[test]
    fn only_read_only_bilibili_cookie_names_are_collected() {
        let header = cookie_header(
            &PLATFORMS[0],
            [
                ("SESSDATA", "fixture"),
                ("bili_jct", "ignore"),
                ("buvid3", "fixture2"),
            ],
        );
        assert_eq!(header.as_deref(), Some("SESSDATA=fixture; buvid3=fixture2"));
        assert!(cookie_header(&PLATFORMS[0], [("DedeUserID", "1")]).is_none());
    }

    #[test]
    #[cfg(windows)]
    fn windows_dpapi_round_trip() {
        use super::dpapi;
        let bytes = b"test credential only";
        let encrypted = dpapi(bytes, true).unwrap();
        assert_ne!(encrypted, bytes);
        assert_eq!(dpapi(&encrypted, false).unwrap(), bytes);
    }

    #[test]
    fn each_platform_accepts_only_its_own_login_hosts_and_signals() {
        for site in PLATFORMS {
            assert!(site.allows(site.page));
            assert!(site.origins.iter().all(|origin| site.allows(origin)));
            assert!(!site.allows(&format!("https://{}.example.com/", site.domain)));
            assert!(!site.allows(&format!("http://{}/", site.domain)));
            assert!(cookie_header(site, [(site.signals[0], "fixture")]).is_some());
            assert!(cookie_header(site, [(site.signals[0], "x; injected=1")]).is_none());
        }
        let twitch = PLATFORMS.iter().find(|site| site.id == "twitch").unwrap();
        assert!(cookie_header(twitch, [("SESSDATA", "fixture")]).is_none());
    }
}
