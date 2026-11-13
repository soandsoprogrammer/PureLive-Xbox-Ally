use gpui_kit::Window;
use objc2::{MainThreadMarker, MainThreadOnly, rc::Retained};
use objc2_app_kit::NSView;
use objc2_foundation::{NSPoint, NSRect, NSSize};
use std::{cell::Cell, path::PathBuf, ptr::NonNull};
use wry::raw_window_handle::{
    AppKitWindowHandle, HandleError, HasWindowHandle, RawWindowHandle, WindowHandle,
};

pub fn profile_directory() -> Option<PathBuf> {
    std::env::var_os("PURELIVE_PROFILE_ROOT")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .map(|home| PathBuf::from(home).join("Library/Application Support"))
        })
}

fn parent_view(window: &Window) -> Result<&NSView, String> {
    let handle = HasWindowHandle::window_handle(window).map_err(|error| error.to_string())?;
    match handle.as_raw() {
        RawWindowHandle::AppKit(handle) => {
            Ok(unsafe { &*handle.ns_view.cast::<NSView>().as_ptr() })
        }
        _ => Err("无法取得 macOS 播放窗口".into()),
    }
}

pub fn minimized(window: &Window) -> bool {
    parent_view(window)
        .ok()
        .and_then(NSView::window)
        .is_some_and(|window| window.isMiniaturized())
}

pub struct Surface(Retained<NSView>, Cell<Option<(f64, f64, f64, f64)>>);

impl Surface {
    pub fn new(window: &Window, top: f32) -> Result<Self, String> {
        Self::create(window, top, 0.0)
    }
    pub fn video(window: &Window, bottom: f32) -> Result<Self, String> {
        Self::create(window, 0.0, bottom)
    }

    fn create(window: &Window, top: f32, bottom: f32) -> Result<Self, String> {
        let marker = MainThreadMarker::new().ok_or("无法在后台线程创建窗口")?;
        let parent = parent_view(window)?;
        let view = NSView::initWithFrame(NSView::alloc(marker), parent.bounds());
        view.setWantsLayer(true);
        parent.addSubview(&view);
        let surface = Self(view, Cell::new(None));
        surface.resize_insets(window, top, bottom);
        Ok(surface)
    }

    pub fn id(&self) -> usize {
        Retained::as_ptr(&self.0) as usize
    }
    pub fn resize(&self, window: &Window, top: f32) -> (i32, i32) {
        self.resize_insets(window, top, 0.0)
    }
    pub fn resize_video(&self, window: &Window, bottom: f32) {
        self.resize_insets(window, 0.0, bottom);
    }

    fn resize_insets(&self, window: &Window, top: f32, bottom: f32) -> (i32, i32) {
        let Ok(parent) = parent_view(window) else {
            return (1, 1);
        };
        let bounds = parent.bounds();
        let y = if parent.isFlipped() {
            f64::from(top)
        } else {
            f64::from(bottom)
        };
        let width = bounds.size.width.max(1.0);
        let height = (bounds.size.height - f64::from(top + bottom)).max(1.0);
        let frame = (bounds.origin.x, bounds.origin.y + y, width, height);
        if self.1.get() != Some(frame) {
            self.0.setFrame(NSRect::new(
                NSPoint::new(frame.0, frame.1),
                NSSize::new(width, height),
            ));
            self.1.set(Some(frame));
        }
        (
            (width * f64::from(window.scale_factor())).round() as i32,
            (height * f64::from(window.scale_factor())).round() as i32,
        )
    }
}

impl HasWindowHandle for Surface {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let view = NonNull::from(&*self.0).cast();
        Ok(unsafe { WindowHandle::borrow_raw(AppKitWindowHandle::new(view).into()) })
    }
}

impl Drop for Surface {
    fn drop(&mut self) {
        self.0.removeFromSuperview();
    }
}

pub mod buttons {
    pub const XINPUT_GAMEPAD_DPAD_UP: u16 = 1;
    pub const XINPUT_GAMEPAD_DPAD_DOWN: u16 = 2;
    pub const XINPUT_GAMEPAD_DPAD_LEFT: u16 = 4;
    pub const XINPUT_GAMEPAD_DPAD_RIGHT: u16 = 8;
    pub const XINPUT_GAMEPAD_START: u16 = 16;
    pub const XINPUT_GAMEPAD_BACK: u16 = 32;
    pub const XINPUT_GAMEPAD_LEFT_SHOULDER: u16 = 256;
    pub const XINPUT_GAMEPAD_RIGHT_SHOULDER: u16 = 512;
    pub const XINPUT_GAMEPAD_A: u16 = 4096;
    pub const XINPUT_GAMEPAD_B: u16 = 8192;
    pub const XINPUT_GAMEPAD_X: u16 = 16384;
    pub const XINPUT_GAMEPAD_Y: u16 = 32768;
}

pub struct PadState {
    pub buttons: u16,
    pub left_x: i16,
    pub left_y: i16,
    pub left_trigger: u8,
    pub right_trigger: u8,
}

pub fn pad() -> Option<PadState> {
    use buttons::*;
    use objc2_game_controller::GCController;
    objc2::rc::autoreleasepool(|_| unsafe {
        let controllers = GCController::controllers();
        let profile = controllers.firstObject()?.extendedGamepad()?;
        let dpad = profile.dpad();
        let stick = profile.leftThumbstick();
        let entries = [
            (dpad.up().isPressed(), XINPUT_GAMEPAD_DPAD_UP),
            (dpad.down().isPressed(), XINPUT_GAMEPAD_DPAD_DOWN),
            (dpad.left().isPressed(), XINPUT_GAMEPAD_DPAD_LEFT),
            (dpad.right().isPressed(), XINPUT_GAMEPAD_DPAD_RIGHT),
            (profile.buttonA().isPressed(), XINPUT_GAMEPAD_A),
            (profile.buttonB().isPressed(), XINPUT_GAMEPAD_B),
            (profile.buttonX().isPressed(), XINPUT_GAMEPAD_X),
            (profile.buttonY().isPressed(), XINPUT_GAMEPAD_Y),
            (
                profile.leftShoulder().isPressed(),
                XINPUT_GAMEPAD_LEFT_SHOULDER,
            ),
            (
                profile.rightShoulder().isPressed(),
                XINPUT_GAMEPAD_RIGHT_SHOULDER,
            ),
            (profile.buttonMenu().isPressed(), XINPUT_GAMEPAD_START),
            (
                profile
                    .buttonOptions()
                    .is_some_and(|button| button.isPressed()),
                XINPUT_GAMEPAD_BACK,
            ),
        ];
        Some(PadState {
            buttons: entries
                .into_iter()
                .filter(|(pressed, _)| *pressed)
                .map(|(_, mask)| mask)
                .fold(0, |state, bit| state | bit),
            left_x: (stick.xAxis().value() * i16::MAX as f32) as i16,
            left_y: (stick.yAxis().value() * i16::MAX as f32) as i16,
            left_trigger: (profile.leftTrigger().value() * u8::MAX as f32) as u8,
            right_trigger: (profile.rightTrigger().value() * u8::MAX as f32) as u8,
        })
    })
}
