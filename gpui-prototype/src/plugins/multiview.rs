use std::{path::Path, time::Duration};

use super::process::PluginProcess;

pub(crate) type Tile = [u8; 4];
pub(crate) const MAX_ROOMS: usize = 4;

pub(crate) fn layout(executable: &Path, count: usize) -> Result<Vec<Tile>, String> {
    let mut child = PluginProcess::start(executable, &count).map_err(|error| error.to_string())?;
    child.close_input();
    let tiles: Vec<Tile> = child.wait(Duration::from_secs(5)).map_err(|error| error.to_string())?;
    let mut cells = [false; 4];
    if tiles.len() != count {
        return Err("同屏插件返回的画面数量不符".into());
    }
    for &[x, y, width, height] in &tiles {
        if width == 0 || height == 0 || u16::from(x) + u16::from(width) > 2 || u16::from(y) + u16::from(height) > 2 {
            return Err("同屏插件返回了无效位置".into());
        }
        for row in y..y + height {
            for col in x..x + width {
                let cell = &mut cells[usize::from(row * 2 + col)];
                if std::mem::replace(cell, true) {
                    return Err("同屏插件返回了重叠的画面".into());
                }
            }
        }
    }
    Ok(tiles)
}
