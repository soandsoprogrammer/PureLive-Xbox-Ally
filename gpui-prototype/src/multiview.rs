use super::*;
use std::collections::VecDeque;

pub(super) const HEADER: f32 = 56.0;
pub(super) const FOOTER: f32 = 48.0;

#[derive(Default)]
pub(super) struct MultiView {
    pub canvas: plugins::multiview_canvas::Canvas,
    pub resize: plugins::multiview_resize::Resize,
    pub selection: plugins::multiview::Selection<Room>,
    pub slots: Option<Vec<Slot>>,
    pub audible: usize,
    pub all_audio: bool,
    generation: u64,
    layouts: Option<[Vec<plugins::multiview::Tile>; 4]>,
    pub layout: plugins::multiview::Layout,
}

pub(super) struct Slot {
    pub room: Room,
    pub status: String,
    video: Option<Video>,
}

// Drop the player before its native view and the source's local relay.
struct Video {
    player: Player,
    surface: Surface,
    chat: Option<compat::Chat>,
    messages: Vec<Message>,
    waiting: VecDeque<Message>,
    _lease: Option<compat::Bridge>,
}

struct Message {
    started: Instant,
    row: usize,
    width: f32,
    parts: Vec<(f32, emotes::Segment)>,
}

impl MultiView {
    pub fn cancel(&mut self) {
        self.selection.cancel();
    }
    pub fn contains(&self, room: &Room) -> bool {
        self.selection
            .items
            .iter()
            .any(|item| item.same_channel(room))
    }
    pub fn toggle_room(&mut self, room: Room) {
        if self.slots.is_none() {
            self.selection.toggle_item(room, Room::same_channel);
        }
    }
}


impl Home {
    pub(super) fn toggle_multiview_selection(&mut self, cx: &mut Context<Self>) {
        if self.multiview_plugin().is_none() {
            return;
        }
        self.multiview.selection.toggle();
        cx.notify();
    }

    pub(super) fn cancel_multiview_selection(&mut self, cx: &mut Context<Self>) {
        self.multiview.cancel();
        cx.notify();
    }

