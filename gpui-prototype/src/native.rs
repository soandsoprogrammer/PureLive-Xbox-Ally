pub(super) mod divider_touch;

use std::{cell::Cell, num::NonZeroIsize, ptr::null_mut};

use gpui_kit::Window;
use windows_sys::Win32::{
    Foundation::{HWND, RECT},
    Graphics::Gdi::{CombineRgn, CreateRectRgn, CreateRoundRectRgn, DeleteObject, RGN_DIFF, RGN_OR, SetWindowRgn},
    System::LibraryLoader::GetModuleHandleW,
    UI::{
        Input::XboxController::{XINPUT_STATE, XInputGetState},
        WindowsAndMessaging::{
            CreateWindowExW, DestroyWindow, GetClientRect, IsIconic, IsZoomed, ShowWindowAsync, SW_MAXIMIZE,
            SW_NORMAL, SWP_NOACTIVATE, SWP_NOZORDER,
            SetWindowPos, WS_CHILD, WS_CLIPCHILDREN, WS_CLIPSIBLINGS, WS_DISABLED, WS_VISIBLE,
        },
    },
};
use wry::raw_window_handle::{
    HandleError, HasWindowHandle, RawWindowHandle, Win32WindowHandle, WindowHandle,
};

pub fn window_handle(window: &Window) -> Result<HWND, String> {
    match HasWindowHandle::window_handle(window)
        .map_err(|err| err.to_string())?
        .as_raw()
    {
        RawWindowHandle::Win32(handle) => Ok(handle.hwnd.get() as HWND),
        _ => Err("无法取得 Win32 窗口".into()),
    }
}

pub fn minimized(window: &Window) -> bool {
    window_handle(window).is_ok_and(|hwnd| unsafe { IsIconic(hwnd) != 0 })
}

pub fn client_size(window: &Window) -> (f32, f32) {
    let mut client = RECT::default();
    if let Ok(hwnd) = window_handle(window) {
        unsafe { GetClientRect(hwnd, &mut client) };
    }
    let scale = window.scale_factor();
    (client.right.max(1) as f32 / scale, client.bottom.max(1) as f32 / scale)
}

pub fn toggle_maximized(window: &Window) {
    if let Ok(hwnd) = window_handle(window) {
        unsafe {
            let command = if IsZoomed(hwnd) != 0 { SW_NORMAL } else { SW_MAXIMIZE };
            // Let the click handler return before Windows delivers resize messages.
            ShowWindowAsync(hwnd, command);
        }
    }
}

/// The buttons, the left thumbstick and the triggers of the first connected pad.
#[derive(Clone, Copy, Debug)]
pub struct PadState {
    pub buttons: u16,
    pub left_x: i16,
    pub left_y: i16,
    pub left_trigger: u8,
    pub right_trigger: u8,
}

pub fn pad() -> Option<PadState> {
    for index in 0..4 {
        let mut raw = XINPUT_STATE::default();
        if unsafe { XInputGetState(index, &mut raw) } == 0 {
            return Some(PadState {
                buttons: raw.Gamepad.wButtons,
                left_x: raw.Gamepad.sThumbLX,
                left_y: raw.Gamepad.sThumbLY,
                left_trigger: raw.Gamepad.bLeftTrigger,
                right_trigger: raw.Gamepad.bRightTrigger,
            });
        }
    }
    None
}

type VideoMask = (i32, i32, [i32; 5]);

pub struct Surface(HWND, Cell<Option<(i32, i32, i32)>>, Cell<Option<VideoMask>>, Cell<bool>);

impl Surface {
    pub fn new(window: &Window, top: f32) -> Result<Self, String> {
        Self::create(window, top, 0.0, 0)
    }

    pub fn video(window: &Window, bottom: f32, panel: Option<crate::floating_panel::Bounds>) -> Result<Self, String> {
        let surface = Self::create(window, 0.0, bottom, WS_DISABLED)?;
        surface.resize_video(window, bottom, panel);
        Ok(surface)
    }

    pub fn video_tile(window: &Window, top: f32, tile: [u8; 4], panel: Option<crate::floating_panel::Bounds>) -> Result<Self, String> {
        let surface = Self::create(window, top, 0.0, WS_DISABLED)?;
        surface.resize_tile(window, top, tile, panel);
        Ok(surface)
    }

