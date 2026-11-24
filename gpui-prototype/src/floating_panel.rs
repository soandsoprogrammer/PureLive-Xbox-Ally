#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Bounds {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub radius: f32,
}

impl Bounds {
    /// Window-relative edges and corner diameter for the native video region.
    pub fn pixels(self, scale: f32) -> [i32; 5] {
        [
            (self.x * scale).round() as i32,
            (self.y * scale).round() as i32,
            ((self.x + self.width) * scale).round() as i32,
            ((self.y + self.height) * scale).round() as i32,
            (self.radius * 2.0 * scale).round() as i32,
        ]
    }
}

/// Shared by GPUI layout and the native video cutout, including on DPI changes.
pub fn room_list(width: f32, height: f32) -> Bounds {
    let width = width.max(1.0);
    let height = height.max(1.0);
    let margin = 12.0_f32.min(width / 4.0).min(height / 4.0);
    let panel_width = 360.0_f32.min(width - margin * 2.0);
    let panel_height = 440.0_f32.min(height - margin * 2.0);
    Bounds {
        x: width - margin - panel_width,
        y: (height - panel_height) / 2.0,
        width: panel_width,
        height: panel_height,
        radius: 12.0_f32.min(panel_width / 2.0).min(panel_height / 2.0),
    }
}

pub fn multiview_settings(width: f32, height: f32, title_height: f32) -> Bounds {
    let width = width.max(1.0);
    let height = height.max(1.0);
    let margin = 12.0_f32.min(width / 4.0).min(height / 4.0);
    let panel_width = 500.0_f32.min(width - margin * 2.0);
    let preferred_height: f32 = if title_height > 0.0 { 188.0 } else { 236.0 };
    let panel_height = preferred_height.min(height - margin * 2.0);
    Bounds {
        x: (width - panel_width) / 2.0,
        y: (title_height + margin).min(height - panel_height - margin).max(margin),
        width: panel_width,
        height: panel_height,
        radius: 12.0_f32.min(panel_width / 2.0).min(panel_height / 2.0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn floating_room_list_stays_inside_small_and_large_windows() {
        for (width, height) in [(1280.0, 720.0), (920.0, 550.0), (620.0, 300.0), (1.0, 1.0)] {
            let panel = room_list(width, height);
            assert!(panel.x >= 0.0 && panel.y >= 0.0);
            assert!(panel.x + panel.width <= width);
            assert!(panel.y + panel.height <= height);
            assert!(panel.width > 0.0 && panel.height > 0.0);
        }
        let panel = room_list(1280.0, 720.0);
        assert_eq!((panel.x, panel.y, panel.width, panel.height), (908.0, 140.0, 360.0, 440.0));
    }

    #[test]
    fn native_cutout_uses_the_same_edges_at_fractional_dpi() {
        let panel = room_list(920.0, 550.0);
        assert_eq!(panel.pixels(1.25), [685, 69, 1135, 619, 30]);
        assert_eq!(panel.pixels(2.0), [1096, 110, 1816, 990, 48]);
    }
}