    pub(super) fn open_multiview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(executable) = self.multiview_plugin() else {
            return;
        };
        if !self.multiview.selection.active
            || self.multiview.slots.is_some()
            || self.content.is_some()
        {
            return;
        }
        if !self.multiview.selection.can_start() {
            self.multiview.selection.notice = "请选择至少 2 个直播间".into();
            cx.notify();
            return;
        }
        self.stop_chat();
        self.request_id += 1;
        self.active_room = None;
        self.multiview.generation += 1;
        let generation = self.multiview.generation;
        self.multiview.selection.active = false;
        self.multiview.selection.notice.clear();
        self.multiview.audible = 0;
        self.multiview.all_audio = false;
        let rooms = self.multiview.selection.items.clone();
        self.multiview.slots = Some(
            rooms
                .iter()
                .map(|room| Slot {
                    room: room.clone(),
                    status: "正在连接…".into(),
                    video: None,
                })
                .collect(),
        );
        self.covers.clear(window, cx);
        self.focus.focus(window, cx);
        cx.notify();
        let count = rooms.len();
        let pending =
            cx.background_spawn(async move { plugins::multiview::layouts(&executable, count) });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if this.multiview.generation != generation {
                    return;
                }
                match result {
                    Ok(layouts) => {
                        this.multiview.layouts = Some(layouts);
                        this.start_multiview_sources(rooms, generation, window, cx);
                    }
                    Err(error) => {
                        this.multiview.slots = None;
                        this.multiview.selection.active = true;
                        this.multiview.selection.notice = format!("无法打开同屏：{error}");
                        cx.notify();
                    }
                }
            });
        })
        .detach();
    }

    fn start_multiview_sources(
        &mut self,
        rooms: Vec<Room>,
        generation: u64,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        for (index, room) in rooms.into_iter().enumerate() {
            let directory = self.options.directory.clone();
            let cookie = self
                .accounts
                .get(&room.platform)
                .map(|account| account.cookie.clone());
            let pending = cx.background_spawn(async move {
                live::resolve(
                    &directory,
                    &room,
                    cookie.as_deref(),
                    &compat::Selection::default(),
                )
            });
            cx.spawn_in(window, async move |entity, cx| {
                let result = pending.await;
                let _ = entity.update_in(cx, |this, window, cx| {
                    if this.multiview.generation != generation {
                        return;
                    }
                    let Some(slots) = &mut this.multiview.slots else {
                        return;
                    };
                    let Some(tile) = this
                        .multiview
                        .layouts
                        .as_ref()
                        .and_then(|layouts| layouts[this.multiview.layout.index()].get(index))
                        .copied()
                    else {
                        return;
                    };
                    let Some(slot) = slots.get_mut(index) else {
                        return;
                    };
                    let (width, height) = native::client_size(window);
                    let audio = AudioSettings {
                        muted: this.audio.muted
                            || (!this.multiview.all_audio && this.multiview.audible != index),
                        ..this.audio
                    };
                    let result: Result<(), String> = result.and_then(|source| {
                        let surface = Surface::video(window, 0.0, None)?;
                        surface.set_tile_rect(window, this.multiview.resize.tile(this.multiview.layout, tile, [0.0, HEADER, width, (height - HEADER - FOOTER).max(1.0)]));
                        let player = Player::start(
                            surface.id(),
                            hardware_player::Input::from_source(&source),
                            false,
                            audio,
                        )
                        .map_err(|error| error.to_string())?;
                        let chat = if source.playback.chat && this.danmaku_enabled {
                            let cookie = this
                                .accounts
                                .get(&slot.room.platform)
                                .map(|account| account.cookie.as_str());
                            compat::chat(&this.options.directory, &slot.room, cookie, true).ok()
                        } else {
                            None
                        };
                        slot.video = Some(Video {
                            player,
                            surface,
                            chat,
                            messages: Vec::new(),
                            waiting: VecDeque::new(),
                            _lease: source.lease,
                        });
                        Ok(())
                    });
                    slot.status = result.err().unwrap_or_default();
                    this.multiview_resize(window);
                    cx.notify();
                });
            })
            .detach();
        }
        cx.spawn_in(window, async move |entity, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_millis(16))
                    .await;
                let keep = entity
                    .update_in(cx, |this, window, cx| {
                        if this.multiview.generation != generation || this.multiview.slots.is_none()
                        {
                            return false;
                        }
                        this.poll_multiview(window, cx);
                        true
                    })
                    .unwrap_or(false);
                if !keep {
                    break;
                }
            }
        })
        .detach();
    }

    pub(super) fn close_multiview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.save_canvas();
        self.multiview.canvas.enabled = false;
        self.multiview.canvas.drag = None;
        self.multiview.resize.dragging = None;
        self.multiview.resize.hovered = None;
        self.multiview.generation += 1;
        self.multiview.slots = None;
        self.multiview.layouts = None;
        self.multiview.cancel();
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn multiview_dividers(&self, window: &Window) -> Vec<plugins::multiview_resize::Divider> {
        let (width, height) = native::client_size(window);
        self.multiview.resize.dividers(self.multiview.layout, self.multiview.slots.as_ref().map_or(0, Vec::len), [0.0, HEADER, width, (height - HEADER - FOOTER).max(1.0)])
    }

    pub(super) fn drag_multiview_divider(&mut self, event: &MouseMoveEvent, window: &Window, cx: &mut Context<Self>) {
        let point = [f32::from(event.position.x), f32::from(event.position.y)];
        let hovered = self.multiview_dividers(window).into_iter().find(|divider| {
            let [x, y, w, h] = divider.rect;
            point[0] >= x && point[0] <= x+w && point[1] >= y && point[1] <= y+h
        }).map(|divider| divider.axis);
        let mut changed = self.multiview.resize.hovered != hovered;
        self.multiview.resize.hovered = hovered;
        if !event.dragging() {
            changed |= self.multiview.resize.dragging.take().is_some();
            if changed { self.multiview_resize(window); cx.notify(); }
            return;
        }
        let (width, height) = native::client_size(window);
        if self.multiview.resize.update(point, [0.0, HEADER, width, (height - HEADER - FOOTER).max(1.0)]) {
            changed = true;
        }
        if changed { self.multiview_resize(window); cx.notify(); }
    }

    fn multiview_divider_overlay(&self, window: &Window) -> Option<[f32; 4]> {
        let axis = self.multiview.resize.dragging.or(self.multiview.resize.hovered)?;
        self.multiview_dividers(window).into_iter().find(|divider| divider.axis == axis).map(|divider| divider.rect)
    }

    pub(super) fn canvas_place_player(&self, slot: &Slot, _index: usize, rect: [f32;4], viewport: [f32;4], occluders: &[[f32;4]], window:&Window) {
        if let Some(video) = &slot.video {
            let regions=plugins::multiview_canvas::visible_regions(rect,viewport,occluders);
            video.surface.set_canvas_rect(window,rect,&regions);
        }
    }

    pub(super) fn multiview_resize(&self, window: &Window) {
        if native::minimized(window) { return; }
        if self.multiview.canvas.enabled { self.resize_canvas_players(window); return; }
        let overlay = self.multiview_divider_overlay(window);
        if native::minimized(window) {
            return;
        }
        if let (Some(slots), Some(layouts)) = (&self.multiview.slots, &self.multiview.layouts) {
            let tiles = &layouts[self.multiview.layout.index()];
            let (width, height) = native::client_size(window);
            for (index, slot) in slots.iter().enumerate() {
                if let Some(video) = &slot.video {
                    video
                        .surface
                         .set_tile_rect(window, self.multiview.resize.tile(self.multiview.layout, tiles[index], [0.0, HEADER, width, (height - HEADER - FOOTER).max(1.0)]));
                    video.surface.set_tile_overlay(self.multiview.resize.tile(self.multiview.layout, tiles[index], [0.0, HEADER, width, (height - HEADER - FOOTER).max(1.0)]), overlay);
                }
            }
        }
    }

    pub(super) fn multiview_plugin(&self) -> Option<PathBuf> {
        let plugin = plugins::catalog::PLUGINS[2];
        let directory = self.follows_path.with_file_name("plugins");
        plugin
            .installed(&directory)
            .then(|| directory.join(plugin.executable))
    }

    pub(super) fn toggle_multiview_plugin(&mut self, cx: &mut Context<Self>) {
        let plugin = plugins::catalog::PLUGINS[2];
        let directory = self.follows_path.with_file_name("plugins");
        let installed = plugin.installed(&directory);
        let result = if installed {
            plugin.uninstall(&directory)
        } else {
            plugin
                .package(&self.options.directory)
                .ok_or_else(|| {
                    std::io::Error::new(std::io::ErrorKind::NotFound, "安装包中没有同屏插件")
                })
                .and_then(|package| plugin.install(&package, &directory))
        };
        self.status = match result {
            Ok(()) => {
                self.multiview.cancel();
                if installed {
                    "已卸载多直播同屏插件"
                } else {
                    "已安装多直播同屏插件"
                }
                .into()
            }
            Err(error) => format!("插件操作失败：{error}"),
        };
        cx.notify();
    }

    pub(super) fn cycle_multiview_layout(&mut self, window: &Window, cx: &mut Context<Self>) {
        self.multiview.resize.dragging = None;
        self.multiview.resize.hovered = None;
        self.multiview.layout =
            plugins::multiview::Layout::OPTIONS[(self.multiview.layout.index() + 1) % 4].0;
        self.multiview_resize(window);
        cx.notify();
    }

    pub(super) fn multiview_audio(&mut self, index: Option<usize>, cx: &mut Context<Self>) {
        if let Some(index) = index {
            self.multiview.audible = index;
            self.multiview.all_audio = false;
        } else {
            self.multiview.all_audio = !self.multiview.all_audio;
        }
        if let Some(slots) = &self.multiview.slots {
            for (i, slot) in slots.iter().enumerate() {
                if let Some(video) = &slot.video {
                    video.player.set_muted(
                        self.audio.muted
                            || (!self.multiview.all_audio && self.multiview.audible != i),
                    );
                }
            }
        }
        cx.notify();
    }

    fn poll_multiview(&mut self, window: &Window, cx: &mut Context<Self>) {
        if native::minimized(window) {
            return;
        }
        let Some(slots) = &mut self.multiview.slots else {
            return;
        };
        let now = Instant::now();
        let mut pictures = Vec::new();
        for slot in slots {
            let Some(video) = &mut slot.video else {
                continue;
            };
            if let Some(end) = video.player.take_end() {
                slot.status = match end {
                    PlaybackEnd::Eof => "直播已结束".into(),
                    PlaybackEnd::Failed(error) => error,
                };
                video.chat = None;
                video.waiting.clear();
                video.messages.clear();
                video.player.set_danmaku(Vec::new());
                cx.notify();
            }
            let duration = |width| {
                #[cfg(target_os = "macos")]
                {
                    video.player.danmaku_duration(width)
                }
                #[cfg(windows)]
                {
                    Duration::from_secs_f32((1280.0 + width) / 210.0)
                }
            };
            let before = video.messages.len();
            video
                .messages
                .retain(|message| now.duration_since(message.started) < duration(message.width));
            if let Some(chat) = &video.chat {
                for _ in 0..32 {
                    let Ok(event) = chat.events.try_recv() else {
                        break;
                    };
                    let Some(text) = event.text else {
                        continue;
                    };
                    let mut width = 0.0;
                    let parts = emotes::segments(&slot.room.platform, &text, &event.emotes)
                        .into_iter()
                        .map(|part| {
                            let offset = width;
                            #[cfg(target_os = "macos")]
                            {
                                width += video.player.danmaku_segment_width(&part);
                            }
                            #[cfg(windows)]
                            {
                                width += part.width() as f32;
                            }
                            (offset, part)
                        })
                        .collect::<Vec<_>>();
                    if !parts.is_empty() {
                        video.waiting.push_back(Message {
                            started: now,
                            row: 0,
                            width,
                            parts,
                        });
                    }
                }
            }
            while video.waiting.front().is_some_and(|m| {
                video.waiting.len() > 120 || now.duration_since(m.started) > Duration::from_secs(5)
            }) {
                video.waiting.pop_front();
            }
            #[cfg(target_os = "macos")]
            let mut rows = vec![None; video.player.danmaku_rows()];
            #[cfg(windows)]
            let mut rows = vec![None; 5];
            for message in &video.messages {
                #[cfg(target_os = "macos")]
                let spacing = video.player.danmaku_spacing(message.width);
                #[cfg(windows)]
                let spacing = duration(message.width);
                if let Some(row) = rows.get_mut(message.row) {
                    *row = Some(message.started + spacing);
                }
            }
            let mut changed = before != video.messages.len();
            for (row, _) in rows
                .iter()
                .enumerate()
                .filter(|(_, time)| time.is_none_or(|time| time <= now))
                .take(4)
            {
                let Some(mut message) = video.waiting.pop_front() else {
                    break;
                };
                for (_, part) in &message.parts {
                    if let emotes::Segment::Picture { source, .. } = part {
                        pictures.push(source.clone());
                    }
                }
                message.started = now;
                message.row = row;
                video.messages.push(message);
                changed = true;
            }
            if changed {
                draw_video_chat(video, &self.emotes);
            }
            #[cfg(target_os = "macos")]
            video.player.paint();
        }
        for source in pictures {
            if self.emotes.begin(&source) {
                let requested = source.clone();
                let pending = cx.background_spawn(async move { emotes::load(&requested) });
                cx.spawn(async move |entity, cx| {
                    let bitmap = pending.await;
                    let _ = entity.update(cx, |this, _| {
                        this.emotes.finish(source, bitmap);
                        if let Some(slots) = &this.multiview.slots {
                            for video in slots.iter().filter_map(|slot| slot.video.as_ref()) {
                                draw_video_chat(video, &this.emotes);
                            }
                        }
                    });
                })
                .detach();
            }
        }
    }
}

fn draw_video_chat(video: &Video, cache: &emotes::Cache) {
    video.player.set_danmaku(
        video
            .messages
            .iter()
            .map(|message| native_danmaku::Lane {
                started: message.started,
                width: message.width,
                #[cfg(target_os = "macos")]
                y: message.row as f32,
                #[cfg(windows)]
                y: 30.0 + message.row as f32 * 39.0,
                #[cfg(windows)]
                duration: Duration::from_secs_f32((1280.0 + message.width) / 210.0),
                parts: message
                    .parts
                    .iter()
                    .map(|(offset, part)| {
                        (
                            *offset,
                            match part {
                                emotes::Segment::Text(text) => {
                                    native_danmaku::Part::Text(text.encode_utf16().collect())
                                }
                                emotes::Segment::Picture { source, alt } => {
                                    cache.get(source).map_or_else(
                                        || native_danmaku::Part::Text(alt.encode_utf16().collect()),
                                        |bitmap| native_danmaku::Part::Image(bitmap.clone()),
                                    )
                                }
                            },
                        )
                    })
                    .collect(),
            })
            .collect(),
    );
}