    pub fn resize_tile(&self, window: &Window, top: f32, [x, y, width, height]: [u8; 4], panel: Option<crate::floating_panel::Bounds>) {
        let mut client = RECT::default();
        let Ok(parent) = window_handle(window) else { return };
        unsafe { GetClientRect(parent, &mut client) };
        let scale = window.scale_factor();
        let top = (top * scale).round() as i32;
        let total_width = client.right.max(1);
        let total_height = (client.bottom - top).max(1);
        let grid = crate::plugins::multiview::GRID;
        let left = total_width * i32::from(x) / grid;
        let right = total_width * i32::from(x + width) / grid;
        let upper = total_height * i32::from(y) / grid;
        let lower = total_height * i32::from(y + height) / grid;
        let gap = (2.0 * scale).round() as i32;
        let (left, top) = (left + gap, top + upper + gap);
        let (width, height) = ((right - left - gap).max(1), (lower - upper - gap * 2).max(1));
        unsafe {
            SetWindowPos(self.0, null_mut(), left, top, width, height, SWP_NOACTIVATE | SWP_NOZORDER);
        }
        self.set_video_mask(width, height, panel.and_then(|panel| {
            let [x0, y0, x1, y1, diameter] = panel.pixels(scale);
            (x0 < left + width && x1 > left && y0 < top + height && y1 > top)
                .then_some([x0 - left, y0 - top, x1 - left, y1 - top, diameter])
        }));
    }


    pub fn resize_tile_rect(&self, window: &Window, rect: [f32; 4], panel: Option<crate::floating_panel::Bounds>, overlay: Option<[f32; 4]>) {
        let scale = window.scale_factor();
        let [x, y, w, h] = rect;
        let (left, top) = ((x * scale).round() as i32, (y * scale).round() as i32);
        let (width, height) = (((x + w) * scale).round() as i32 - left, ((y + h) * scale).round() as i32 - top);
        let (width, height) = (width.max(1), height.max(1));
        unsafe { SetWindowPos(self.0, null_mut(), left, top, width, height, SWP_NOACTIVATE | SWP_NOZORDER); }
        let panel = panel.map(|panel| panel.pixels(scale));
        let overlay = overlay.map(|[x, y, w, h]| [(x * scale).round() as i32, (y * scale).round() as i32, ((x+w) * scale).round() as i32, ((y+h) * scale).round() as i32, 0]);
        unsafe {
            if panel.is_none() && overlay.is_none() {
                if SetWindowRgn(self.0, null_mut(), 1) != 0 { self.2.set(None); self.3.set(false); }
                return;
            }
            let region = CreateRectRgn(0, 0, width, height);
            if region.is_null() { return; }
            for [x0, y0, x1, y1, diameter] in panel.into_iter().chain(overlay) {
                let hole = if diameter > 0 { CreateRoundRectRgn(x0-left, y0-top, x1-left, y1-top, diameter, diameter) }
                    else { CreateRectRgn(x0-left, y0-top, x1-left, y1-top) };
                if !hole.is_null() { CombineRgn(region, region, hole, RGN_DIFF); DeleteObject(hole); }
            }
            if SetWindowRgn(self.0, region, 1) != 0 { self.3.set(true); }
            else { DeleteObject(region); }
        }
    }

    pub fn set_canvas_rect(&self, window:&Window, rect:[f32;4], regions:&[[f32;4]]) {
        let scale=window.scale_factor(); let [x,y,w,h]=rect;
        let left=(x*scale).round() as i32; let top=(y*scale).round() as i32;
        let width=(((x+w)*scale).round() as i32-left).max(1); let height=(((y+h)*scale).round() as i32-top).max(1);
        unsafe {
            SetWindowPos(self.0,null_mut(),left,top,width,height,SWP_NOACTIVATE|SWP_NOZORDER);
            let region=CreateRectRgn(0,0,0,0); if region.is_null() { return; }
            for &[x,y,w,h] in regions {
                let part=CreateRectRgn((x*scale).round() as i32-left,(y*scale).round() as i32-top,((x+w)*scale).round() as i32-left,((y+h)*scale).round() as i32-top);
                if !part.is_null() { CombineRgn(region,region,part,RGN_OR); DeleteObject(part); }
            }
            if SetWindowRgn(self.0,region,1)!=0 { self.3.set(true); } else { DeleteObject(region); }
        }
    }

    fn create(window: &Window, top: f32, bottom: f32, style: u32) -> Result<Self, String> {
        let parent = window_handle(window)?;
        let class = [83u16, 84, 65, 84, 73, 67, 0]; // STATIC
        let hwnd = unsafe {
            CreateWindowExW(
                0,
                class.as_ptr(),
                null_mut(),
                WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | style,
                0,
                0,
                1,
                1,
                parent,
                null_mut(),
                GetModuleHandleW(null_mut()),
                null_mut(),
            )
        };
        if hwnd.is_null() {
            return Err(format!(
                "无法创建播放区域：{}",
                std::io::Error::last_os_error()
            ));
        }
        let surface = Self(hwnd, Cell::new(None), Cell::new(None), Cell::new(false));
        surface.resize_insets(window, top, bottom);
        Ok(surface)
    }

