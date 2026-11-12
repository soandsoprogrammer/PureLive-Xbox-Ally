use std::{cell::Cell, num::NonZeroIsize, ptr::null_mut};

use gpui_kit::Window;
use windows_sys::Win32::{
    Foundation::{HWND, RECT},
    System::LibraryLoader::GetModuleHandleW,
    UI::{
        Input::XboxController::{XINPUT_STATE, XInputGetState},
        WindowsAndMessaging::{
            CreateWindowExW, DestroyWindow, GetClientRect, IsIconic, SWP_NOACTIVATE, SWP_NOZORDER,
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

pub struct Surface(HWND, Cell<Option<(i32, i32, i32)>>);

impl Surface {
    pub fn new(window: &Window, top: f32) -> Result<Self, String> {
        Self::create(window, top, 0.0, 0)
    }

    pub fn video(window: &Window, bottom: f32) -> Result<Self, String> {
        Self::create(window, 0.0, bottom, WS_DISABLED)
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
        let surface = Self(hwnd, Cell::new(None));
        surface.resize_insets(window, top, bottom);
        Ok(surface)
    }

    pub fn id(&self) -> usize {
        self.0 as usize
    }

    pub fn resize(&self, window: &Window, top: f32) -> (i32, i32) {
        self.resize_insets(window, top, 0.0)
    }

    pub fn resize_video(&self, window: &Window, bottom: f32) {
        self.resize_insets(window, 0.0, bottom);
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
