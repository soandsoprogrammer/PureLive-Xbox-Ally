use super::*;
use plugins::multiview::{MAX_ROOMS, Tile};

pub(super) const TOOLBAR_HEIGHT: f32 = 96.0;

#[derive(Default)]
pub(super) struct MultiView {
    pub rooms: Vec<Room>,
    pub slots: Option<Vec<Slot>>,
    pub audible: usize,
    pub all_audio: bool,
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
    _lease: Option<compat::Bridge>,
}

impl Slot {
    pub fn playing(&self) -> bool {
        self.video.is_some()
    }
}

impl Home {
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
        self.multiview.notice.clear();
        self.multiview.slots = Some(self.multiview.rooms.iter().map(|room| Slot {
            room: room.clone(),
            status: "正在连接…".into(),
            tile: None,
            video: None,
        }).collect());
        self.focus.focus(window, cx);
        cx.notify();

        let pending = cx.background_spawn(async move { plugins::multiview::layout(&executable, count) });
        cx.spawn_in(window, async move |entity, cx| {
            let result = pending.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                if this.multiview.generation != generation {
                    return;
                }
                match result {
                    Ok(tiles) => this.start_multiview_tiles(tiles, generation, window, cx),
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
        for (index, (slot, tile)) in slots.iter_mut().zip(tiles).enumerate() {
            slot.tile = Some(tile);
            let room = slot.room.clone();
            let directory = self.options.directory.clone();
            let cookie = self.accounts.get(&room.platform).map(|account| account.cookie.clone());
            let pending = cx.background_spawn(async move {
                live::resolve(&directory, &room, cookie.as_deref(), &compat::Selection::default())
            });
            cx.spawn_in(window, async move |entity, cx| {
                let result = pending.await;
                let _ = entity.update_in(cx, |this, window, cx| {
                    if this.multiview.generation != generation {
                        return;
                    }
                    let muted = this.audio.muted || (!this.multiview.all_audio && this.multiview.audible != index);
                    let audio = AudioSettings { muted, ..this.audio };
                    let Some(slot) = this.multiview.slots.as_mut().and_then(|slots| slots.get_mut(index)) else { return };
                    slot.status = match result.and_then(|mut source| {
                        let surface = Surface::video_tile(window, TOOLBAR_HEIGHT, tile)?;
                        let player = Player::start(surface.id(), hardware_player::Input::from_source(&source), false, audio)
                            .map_err(|error| error.to_string())?;
                        slot.video = Some(Video { player, surface, _lease: source.lease.take() });
                        Ok(())
                    }) {
                        Ok(()) => String::new(),
                        Err(error) => error,
                    };
                    cx.notify();
                });
            }).detach();
        }
    }

    pub(super) fn close_multiview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.multiview.generation += 1;
        self.multiview.slots = None;
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

    pub(super) fn multiview_resize(&self, window: &Window) {
        if let Some(slots) = &self.multiview.slots {
            for slot in slots {
                if let (Some(video), Some(tile)) = (&slot.video, slot.tile) {
                    video.surface.resize_tile(window, TOOLBAR_HEIGHT, tile);
                }
            }
        }
    }

    pub(super) fn multiview_tick(&mut self, cx: &mut Context<Self>) {
        let Some(slots) = &mut self.multiview.slots else { return };
        for slot in slots {
            if let Some(end) = slot.video.as_ref().and_then(|video| video.player.take_end()) {
                slot.video = None;
                slot.status = match end {
                    PlaybackEnd::Eof => "直播已结束".into(),
                    PlaybackEnd::Failed(error) => error,
                };
                cx.notify();
            }
        }
    }
}