    pub fn id(&self) -> usize {
        self.0 as usize
    }

    pub fn resize(&self, window: &Window, top: f32) -> (i32, i32) {
        self.resize_insets(window, top, 0.0)
    }

    pub fn resize_video(&self, window: &Window, bottom: f32, panel: Option<crate::floating_panel::Bounds>) {
        let (width, height) = self.resize_insets(window, 0.0, bottom);
        self.set_video_mask(width, height, panel.map(|panel| panel.pixels(window.scale_factor())));
    }

    fn set_video_mask(&self, width: i32, height: i32, panel: Option<[i32; 5]>) {
        let next = panel.map(|panel| (width, height, panel));
        if !self.3.replace(false) && self.2.get() == next {
            return;
        }
        unsafe {
            let Some((_, _, [left, top, right, bottom, diameter])) = next else {
                if SetWindowRgn(self.0, null_mut(), 1) != 0 {
                    self.2.set(None);
                }
                return;
            };
            // The native swap chain normally covers GPUI. Expose only the
            // floating panel, keeping the video and danmaku at full size.
            let region = CreateRectRgn(0, 0, width, height);
            let hole = CreateRoundRectRgn(left, top, right, bottom, diameter, diameter);
            if region.is_null() || hole.is_null() {
                if !region.is_null() { DeleteObject(region); }
                if !hole.is_null() { DeleteObject(hole); }
                return;
            }
            let combined = CombineRgn(region, region, hole, RGN_DIFF);
            DeleteObject(hole);
            if combined != 0 && SetWindowRgn(self.0, region, 1) != 0 {
                // Windows owns region after a successful SetWindowRgn call.
                self.2.set(next);
            } else {
                DeleteObject(region);
            }
        }
    }

    fn resize_insets(&self, window: &Window, top: f32, bottom: f32) -> (i32, i32) {
        let mut client = RECT::default();
        if let Ok(parent) = window_handle(window) {
            unsafe { GetClientRect(parent, &mut client) };
        }
        let top = (top * window.scale_factor()).round() as i32;
        let bottom = (bottom * window.scale_factor()).round() as i32;
        let width = client.right.max(1);
        let height = (client.bottom - top - bottom).max(1);
        let bounds = (top, width, height);
        if self.1.get() != Some(bounds)
            && unsafe {
                SetWindowPos(
                    self.0,
                    null_mut(),
                    0,
                    top,
                    width,
                    height,
                    SWP_NOACTIVATE | SWP_NOZORDER,
                ) != 0
            }
        {
            self.1.set(Some(bounds));
        }
        (width, height)
    }
}

impl HasWindowHandle for Surface {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let hwnd = NonZeroIsize::new(self.0 as isize).ok_or(HandleError::Unavailable)?;
        // The borrowed handle cannot outlive the HWND owned by this Surface.
        Ok(unsafe { WindowHandle::borrow_raw(Win32WindowHandle::new(hwnd).into()) })
    }
}

impl Drop for Surface {
    fn drop(&mut self) {
        unsafe { DestroyWindow(self.0) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use windows_sys::Win32::Graphics::Gdi::{GetWindowRgn, PtInRegion};

    #[test]
    fn floating_menu_masks_only_its_area_and_restores_video_on_close() {
        let class = [83u16, 84, 65, 84, 73, 67, 0];
        unsafe {
            // A hidden test window exercises GDI without opening any UI.
            let hwnd = CreateWindowExW(
                0, class.as_ptr(), null_mut(), 0, 0, 0, 1280, 720,
                null_mut(), null_mut(), GetModuleHandleW(null_mut()), null_mut(),
            );
            assert!(!hwnd.is_null());
            let surface = Surface(hwnd, Cell::new(None), Cell::new(None), Cell::new(false));
            let mut before = RECT::default();
            GetClientRect(hwnd, &mut before);
            let panel = crate::floating_panel::room_list(1280.0, 720.0).pixels(1.0);
            surface.set_video_mask(1280, 720, Some(panel));
            let region = CreateRectRgn(0, 0, 0, 0);
            assert!(!region.is_null());
            assert_ne!(GetWindowRgn(hwnd, region), 0);
            assert_eq!(PtInRegion(region, 1000, 300), 0);
            assert_ne!(PtInRegion(region, 100, 300), 0);
            assert_ne!(PtInRegion(region, 1000, 50), 0);
            surface.set_video_mask(1280, 720, None);
            assert_eq!(GetWindowRgn(hwnd, region), 0);
            let mut after = RECT::default();
            GetClientRect(hwnd, &mut after);
            assert_eq!((before.right, before.bottom), (after.right, after.bottom));
            DeleteObject(region);
        }
    }
}
