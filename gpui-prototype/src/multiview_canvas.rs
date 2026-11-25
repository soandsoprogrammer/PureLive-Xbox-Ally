use super::*;
use plugins::multiview_canvas::{Canvas, Gesture};

impl Home {
    pub(super) fn canvas_viewport(&self, window: &Window) -> [f32; 4] {
        let (width, height) = native::client_size(window);
        Canvas::viewport(width, height)
    }
    pub(super) fn toggle_canvas(&mut self, window: &Window, cx: &mut Context<Self>) {
        if self.multiview.slots.is_none() {
            return;
        }
        if self.multiview.canvas.enabled {
            self.save_canvas();
            self.multiview.canvas.enabled = false;
        } else {
            if !self.multiview.canvas.loaded {
                let path = self
                    .follows_path
                    .with_file_name("plugins")
                    .join("multiview-canvas.json");
                self.multiview.canvas = fs::read(path)
                    .ok()
                    .filter(|bytes| bytes.len() <= 65536)
                    .and_then(|bytes| serde_json::from_slice(&bytes).ok())
                    .unwrap_or_default();
                self.multiview.canvas.loaded = true;
            }
            let keys: Vec<_> = self
                .multiview
                .slots
                .as_ref()
                .unwrap()
                .iter()
                .map(|slot| Self::canvas_key(&slot.room))
                .collect();
            let first = self.multiview.canvas.panes.is_empty();
            self.multiview.canvas.sync(&keys);
            self.multiview.canvas.enabled = true;
            if first {
                self.multiview.canvas.fit(self.canvas_viewport(window));
            }
            #[cfg(windows)]
            {
                self.multiview.settings_open = false;
            }
        }
        self.multiview.canvas.drag = None;
        self.multiview.resize.dragging = None;
        self.multiview.resize.hovered = None;
        self.multiview_resize(window);
        cx.notify();
    }
    pub(super) fn canvas_key(room: &Room) -> String {
        format!("{}:{}", room.platform, room.id)
    }
    pub(super) fn canvas_begin(
        &mut self,
        gesture: Gesture,
        event: &MouseDownEvent,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        self.multiview
            .canvas
            .begin(gesture, [event.position.x.into(), event.position.y.into()]);
        self.multiview_resize(window);
        cx.stop_propagation();
        cx.notify();
    }
    pub(super) fn canvas_move(
        &mut self,
        event: &MouseMoveEvent,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        if !self.multiview.canvas.enabled || self.multiview.canvas.drag.is_none() {
            return;
        }
        if event.pressed_button.is_none() {
            self.canvas_end(cx);
            return;
        }
        if self
            .multiview
            .canvas
            .update([event.position.x.into(), event.position.y.into()])
        {
            self.multiview_resize(window);
            cx.notify();
        }
    }
    pub(super) fn canvas_end(&mut self, cx: &mut Context<Self>) {
        if self.multiview.canvas.drag.take().is_some() {
            self.save_canvas();
            cx.notify();
        }
    }
    pub(super) fn save_canvas(&mut self) {
        if !self.multiview.canvas.loaded {
            return;
        }
        let path = self
            .follows_path
            .with_file_name("plugins")
            .join("multiview-canvas.json");
        if playback::save_preference(&path, &self.multiview.canvas).is_err() {
            self.multiview.selection.notice = "无法保存画布布局".into();
        }
    }
    pub(super) fn canvas_focus(&mut self, index: usize, window: &Window, cx: &mut Context<Self>) {
        self.multiview.canvas.front(index);
        self.multiview_resize(window);
        cx.stop_propagation();
        cx.notify();
    }
    pub(super) fn canvas_zoom(&mut self, factor: f32, window: &Window, cx: &mut Context<Self>) {
        let v = self.canvas_viewport(window);
        self.multiview
            .canvas
            .zoom_at(factor, [v[0] + v[2] / 2.0, v[1] + v[3] / 2.0], v);
        self.multiview_resize(window);
        cx.notify();
    }
    pub(super) fn canvas_fit(&mut self, reset: bool, window: &Window, cx: &mut Context<Self>) {
        let v = self.canvas_viewport(window);
        if reset {
            self.multiview.canvas.reset(v);
        } else {
            self.multiview.canvas.fit(v);
        }
        self.save_canvas();
        self.multiview_resize(window);
        cx.notify();
    }
    pub(super) fn canvas_scroll(
        &mut self,
        event: &ScrollEvent,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        let point = [event.position.x.into(), event.position.y.into()];
        let v = self.canvas_viewport(window);
        if point[1] < v[1] || point[1] > v[1] + v[3] {
            return;
        }
        let delta = event.delta.pixel_delta(px(24.0));
        let (dx, dy) = (f32::from(delta.x), f32::from(delta.y));
        if event.modifiers.control || event.modifiers.platform || !event.delta.precise() {
            self.multiview
                .canvas
                .zoom_at((dy * 0.004).clamp(-0.5, 0.5).exp(), point, v);
        } else {
            self.multiview.canvas.pan_by([dx, dy]);
        }
        self.multiview_resize(window);
        cx.stop_propagation();
        cx.notify();
    }
    pub(super) fn canvas_pinch(
        &mut self,
        event: &PinchEvent,
        window: &Window,
        cx: &mut Context<Self>,
    ) {
        let v = self.canvas_viewport(window);
        let point = [event.position.x.into(), event.position.y.into()];
        if point[1] < v[1] || point[1] > v[1] + v[3] {
            return;
        }
        self.multiview
            .canvas
            .zoom_at((1.0 + event.delta).max(0.1), point, v);
        self.multiview_resize(window);
        cx.stop_propagation();
        cx.notify();
    }
    pub(super) fn resize_canvas_players(&self, window: &Window) {
        let Some(slots) = &self.multiview.slots else {
            return;
        };
        let canvas = &self.multiview.canvas;
        let viewport = self.canvas_viewport(window);
        for (index, pane) in canvas.panes.iter().enumerate() {
            let Some(slot) = slots
                .iter()
                .find(|slot| Self::canvas_key(&slot.room) == pane.key)
            else {
                continue;
            };
            // Player internals remain owned by the existing playback integration.
            self.canvas_place_player(
                slot,
                index,
                canvas.video(index, viewport),
                viewport,
                &canvas.occluders(index, viewport),
                window,
            );
        }
    }
    pub(super) fn canvas_key_down(&mut self, key: &str, window: &Window, cx: &mut Context<Self>) {
        match key {
            "escape" => {
                self.toggle_canvas(window, cx);
                return;
            }
            "+" | "=" => {
                self.canvas_zoom(1.2, window, cx);
                return;
            }
            "-" => {
                self.canvas_zoom(1.0 / 1.2, window, cx);
                return;
            }
            "0" => {
                self.canvas_fit(false, window, cx);
                return;
            }
            "left" => self.multiview.canvas.pan_by([40.0, 0.0]),
            "right" => self.multiview.canvas.pan_by([-40.0, 0.0]),
            "up" => self.multiview.canvas.pan_by([0.0, 40.0]),
            "down" => self.multiview.canvas.pan_by([0.0, -40.0]),
            "a" => {
                self.canvas_mix(cx);
                return;
            }
            _ => return,
        }
        self.multiview_resize(window);
        cx.notify();
    }

    pub(super) fn canvas_audio(&mut self, index: usize, cx: &mut Context<Self>) {
        #[cfg(target_os = "macos")]
        self.multiview_audio(Some(index), cx);
        #[cfg(windows)]
        self.multiview_audio(index, cx);
    }
    pub(super) fn canvas_mix(&mut self, cx: &mut Context<Self>) {
        #[cfg(target_os = "macos")]
        self.multiview_audio(None, cx);
        #[cfg(windows)]
        self.toggle_multiview_all_audio(cx);
    }
}
