use crate::floating_panel::Bounds;
use gpui_kit::Window;
use objc2::{MainThreadMarker, MainThreadOnly, rc::Retained};
use objc2_app_kit::NSView;
use objc2_core_graphics::CGMutablePath;
use objc2_foundation::{NSPoint, NSRect, NSSize};
use objc2_quartz_core::{CAShapeLayer, CATransaction, kCAFillRuleEvenOdd};
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

pub fn client_size(window: &Window) -> (f32, f32) {
    parent_view(window).map_or((1.0, 1.0), |view| {
        let size = view.bounds().size;
        (size.width as f32, size.height as f32)
    })
}

thread_local! {
    // The app has one main window; remember its frame without retaining it.
    static RESTORE_FRAME: Cell<Option<(usize, NSRect)>> = const { Cell::new(None) };
}

pub fn toggle_maximized(window: &Window, cx: &gpui_kit::App) {
    let Some(window) = parent_view(window).ok().and_then(NSView::window) else {
        return;
    };
    // Let the event handler release GPUI's window before AppKit sends resize
    // and screen-scale notifications back to it.
    cx.foreground_executor()
        .spawn(async move { toggle_window_frame(&window) })
        .detach();
}

fn toggle_window_frame(window: &objc2_app_kit::NSWindow) {
    let Some(screen) = window.screen() else {
        return;
    };
    // AppKit's zoom actions do not resize this borderless window. Fill the
    // usable screen area directly, keeping the menu bar and Dock available.
    let frame = window.frame();
    let visible = screen.visibleFrame();
    let id = std::ptr::from_ref(window) as usize;
    let filled = (frame.origin.x - visible.origin.x).abs() < 1.0
        && (frame.origin.y - visible.origin.y).abs() < 1.0
        && (frame.size.width - visible.size.width).abs() < 1.0
        && (frame.size.height - visible.size.height).abs() < 1.0;
    RESTORE_FRAME.with(|saved| {
        let target = match saved.get().filter(|(previous, _)| filled && *previous == id) {
            Some((_, original)) => {
                saved.set(None);
                original
            }
            None => {
                saved.set(Some((id, frame)));
                visible
            }
        };
        window.setFrame_display(target, true);
    });
}

pub struct Surface {
    view: Retained<NSView>,
    frame: Cell<Option<NSRect>>,
    panel: Cell<Option<Bounds>>,
}

impl Surface {
    pub fn new(window: &Window, top: f32) -> Result<Self, String> {
        Self::create(window, top, 0.0)
    }
    pub fn video(window: &Window, bottom: f32, panel: Option<Bounds>) -> Result<Self, String> {
        let surface = Self::create(window, 0.0, bottom)?;
        surface.resize_video(window, bottom, panel);
        Ok(surface)
    }

    fn create(window: &Window, top: f32, bottom: f32) -> Result<Self, String> {
        let marker = MainThreadMarker::new().ok_or("无法在后台线程创建窗口")?;
        let parent = parent_view(window)?;
        let view = NSView::initWithFrame(NSView::alloc(marker), parent.bounds());
        view.setWantsLayer(true);
        parent.addSubview(&view);
        let surface = Self {
            view,
            frame: Cell::new(None),
            panel: Cell::new(None),
        };
        surface.resize_insets(window, top, bottom);
        Ok(surface)
    }

    pub fn id(&self) -> usize {
        Retained::as_ptr(&self.view) as usize
    }
    pub fn resize(&self, window: &Window, top: f32) -> (i32, i32) {
        self.resize_insets(window, top, 0.0)
    }
    pub fn resize_video(&self, window: &Window, bottom: f32, panel: Option<Bounds>) {
        let previous_frame = self.frame.get();
        self.resize_insets(window, 0.0, bottom);
        let previous_panel = self.panel.replace(panel);
        if previous_panel == panel && previous_frame == self.frame.get() {
            return;
        }
        let Some(layer) = self.view.layer() else {
            return;
        };
        let mask = panel.map(|panel| {
            let bounds = self.view.bounds();
            let cutout = NSRect::new(
                NSPoint::new(
                    f64::from(panel.x),
                    bounds.size.height - f64::from(panel.y + panel.height),
                ),
                NSSize::new(f64::from(panel.width), f64::from(panel.height)),
            );
            let path = CGMutablePath::new();
            let radius = f64::from(panel.radius);
            let mask = CAShapeLayer::layer();
            unsafe {
                CGMutablePath::add_rect(Some(&path), std::ptr::null(), bounds);
                CGMutablePath::add_rounded_rect(
                    Some(&path),
                    std::ptr::null(),
                    cutout,
                    radius,
                    radius,
                );
                mask.setFillRule(kCAFillRuleEvenOdd);
            }
            mask.setFrame(bounds);
            mask.setPath(Some(&path));
            Retained::into_super(mask)
        });
        CATransaction::begin();
        CATransaction::setDisableActions(true);
        unsafe { layer.setMask(mask.as_deref()) };
        CATransaction::commit();
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
        let frame = NSRect::new(
            NSPoint::new(bounds.origin.x, bounds.origin.y + y),
            NSSize::new(width, height),
        );
        if self.frame.replace(Some(frame)) != Some(frame) {
            self.view.setFrame(frame);
        }
        (
            (width * f64::from(window.scale_factor())).round() as i32,
            (height * f64::from(window.scale_factor())).round() as i32,
        )
    }
}

impl HasWindowHandle for Surface {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let view = NonNull::from(&*self.view).cast();
        Ok(unsafe { WindowHandle::borrow_raw(AppKitWindowHandle::new(view).into()) })
    }
}

impl Drop for Surface {
    fn drop(&mut self) {
        self.view.removeFromSuperview();
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
