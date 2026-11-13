#[cfg(target_os = "macos")]
use std::collections::VecDeque;
use std::time::{Duration, Instant};

use async_channel::{Receiver, TryRecvError};

use super::*;
use compat::{ChatEvent, Choice, Playback, Selection, SuperChat};

pub(super) const CONTROL_HEIGHT: f32 = 144.0;
pub(super) const DIRECT_HEIGHT: f32 = 96.0;
pub(super) const CHOICES_HEIGHT: f32 = 86.0;
pub(super) const VOLUME_HEIGHT: f32 = 112.0;
pub(super) const SUPER_CHAT_HEIGHT: f32 = 206.0;
pub(super) const CHOICES_PER_PAGE: usize = 3;
const ROOM_ACTIONS: [usize; 8] = [0, 1, 6, 2, 3, 4, 7, 5];
const DIRECT_ACTIONS: [usize; 4] = [0, 1, 6, 2];
const HIDE_DELAY: Duration = Duration::from_secs(5);
const CHAT_TICK: Duration = Duration::from_millis(16);
#[cfg(windows)]
const CHAT_DURATION: Duration = Duration::from_secs(7);
const SUPER_CHAT_INTERVAL: Duration = Duration::from_secs(30);
const SUPER_CHAT_LIMIT: usize = 100;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ChoiceMenu {
    Lines,
    Qualities,
    Volume,
    SuperChat,
}

#[derive(Clone, Copy, PartialEq, Eq, serde::Deserialize, serde::Serialize)]
#[serde(default)]
pub(super) struct AudioSettings {
    pub volume: u8,
    pub muted: bool,
}

impl Default for AudioSettings {
    fn default() -> Self {
        Self {
            volume: 100,
            muted: false,
        }
    }
}

impl AudioSettings {
    pub fn load(path: &std::path::Path) -> Self {
        let mut audio: Self = fs::read(path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        audio.volume = audio.volume.min(100);
        audio
    }

    fn save(self, path: &std::path::Path) -> std::io::Result<()> {
        save_preference(path, &self)
    }
}

fn save_preference(path: &std::path::Path, value: &impl serde::Serialize) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&temp, serde_json::to_vec(value)?)?;
    fs::rename(temp, path)
}

pub(super) fn load_danmaku_preference(path: &std::path::Path) -> bool {
    fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or(true)
}

#[derive(Default)]
pub(super) struct SuperChatHistory {
    pub entries: Vec<SuperChat>,
    pub loading: bool,
    pub error: Option<String>,
    pub connection: Option<&'static str>,
    enabled: bool,
    next_fetch: Option<Instant>,
}

impl SuperChatHistory {
    fn merge(&mut self, incoming: impl IntoIterator<Item = SuperChat>) {
        for item in incoming {
            if !self.entries.iter().any(|saved| saved.same_event(&item)) {
                self.entries.push(item);
            }
        }
        self.entries
            .sort_by_key(|item| std::cmp::Reverse(item.start));
        self.entries.truncate(SUPER_CHAT_LIMIT);
    }
}

#[derive(Default)]
pub(super) struct PlaybackUi {
    pub direct: bool,
    pub busy: bool,
    pub paused: bool,
    pub focus: usize,
    pub menu: Option<ChoiceMenu>,
    pub cursor: usize,
    pub options: Playback,
    pub selection: Selection,
    pub resume_selection: Option<Selection>,
    pub chat_enabled: bool,
    pub super_chats: SuperChatHistory,
    hide_at: Option<Instant>,
    chat: Option<compat::Chat>,
    chat_updates: Option<Task<()>>,
    messages: Vec<FlyingMessage>,
    #[cfg(target_os = "macos")]
    waiting_messages: VecDeque<FlyingMessage>,
}

struct FlyingMessage {
    parts: Vec<emotes::Segment>,
    widths: Vec<f32>,
    width: f32,
    time: Instant,
    row: usize,
}

