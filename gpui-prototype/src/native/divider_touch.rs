use std::cell::{Cell, RefCell};

use async_channel::Sender;
use gpui_kit::Window;
use windows_sys::Win32::{
    Foundation::{HWND, LPARAM, LRESULT, POINT, WPARAM},
    Graphics::Gdi::ScreenToClient,
    UI::{
        Input::Pointer::GetPointerType,
        Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass},
        WindowsAndMessaging::{
            POINTER_MESSAGE_FLAG_CANCELED, PT_TOUCH, WM_NCDESTROY, WM_POINTERCAPTURECHANGED,
            WM_POINTERDOWN, WM_POINTERENTER, WM_POINTERLEAVE, WM_POINTERUP, WM_POINTERUPDATE,
        },
    },
};

use crate::{
    floating_panel::Bounds,
    plugins::multiview_resize::{Axis, Divider},
};

const TOUCH_WIDTH: f32 = 32.0;

pub(crate) enum Event {
    Start(Axis),
    Move([f32; 2]),
    End(Option<[f32; 2]>),
}

struct Targets {
    scale: f32,
    dividers: Vec<Divider>,
    panel: Option<Bounds>,
}

#[derive(Clone, Copy)]
struct Grab {
    id: u16,
    coordinate: usize,
    offset: f32,
}

impl Targets {
    fn hit(&self, point: [f32; 2], id: u16) -> Option<(Axis, Grab)> {
        let [x, y] = point;
        if self.panel.is_some_and(|panel| {
            x >= panel.x && x < panel.x + panel.width && y >= panel.y && y < panel.y + panel.height
        }) {
            return None;
        }
        self.dividers
            .iter()
            .filter_map(|divider| {
                let [left, top, width, height] = divider.rect;
                let (coordinate, offset) = match divider.axis {
                    Axis::Vertical if y >= top && y < top + height => (0, x - (left + width / 2.0)),
                    Axis::Horizontal if x >= left && x < left + width => (1, y - (top + height / 2.0)),
                    _ => return None,
                };
                (offset.abs() <= TOUCH_WIDTH / 2.0)
                    .then_some((divider.axis, Grab { id, coordinate, offset }))
            })
            .min_by(|(_, a), (_, b)| a.offset.abs().total_cmp(&b.offset.abs()))
    }
}

impl Grab {
    fn split_position(self, mut point: [f32; 2]) -> [f32; 2] {
        point[self.coordinate] -= self.offset;
        point
    }
}

struct State {
    attached: Cell<bool>,
    events: Sender<Event>,
    targets: RefCell<Targets>,
    grab: Cell<Option<Grab>>,
}

pub(crate) struct TouchDividers {
    window: HWND,
    state: Box<State>,
}

impl TouchDividers {
    pub(crate) fn attach(window: &Window, events: Sender<Event>) -> Option<Self> {
        let hwnd = super::window_handle(window).ok()?;
        let state = Box::new(State {
            attached: Cell::new(true),
            events,
            targets: RefCell::new(Targets {
                scale: window.scale_factor(),
                dividers: Vec::new(),
                panel: None,
            }),
            grab: Cell::new(None),
        });
        let data = (&*state as *const State) as usize;
        // The boxed state remains valid until the subclass is removed on the UI thread.
        if unsafe { SetWindowSubclass(hwnd, Some(pointer_proc), data, data) } == 0 {
            return None;
        }
        Some(Self { window: hwnd, state })
    }

    pub(crate) fn set_targets(&self, scale: f32, dividers: Vec<Divider>, panel: Option<Bounds>) {
        *self.state.targets.borrow_mut() = Targets { scale, dividers, panel };
    }
}

impl Drop for TouchDividers {
    fn drop(&mut self) {
        if self.state.attached.get() {
            let id = (&*self.state as *const State) as usize;
            unsafe { RemoveWindowSubclass(self.window, Some(pointer_proc), id) };
        }
    }
}

unsafe extern "system" fn pointer_proc(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    subclass: usize,
    data: usize,
) -> LRESULT {
    let state = unsafe { &*(data as *const State) };
    if message == WM_NCDESTROY {
        state.attached.set(false);
        unsafe { RemoveWindowSubclass(hwnd, Some(pointer_proc), subclass) };
    } else if state.handle(hwnd, message, wparam, lparam) {
        return 0;
    }
    unsafe { DefSubclassProc(hwnd, message, wparam, lparam) }
}

impl State {
    fn handle(&self, hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> bool {
        let id = wparam as u16;
        if let Some(grab) = self.grab.get().filter(|grab| grab.id == id) {
            let canceled = ((wparam >> 16) as u32) & POINTER_MESSAGE_FLAG_CANCELED != 0;
            match message {
                WM_POINTERUPDATE if !canceled => {
                    if let Some(point) = self.client_point(hwnd, lparam) {
                        let _ = self.events.try_send(Event::Move(grab.split_position(point)));
                    }
                }
                WM_POINTERUP | WM_POINTERUPDATE | WM_POINTERCAPTURECHANGED => {
                    self.grab.set(None);
                    let point = (message == WM_POINTERUP && !canceled)
                        .then(|| self.client_point(hwnd, lparam))
                        .flatten()
                        .map(|point| grab.split_position(point));
                    let _ = self.events.try_send(Event::End(point));
                }
                WM_POINTERENTER | WM_POINTERLEAVE => {}
                _ => return false,
            }
            return true;
        }
        if message != WM_POINTERDOWN || self.grab.get().is_some() {
            return false;
        }
        let Some(point) = self.client_point(hwnd, lparam) else { return false };
        let Some((axis, grab)) = self.targets.borrow().hit(point, id) else { return false };
        let mut pointer_type = 0;
        if unsafe { GetPointerType(u32::from(id), &mut pointer_type) } == 0 || pointer_type != PT_TOUCH {
            return false;
        }
        if self.events.try_send(Event::Start(axis)).is_err() {
            return false;
        }
        // Windows captures this contact until up or capture change, even off the divider.
        self.grab.set(Some(grab));
        true
    }

    fn client_point(&self, hwnd: HWND, lparam: LPARAM) -> Option<[f32; 2]> {
        let mut point = POINT {
            x: i32::from(lparam as i16),
            y: i32::from((lparam >> 16) as i16),
        };
        if unsafe { ScreenToClient(hwnd, &mut point) } == 0 {
            return None;
        }
        let scale = self.targets.borrow().scale;
        Some([point.x as f32 / scale, point.y as f32 / scale])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touch_grabs_the_nearest_divider_without_moving_it_on_contact() {
        let targets = Targets {
            scale: 1.5,
            dividers: vec![
                Divider { axis: Axis::Vertical, rect: [496.0, 48.0, 8.0, 500.0] },
                Divider { axis: Axis::Horizontal, rect: [504.0, 294.0, 496.0, 8.0] },
            ],
            panel: Some(Bounds { x: 400.0, y: 55.0, width: 200.0, height: 100.0, radius: 8.0 }),
        };
        let (axis, grab) = targets.hit([512.0, 296.0], 1).unwrap();
        assert_eq!(axis, Axis::Horizontal);
        assert_eq!(grab.split_position([512.0, 296.0]), [512.0, 298.0]);
        let (axis, grab) = targets.hit([488.0, 298.0], 1).unwrap();
        assert_eq!(axis, Axis::Vertical);
        assert_eq!(grab.split_position([488.0, 298.0]), [500.0, 298.0]);
        assert!(targets.hit([500.0, 100.0], 1).is_none());
        assert!(targets.hit([600.0, 320.0], 1).is_none());
    }
}
