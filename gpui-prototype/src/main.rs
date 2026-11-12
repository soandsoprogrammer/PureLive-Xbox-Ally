#![windows_subsystem = "windows"]

mod account;
mod compat;
mod emotes;
mod live;
mod native;
mod platform_icons;
mod platform_picker;
mod playback;
mod player;
mod style;

use std::{
    collections::BTreeMap,
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
    time::{Duration, Instant},
};

use compat::Source;
use gpui_kit::base::StyledExt;
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::prelude::FluentBuilder;
use gpui_kit::*;
use live::{BroadcastStatus, FollowFilter, Room, RoomKey};
use native::Surface;
use playback::{AudioSettings, PlaybackUi};
use player::{PlaybackEnd, Player};
use style::Pane;
use windows_sys::Win32::UI::Input::XboxController::{
    XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_DPAD_DOWN, XINPUT_GAMEPAD_DPAD_LEFT,
    XINPUT_GAMEPAD_DPAD_RIGHT, XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_LEFT_SHOULDER,
    XINPUT_GAMEPAD_RIGHT_SHOULDER, XINPUT_GAMEPAD_START, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y,
};
use wry::{PageLoadEvent, Rect, WebView, WebViewBuilder, dpi::PhysicalSize};

const TOOLBAR: f32 = 88.0;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Action {
    Back,
    Exit,
    Minimize,
    SearchPlatform,
    Login,
    Logout,
    FinishLogin,
}

const SETTINGS_ACTIONS: [Action; 4] = [
    Action::Login,
    Action::Logout,
    Action::Minimize,
    Action::Exit,
];
const LOGIN_ACTIONS: [Action; 2] = [Action::FinishLogin, Action::Back];

struct Options {
    directory: PathBuf,
    stream: Option<String>,
    probe: Option<String>,
    launch_platform: Option<String>,
    launch_room: Option<String>,
    vsync: bool,
    started: Instant,
}

impl Options {
    fn read() -> Self {
        let exe = std::env::current_exe().expect("resolve executable");
        let directory = exe.parent().expect("executable directory").to_owned();
        let mut options = Self {
            directory,
            stream: None,
            probe: None,
            launch_platform: None,
            launch_room: None,
            vsync: false,
            started: Instant::now(),
        };
        let mut args = std::env::args().skip(1);
        while let Some(flag) = args.next() {
            match flag.as_str() {
                "--stream" => options.stream = args.next(),
                "--probe" => options.probe = args.next(),
                "--platform" => options.launch_platform = args.next(),
                "--room" => options.launch_room = args.next(),
                "--vsync" => options.vsync = true,
                _ => {}
            }
        }
        options
    }
}

fn mark(path: &Option<PathBuf>, line: impl AsRef<str>) {
    if let Some(path) = path {
        if let Ok(mut file) = OpenOptions::new().append(true).create(true).open(path) {
            let _ = writeln!(file, "{}", line.as_ref());
        }
    }
}

// Drop the player or WebView before destroying the HWND it uses.
enum Content {
    Video {
        player: Player,
        surface: Surface,
        _lease: Option<compat::Bridge>,
    },
    Login {
        web: WebView,
        surface: Surface,
        site_index: usize,
    },
}

impl Content {
    fn resize(&self, window: &Window, controls_height: f32) {
        match self {
            Self::Video { surface, .. } => {
                surface.resize_video(window, controls_height);
            }
            Self::Login { web, surface, .. } => {
                let (width, height) = surface.resize(window, TOOLBAR);
                let _ = web.set_bounds(web_bounds(width, height));
            }
        }
    }
}

fn web_bounds(width: i32, height: i32) -> Rect {
    Rect {
        size: PhysicalSize::new(width as u32, height as u32).into(),
        ..Rect::default()
    }
}

struct Home {
    options: Options,
    log: Option<PathBuf>,
    focus: FocusHandle,
    selected: Action,
    content: Option<Content>,
    status: String,
    reopen_video: bool,
    playback: PlaybackUi,
    emotes: emotes::Cache,
    playback_epoch: u64,
    audio: AudioSettings,
    danmaku_enabled: bool,
    gamepad: Option<Task<()>>,
    probe_reported: bool,
    chat_probe_reported: bool,
    emote_probe_reported: bool,
    first_poll: bool,
    query: Entity<InputState>,
    follows_path: PathBuf,
    follows: Vec<Room>,
    follow_filter: FollowFilter,
    follow_rows: Vec<usize>,
    room_status_task: Option<Task<()>>,
    next_follow_check: Option<Instant>,
    results: Vec<Room>,
    show_follows: bool,
    room_selection: Option<usize>,
    request_id: u64,
    active_room: Option<Room>,
    platforms: Vec<live::Platform>,
    platform: usize,
    search_platform: Option<usize>,
    platform_cursor: Option<usize>,
    platform_scroll: ScrollHandle,
    pane: Pane,
    rooms_scroll: UniformListScrollHandle,
    covers: style::CoverCache,
    settings_scroll: ScrollHandle,
    accounts: BTreeMap<String, account::Account>,
    account_site: usize,
    account_tabs_focused: bool,
    checking_login: bool,
}

