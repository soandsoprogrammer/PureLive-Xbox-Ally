use serde::{Deserialize, Serialize};

pub const HEADER: f32 = 56.0;
pub const TOOLS: f32 = 44.0;
pub const FOOTER: f32 = 48.0;
pub const TITLE: f32 = 28.0;
pub const GRIP: f32 = 16.0;
const MIN_ZOOM: f32 = 0.25;
const MAX_ZOOM: f32 = 2.5;

#[derive(Clone, Serialize, Deserialize)]
pub struct Pane {
    pub key: String,
    pub rect: [f32; 4],
}

#[derive(Clone, Copy)]
pub enum Gesture {
    Pan,
    Move(usize),
    Resize(usize),
}

#[derive(Serialize, Deserialize)]
#[serde(default)]
pub struct Canvas {
    pub panes: Vec<Pane>,
    pub zoom: f32,
    pub pan: [f32; 2],
    #[serde(skip)]
    pub enabled: bool,
    #[serde(skip)]
    pub loaded: bool,
    #[serde(skip)]
    pub drag: Option<(Gesture, [f32; 2])>,
}
impl Default for Canvas {
    fn default() -> Self {
        Self {
            panes: Vec::new(),
            zoom: 1.0,
            pan: [0.0, 0.0],
            enabled: false,
            loaded: false,
            drag: None,
        }
    }
}
impl Canvas {
    pub fn sync(&mut self, keys: &[String]) {
        self.zoom = if self.zoom.is_finite() {
            self.zoom.clamp(MIN_ZOOM, MAX_ZOOM)
        } else {
            1.0
        };
        if !self
            .pan
            .iter()
            .all(|v| v.is_finite() && v.abs() < 1_000_000.0)
        {
            self.pan = [0.0, 0.0];
        }
        let mut seen = std::collections::BTreeSet::new();
        self.panes
            .retain(|pane| keys.contains(&pane.key) && seen.insert(pane.key.clone()));
        for (index, key) in keys.iter().enumerate() {
            let valid = |r: [f32; 4]| {
                r.iter().all(|v| v.is_finite() && v.abs() <= 100_000.0)
                    && r[2] >= 240.0
                    && r[3] >= 160.0
                    && r[2] <= 1920.0
                    && r[3] <= 1200.0
            };
            if let Some(pane) = self.panes.iter_mut().find(|pane| &pane.key == key) {
                if !valid(pane.rect) {
                    pane.rect = Self::initial(index);
                }
            } else {
                self.panes.push(Pane {
                    key: key.clone(),
                    rect: Self::initial(index),
                });
            }
        }
        self.drag = None;
    }
    fn initial(index: usize) -> [f32; 4] {
        [
            (index % 2) as f32 * 672.0,
            (index / 2) as f32 * 420.0,
            640.0,
            388.0,
        ]
    }
    pub fn viewport(width: f32, height: f32) -> [f32; 4] {
        [
            0.0,
            HEADER + TOOLS,
            width,
            (height - HEADER - TOOLS - FOOTER).max(1.0),
        ]
    }
    pub fn screen(&self, index: usize, viewport: [f32; 4]) -> [f32; 4] {
        let [x, y, w, h] = self.panes[index].rect;
        [
            viewport[0] + self.pan[0] + x * self.zoom,
            viewport[1] + self.pan[1] + y * self.zoom,
            w * self.zoom,
            h * self.zoom,
        ]
    }
    pub fn video(&self, index: usize, viewport: [f32; 4]) -> [f32; 4] {
        let [x, y, w, h] = self.screen(index, viewport);
        [
            x + 1.0,
            y + TITLE,
            (w - 2.0).max(1.0),
            (h - TITLE - 1.0).max(1.0),
        ]
    }
    pub fn grip(&self, index: usize, viewport: [f32; 4]) -> [f32; 4] {
        let [x, y, w, h] = self.screen(index, viewport);
        [x + w - GRIP, y + h - GRIP, GRIP, GRIP]
    }
    pub fn occluders(&self, index: usize, viewport: [f32; 4]) -> Vec<[f32; 4]> {
        let mut result = vec![self.grip(index, viewport)];
        result.extend((index + 1..self.panes.len()).map(|index| self.screen(index, viewport)));
        result
    }
    pub fn front(&mut self, index: usize) -> usize {
        if index + 1 < self.panes.len() {
            let pane = self.panes.remove(index);
            self.panes.push(pane);
        }
        self.panes.len().saturating_sub(1)
    }
    pub fn begin(&mut self, gesture: Gesture, point: [f32; 2]) {
        let gesture = match gesture {
            Gesture::Move(index) => Gesture::Move(self.front(index)),
            Gesture::Resize(index) => Gesture::Resize(self.front(index)),
            Gesture::Pan => Gesture::Pan,
        };
        self.drag = Some((gesture, point));
    }
    pub fn update(&mut self, point: [f32; 2]) -> bool {
        let Some((gesture, last)) = self.drag else {
            return false;
        };
        let delta = [point[0] - last[0], point[1] - last[1]];
        if !delta.iter().all(|v| v.is_finite()) || delta == [0.0, 0.0] {
            return false;
        }
        match gesture {
            Gesture::Pan => self.pan_by(delta),
            Gesture::Move(index) => {
                if let Some(pane) = self.panes.get_mut(index) {
                    for axis in 0..2 {
                        pane.rect[axis] = (pane.rect[axis] + delta[axis] / self.zoom)
                            .clamp(-100_000.0, 100_000.0);
                    }
                }
            }
            Gesture::Resize(index) => {
                if let Some(pane) = self.panes.get_mut(index) {
                    pane.rect[2] = (pane.rect[2] + delta[0] / self.zoom).clamp(240.0, 1920.0);
                    pane.rect[3] = (pane.rect[3] + delta[1] / self.zoom).clamp(160.0, 1200.0);
                }
            }
        }
        self.drag = Some((gesture, point));
        true
    }
    pub fn pan_by(&mut self, delta: [f32; 2]) {
        for axis in 0..2 {
            if delta[axis].is_finite() {
                self.pan[axis] = (self.pan[axis] + delta[axis]).clamp(-1_000_000.0, 1_000_000.0);
            }
        }
    }
    pub fn zoom_at(&mut self, factor: f32, point: [f32; 2], viewport: [f32; 4]) {
        if !factor.is_finite() || factor <= 0.0 {
            return;
        }
        let zoom = (self.zoom * factor).clamp(MIN_ZOOM, MAX_ZOOM);
        for axis in 0..2 {
            let p = point[axis] - viewport[axis];
            self.pan[axis] = p - (p - self.pan[axis]) * zoom / self.zoom;
        }
        self.zoom = zoom;
    }
    pub fn fit(&mut self, viewport: [f32; 4]) {
        if self.panes.is_empty() {
            return;
        }
        let mut bounds = [
            f32::INFINITY,
            f32::INFINITY,
            f32::NEG_INFINITY,
            f32::NEG_INFINITY,
        ];
        for pane in &self.panes {
            let [x, y, w, h] = pane.rect;
            bounds[0] = bounds[0].min(x);
            bounds[1] = bounds[1].min(y);
            bounds[2] = bounds[2].max(x + w);
            bounds[3] = bounds[3].max(y + h);
        }
        let w = (bounds[2] - bounds[0]).max(1.0);
        let h = (bounds[3] - bounds[1]).max(1.0);
        self.zoom = ((viewport[2] - 40.0).max(1.0) / w)
            .min((viewport[3] - 40.0).max(1.0) / h)
            .clamp(MIN_ZOOM, MAX_ZOOM);
        self.pan = [
            (viewport[2] - w * self.zoom) / 2.0 - bounds[0] * self.zoom,
            (viewport[3] - h * self.zoom) / 2.0 - bounds[1] * self.zoom,
        ];
        self.drag = None;
    }
    pub fn reset(&mut self, viewport: [f32; 4]) {
        for (i, pane) in self.panes.iter_mut().enumerate() {
            pane.rect = Self::initial(i);
        }
        self.fit(viewport);
    }
}