impl PlaybackUi {
    pub fn update_chat_filter(&self) {
        if let Some(chat) = &self.chat {
            chat.set_text_enabled(self.chat_enabled && !self.paused);
        }
    }

    pub fn actions(&self) -> Vec<usize> {
        if self.direct {
            return DIRECT_ACTIONS.to_vec();
        }
        ROOM_ACTIONS
            .into_iter()
            .filter(|action| match action {
                3 => !self.options.lines.is_empty(),
                4 => !self.options.qualities.is_empty(),
                7 => self.options.super_chat,
                _ => true,
            })
            .collect()
    }

    pub fn visible(&self) -> bool {
        self.hide_at.is_some()
    }

    pub fn height(&self) -> f32 {
        match self.menu {
            Some(ChoiceMenu::Volume) => VOLUME_HEIGHT,
            Some(ChoiceMenu::SuperChat) => SUPER_CHAT_HEIGHT,
            Some(ChoiceMenu::Lines | ChoiceMenu::Qualities) => CHOICES_HEIGHT,
            None if self.visible() && self.direct => DIRECT_HEIGHT,
            None if self.visible() => CONTROL_HEIGHT,
            None => 0.0,
        }
    }

    pub fn choices(&self, menu: ChoiceMenu) -> &[Choice] {
        match menu {
            ChoiceMenu::Lines => &self.options.lines,
            ChoiceMenu::Qualities => &self.options.qualities,
            _ => &[],
        }
    }

    pub fn current(&self, menu: ChoiceMenu) -> Option<&str> {
        match menu {
            ChoiceMenu::Lines => self.options.line.as_deref(),
            ChoiceMenu::Qualities => self.options.quality.as_deref(),
            _ => None,
        }
    }
}

impl Home {
    pub(super) fn in_playback(&self) -> bool {
        self.active_room.is_some() || self.playback.direct
    }

    pub(super) fn show_controls(&mut self, window: &Window, cx: &mut Context<Self>) {
        self.playback.hide_at = Some(Instant::now() + HIDE_DELAY);
        self.resize_video(window);
        cx.notify();
    }

    pub(super) fn toggle_controls(&mut self, window: &Window, cx: &mut Context<Self>) {
        if self.playback.visible() {
            self.playback.menu = None;
            self.playback.hide_at = None;
            self.resize_video(window);
            cx.notify();
        } else {
            self.show_controls(window, cx);
        }
    }

    pub(super) fn resize_video(&self, window: &Window) {
        if let Some(Content::Video { surface, .. }) = &self.content {
            surface.resize_video(window, self.playback.height());
        }
    }

    pub(super) fn playback_back(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.playback.menu.take().is_some() {
            self.show_controls(window, cx);
        } else if self.playback.visible() {
            self.toggle_controls(window, cx);
        } else {
            self.leave_playback(window, cx);
        }
    }

