use super::multiview::{Layout, Tile};

pub(crate) const DIVIDER_SIZE: f32 = 8.0;
const MIN_SHARE: f32 = 0.2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Axis {
    Vertical,
    Horizontal,
}

#[derive(Clone, Copy)]
pub(crate) struct Divider {
    pub axis: Axis,
    pub rect: [f32; 4],
}

#[derive(Clone, Copy)]
pub(crate) struct Resize {
    x: f32,
    y: f32,
    pub dragging: Option<Axis>,
    pub touch_dragging: bool,
    pub hovered: Option<Axis>,
}

impl Default for Resize {
    fn default() -> Self {
        Self {
            x: 0.5,
            y: 0.5,
            dragging: None,
            touch_dragging: false,
            hovered: None,
        }
    }
}

impl Resize {
    pub fn end_drag(&mut self) -> bool {
        self.touch_dragging = false;
        self.dragging.take().is_some()
    }

    // Viewport coordinates are logical window pixels, including any toolbar offset.
    pub fn update(&mut self, point: [f32; 2], viewport: [f32; 4]) -> bool {
        let Some(axis) = self.dragging else {
            return false;
        };
        let [left, top, width, height] = viewport;
        let (position, start, size, value) = match axis {
            Axis::Vertical => (point[0], left, width, &mut self.x),
            Axis::Horizontal => (point[1], top, height, &mut self.y),
        };
        if !position.is_finite() || size <= 0.0 {
            return false;
        }
        let next = ((position - start) / size).clamp(MIN_SHARE, 1.0 - MIN_SHARE);
        if (*value - next).abs() < f32::EPSILON {
            return false;
        }
        *value = next;
        true
    }

    pub fn dividers(&self, layout: Layout, rooms: usize, viewport: [f32; 4]) -> Vec<Divider> {
        if layout != Layout::Auto || !(2..=4).contains(&rooms) {
            return Vec::new();
        }
        let [left, top, width, height] = viewport;
        let x = left + width * self.x;
        let y = top + height * self.y;
        let mut dividers = vec![Divider {
            axis: Axis::Vertical,
            rect: [x - DIVIDER_SIZE / 2.0, top, DIVIDER_SIZE, height],
        }];
        if rooms >= 3 {
            let start = if rooms == 3 {
                x + DIVIDER_SIZE / 2.0
            } else {
                left
            };
            dividers.push(Divider {
                axis: Axis::Horizontal,
                rect: [
                    start,
                    y - DIVIDER_SIZE / 2.0,
                    (left + width - start).max(1.0),
                    DIVIDER_SIZE,
                ],
            });
        }
        dividers
    }

    pub fn tile(&self, layout: Layout, tile: Tile, viewport: [f32; 4]) -> [f32; 4] {
        let [left, top, width, height] = viewport;
        let [x, y, w, h] = tile;
        let map = |coordinate: u8, split: f32| {
            let position = f32::from(coordinate) / 12.0;
            if layout != Layout::Auto {
                position
            } else if position <= 0.5 {
                position * 2.0 * split
            } else {
                split + (position - 0.5) * 2.0 * (1.0 - split)
            }
        };
        let (x0, x1) = (map(x, self.x), map(x + w, self.x));
        let (y0, y1) = (map(y, self.y), map(y + h, self.y));
        // Divider hit targets overlay these edge-to-edge tiles; they reserve no space.
        [
            left + x0 * width,
            top + y0 * height,
            ((x1 - x0) * width).max(1.0),
            ((y1 - y0) * height).max(1.0),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::{Axis, DIVIDER_SIZE, Resize};
    use crate::plugins::multiview::Layout;
    #[test]
    fn drag_clamps_panels_and_preserves_the_ratio_after_window_resize() {
        let mut resize = Resize::default();
        assert!(!resize.update([650.0, 300.0], [0.0, 56.0, 1000.0, 500.0]));
        resize.dragging = Some(Axis::Vertical);
        assert!(resize.update([650.0, 300.0], [0.0, 56.0, 1000.0, 500.0]));
        assert_eq!(
            resize.tile(Layout::Auto, [0, 0, 6, 12], [0.0, 56.0, 1000.0, 500.0]),
            [0.0, 56.0, 650.0, 500.0]
        );
        assert_eq!(
            resize.tile(Layout::Auto, [6, 0, 6, 12], [0.0, 56.0, 2000.0, 500.0])[0],
            1300.0
        );
        resize.update([-100.0, 0.0], [0.0, 56.0, 1000.0, 500.0]);
        assert_eq!(resize.x, 0.2);
        resize.update([2000.0, 0.0], [0.0, 56.0, 1000.0, 500.0]);
        assert_eq!(resize.x, 0.8);
        resize.dragging = None;
        assert!(!resize.update([500.0, 0.0], [0.0, 56.0, 1000.0, 500.0]));
    }
    #[test]
    fn three_rooms_keep_the_horizontal_split_inside_the_right_column() {
        let mut resize = Resize::default();
        resize.dragging = Some(Axis::Horizontal);
        resize.update([0.0, 406.0], [0.0, 56.0, 1000.0, 500.0]);
        let dividers = resize.dividers(Layout::Auto, 3, [0.0, 56.0, 1000.0, 500.0]);
        assert_eq!(dividers.len(), 2);
        assert_eq!(dividers[1].rect, [504.0, 402.0, 496.0, DIVIDER_SIZE]);
        assert_eq!(
            resize.tile(Layout::Auto, [0, 0, 6, 12], [0.0, 56.0, 1000.0, 500.0])[3],
            500.0
        );
        let upper = resize.tile(Layout::Auto, [6, 0, 6, 6], [0.0, 56.0, 1000.0, 500.0]);
        let lower = resize.tile(Layout::Auto, [6, 6, 6, 6], [0.0, 56.0, 1000.0, 500.0]);
        assert!((lower[1] - (upper[1] + upper[3])).abs() < 0.01);
        assert!(
            resize
                .dividers(Layout::Horizontal, 3, [0.0, 56.0, 1000.0, 500.0])
                .is_empty()
        );
    }
    #[test]
    fn four_room_tiles_do_not_overlap_at_extreme_splits() {
        let tiles = [[0, 0, 6, 6], [6, 0, 6, 6], [0, 6, 6, 6], [6, 6, 6, 6]];
        for x in [0.2, 0.5, 0.8] {
            for y in [0.2, 0.5, 0.8] {
                let resize = Resize {
                    x,
                    y,
                    dragging: None,
                    touch_dragging: false,
                    hovered: None,
                };
                let rects =
                    tiles.map(|tile| resize.tile(Layout::Auto, tile, [0.0, 56.0, 920.0, 446.0]));
                let covered: f32 = rects.iter().map(|rect| rect[2] * rect[3]).sum();
                assert!((covered - 920.0 * 446.0).abs() < 0.1);
                for (i, [ax, ay, aw, ah]) in rects.iter().copied().enumerate() {
                    assert!(aw > 0.0 && ah > 0.0 && ax >= 0.0 && ay >= 56.0);
                    assert!(ax + aw <= 920.01 && ay + ah <= 502.01);
                    for [bx, by, bw, bh] in rects.iter().skip(i + 1).copied() {
                        assert!(ax + aw <= bx || bx + bw <= ax || ay + ah <= by || by + bh <= ay);
                    }
                }
            }
        }
    }
}
