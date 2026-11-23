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
    let layouts: [Vec<Tile>; 4] = child.wait(Duration::from_secs(5))
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
        if width == 0 || height == 0 || u16::from(x) + u16::from(width) > u16::from(edge)
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
