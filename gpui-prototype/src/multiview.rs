use super::*;
use plugins::multiview::{Layout, MAX_ROOMS, Tile};

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(default)]
pub(super) struct Preferences {
    pub layout: Layout,
    pub show_titles: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self { layout: Layout::Auto, show_titles: true }
    }
}

#[derive(Default)]
pub(super) struct MultiView {
    pub rooms: Vec<Room>,
    pub slots: Option<Vec<Slot>>,
    pub audible: usize,
    pub all_audio: bool,
    pub settings_open: bool,
    pub preferences: Preferences,
    layouts: Option<[Vec<Tile>; 4]>,
    pub notice: String,
    generation: u64,
}

pub(super) struct Slot {
    pub room: Room,
    pub status: String,
    tile: Option<Tile>,
    video: Option<Video>,
}

struct Video {
    player: Player,
    surface: Surface,
    playback: compat::Playback,
    chat: Option<compat::Chat>,
    danmaku: danmaku::Overlay,
    danmaku_reported: bool,
    _lease: Option<compat::Bridge>,
}

impl Video {
    fn open_chat(&mut self, directory: &Path, room: &Room, cookie: Option<&str>) -> Result<(), String> {
        if self.playback.chat && self.chat.is_none() {
            self.chat = Some(compat::chat(directory, room, cookie, true)?);
        }
        Ok(())
    }

    fn close_chat(&mut self) {
        self.chat = None;
        self.danmaku = danmaku::Overlay::default();
        self.player.set_danmaku(Vec::new());
    }
}

impl Slot {
    pub fn playing(&self) -> bool {
        self.video.is_some()
    }
}

impl Home {
    pub(super) fn multiview_title_height(&self) -> f32 {
        if self.multiview.preferences.show_titles { 48.0 } else { 0.0 }
    }

    pub(super) fn multiview_plugin(&self) -> Option<PathBuf> {
        let path = self.follows_path.with_file_name("plugins").join("purelive-multiview.exe");
        path.is_file().then_some(path)
    }

    pub(super) fn queue_multiview_room(&mut self, room: Room, cx: &mut Context<Self>) {
        let rooms = &mut self.multiview.rooms;
        if let Some(index) = rooms.iter().position(|item| item.key() == room.key()) {
            rooms.remove(index);
            self.multiview.notice.clear();
        } else if rooms.len() == MAX_ROOMS {
            self.multiview.notice = "最多选择 4 个直播间。".into();
        } else {
            rooms.push(room);
            self.multiview.notice.clear();
        }
        cx.notify();
    }

    pub(super) fn open_multiview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(executable) = self.multiview_plugin() else { return };
        if self.multiview.slots.is_some() || self.content.is_some() {
            return;
        }
        let count = self.multiview.rooms.len();
        if count < 2 {
            self.multiview.notice = "先在房间卡片上选择至少 2 个直播间。".into();
            cx.notify();
            return;
        }

        self.request_id += 1;
        self.active_room = None;
        self.reopen_video = false;
        self.multiview.generation += 1;
        let generation = self.multiview.generation;
        self.multiview.audible = 0;
        self.multiview.all_audio = false;
        self.multiview.settings_open = false;
        self.multiview.layouts = None;
        let settings = self.follows_path.with_file_name("plugins").join("multiview.json");
        self.multiview.preferences = plugin_config::load(&settings).unwrap_or_default();
        self.multiview.notice.clear();
        self.multiview.slots = Some(self.multiview.rooms.iter().map(|room| Slot {
            room: room.clone(),
            status: "正在连接…".into(),
            tile: None,
            video: None,
        }).collect());
        self.focus.focus(window, cx);
        cx.notify();