impl Home {
    fn new(options: Options, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let log = options
            .probe
            .as_ref()
            .map(|_| options.directory.join("probe.log"));
        if let Some(path) = &log {
            let _ = fs::remove_file(path);
        }
        let elapsed = options.started;
        let frame_log = log.clone();
        window.on_next_frame(move |_, _| {
            mark(
                &frame_log,
                format!("first_frame_ms={}", elapsed.elapsed().as_millis()),
            );
        });
        window.set_window_title("纯粹直播 · Rust 掌机版");
        let query =
            cx.new(|cx| InputState::new(window, cx).placeholder("关键词、房间号或直播间链接"));
        let follows_path = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| options.directory.clone())
            .join("PureLiveRust/follows.json");
        let follows = live::load(&follows_path);
        let follow_rows = (0..follows.len()).collect();
        let audio = AudioSettings::load(&follows_path.with_file_name("audio.json"));
        let danmaku_enabled =
            playback::load_danmaku_preference(&follows_path.with_file_name("danmaku.json"));
        let accounts = account::PLATFORMS
            .iter()
            .filter_map(|site| {
                account::load(&account::path(&follows_path, site.id))
                    .map(|value| (site.id.to_owned(), value))
            })
            .collect();
        let pane = if follows.is_empty() {
            Pane::Popular
        } else {
            Pane::Follows
        };
        cx.subscribe_in(&query, window, |this, _, event, window, cx| {
            if matches!(event, InputEvent::PressEnter { .. }) {
                this.search(window, cx);
            }
        })
        .detach();
        let focus = cx.focus_handle();
        focus.focus(window, cx);
        let entity = cx.weak_entity();
        window.on_window_should_close(cx, move |_, app| {
            let _ = entity.update(app, |this, _| {
                this.stop_chat();
                this.content = None;
            });
            true
        });
        cx.observe_window_bounds(window, |this, window, _| {
            if !native::minimized(window) {
                if let Some(content) = &this.content {
                    content.resize(window, this.playback.height());
                }
            }
        })
        .detach();
        cx.observe_window_activation(window, Self::sync_gamepad)
            .detach();
        cx.spawn_in(window, async move |entity, cx| {
            let mut delay = Duration::from_millis(120);
            loop {
                cx.background_executor().timer(delay).await;
                if entity.update_in(cx, Self::tick).is_err() {
                    break;
                }
                delay = Duration::from_millis(200);
            }
        })
        .detach();
        Self {
            options,
            log,
            focus,
            selected: Action::Back,
            content: None,
            status: String::new(),
            reopen_video: false,
            playback: PlaybackUi::default(),
            emotes: emotes::Cache::default(),
            playback_epoch: 0,
            audio,
            danmaku_enabled,
            gamepad: None,
            probe_reported: false,
            chat_probe_reported: false,
            emote_probe_reported: false,
            first_poll: true,
            query,
            follows_path,
            follows,
            follow_filter: FollowFilter::All,
            follow_rows,
            room_status_task: None,
            next_follow_check: None,
            results: Vec::new(),
            show_follows: true,
            room_selection: None,
            request_id: 0,
            active_room: None,
            platforms: live::platforms(),
            platform: 0,
            search_platform: None,
            platform_cursor: (pane == Pane::Popular).then_some(0),
            platform_scroll: ScrollHandle::new(),
            pane,
            rooms_scroll: UniformListScrollHandle::new(),
            covers: style::CoverCache::default(),
            settings_scroll: ScrollHandle::new(),
            accounts,
            account_site: 0,
            account_tabs_focused: false,
            checking_login: false,
        }
    }

    fn play_stream(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.reopen_video = false;
        let Some(url) = self.options.stream.clone() else {
            return;
        };
        self.playback.direct = true;
        let source = Source {
            url,
            ..Source::default()
        };
        self.status = match self.open_video(window, source, cx) {
            Ok(()) => {
                self.selected = Action::Back;
                self.platform_cursor = None;
                self.room_selection = None;
                String::new()
            }
            Err(error) => {
                self.show_controls(window, cx);
                error
            }
        };
        mark(&self.log, &self.status);
        cx.notify();
    }

    fn open_video(
        &mut self,
        window: &mut Window,
        source: Source,
        cx: &mut Context<Self>,
    ) -> Result<(), String> {
        let reused = match &mut self.content {
            Some(Content::Video { player, .. }) => player.try_reload(&source),
            _ => false,
        };
        if !reused {
            let surface = Surface::video(window, self.playback.height())?;
            let player = Player::start(
                &self.options.directory,
                surface.id(),
                &source,
                self.options.vsync,
                self.playback.paused,
                self.audio,
            )?;
            self.content = Some(Content::Video {
                player,
                surface,
                _lease: source.lease,
            });
        }
        self.playback.selection = compat::Selection {
            quality: source.playback.quality.clone(),
            line: source.playback.line.clone(),
        };
        self.playback.options = source.playback;
        self.playback.chat_enabled = self.danmaku_enabled && self.playback.options.chat;
        self.reopen_video = false;
        mark(
            &self.log,
            if reused {
                "player_reused"
            } else {
                "player_created"
            },
        );
        if self.playback.options.chat {
            self.playback.update_chat_filter();
            self.connect_chat(window, cx);
        } else {
            self.release_chat();
        }
        Ok(())
    }

    fn show_login(&self, window: &Window) -> Result<Content, String> {
        let surface = Surface::new(window, TOOLBAR)?;
        let (width, height) = surface.resize(window, TOOLBAR);
        let log = self.log.clone();
        let site_index = self.account_site;
        let site = &account::PLATFORMS[site_index];
        let web = WebViewBuilder::new()
            .with_bounds(web_bounds(width, height))
            .with_navigation_handler(move |url| url == "about:blank" || site.allows(&url))
            .with_on_page_load_handler(move |event, url| {
                if matches!(event, PageLoadEvent::Finished) && site.allows(&url) {
                    mark(&log, format!("{}_login_page_opened", site.id));
                }
            })
            .with_incognito(true)
            .with_url(site.page)
            .build_as_child(&surface)
            .map_err(|err| format!("WebView2 启动失败：{err}"))?;
        Ok(Content::Login {
            web,
            surface,
            site_index,
        })
    }

    fn choose(&mut self, action: Action, window: &mut Window, cx: &mut Context<Self>) {
        match action {
            Action::FinishLogin => return self.finish_login(window, cx),
            Action::Minimize => return window.minimize_window(),
            _ => {}
        }
        self.checking_login = false;
        self.selected = action;
        self.platform_cursor = None;
        self.room_selection = None;
        self.request_id += 1;
        self.active_room = None;
        match action {
            Action::Login => {
                self.content = None;
                self.reopen_video = false;
                self.account_tabs_focused = false;
                match self.show_login(window) {
                    Ok(content) => {
                        self.status = "在网页完成登录后，选择「完成登录」".into();
                        self.content = Some(content);
                        self.selected = Action::FinishLogin;
                    }
                    Err(error) => {
                        mark(&self.log, &error);
                        self.status = error;
                    }
                }
            }
            Action::Back | Action::Exit => {
                self.stop_chat();
                self.playback = PlaybackUi::default();
                self.content = None;
                self.reopen_video = false;
                self.status.clear();
                if action == Action::Exit {
                    window.remove_window();
                } else {
                    if self.pane == Pane::Settings {
                        self.selected = Action::Login;
                    }
                    self.focus.focus(window, cx);
                }
            }
            Action::SearchPlatform => {
                self.content = None;
                self.reopen_video = false;
                self.open_platform_picker();
                self.focus.focus(window, cx);
            }
            Action::Logout => {
                let site = &account::PLATFORMS[self.account_site];
                self.status = match account::logout(&account::path(&self.follows_path, site.id)) {
                    Ok(()) => {
                        self.accounts.remove(site.id);
                        format!("已退出应用内的{}账号", site.name)
                    }
                    Err(error) => error,
                };
            }
            Action::FinishLogin | Action::Minimize => unreachable!(),
        }
        cx.notify();
    }

    fn finish_login(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.checking_login {
            return;
        }
        let Some(Content::Login {
            web, site_index, ..
        }) = &self.content
        else {
            return;
        };
        let site = &account::PLATFORMS[*site_index];
        self.checking_login = true;
        let cookies: Vec<_> = site
            .origins
            .iter()
            .filter_map(|origin| web.cookies_for_url(origin).ok())
            .flatten()
            .collect();
        let cookie = account::cookie_header(
            site,
            cookies.iter().map(|cookie| (cookie.name(), cookie.value())),
        );
        let Some(cookie) = cookie else {
            self.checking_login = false;
            self.status = format!("尚未读到{}的登录状态，请在官方网页完成登录", site.name);
            cx.notify();
            return;
        };
        self.request_id += 1;
        let request = self.request_id;
        self.status = format!("正在保存{}登录状态…", site.name);
        cx.notify();
        let pending = cx.background_spawn(async move {
            let name = if site.id == "bilibili" {
                live::account_name(&cookie)?
            } else {
                site.name.to_owned()
            };
            Ok::<_, String>(account::Account { name, cookie })
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if request != this.request_id {
                    return;
                }
                this.checking_login = false;
                let result = result.and_then(|verified| {
                    account::save(&account::path(&this.follows_path, site.id), &verified)?;
                    Ok(verified)
                });
                this.status = match result {
                    Ok(verified) => {
                        let message = format!("已保存登录状态 · {}", verified.name);
                        this.accounts.insert(site.id.to_owned(), verified);
                        this.content = None;
                        this.pane = Pane::Settings;
                        this.selected = Action::Login;
                        this.focus.focus(window, cx);
                        message
                    }
                    Err(error) => error,
                };
                cx.notify();
            });
        })
        .detach();
    }

    fn move_selection(&mut self, right: bool, cx: &mut Context<Self>) {
        if self.pane == Pane::Settings && self.content.is_none() && self.account_tabs_focused {
            let count = account::PLATFORMS.len();
            self.account_site = (self.account_site + if right { 1 } else { count - 1 }) % count;
            self.status.clear();
            cx.notify();
            return;
        }
        if matches!(self.content, Some(Content::Video { .. })) {
            return;
        }
        if self.platform_cursor.is_some() {
            self.move_platform(if right { 1 } else { -1 }, 0, cx);
            return;
        }
        if self.content.is_none() && self.pane != Pane::Settings {
            self.move_card(if right { 1 } else { -1 }, cx);
            return;
        }
        self.room_selection = None;
        let actions: &[Action] = match self.content {
            Some(Content::Login { .. }) => &LOGIN_ACTIONS,
            Some(Content::Video { .. }) => return,
            None => &SETTINGS_ACTIONS,
        };
        let current = actions.iter().position(|action| *action == self.selected);
        let next = current.map_or(0, |current| {
            (current + if right { 1 } else { actions.len() - 1 }) % actions.len()
        });
        self.selected = actions[next];
        if self.pane == Pane::Settings && self.content.is_none() {
            self.settings_scroll.scroll_to_item(usize::from(next >= 2));
        }
        cx.notify();
    }

    fn room_count(&self) -> usize {
        if self.show_follows {
            self.follow_rows.len()
        } else {
            self.results.len()
        }
    }

    fn room_at(&self, index: usize) -> Option<&Room> {
        if self.show_follows {
            self.follow_rows
                .get(index)
                .and_then(|&row| self.follows.get(row))
        } else {
            self.results.get(index)
        }
    }

    fn selected_follow(&self) -> Option<RoomKey> {
        if !self.show_follows {
            return None;
        }
        self.room_selection
            .and_then(|index| self.room_at(index))
            .map(Room::key)
    }

    fn rebuild_follow_rows(&mut self, selected: Option<RoomKey>) {
        self.follow_rows.clear();
        self.follow_rows
            .extend(self.follows.iter().enumerate().filter_map(|(index, room)| {
                self.follow_filter
                    .includes(room.broadcast_status())
                    .then_some(index)
            }));
        if self.show_follows {
            self.room_selection = selected.and_then(|key| {
                self.follow_rows.iter().position(|&index| {
                    let room = &self.follows[index];
                    room.platform == key.platform && room.id == key.id
                })
            });
            if let Some(index) = self.room_selection {
                self.rooms_scroll
                    .scroll_to_item(index / 3, ScrollStrategy::Nearest);
            }
        }
    }

    fn select_follow_filter(&mut self, filter: FollowFilter, cx: &mut Context<Self>) {
        if self.follow_filter == filter && self.room_selection.is_none() {
            return;
        }
        self.follow_filter = filter;
        self.rooms_scroll = UniformListScrollHandle::new();
        self.rebuild_follow_rows(None);
        cx.notify();
    }

    /// Bumpers on a list page: cycle the row at its top. 关注 cycles the follow
    /// filters, 热门 selects the next platform and reloads its rooms.
    fn page_bar(&mut self, right: bool, window: &mut Window, cx: &mut Context<Self>) {
        if self.content.is_some() {
            return;
        }
        match self.pane {
            Pane::Follows => {
                let current = FollowFilter::TABS
                    .iter()
                    .position(|tab| *tab == self.follow_filter)
                    .unwrap_or(0);
                let step = if right {
                    1
                } else {
                    FollowFilter::TABS.len() - 1
                };
                let next = (current + step) % FollowFilter::TABS.len();
                self.select_follow_filter(FollowFilter::TABS[next], cx);
            }
            Pane::Popular => {
                let count = self.platforms.len();
                if count == 0 {
                    return;
                }
                let current = self.platform_cursor.unwrap_or(self.platform).min(count - 1);
                let next = if right {
                    (current + 1) % count
                } else {
                    (current + count - 1) % count
                };
                self.select_platform(next, window, cx);
            }
            _ => {}
        }
    }

    fn move_room(&mut self, down: bool, cx: &mut Context<Self>) {
        if self.pane == Pane::Follows && self.content.is_none() {
            if down {
                match self.room_selection {
                    None => self.move_card(0, cx),
                    Some(index) if index / 3 + 1 < self.room_count().div_ceil(3) => {
                        let target = (index + 3).min(self.room_count() - 1);
                        self.select_room_card(target, cx);
                    }
                    _ => {}
                }
            } else if let Some(index) = self.room_selection {
                // Up never leaves the grid: the filter row belongs to LB/RB.
                if index >= 3 {
                    self.select_room_card(index - 3, cx);
                }
            }
            return;
        }
        if self.pane == Pane::Popular && self.content.is_none() {
            if self.room_selection.is_none() {
                if self.room_count() != 0 {
                    self.move_card(0, cx);
                }
                return;
            }
        }
        if self.platform_cursor.is_some() {
            self.move_platform(0, if down { 1 } else { -1 }, cx);
            return;
        }
        if self.pane == Pane::Settings {
            if self.content.is_none()
                && (self.account_tabs_focused || (!down && self.selected == Action::Login))
            {
                self.account_tabs_focused = !down;
                self.selected = Action::Login;
                self.settings_scroll.scroll_to_item(0);
                cx.notify();
                return;
            }
            self.move_selection(down, cx);
            return;
        }
        self.move_card(if down { 3 } else { -3 }, cx);
    }

    fn move_card(&mut self, delta: isize, cx: &mut Context<Self>) {
        let count = self.room_count();
        if self.content.is_some() || count == 0 {
            return;
        }
        let index = self.room_selection.map_or(0, |index| {
            (index as isize + delta).rem_euclid(count as isize) as usize
        });
        self.select_room_card(index, cx);
    }

    fn select_room_card(&mut self, index: usize, cx: &mut Context<Self>) {
        self.room_selection = Some(index);
        self.rooms_scroll
            .scroll_to_item(index / 3, ScrollStrategy::Nearest);
        cx.notify();
    }

    fn confirm(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.pane == Pane::Settings && self.content.is_none() && self.account_tabs_focused {
            self.choose(Action::Login, window, cx);
            return;
        }
        if matches!(self.content, Some(Content::Video { .. })) {
            return;
        }
        if let Some(index) = self.platform_cursor {
            if self.pane == Pane::Search {
                self.select_search_platform(index, window, cx);
            } else {
                self.select_platform(index, window, cx);
            }
            return;
        }
        if let Some(room) = self
            .room_selection
            .and_then(|index| self.room_at(index))
            .cloned()
        {
            self.play_room(room, window, cx);
        } else if self.pane == Pane::Settings || self.content.is_some() {
            self.choose(self.selected, window, cx);
        } else if self.pane == Pane::Follows {
            self.move_card(0, cx);
        }
    }

    fn move_platform(&mut self, x: isize, y: isize, cx: &mut Context<Self>) {
        let current = self.platform_cursor.unwrap_or(self.platform);
        let next = if self.pane == Pane::Popular {
            current
                .saturating_add_signed(x)
                .min(self.platforms.len() - 1)
        } else {
            platform_picker::move_index(current, x, y, self.platforms.len() + 1)
        };
        self.platform_cursor = Some(next);
        let item = if self.pane == Pane::Popular {
            next
        } else {
            next / platform_picker::COLUMNS
        };
        self.platform_scroll.scroll_to_item(item);
        cx.notify();
    }

    fn select_platform(&mut self, index: usize, window: &mut Window, cx: &mut Context<Self>) {
        self.platform = index;
        self.platform_cursor = None;
        self.show_follows = false;
        self.results.clear();
        self.room_selection = None;
        self.request_id += 1;
        self.status = if self.platforms[index].id == "iptv" {
            "输入 M3U / TXT 播放列表路径或网址".into()
        } else {
            format!("{} · 搜索关键词或输入房间链接", self.platforms[index].name)
        };
        self.focus.focus(window, cx);
        if self.pane == Pane::Popular && self.platforms[index].id == "iptv" {
            self.search_platform = Some(index);
            self.pane = Pane::Search;
        }
        if self.pane == Pane::Popular {
            self.request_rooms(String::new(), window, cx);
        }
        cx.notify();
    }

    fn select_search_platform(
        &mut self,
        index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.search_platform = index.checked_sub(1);
        self.platform_cursor = None;
        self.request_id += 1;
        self.results.clear();
        self.room_selection = None;
        self.status = if self
            .search_platform
            .is_some_and(|index| self.platforms[index].id == "iptv")
        {
            "输入 M3U / TXT 播放列表路径或网址"
        } else if self.search_platform.is_none() {
            "输入关键词或粘贴直播间链接"
        } else {
            "输入关键词、房间号或直播间链接"
        }
        .into();
        self.query.read(cx).focus_handle(cx).focus(window, cx);
        cx.notify();
    }

    fn search(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let input = self.query.read(cx).value().to_string();
        self.pane = Pane::Search;
        if self.search_platform.is_none() && input.trim().is_empty() {
            self.status = "输入关键词或粘贴直播间链接".into();
            cx.notify();
            return;
        }
        self.request_rooms(input, window, cx);
    }

    fn request_rooms(&mut self, input: String, window: &mut Window, cx: &mut Context<Self>) {
        self.request_id += 1;
        let request = self.request_id;
        let site = if self.pane == Pane::Search {
            self.search_platform.map(|index| &self.platforms[index])
        } else {
            Some(&self.platforms[self.platform])
        };
        let platform = site.map_or("all", |site| site.id.as_str()).to_owned();
        let directory = self.options.directory.clone();
        self.status = site.map_or_else(
            || "正在搜索全部直播平台…".into(),
            |site| format!("正在查询 {}…", site.name),
        );
        self.show_follows = false;
        self.covers.retry_failed(cx);
        self.results.clear();
        self.room_selection = None;
        self.rooms_scroll = UniformListScrollHandle::new();
        if self.pane == Pane::Popular {
            self.platform_scroll.scroll_to_item(self.platform);
        }
        self.focus.focus(window, cx);
        let cookie = self
            .accounts
            .get(&platform)
            .map(|account| account.cookie.clone());
        let pending = cx.background_spawn(async move {
            live::find(&directory, &platform, &input, cookie.as_deref())
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, _, cx| {
                if this.request_id != request {
                    return;
                }
                this.status = match result {
                    Ok(rooms) => {
                        mark(&this.log, format!("rooms_loaded={}", rooms.len()));
                        this.results = rooms;
                        // Do not pre-select a card: the mint ring means the user moved
                        // to it, not that the list has just loaded.
                        this.room_selection = None;
                        if this.results.is_empty() {
                            if this.pane == Pane::Search && this.search_platform.is_none() {
                                "暂无结果，可换个关键词或粘贴直播间链接".into()
                            } else {
                                "暂无结果，可粘贴直播间链接或输入 @频道ID".into()
                            }
                        } else {
                            format!("找到 {} 个房间", this.results.len())
                        }
                    }
                    Err(error) => error,
                };
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn play_room(&mut self, room: Room, window: &mut Window, cx: &mut Context<Self>) {
        self.covers.clear(window, cx);
        self.stop_chat();
        self.playback_epoch += 1;
        self.playback = PlaybackUi::default();
        self.content = None;
        self.reopen_video = false;
        self.active_room = Some(room);
        self.focus.focus(window, cx);
        self.reload_room(compat::Selection::default(), window, cx);
    }

    /// Bumpers (or left/right) while watching a room opened from the follow list:
    /// plays the next followed room that is live, wrapping around, and shows which
    /// one it is ("3/6 神棍老师") over the video.
    fn switch_follow(&mut self, forward: bool, window: &mut Window, cx: &mut Context<Self>) {
        if self.pane != Pane::Follows {
            return;
        }
        let Some(current) = self.active_room.as_ref().map(Room::key) else {
            return;
        };
        let mut candidates: Vec<usize> = self
            .follows
            .iter()
            .enumerate()
            .filter(|(_, room)| room.broadcast_status() == BroadcastStatus::Live)
            .map(|(index, _)| index)
            .collect();
        if candidates.len() < 2 {
            candidates = (0..self.follows.len()).collect();
        }
        if candidates.len() < 2 {
            return;
        }
        let Some(position) = candidates
            .iter()
            .position(|&index| self.follows[index].key() == current)
        else {
            return;
        };
        let next = if forward {
            (position + 1) % candidates.len()
        } else {
            (position + candidates.len() - 1) % candidates.len()
        };
        let room = self.follows[candidates[next]].clone();
        self.play_room(room, window, cx);
    }

    /// The room's place in the follow list ("3/6 神棍老师"), or just its name when
    /// it is not a follow; used in the status line while the source connects.
    fn room_label(&self, room: &Room) -> String {
        let name = if room.nick.trim().is_empty() {
            room.title.trim()
        } else {
            room.nick.trim()
        };
        let live: Vec<&Room> = self
            .follows
            .iter()
            .filter(|followed| followed.broadcast_status() == BroadcastStatus::Live)
            .collect();
        let list: Vec<&Room> = if live.len() >= 2 {
            live
        } else {
            self.follows.iter().collect()
        };
        match list
            .iter()
            .position(|followed| followed.key() == room.key())
        {
            Some(index) => format!("{}/{}  {}", index + 1, list.len(), name),
            None => name.to_string(),
        }
    }

    fn refresh_playback(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.playback.direct {
            self.play_stream(window, cx);
        } else {
            self.reload_room(self.playback.selection.clone(), window, cx);
        }
    }

    fn reload_room(
        &mut self,
        selection: compat::Selection,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(room) = self.active_room.clone() else {
            return;
        };
        self.request_id += 1;
        let request = self.request_id;
        self.reopen_video = false;
        self.playback.busy = true;
        self.status = if self.content.is_some() {
            "正在切换播放源…"
        } else {
            "正在连接直播…"
        }
        .into();
        if let Some(label) = self
            .active_room
            .as_ref()
            .map(|room| self.room_label(room))
        {
            self.status = format!("{}  {label}", self.status);
        }
        let directory = self.options.directory.clone();
        let cookie = self
            .accounts
            .get(&room.platform)
            .map(|account| account.cookie.clone());
        let selected = selection.clone();
        let room_key = room.key();
        let pending = cx.background_spawn(async move {
            live::resolve(&directory, &room, cookie.as_deref(), &selected)
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if this.request_id != request {
                    return;
                }
                this.playback.busy = false;
                if native::minimized(window) {
                    this.reopen_video = true;
                    this.playback.resume_selection = Some(selection);
                    return;
                }
                match result.and_then(|source| this.open_video(window, source, cx)) {
                    Ok(()) => {
                        if selection.quality.as_deref().is_some_and(|quality| {
                            Some(quality) != this.playback.options.quality.as_deref()
                        }) {
                            let label = this
                                .playback
                                .options
                                .quality_label
                                .as_deref()
                                .unwrap_or("自动");
                            this.status = format!("平台当前提供 {label}");
                        } else if this.status.starts_with("正在切换")
                            || this.status.starts_with("正在连接直播")
                        {
                            this.status.clear();
                        }
                        this.focus.focus(window, cx);
                        if this.playback.visible() {
                            this.show_controls(window, cx);
                        }
                        mark(&this.log, "source_opened");
                    }
                    Err(error) => {
                        this.status = error;
                        this.show_controls(window, cx);
                        mark(&this.log, &this.status);
                        if this.content.is_none() {
                            this.check_room_statuses(vec![room_key], true, window, cx);
                        }
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    fn refresh_follow_statuses(&mut self, window: &Window, cx: &mut Context<Self>) {
        if self.room_status_task.is_some() {
            return;
        }
        self.next_follow_check = Some(Instant::now() + Duration::from_secs(45));
        self.check_room_statuses(
            self.follows.iter().map(Room::key).collect(),
            false,
            window,
            cx,
        );
        if self.room_status_task.is_some() {
            cx.notify();
        }
    }

    fn check_room_statuses(
        &mut self,
        mut rooms: Vec<RoomKey>,
        verify_end: bool,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        rooms.retain(|room| room.platform != "iptv");
        if rooms.is_empty() {
            return;
        }
        let directory = self.options.directory.clone();
        let cookies = rooms
            .iter()
            .filter_map(|room| {
                self.accounts
                    .get(&room.platform)
                    .map(|account| (room.platform.clone(), account.cookie.clone()))
            })
            .collect();
        let ended_request = verify_end.then_some(self.request_id);
        let pending = cx.background_spawn(async move {
            let results = compat::room_statuses(&directory, &rooms, &cookies).unwrap_or_default();
            let mut statuses: BTreeMap<_, _> = rooms
                .into_iter()
                .map(|key| (key, BroadcastStatus::Unknown))
                .collect();
            for result in results {
                if let Some(status) = statuses.get_mut(&result.key) {
                    *status = result.status;
                }
            }
            statuses
        });
        self.room_status_task = Some(cx.spawn_in(window, async move |entity, cx| {
            let statuses = pending.await;
            let _ = entity.update_in(cx, |this, _, cx| {
                this.room_status_task = None;
                let selected_follow = this.selected_follow();
                let mut follows_changed = false;
                let mut changed = false;
                for room in &mut this.follows {
                    if let Some(&status) = statuses.get(&room.key()) {
                        follows_changed |= room.broadcast_status() != status;
                        room.broadcast = Some(status);
                    }
                }
                if follows_changed {
                    this.rebuild_follow_rows(selected_follow);
                    changed = true;
                }
                for room in &mut this.results {
                    if let Some(&status) = statuses.get(&room.key()) {
                        changed |= room.broadcast_status() != status;
                        room.broadcast = Some(status);
                    }
                }
                if ended_request == Some(this.request_id)
                    && this.content.is_none()
                    && this.active_room.as_ref().is_some_and(|room| {
                        statuses.get(&room.key()) == Some(&BroadcastStatus::Offline)
                    })
                {
                    this.status = "直播已结束".into();
                    mark(&this.log, &this.status);
                    changed = true;
                }
                if this.log.is_some() {
                    for (key, status) in &statuses {
                        mark(
                            &this.log,
                            format!("room_status={}/{}:{status:?}", key.platform, key.id),
                        );
                    }
                }
                if changed || this.pane == Pane::Follows {
                    cx.notify();
                }
            });
        }));
    }

    fn toggle_follow(&mut self, room: Room, cx: &mut Context<Self>) {
        let mut updated = self.follows.clone();
        let followed =
            if let Some(index) = updated.iter().position(|saved| saved.same_channel(&room)) {
                updated.remove(index);
                false
            } else {
                updated.push(room);
                true
            };
        match live::save(&self.follows_path, &updated) {
            Ok(()) => {
                let selected_follow = self.selected_follow();
                self.follows = updated;
                self.rebuild_follow_rows(selected_follow);
                if self.in_playback() {
                    self.status = if followed {
                        "已关注"
                    } else {
                        "已取消关注"
                    }
                    .into();
                }
                if self.show_follows {
                    self.next_follow_check = None;
                }
            }
            Err(error) => self.status = error,
        }
        cx.notify();
    }

    fn tick(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.sync_gamepad(window, cx);
        if self.first_poll {
            self.first_poll = false;
            if let Some(id) = self.options.launch_room.take() {
                let platform = self
                    .options
                    .launch_platform
                    .as_deref()
                    .unwrap_or("bilibili");
                if let Some(site) = self.platforms.iter().find(|site| site.id == platform) {
                    let room = Room {
                        platform: platform.into(),
                        id,
                        ..Room::bili(0, site.name.clone())
                    };
                    self.play_room(room, window, cx);
                } else {
                    self.status = "无法识别启动参数中的平台".into();
                    cx.notify();
                }
            } else if self.options.stream.is_some() {
                self.play_stream(window, cx);
            } else {
                match self.options.probe.as_deref() {
                    Some("login") => {
                        if let Some(id) = self.options.launch_platform.as_deref() {
                            if let Some(index) =
                                account::PLATFORMS.iter().position(|site| site.id == id)
                            {
                                self.account_site = index;
                            }
                        }
                        self.select_pane(Pane::Settings, window, cx);
                        self.choose(Action::Login, window, cx);
                    }
                    Some("browse") => self.request_rooms(String::new(), window, cx),
                    Some("bilibili") => {
                        self.play_room(Room::bili(7734200, "哔哩哔哩测试房间".into()), window, cx)
                    }
                    _ if self.options.probe.is_none() && self.pane == Pane::Popular => {
                        self.request_rooms(String::new(), window, cx);
                    }
                    _ => {}
                }
            }
        }
        if native::minimized(window) {
            if matches!(self.content, Some(Content::Video { .. })) {
                self.release_chat();
                self.content = None;
                self.reopen_video = true;
            }
            return;
        }
        if self.reopen_video && !self.playback.busy {
            if self.active_room.is_some() {
                let selection = self
                    .playback
                    .resume_selection
                    .take()
                    .unwrap_or_else(|| self.playback.selection.clone());
                self.reload_room(selection, window, cx);
            } else {
                self.play_stream(window, cx);
            }
        }
        let track_live_end = self
            .active_room
            .as_ref()
            .is_some_and(|room| room.platform != "iptv");
        if let Some(Content::Video { player, .. }) = &mut self.content
            && let Some(end) = player.playback_end(track_live_end)
        {
            self.release_chat();
            self.content = None;
            self.status = match end {
                PlaybackEnd::Error(code) => {
                    format!("播放失败（mpv {code}），请重新打开房间或更换播放源")
                }
                PlaybackEnd::Eof => "播放已结束，可刷新或更换线路".into(),
            };
            mark(&self.log, &self.status);
            self.show_controls(window, cx);
            if let Some(room) = &self.active_room {
                self.check_room_statuses(vec![room.key()], true, window, cx);
            }
        }
        if self.log.is_some() && !self.probe_reported {
            if let Some(Content::Video { player, .. }) = &self.content {
                if player
                    .property(c"time-pos")
                    .and_then(|s| s.parse::<f64>().ok())
                    .is_some_and(|pos| pos >= 6.0)
                {
                    mark(
                        &self.log,
                        format!(
                            "video_playing {} {}",
                            player.stats(),
                            player.display_stats()
                        ),
                    );
                    self.probe_reported = true;
                }
            }
        }
        if self.in_playback() {
            self.hide_playback_controls(window, cx);
        } else if self.pane == Pane::Follows
            && self.content.is_none()
            && window.is_window_active()
            && self.next_follow_check.is_none_or(|at| at <= Instant::now())
        {
            self.refresh_follow_statuses(window, cx);
        }
    }

    fn sync_gamepad(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !window.is_window_active() || native::minimized(window) {
            self.gamepad = None;
            return;
        }
        if self.gamepad.is_some() {
            return;
        }
        let (input, presses) = async_channel::bounded(8);
        let executor = cx.background_executor().clone();
        self.gamepad = Some(cx.spawn_in(window, async move |entity, cx| {
            let _poll = executor.spawn({
                let executor = executor.clone();
                async move {
                    let mut previous: Option<u16> = None;
                    let mut repeat_at: Option<Instant> = None;
                    loop {
                        // The left stick feeds the same d-pad bits, so every direction handler
                        // keeps working without a second path through the UI.
                        let pad = native::pad();
                        let buttons = pad.map(|pad| {
                            pad.buttons
                                | stick_buttons(pad.left_x, pad.left_y)
                                | trigger_buttons(pad.left_trigger, pad.right_trigger)
                        });
                        if let (Some(current), Some(last)) = (buttons, previous) {
                            let now = Instant::now();
                            let pressed = current & !last;
                            let mut send = pressed;
                            if pressed & DIRECTION_BUTTONS != 0 {
                                repeat_at = Some(now + Duration::from_millis(REPEAT_DELAY_MS));
                            } else if current & DIRECTION_BUTTONS != 0 {
                                if repeat_at.is_some_and(|at| at <= now) {
                                    send |= current & DIRECTION_BUTTONS;
                                    repeat_at =
                                        Some(now + Duration::from_millis(REPEAT_INTERVAL_MS));
                                }
                            } else {
                                repeat_at = None;
                            }
                            if send != 0 {
                                let _ = input.try_send(send);
                            }
                        }
                        previous = buttons;
                        let delay = if buttons.is_some() { 16 } else { 200 };
                        executor.timer(Duration::from_millis(delay)).await;
                    }
                }
            });
            while let Ok(pressed) = presses.recv().await {
                if entity
                    .update_in(cx, |this, window, cx| {
                        if window.is_window_active() && !native::minimized(window) {
                            this.on_gamepad(pressed, window, cx);
                        }
                    })
                    .is_err()
                {
                    break;
                }
            }
        }));
    }

    fn on_gamepad(&mut self, pressed: u16, window: &mut Window, cx: &mut Context<Self>) {
        if self.in_playback() {
            if pressed & XINPUT_GAMEPAD_B != 0 {
                self.playback_back(window, cx);
            } else if pressed & XINPUT_GAMEPAD_A != 0 {
                self.confirm_playback(window, cx);
            } else if pressed & XINPUT_GAMEPAD_X != 0 {
                self.playback_action(1, window, cx);
            } else if pressed & XINPUT_GAMEPAD_Y != 0 {
                self.playback_action(5, window, cx);
            } else if self.playback.menu.is_some()
                && pressed & (XINPUT_GAMEPAD_LEFT_SHOULDER | XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0
            {
                self.page_playback(pressed & XINPUT_GAMEPAD_RIGHT_SHOULDER != 0, window, cx);
            } else if self.playback.menu.is_none()
                && pressed & (XINPUT_GAMEPAD_LEFT_SHOULDER | XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0
            {
                self.switch_follow(pressed & XINPUT_GAMEPAD_RIGHT_SHOULDER != 0, window, cx);
            } else if self.playback.menu.is_none()
                && !self.playback.visible()
                && pressed & (XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_DPAD_RIGHT) != 0
            {
                self.switch_follow(pressed & XINPUT_GAMEPAD_DPAD_RIGHT != 0, window, cx);
            } else if pressed & XINPUT_GAMEPAD_DPAD_UP != 0 {
                self.move_playback_vertical(false, window, cx);
            } else if pressed & XINPUT_GAMEPAD_DPAD_DOWN != 0 {
                self.move_playback_vertical(true, window, cx);
            } else if pressed & (XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_LEFT_SHOULDER) != 0 {
                self.move_playback(-1, window, cx);
            } else if pressed & (XINPUT_GAMEPAD_DPAD_RIGHT | XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0 {
                self.move_playback(1, window, cx);
            }
            return;
        }
        // Bumpers switch the row at the top of the current page: the follow filters
        // on 关注, the platform strip on 热门 (selected right away so the list
        // reloads); the triggers switch the main tabs.
        if pressed & XINPUT_GAMEPAD_LEFT_SHOULDER != 0 {
            self.page_bar(false, window, cx);
        }
        if pressed & XINPUT_GAMEPAD_RIGHT_SHOULDER != 0 {
            self.page_bar(true, window, cx);
        }
        if pressed & TRIGGER_LEFT != 0 {
            self.step_pane(-1, window, cx);
        }
        if pressed & TRIGGER_RIGHT != 0 {
            self.step_pane(1, window, cx);
        }
        if pressed & XINPUT_GAMEPAD_DPAD_LEFT != 0 {
            self.move_selection(false, cx);
        }
        if pressed & XINPUT_GAMEPAD_DPAD_RIGHT != 0 {
            self.move_selection(true, cx);
        }
        if pressed & XINPUT_GAMEPAD_A != 0 {
            self.confirm(window, cx);
        }
        if pressed & XINPUT_GAMEPAD_DPAD_UP != 0 {
            self.move_room(false, cx);
        }
        if pressed & XINPUT_GAMEPAD_DPAD_DOWN != 0 {
            self.move_room(true, cx);
        }
        if pressed & XINPUT_GAMEPAD_Y != 0 && self.platform_cursor.is_none() {
            if let Some(room) = self
                .room_selection
                .and_then(|index| self.room_at(index))
                .cloned()
            {
                self.toggle_follow(room, cx);
            }
        }
        if pressed & XINPUT_GAMEPAD_X != 0
            && self.content.is_none()
            && (self.platform_cursor.is_none() || self.pane == Pane::Popular)
        {
            if self.pane == Pane::Follows {
                self.refresh_follow_statuses(window, cx);
            } else {
                self.select_pane(Pane::Search, window, cx);
                self.query.read(cx).focus_handle(cx).focus(window, cx);
            }
        }
        if pressed & XINPUT_GAMEPAD_START != 0
            && self.pane == Pane::Search
            && self.content.is_none()
        {
            self.choose(Action::SearchPlatform, window, cx);
        }
        if pressed & XINPUT_GAMEPAD_B != 0 {
            self.go_back(window, cx);
        }
    }
}

impl Render for Home {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .track_focus(&self.focus)
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, window, cx| {
                if this.in_playback() {
                    match event.keystroke.key.as_str() {
                        "left" => this.move_playback(-1, window, cx),
                        "right" => this.move_playback(1, window, cx),
                        "up" => this.move_playback_vertical(false, window, cx),
                        "down" => this.move_playback_vertical(true, window, cx),
                        "enter" => this.confirm_playback(window, cx),
                        "escape" => this.playback_back(window, cx),
                        "space" if !event.is_held => this.playback_action(0, window, cx),
                        "r" if !event.is_held => this.playback_action(1, window, cx),
                        "d" if !event.is_held => this.playback_action(2, window, cx),
                        "y" if !event.is_held => this.playback_action(5, window, cx),
                        "m" if !event.is_held => this.toggle_mute(window, cx),
                        "-" if !event.is_held => this.adjust_volume(-5, window, cx),
                        "+" | "=" if !event.is_held => this.adjust_volume(5, window, cx),
                        _ => {}
                    }
                    return;
                }
                if event.keystroke.key == "f2"
                    && this.pane == Pane::Search
                    && this.content.is_none()
                {
                    this.choose(Action::SearchPlatform, window, cx);
                    return;
                }
                if this.query.read(cx).focus_handle(cx).is_focused(window) {
                    if event.keystroke.key == "escape" {
                        this.focus.focus(window, cx);
                    }
                    return;
                }
                match event.keystroke.key.as_str() {
                    "left" => this.move_selection(false, cx),
                    "right" => this.move_selection(true, cx),
                    "up" => this.move_room(false, cx),
                    "down" => this.move_room(true, cx),
                    "enter" => this.confirm(window, cx),
                    "escape" => this.go_back(window, cx),
                    "r" if !event.is_held
                        && this.pane == Pane::Follows
                        && this.content.is_none() =>
                    {
                        this.refresh_follow_statuses(window, cx);
                    }
                    "y" if !event.is_held && this.platform_cursor.is_none() => {
                        if let Some(room) = this
                            .room_selection
                            .and_then(|index| this.room_at(index))
                            .cloned()
                        {
                            this.toggle_follow(room, cx);
                        }
                    }
                    _ => {}
                }
            }))
            .child(self.view(cx))
    }
}

fn main() {
    let options = Options::read();
    gpui_kit::application()
        .with_quit_mode(QuitMode::LastWindowClosed)
        .run(move |cx| {
            gpui_kit::init(cx);
            style::init_theme(cx);
            let bounds = Bounds::centered(None, size(px(920.0), px(550.0)), cx);
            let window = WindowOptions {
                titlebar: None,
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                window_min_size: Some(size(px(620.0), px(300.0))),
                ..WindowOptions::default()
            };
            gpui_kit::open_window(window, cx, |window, cx| {
                cx.new(|cx| Home::new(options, window, cx))
            })
            .expect("open PureLive window");
        });
}

/// The left stick counts as a d-pad once it passes this fraction of full tilt.
const STICK_DEADZONE: f32 = 0.45;
/// The bits a held direction repeats, so lists keep moving like a d-pad would.
const DIRECTION_BUTTONS: u16 = XINPUT_GAMEPAD_DPAD_UP
    | XINPUT_GAMEPAD_DPAD_DOWN
    | XINPUT_GAMEPAD_DPAD_LEFT
    | XINPUT_GAMEPAD_DPAD_RIGHT;
/// Delay before a held direction starts repeating, and the interval after that.
const REPEAT_DELAY_MS: u64 = 350;
const REPEAT_INTERVAL_MS: u64 = 90;

fn stick_buttons(x: i16, y: i16) -> u16 {
    let x = f32::from(x) / 32767.0;
    let y = f32::from(y) / 32767.0;
    let mut buttons = 0;
    if y > STICK_DEADZONE {
        buttons |= XINPUT_GAMEPAD_DPAD_UP;
    }
    if y < -STICK_DEADZONE {
        buttons |= XINPUT_GAMEPAD_DPAD_DOWN;
    }
    if x < -STICK_DEADZONE {
        buttons |= XINPUT_GAMEPAD_DPAD_LEFT;
    }
    if x > STICK_DEADZONE {
        buttons |= XINPUT_GAMEPAD_DPAD_RIGHT;
    }
    buttons
}

/// The triggers are analogue, so they get the two button bits XInput leaves free.
const TRIGGER_LEFT: u16 = 0x0400;
const TRIGGER_RIGHT: u16 = 0x0800;
/// How far a trigger has to travel before it counts as pressed.
const TRIGGER_THRESHOLD: u8 = 30;

fn trigger_buttons(left: u8, right: u8) -> u16 {
    let mut buttons = 0;
    if left > TRIGGER_THRESHOLD {
        buttons |= TRIGGER_LEFT;
    }
    if right > TRIGGER_THRESHOLD {
        buttons |= TRIGGER_RIGHT;
    }
    buttons
}