#[cfg(test)]
mod tests {
    use super::{Canvas, Gesture};
    fn canvas() -> Canvas {
        let mut c = Canvas::default();
        c.sync(&["a".into(), "b".into()]);
        c
    }
    #[test]
    fn zoom_keeps_the_world_point_under_the_pointer() {
        let mut c = canvas();
        let viewport = Canvas::viewport(920.0, 550.0);
        c.pan = [30.0, -20.0];
        let point = [300.0, 250.0];
        let world = [
            (point[0] - viewport[0] - c.pan[0]) / c.zoom,
            (point[1] - viewport[1] - c.pan[1]) / c.zoom,
        ];
        c.zoom_at(1.4, point, viewport);
        for axis in 0..2 {
            assert!(
                (viewport[axis] + c.pan[axis] + world[axis] * c.zoom - point[axis]).abs() < 0.001
            );
        }
    }
    #[test]
    fn gestures_use_world_coordinates_and_bring_the_same_room_to_front() {
        let mut c = canvas();
        c.zoom = 0.5;
        c.begin(Gesture::Move(0), [100.0, 100.0]);
        c.update([150.0, 130.0]);
        assert_eq!(c.panes[1].key, "a");
        assert_eq!(&c.panes[1].rect[..2], &[100.0, 60.0]);
        c.drag = None;
        assert!(!c.update([300.0, 300.0]));
        c.begin(Gesture::Resize(1), [0.0, 0.0]);
        c.update([-10000.0, -10000.0]);
        assert_eq!(&c.panes[1].rect[2..], &[240.0, 160.0]);
    }
    #[test]
    fn saved_layout_restores_geometry_but_never_restores_a_drag_or_enables_the_mode() {
        let mut c = canvas();
        c.enabled = true;
        c.begin(Gesture::Pan, [0.0, 0.0]);
        c.update([50.0, 30.0]);
        let mut restored: Canvas =
            serde_json::from_slice(&serde_json::to_vec(&c).unwrap()).unwrap();
        assert!(!restored.enabled && restored.drag.is_none());
        assert_eq!(restored.pan, [50.0, 30.0]);
        restored.panes[0].rect = [f32::INFINITY, 0.0, 1.0, 1.0];
        restored.zoom = f32::NAN;
        restored.sync(&["a".into(), "c".into()]);
        assert!(
            restored
                .panes
                .iter()
                .all(|p| p.rect.iter().all(|v| v.is_finite()))
        );
        assert_eq!(restored.panes[1].key, "c");
    }
    #[test]
    fn fit_and_occlusion_follow_the_front_to_back_order() {
        let mut c = canvas();
        let viewport = Canvas::viewport(920.0, 550.0);
        c.fit(viewport);
        for i in 0..2 {
            let [x, y, w, h] = c.screen(i, viewport);
            assert!(x >= 0.0 && y >= viewport[1] && x + w <= 920.1 && y + h <= 502.1);
        }
        assert_eq!(c.occluders(0, viewport).len(), 2);
        assert_eq!(c.occluders(1, viewport).len(), 1);
    }
}