        let pending = cx.background_spawn(async move { plugins::multiview::layouts(&executable, count) });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if this.multiview.generation != generation {
                    return;
                }
                match result {
                    Ok(layouts) => {
                        let tiles = layouts[this.multiview.preferences.layout.index()].clone();
                        this.multiview.layouts = Some(layouts);
                        this.start_multiview_tiles(tiles, generation, window, cx);
                    }
                    Err(error) => {
                        this.multiview.slots = None;
                        this.multiview.notice = format!("无法打开同屏：{error}");
                        cx.notify();
                    }
                }
            });
        }).detach();
    }

    fn start_multiview_tiles(&mut self, tiles: Vec<Tile>, generation: u64, window: &mut Window, cx: &mut Context<Self>) {
        let Some(slots) = &mut self.multiview.slots else { return };
        let rooms: Vec<_> = slots.iter_mut().zip(tiles).map(|(slot, tile)| {
            slot.tile = Some(tile);
            slot.room.clone()
        }).collect();
        for room in rooms {
            self.load_multiview_source(room, generation, None, window, cx);
        }
    }

    fn load_multiview_source(
        &self,
        room: Room,
        generation: u64,
        finished: Option<live::FinishedReplay>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let key = room.key();
        let directory = self.options.directory.clone();
        let cookie = self.accounts.get(&room.platform).map(|account| account.cookie.clone());
        let pending = cx.background_spawn(async move {
            if let Some(finished) = finished {
                live::continue_carousel(&directory, &room, cookie.as_deref(), &finished)
            } else {
                live::resolve(&directory, &room, cookie.as_deref(), &compat::Selection::default())
            }
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if this.multiview.generation != generation {
                    return;
                }
                let Some(index) = this.multiview.slots.as_ref()
                    .and_then(|slots| slots.iter().position(|slot| slot.room.key() == key)) else { return };
                let panel = this.multiview_panel(window);
                let title_height = this.multiview_title_height();
                let muted = this.audio.muted || (!this.multiview.all_audio && this.multiview.audible != index);
                let audio = AudioSettings { muted, ..this.audio };
                let Some(slot) = this.multiview.slots.as_mut().and_then(|slots| slots.get_mut(index)) else { return };
                slot.status = match result.and_then(|source| {
                    let tile = slot.tile.ok_or("画面位置暂不可用")?;
                    let surface = Surface::video_tile(window, title_height, tile, panel)?;
                    let player = Player::start(surface.id(), hardware_player::Input::from_source(&source), false, audio)
                        .map_err(|error| error.to_string())?;
                    let mut video = Video {
                        player, surface, playback: source.playback, _lease: source.lease,
                        chat: None, danmaku: danmaku::Overlay::default(), danmaku_reported: false,
                    };
                    if this.danmaku_enabled {
                        let cookie = this.accounts.get(&slot.room.platform).map(|account| account.cookie.as_str());
                        if let Err(error) = video.open_chat(&this.options.directory, &slot.room, cookie) {
                            mark(&this.log, error);
                        }
                    }
                    slot.video = Some(video);
                    Ok(())
                }) {
                    Ok(()) => String::new(),
                    Err(error) => error,
                };
                cx.notify();
            });
        }).detach();
    }

    pub(super) fn close_multiview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.multiview.generation += 1;
        self.multiview.slots = None;
        self.multiview.settings_open = false;
        self.multiview.layouts = None;
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn multiview_audio(&mut self, index: usize, cx: &mut Context<Self>) {
        let Some(slots) = &self.multiview.slots else { return };
        if index >= slots.len() {
            return;
        }
        self.multiview.audible = index;
        self.multiview.all_audio = false;
        self.apply_multiview_audio(cx);
    }

    pub(super) fn toggle_multiview_all_audio(&mut self, cx: &mut Context<Self>) {
        self.multiview.all_audio = !self.multiview.all_audio;
        self.apply_multiview_audio(cx);
    }

    pub(super) fn toggle_multiview_chat(&mut self, cx: &mut Context<Self>) {
        self.danmaku_enabled = !self.danmaku_enabled;
        if self.save_danmaku_preference().is_err() {
            self.multiview.notice = "弹幕已切换，无法保存到本地".into();
        }
        if let Some(slots) = &mut self.multiview.slots {
            for slot in slots {
                let Some(video) = &mut slot.video else { continue };
                if self.danmaku_enabled {
                    let cookie = self.accounts.get(&slot.room.platform).map(|account| account.cookie.as_str());
                    if let Err(error) = video.open_chat(&self.options.directory, &slot.room, cookie) {
                        mark(&self.log, error);
                    }
                } else {
                    video.close_chat();
                }
            }
        }
        cx.notify();
    }

    pub(super) fn draw_multiview_chat(&self) {
        if let Some(slots) = &self.multiview.slots {
            for video in slots.iter().filter_map(|slot| slot.video.as_ref()) {
                if video.danmaku.active() {
                    video.danmaku.draw(&video.player, &self.emotes);
                }
            }
        }
    }

    fn update_multiview_chat(&mut self, cx: &mut Context<Self>) {
        let Some(slots) = &mut self.multiview.slots else { return };
        let now = Instant::now();
        let mut pictures = Vec::new();
        for slot in slots {
            let Some(video) = &mut slot.video else { continue };
            let Some(chat) = &video.chat else { continue };
            let mut changed = video.danmaku.advance(now, &self.plugins);
            let mut disconnected = false;
            for _ in 0..32 {
                let event = match chat.events.try_recv() {
                    Ok(event) if event.error.is_none() && event.state.as_deref() != Some("closed") => event,
                    Err(async_channel::TryRecvError::Empty) => break,
                    _ => {
                        disconnected = true;
                        break;
                    }
                };
                if let Some(text) = event.text {
                    changed |= video.danmaku.push(
                        now, &slot.room.platform, &text, &event.emotes, &self.plugins, &mut pictures,
                    );
                }
            }
            if disconnected {
                video.close_chat();
                continue;
            }
            if changed {
                video.danmaku.draw(&video.player, &self.emotes);
            }
            if self.log.is_some() && !video.danmaku_reported && video.player.danmaku_rendered().0 {
                video.danmaku_reported = true;
                mark(&self.log, format!("multiview_danmaku_rendered={}/{}", slot.room.platform, slot.room.id));
            }
        }
        self.load_danmaku_emotes(pictures, cx);
    }

    fn apply_multiview_audio(&self, cx: &mut Context<Self>) {
        if let Some(slots) = &self.multiview.slots {
            for (index, slot) in slots.iter().enumerate() {
                if let Some(video) = &slot.video {
                    let muted = self.audio.muted
                        || (!self.multiview.all_audio && self.multiview.audible != index);
                    video.player.set_muted(muted);
                }
            }
        }
        cx.notify();
    }

    pub(super) fn toggle_multiview_settings(&mut self, window: &Window, cx: &mut Context<Self>) {
        self.multiview.settings_open = !self.multiview.settings_open;
        self.multiview_resize(window);
        cx.notify();
    }

    pub(super) fn toggle_multiview_titles(&mut self, window: &Window, cx: &mut Context<Self>) {
        self.multiview.preferences.show_titles = !self.multiview.preferences.show_titles;
        self.save_multiview_preferences();
        self.multiview_resize(window);
        cx.notify();
    }

    pub(super) fn choose_multiview_layout(&mut self, layout: Layout, window: &Window, cx: &mut Context<Self>) {
        self.multiview.preferences.layout = layout;
        if let (Some(slots), Some(layouts)) = (&mut self.multiview.slots, &self.multiview.layouts) {
            for (slot, tile) in slots.iter_mut().zip(&layouts[layout.index()]) {
                slot.tile = Some(*tile);
            }
        }
        self.save_multiview_preferences();
        self.multiview_resize(window);
        cx.notify();
    }

    pub(super) fn step_multiview_layout(&mut self, forward: bool, window: &Window, cx: &mut Context<Self>) {
        let count = Layout::OPTIONS.len();
        let step = if forward { 1 } else { count - 1 };
        let index = (self.multiview.preferences.layout.index() + step) % count;
        self.choose_multiview_layout(Layout::OPTIONS[index].0, window, cx);
    }

    fn save_multiview_preferences(&mut self) {
        let path = self.follows_path.with_file_name("plugins").join("multiview.json");
        self.multiview.notice = match playback::save_preference(&path, &self.multiview.preferences) {
            Ok(()) => String::new(),
            Err(error) => format!("无法保存同屏设置：{error}"),
        };
    }

    pub(super) fn swap_multiview_rooms(&mut self, key: &RoomKey, target: usize, window: &Window, cx: &mut Context<Self>) {
        let Some(slots) = &mut self.multiview.slots else { return };
        let Some(source) = slots.iter().position(|slot| slot.room.key() == *key) else { return };
        if source == target || target >= slots.len() {
            return;
        }
        let tiles = (slots[source].tile, slots[target].tile);
        slots.swap(source, target);
        slots[source].tile = tiles.0;
        slots[target].tile = tiles.1;
        self.multiview.rooms.swap(source, target);
        if self.multiview.audible == source {
            self.multiview.audible = target;
        } else if self.multiview.audible == target {
            self.multiview.audible = source;
        }
        self.multiview_resize(window);
        cx.notify();
    }


    pub(super) fn multiview_panel(&self, window: &Window) -> Option<floating_panel::Bounds> {
        if !self.multiview.settings_open {
            return None;
        }
        let (width, height) = native::client_size(window);
        Some(floating_panel::multiview_settings(width, height, self.multiview_title_height()))
    }


    pub(super) fn multiview_resize(&self, window: &Window) {
        if let Some(slots) = &self.multiview.slots {
            let title_height = self.multiview_title_height();
            let panel = self.multiview_panel(window);
            for slot in slots {
                if let (Some(video), Some(tile)) = (&slot.video, slot.tile) {
                    video.surface.resize_tile(window, title_height, tile, panel);
                }
            }
        }
    }

    pub(super) fn multiview_tick(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(slots) = &mut self.multiview.slots else { return };
        let mut continuations = Vec::new();
        for slot in slots {
            let Some(video) = &slot.video else { continue };
            let Some(end) = video.player.take_end() else { continue };
            slot.status = match end {
                PlaybackEnd::Eof if video.playback.is_carousel() => {
                    let finished = live::FinishedReplay::new(&video.playback, video.player.media_position_ms());
                    continuations.push((slot.room.clone(), finished));
                    "正在接续回放…".into()
                }
                PlaybackEnd::Eof => "直播已结束".into(),
                PlaybackEnd::Failed(error) => error,
            };
            slot.video = None;
            cx.notify();
        }
        for (room, finished) in continuations {
            self.load_multiview_source(room, self.multiview.generation, Some(finished), window, cx);
        }
        if self.danmaku_enabled {
            self.update_multiview_chat(cx);
        }
    }
}
