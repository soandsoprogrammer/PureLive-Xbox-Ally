use std::{path::Path, time::Duration};

use super::process::PluginProcess;

pub(crate) type Tile = [u8; 4];
pub(crate) const MAX_ROOMS: usize = 4;
pub(crate) const GRID: i32 = 12;

#[derive(Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Layout {
    #[default]
    Auto,
    Horizontal,
    Vertical,
    Main,
}

impl Layout {
    pub(crate) const OPTIONS: [(Self, &'static str); 4] = [
        (Self::Auto, "自动"),
        (Self::Horizontal, "横排"),
        (Self::Vertical, "竖排"),
        (Self::Main, "主画面"),
    ];

    pub(crate) fn index(self) -> usize {
        self as usize
    }
}

pub(crate) fn layouts(executable: &Path, count: usize) -> Result<[Vec<Tile>; 4], String> {
    let mut child = PluginProcess::start(executable, &serde_json::json!({"rooms": count}))
        .map_err(|error| error.to_string())?;
    child.close_input();
    let layouts: [Vec<Tile>; 4] = child
        .wait(Duration::from_secs(5))
        .map_err(|_| "请从插件管理卸载并重新安装新版「多直播同屏」。".to_owned())?;
    for tiles in &layouts {
        validate(tiles, count)?;
    }
    Ok(layouts)
}

fn validate(tiles: &[Tile], count: usize) -> Result<(), String> {
    let mut cells = [false; (GRID * GRID) as usize];
    if tiles.len() != count {
        return Err("同屏插件返回的画面数量不符".into());
    }
    let edge = GRID as u8;
    for &[x, y, width, height] in tiles {
        if width == 0
            || height == 0
            || u16::from(x) + u16::from(width) > u16::from(edge)
            || u16::from(y) + u16::from(height) > u16::from(edge)
        {
            return Err("同屏插件返回了无效位置".into());
        }
        for row in y..y + height {
            for col in x..x + width {
                let cell = &mut cells[usize::from(row) * GRID as usize + usize::from(col)];
                if std::mem::replace(cell, true) {
                    return Err("同屏插件返回了重叠的画面".into());
                }
            }
        }
    }
    if cells.contains(&false) {
        return Err("同屏插件返回的布局没有填满播放区域".into());
    }
    Ok(())
}

/// Selection belongs to the optional multiview feature; the host only renders it.
pub(crate) struct Selection<T> {
    pub active: bool,
    pub items: Vec<T>,
    pub notice: String,
}

impl<T> Default for Selection<T> {
    fn default() -> Self {
        Self {
            active: false,
            items: Vec::new(),
            notice: String::new(),
        }
    }
}

impl<T> Selection<T> {
    pub fn cancel(&mut self) {
        self.active = false;
        self.items.clear();
        self.notice.clear();
    }

    pub fn toggle(&mut self) {
        let active = !self.active;
        self.cancel();
        self.active = active;
    }

    pub fn toggle_item(&mut self, item: T, same: impl Fn(&T, &T) -> bool) {
        if !self.active {
            return;
        }
        self.notice.clear();
        if let Some(index) = self.items.iter().position(|saved| same(saved, &item)) {
            self.items.remove(index);
        } else if self.items.len() < MAX_ROOMS {
            self.items.push(item);
        } else {
            self.notice = "最多选择 4 个直播间".into();
        }
    }

    pub fn can_start(&self) -> bool {
        self.active && (2..=MAX_ROOMS).contains(&self.items.len())
    }
}

#[cfg(test)]
mod selection_tests {
    use super::Selection;
    #[test]
    fn selection_requires_mode_and_cancel_resets_the_next_session() {
        let mut state = Selection::<u8>::default();
        state.toggle_item(1, u8::eq);
        assert!(state.items.is_empty());
        assert!(!state.can_start());
        state.toggle();
        state.toggle_item(1, u8::eq);
        assert!(!state.can_start());
        state.toggle_item(2, u8::eq);
        assert!(state.can_start());
        state.toggle_item(1, u8::eq);
        assert_eq!(state.items, [2]);
        state.cancel();
        assert!(!state.active && state.items.is_empty() && state.notice.is_empty());
        state.toggle();
        assert!(state.items.is_empty());
        state.toggle();
        assert!(!state.active);
    }
    #[test]
    fn fifth_room_is_rejected_and_deselection_releases_capacity() {
        let mut state = Selection::<u8>::default();
        state.toggle();
        for room in 1..=5 {
            state.toggle_item(room, u8::eq);
        }
        assert_eq!(state.items, [1, 2, 3, 4]);
        assert!(!state.notice.is_empty());
        state.toggle_item(3, u8::eq);
        state.toggle_item(5, u8::eq);
        assert_eq!(state.items, [1, 2, 4, 5]);
        assert!(state.notice.is_empty());
        state.cancel();
        assert!(!state.can_start());
    }
}

#[cfg(test)]
mod layout_validation_tests {
    use super::validate;
    #[test]
    fn rejects_incomplete_overlapping_and_out_of_bounds_plugin_replies() {
        assert!(validate(&[[0,0,6,12],[6,0,6,12]], 2).is_ok());
        assert!(validate(&[[0,0,6,12]], 2).is_err());
        assert!(validate(&[[0,0,6,12],[5,0,6,12]], 2).is_err());
        assert!(validate(&[[0,0,6,12],[7,0,6,12]], 2).is_err());
        assert!(validate(&[[0,0,5,12],[6,0,6,12]], 2).is_err());
        assert!(validate(&[[0,0,0,12],[0,0,12,12]], 2).is_err());
    }
}