/// Disjoint visible rectangles prevent native players leaking across toolbar,
/// viewport edges, or windows above them. Subtraction also handles overlapping holes.
pub fn visible_regions(
    rect: [f32; 4],
    viewport: [f32; 4],
    occluders: &[[f32; 4]],
) -> Vec<[f32; 4]> {
    fn intersection(a: [f32; 4], b: [f32; 4]) -> Option<[f32; 4]> {
        let x = a[0].max(b[0]);
        let y = a[1].max(b[1]);
        let right = (a[0] + a[2]).min(b[0] + b[2]);
        let bottom = (a[1] + a[3]).min(b[1] + b[3]);
        (right > x && bottom > y).then_some([x, y, right - x, bottom - y])
    }
    let mut regions: Vec<_> = intersection(rect, viewport).into_iter().collect();
    for &cover in occluders {
        regions = regions
            .into_iter()
            .flat_map(|part| {
                let Some([x, y, w, h]) = intersection(part, cover) else {
                    return vec![part];
                };
                let [px, py, pw, ph] = part;
                [
                    [px, py, pw, y - py],
                    [px, y + h, pw, py + ph - y - h],
                    [px, y, x - px, h],
                    [x + w, y, px + pw - x - w, h],
                ]
                .into_iter()
                .filter(|r| r[2] > 0.01 && r[3] > 0.01)
                .collect()
            })
            .collect();
    }
    regions
}

#[cfg(test)]
mod clipping_tests {
    use super::visible_regions;
    #[test]
    fn offscreen_and_overlapping_covers_never_reveal_video_outside_the_viewport() {
        let parts = visible_regions(
            [-50.0, 80.0, 250.0, 200.0],
            [0.0, 100.0, 300.0, 300.0],
            &[[50.0, 110.0, 100.0, 100.0], [100.0, 160.0, 100.0, 100.0]],
        );
        for [x, y, w, h] in parts {
            assert!(x >= 0.0 && y >= 100.0 && x + w <= 200.0 && y + h <= 280.0);
            for [cx, cy, cw, ch] in [[50.0, 110.0, 100.0, 100.0], [100.0, 160.0, 100.0, 100.0]] {
                assert!(x + w <= cx || cx + cw <= x || y + h <= cy || cy + ch <= y);
            }
        }
        assert!(
            visible_regions([500.0, 0.0, 100.0, 100.0], [0.0, 100.0, 300.0, 300.0], &[]).is_empty()
        );
    }
}