    pub(super) fn leave_playback(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.request_id += 1;
        self.playback_epoch += 1;
        let room = self.active_room.take();
        self.reopen_video = false;
        self.content = None;
        self.playback = PlaybackUi::default();
        self.status.clear();
        if self.pane == Pane::Follows {
            self.next_follow_check = None;
        } else if let Some(room) = room {
            self.check_room_statuses(vec![room.key()], false, window, cx);
        }
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn move_playback(&mut self, delta: isize, window: &Window, cx: &mut Context<Self>) {
        match self.playback.menu {
            Some(ChoiceMenu::Volume) => {
                return self.adjust_volume(delta.signum() as i16 * 5, window, cx);
            }
            Some(ChoiceMenu::SuperChat) => {
                self.playback.cursor = self
                    .playback
                    .cursor
                    .saturating_add_signed(delta)
                    .min(self.playback.super_chats.entries.len().saturating_sub(1));
            }
            Some(menu) => {
                let count = self.playback.choices(menu).len() + 1;
                self.playback.cursor =
                    (self.playback.cursor as isize + delta).rem_euclid(count as isize) as usize;
            }
            None if self.playback.visible() => {
                let actions = self.playback.actions();
                let current = actions
                    .iter()
                    .position(|&id| id == self.playback.focus)
                    .unwrap_or(0);
                self.playback.focus =
                    actions[(current as isize + delta).rem_euclid(actions.len() as isize) as usize];
            }
            None => {}
        }
        self.show_controls(window, cx);
    }

    pub(super) fn move_playback_vertical(
        &mut self,
        down: bool,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        if self.playback.menu == Some(ChoiceMenu::Volume) {
            self.adjust_volume(if down { -5 } else { 5 }, window, cx);
            return;
        }
        if self.playback.menu.is_some() {
            self.move_playback(if down { 1 } else { -1 }, window, cx);
            return;
        }
        if self.playback.visible() && !self.playback.direct {
            let actions = self.playback.actions();
            let current = actions
                .iter()
                .position(|&id| id == self.playback.focus)
                .unwrap_or(0);
            let next = if current < 4 {
                (current + 4).min(actions.len() - 1)
            } else {
                current - 4
            };
            self.playback.focus = actions[next];
        }
        self.show_controls(window, cx);
    }

    pub(super) fn confirm_playback(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.playback.visible() {
            match self.playback.menu {
                Some(ChoiceMenu::Volume) => self.toggle_mute(window, cx),
                Some(ChoiceMenu::SuperChat) => self.refresh_super_chats(window, cx),
                Some(_) => self.apply_playback_choice(self.playback.cursor, window, cx),
                None => self.playback_action(self.playback.focus, window, cx),
            }
        } else {
            self.show_controls(window, cx);
        }
    }

    pub(super) fn page_playback(&mut self, forward: bool, window: &Window, cx: &mut Context<Self>) {
        let Some(menu) = self.playback.menu else {
            return;
        };
        if matches!(menu, ChoiceMenu::Volume | ChoiceMenu::SuperChat) {
            self.move_playback(if forward { 1 } else { -1 }, window, cx);
            return;
        }
        let count = self.playback.choices(menu).len() + 1;
        let pages = count.div_ceil(CHOICES_PER_PAGE);
        let page = self.playback.cursor / CHOICES_PER_PAGE;
        let step = if forward { 1 } else { pages - 1 };
        self.playback.cursor = (page + step) % pages * CHOICES_PER_PAGE;
        self.show_controls(window, cx);
    }

    pub(super) fn playback_action(
        &mut self,
        index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.playback.actions().contains(&index) {
            return;
        }
        if index == 1 && self.playback.menu == Some(ChoiceMenu::SuperChat) {
            self.refresh_super_chats(window, cx);
            return;
        }
        self.playback.focus = index;
        self.playback.menu = None;
        match index {
            0 => {
                if let Some(Content::Video { player, .. }) = &self.content {
                    let paused = !self.playback.paused;
                    player.set_paused(paused);
                    self.playback.paused = paused;
                    self.playback.update_chat_filter();
                    if paused {
                        self.clear_chat_overlay();
                    }
                    mark(&self.log, format!("paused={paused}"));
                }
            }
            1 if !self.playback.busy => self.refresh_playback(window, cx),
            2 => self.toggle_chat(window, cx),
            3 => self.open_choice_menu(ChoiceMenu::Lines),
            4 => self.open_choice_menu(ChoiceMenu::Qualities),
            5 => {
                if let Some(room) = self.active_room.clone() {
                    self.toggle_follow(room, cx);
                } else {
                    return;
                }
            }
            6 => self.playback.menu = Some(ChoiceMenu::Volume),
            7 => self.open_super_chats(window, cx),
            _ => {}
        }
        self.show_controls(window, cx);
    }

    fn open_choice_menu(&mut self, menu: ChoiceMenu) {
        let choices = self.playback.choices(menu);
        if choices.is_empty() {
            self.status = match menu {
                ChoiceMenu::Lines => "当前播放源由平台自动选线",
                ChoiceMenu::Qualities => "当前播放源由平台自动选择画质",
                _ => return,
            }
            .into();
            return;
        }
        self.playback.cursor = choices
            .iter()
            .position(|choice| Some(choice.id.as_str()) == self.playback.current(menu))
            .map_or(0, |index| index + 1);
        self.playback.menu = Some(menu);
    }

    pub(super) fn apply_playback_choice(
        &mut self,
        index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(menu) = self.playback.menu.take() else {
            return;
        };
        let id = index
            .checked_sub(1)
            .and_then(|index| self.playback.choices(menu).get(index))
            .map(|choice| choice.id.clone());
        if !self.playback.busy && (index == 0 || id.as_deref() != self.playback.current(menu)) {
            let selection = match menu {
                ChoiceMenu::Lines => Selection {
                    quality: self.playback.selection.quality.clone(),
                    line: id,
                },
                ChoiceMenu::Qualities => Selection {
                    quality: id,
                    line: None,
                },
                _ => return,
            };
            self.reload_room(selection, window, cx);
        }
        self.show_controls(window, cx);
    }

    pub(super) fn adjust_volume(&mut self, delta: i16, window: &Window, cx: &mut Context<Self>) {
        let volume = (i16::from(self.audio.volume) + delta).clamp(0, 100) as u8;
        if volume != self.audio.volume {
            if let Some(Content::Video { player, .. }) = &self.content {
                player.set_volume(volume);
            }
            self.audio.volume = volume;
            self.save_audio();
        }
        self.show_controls(window, cx);
    }

    pub(super) fn toggle_mute(&mut self, window: &Window, cx: &mut Context<Self>) {
        let muted = !self.audio.muted;
        if let Some(Content::Video { player, .. }) = &self.content {
            player.set_muted(muted);
        }
        self.audio.muted = muted;
        self.save_audio();
        self.show_controls(window, cx);
    }

    fn save_audio(&mut self) {
        if self
            .audio
            .save(&self.follows_path.with_file_name("audio.json"))
            .is_err()
        {
            self.status = "音量已调整，无法保存到本地".into();
        }
        if self.log.is_some() {
            if let Some(Content::Video { player, .. }) = &self.content {
                let volume = player.property(c"volume").unwrap_or_default();
                let mute = player.property(c"mute").unwrap_or_default();
                mark(
                    &self.log,
                    format!("audio_volume={volume} audio_mute={mute}"),
                );
            }
        }
    }

    fn open_super_chats(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.playback.options.super_chat {
            return;
        }
        self.playback.menu = Some(ChoiceMenu::SuperChat);
        self.playback.cursor = 0;
        self.playback.super_chats.enabled = true;
        self.connect_chat(window, cx);
        if self
            .playback
            .super_chats
            .next_fetch
            .is_none_or(|at| at <= Instant::now())
        {
            self.fetch_super_chat_board(window, cx);
        }
    }

    pub(super) fn refresh_super_chats(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.playback.options.super_chat {
            self.connect_chat(window, cx);
            self.fetch_super_chat_board(window, cx);
        }
        self.show_controls(window, cx);
    }

    fn fetch_super_chat_board(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.playback.options.super_chat_board || self.playback.super_chats.loading {
            return;
        }
        let Some(room) = self.active_room.clone() else {
            return;
        };
        self.playback.super_chats.loading = true;
        self.playback.super_chats.error = None;
        self.playback.super_chats.next_fetch = Some(Instant::now() + SUPER_CHAT_INTERVAL);
        let epoch = self.playback_epoch;
        let directory = self.options.directory.clone();
        let cookie = self
            .accounts
            .get(&room.platform)
            .map(|account| account.cookie.clone());
        let task = cx.background_spawn(async move {
            compat::super_chats(&directory, &room, cookie.as_deref())
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = task.await;
            let _ = entity.update_in(cx, |this, _, cx| {
                if this.playback_epoch != epoch {
                    return;
                }
                this.playback.super_chats.loading = false;
                match result {
                    Ok(entries) => this.merge_super_chats(entries),
                    Err(error) => this.playback.super_chats.error = Some(error),
                }
                if this.playback.menu == Some(ChoiceMenu::SuperChat) {
                    cx.notify();
                }
            });
        })
        .detach();
    }

    fn merge_super_chats(&mut self, entries: impl IntoIterator<Item = SuperChat>) {
        let history = &mut self.playback.super_chats;
        let previous = (self.playback.cursor > 0
            && self.playback.menu == Some(ChoiceMenu::SuperChat))
        .then(|| history.entries.get(self.playback.cursor).cloned())
        .flatten();
        history.merge(entries);
        if let Some(card) = previous {
            self.playback.cursor = history
                .entries
                .iter()
                .position(|entry| entry.same_event(&card))
                .unwrap_or_else(|| history.entries.len().saturating_sub(1));
        }
    }

    fn toggle_chat(&mut self, window: &Window, cx: &mut Context<Self>) {
        self.danmaku_enabled = !self.danmaku_enabled;
        self.playback.chat_enabled = self.danmaku_enabled && self.playback.options.chat;
        mark(
            &self.log,
            format!("danmaku_enabled={}", self.danmaku_enabled),
        );
        self.playback.update_chat_filter();
        if self.playback.chat_enabled {
            if self.playback.chat.is_some() {
                self.status = "弹幕已开启".into();
            } else {
                self.connect_chat(window, cx);
            }
        } else {
            self.clear_chat_overlay();
            if !self.playback.super_chats.enabled {
                self.release_chat();
            }
            self.status = if self.danmaku_enabled {
                "已开启弹幕，当前直播间暂无弹幕接口".into()
            } else {
                "弹幕已关闭".into()
            };
        }
        if save_preference(
            &self.follows_path.with_file_name("danmaku.json"),
            &self.danmaku_enabled,
        )
        .is_err()
        {
            self.status = "弹幕已切换，无法保存到本地".into();
        }
    }

    pub(super) fn stop_chat(&mut self) {
        self.playback.chat_enabled = false;
        self.release_chat();
    }

    pub(super) fn release_chat(&mut self) {
        self.clear_chat_overlay();
        self.playback.chat_updates = None;
        self.playback.chat = None;
    }

    fn clear_chat_overlay(&mut self) {
        if let Some(Content::Video { player, .. }) = &self.content {
            player.set_danmaku(Vec::new());
        }
        self.playback.messages.clear();
        #[cfg(target_os = "macos")]
        self.playback.waiting_messages.clear();
    }

    pub(super) fn connect_chat(&mut self, window: &Window, cx: &mut Context<Self>) {
        if (!self.playback.chat_enabled && !self.playback.super_chats.enabled)
            || !self.playback.options.chat
            || self.playback.chat.is_some()
        {
            return;
        }
        let Some(room) = &self.active_room else {
            return;
        };
        let cookie = self
            .accounts
            .get(&room.platform)
            .map(|account| account.cookie.as_str());
        let text_enabled = self.playback.chat_enabled && !self.playback.paused;
        match compat::chat(&self.options.directory, room, cookie, text_enabled) {
            Ok(chat) => {
                let events = chat.events.clone();
                self.playback.chat = Some(chat);
                self.playback.chat_updates = Some(cx.spawn_in(window, async move |entity, cx| {
                    let mut animating = false;
                    loop {
                        let first = if animating {
                            cx.background_executor().timer(CHAT_TICK).await;
                            None
                        } else {
                            Some(events.recv().await.map_err(|_| TryRecvError::Closed))
                        };
                        let Ok(Some(next)) = entity.update_in(cx, |this, window, cx| {
                            this.update_chat(first, &events, window, cx)
                        }) else {
                            break;
                        };
                        animating = next;
                        if !animating && !events.is_empty() {
                            cx.background_executor().timer(CHAT_TICK).await;
                        }
                    }
                }));
                if self.playback.chat_enabled {
                    self.status = "正在连接弹幕…".into();
                }
                self.playback.super_chats.connection = Some("正在连接实时 SC…");
            }
            Err(error) => {
                self.playback.super_chats.connection = Some("实时 SC 连接失败，按 X 重试");
                self.status = error;
            }
        }
    }

    pub(super) fn hide_playback_controls(&mut self, window: &Window, cx: &mut Context<Self>) {
        let now = Instant::now();
        if self.playback.menu.is_none()
            && !self.playback.busy
            && !self.playback.paused
            && self.playback.hide_at.is_some_and(|until| until <= now)
            && self.content.is_some()
        {
            self.toggle_controls(window, cx);
        }
    }

    fn update_chat(
        &mut self,
        mut first: Option<Result<ChatEvent, TryRecvError>>,
        events: &Receiver<ChatEvent>,
        _window: &Window,
        cx: &mut Context<Self>,
    ) -> Option<bool> {
        let now = Instant::now();
        let count = self.playback.messages.len();
        self.playback.messages.retain(|message| {
            #[cfg(windows)]
            let duration = CHAT_DURATION;
            #[cfg(target_os = "macos")]
            let duration = match &self.content {
                Some(Content::Video { player, .. }) => player.danmaku_duration(message.width),
                _ => Duration::ZERO,
            };
            now.duration_since(message.time) < duration
        });
        let mut changed = self.playback.messages.len() != count;
        let mut closed = None;
        let mut super_chats = Vec::new();
        let mut incoming = Vec::new();
        let platform = self
            .active_room
            .as_ref()
            .map_or("", |room| room.platform.as_str());
        for _ in 0..32 {
            match first.take().unwrap_or_else(|| events.try_recv()) {
                Ok(event) => {
                    if let Some(error) = event.error {
                        closed = Some(error);
                        break;
                    }
                    match event.state.as_deref() {
                        Some("ready") => {
                            if self.playback.chat_enabled {
                                self.status = "弹幕已开启".into();
                            }
                            self.playback.super_chats.connection = Some("正在接收实时 SC");
                            cx.notify();
                        }
                        Some("reconnecting") => {
                            if self.playback.chat_enabled {
                                self.status = "弹幕正在重连…".into();
                            }
                            self.playback.super_chats.connection = Some("正在重连实时 SC…");
                            cx.notify();
                        }
                        Some("closed") => {
                            closed = Some("弹幕连接已断开，可再次开启".into());
                            break;
                        }
                        _ => {}
                    }
                    if let Some(card) = event.super_chat {
                        super_chats.push(card);
                    }
                    if self.playback.chat_enabled && !self.playback.paused {
                        if let Some(text) = event.text {
                            let parts = emotes::segments(platform, &text, &event.emotes);
                            if !parts.is_empty() {
                                #[cfg(target_os = "macos")]
                                let Some(Content::Video { player, .. }) = &self.content else {
                                    continue;
                                };
                                let widths: Vec<f32> = parts
                                    .iter()
                                    .map(|part| {
                                        #[cfg(windows)]
                                        return part.width() as f32;
                                        #[cfg(target_os = "macos")]
                                        return player.danmaku_segment_width(part);
                                    })
                                    .collect();
                                let width = widths.iter().sum();
                                incoming.push(FlyingMessage {
                                    parts,
                                    widths,
                                    width,
                                    time: now,
                                    row: 0,
                                });
                            }
                        }
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Closed) => {
                    closed = Some("弹幕连接已断开，可再次开启".into());
                    break;
                }
            }
        }
        if !super_chats.is_empty() {
            self.merge_super_chats(super_chats);
            if self.log.is_some() {
                mark(
                    &self.log,
                    format!(
                        "super_chat_count={}",
                        self.playback.super_chats.entries.len()
                    ),
                );
            }
            if self.playback.visible() {
                cx.notify();
            }
        }
        if let Some(error) = closed {
            let displayed_chat = self.playback.chat_enabled;
            self.release_chat();
            if displayed_chat {
                self.status = error;
            }
            self.playback.super_chats.connection = Some("实时 SC 已断开，按 X 重试");
            cx.notify();
            return None;
        }
        #[cfg(target_os = "macos")]
        let incoming = self.admit_danmaku(incoming, now);
        #[cfg(windows)]
        let incoming = incoming
            .into_iter()
            .zip((0..5).filter(|row| {
                !self
                    .playback
                    .messages
                    .iter()
                    .any(|message| message.row == *row)
            }))
            .map(|(mut message, row)| {
                message.row = row;
                message
            })
            .collect::<Vec<_>>();
        changed |= !incoming.is_empty();
        let pictures: Vec<_> = incoming
            .iter()
            .flat_map(|message| &message.parts)
            .filter_map(|part| match part {
                emotes::Segment::Picture { source, .. } => Some(source.clone()),
                _ => None,
            })
            .collect();
        self.playback.messages.extend(incoming);
        for source in pictures {
            if self.emotes.begin(&source) {
                let requested = source.clone();
                let task = cx.background_spawn(async move { emotes::load(&requested) });
                cx.spawn(async move |entity, cx| {
                    let bitmap = task.await;
                    let _ = entity.update(cx, |this, _| {
                        this.emotes.finish(source, bitmap);
                        this.draw_chat();
                    });
                })
                .detach();
            }
        }
        let animating = !self.playback.messages.is_empty();
        if changed {
            self.draw_chat();
        }
        #[cfg(target_os = "macos")]
        if changed && animating {
            self.schedule_danmaku_frame(_window, cx);
        }
        #[cfg(target_os = "macos")]
        let animating = animating || !self.playback.waiting_messages.is_empty();
        Some(animating)
    }

    #[cfg(target_os = "macos")]
    fn admit_danmaku(&mut self, incoming: Vec<FlyingMessage>, now: Instant) -> Vec<FlyingMessage> {
        const MAX_VISIBLE: usize = 48;
        const MAX_PENDING: usize = 120;
        const MAX_WAIT: Duration = Duration::from_secs(5);
        const MAX_PER_TICK: usize = 4;

        let pending = &mut self.playback.waiting_messages;
        if !self.playback.chat_enabled || self.playback.paused {
            pending.clear();
            return Vec::new();
        }
        let Some(Content::Video { player, .. }) = &self.content else {
            pending.clear();
            return Vec::new();
        };
        pending.extend(incoming);
        while pending.front().is_some_and(|message| {
            pending.len() > MAX_PENDING || now.duration_since(message.time) >= MAX_WAIT
        }) {
            pending.pop_front();
        }

        let messages = &self.playback.messages;
        let mut rows = vec![None; player.danmaku_rows()];
        for message in messages {
            if let Some(last) = rows.get_mut(message.row) {
                *last = Some(message.time + player.danmaku_spacing(message.width));
            }
        }

        let mut admitted = Vec::new();
        let limit = MAX_VISIBLE.saturating_sub(messages.len()).min(MAX_PER_TICK);
        for _ in 0..limit {
            let Some((row, available)) = rows
                .iter_mut()
                .enumerate()
                .filter(|(_, time)| time.is_none_or(|time| time <= now))
                .min_by_key(|(_, time)| **time)
            else {
                break;
            };
            let Some(mut message) = pending.pop_front() else {
                break;
            };
            message.time = now;
            message.row = row;
            *available = Some(now + player.danmaku_spacing(message.width));
            admitted.push(message);
        }
        admitted
    }

    #[cfg(target_os = "macos")]
    fn schedule_danmaku_frame(&mut self, window: &Window, cx: &mut Context<Self>) {
        if self.danmaku_frame_pending {
            return;
        }
        self.danmaku_frame_pending = true;
        let entity = cx.weak_entity();
        window.on_next_frame(move |window, app| {
            let _ = entity.update(app, |this, cx| {
                this.danmaku_frame_pending = false;
                if let Some(Content::Video { player, .. }) = &this.content
                    && player.paint()
                {
                    this.schedule_danmaku_frame(window, cx);
                }
            });
        });
    }

    fn draw_chat(&self) {
        let Some(Content::Video { player, .. }) = &self.content else {
            return;
        };
        let lanes = self
            .playback
            .messages
            .iter()
            .map(|message| {
                let mut offset = 0.0;
                let parts = message
                    .parts
                    .iter()
                    .zip(&message.widths)
                    .map(|(segment, width)| {
                        use crate::native_danmaku::Part;
                        let part = match segment {
                            emotes::Segment::Text(text) => {
                                Part::Text(text.encode_utf16().collect())
                            }
                            emotes::Segment::Picture { source, alt } => {
                                self.emotes.get(source).map_or_else(
                                    || Part::Text(alt.encode_utf16().collect()),
                                    |bitmap| Part::Image(bitmap.clone()),
                                )
                            }
                        };
                        let positioned = (offset, part);
                        offset += width;
                        positioned
                    })
                    .collect();
                crate::native_danmaku::Lane {
                    started: message.time,
                    #[cfg(windows)]
                    duration: CHAT_DURATION,
                    width: message.width,
                    #[cfg(windows)]
                    y: 30.0 + 39.0 * message.row as f32,
                    #[cfg(target_os = "macos")]
                    y: message.row as f32,
                    parts,
                }
            })
            .collect();
        player.set_danmaku(lanes);
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AudioSettings, PlaybackUi, SuperChatHistory, load_danmaku_preference, save_preference,
    };
    use crate::compat::SuperChat;
    use std::fs;

    fn card(id: &str, start: i64, estimated: bool) -> SuperChat {
        SuperChat {
            id: id.into(),
            user: "viewer".into(),
            text: "hello".into(),
            price: "30 元".into(),
            time: "12:00".into(),
            start,
            end: start + 60,
            estimated,
            picture: false,
        }
    }

    #[test]
    fn history_merges_live_and_board_events_without_losing_later_purchases() {
        let mut history = SuperChatHistory::default();
        history.merge([card("sc-1", 20, false), card("", 100, true)]);
        history.merge([
            card("sc-1", 21, true),
            card("", 110, true),
            card("", 300, true),
        ]);
        assert_eq!(
            history
                .entries
                .iter()
                .map(|entry| entry.start)
                .collect::<Vec<_>>(),
            [300, 100, 20]
        );
    }

    #[test]
    fn super_chat_control_is_only_available_for_supported_rooms() {
        let mut ui = PlaybackUi::default();
        assert_eq!(ui.actions(), [0, 1, 6, 2, 5]);
        assert!(!ui.actions().contains(&7));
        ui.options.super_chat = true;
        assert!(ui.actions().contains(&7));
        ui.direct = true;
        assert!(!ui.actions().contains(&7));
    }

    #[test]
    fn danmaku_is_on_by_default_and_keeps_an_explicit_off_choice() {
        let path =
            std::env::temp_dir().join(format!("purelive-danmaku-{}.json", std::process::id()));
        assert!(load_danmaku_preference(&path));
        save_preference(&path, &false).unwrap();
        assert!(!load_danmaku_preference(&path));
        save_preference(&path, &true).unwrap();
        assert!(load_danmaku_preference(&path));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn audio_settings_persist_volume_and_mute_and_clamp_saved_values() {
        let path = std::env::temp_dir().join(format!("purelive-audio-{}.json", std::process::id()));
        assert!(AudioSettings::load(&path) == AudioSettings::default());
        AudioSettings {
            volume: 35,
            muted: true,
        }
        .save(&path)
        .unwrap();
        let audio = AudioSettings::load(&path);
        assert_eq!(audio.volume, 35);
        assert!(audio.muted);
        AudioSettings {
            volume: 200,
            muted: false,
        }
        .save(&path)
        .unwrap();
        assert_eq!(AudioSettings::load(&path).volume, 100);
        fs::remove_file(path).unwrap();
    }
}
