use std::{
    cell::RefCell,
    collections::VecDeque,
    ops::Range,
    rc::Rc,
    sync::{Arc, LazyLock},
    time::Duration,
};

use super::*;
use playback::{CHOICES_HEIGHT, CHOICES_PER_PAGE, ChoiceMenu};

const BG: u32 = 0x10171e;
const PANEL: u32 = 0x17232c;
const SURFACE: u32 = 0x1b2a34;
const DIVIDER: u32 = 0x293741;
const TEXT: u32 = 0xf2f5f7;
const MUTED: u32 = 0xa8b7c1;
const MINT: u32 = 0x4ff2ba;
const ROOM_CARD_HEIGHT: f32 = 214.0;

pub(super) fn init_theme(cx: &mut App) {
    use gpui_kit::component::{Theme, ThemeMode};
    Theme::change(ThemeMode::Dark, None, cx);
    Theme::update(cx, |theme| {
        theme.colors.foreground = rgb(TEXT).into();
        theme.colors.muted_foreground = rgb(MUTED).into();
        theme.colors.input = rgb(DIVIDER).into();
        theme.colors.ring = rgb(MINT).into();
        theme.colors.caret = rgb(MINT).into();
    });
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Pane {
    Follows,
    Popular,
    Search,
    Settings,
}

impl Pane {
    const TABS: [Self; 3] = [Self::Follows, Self::Popular, Self::Search];

    fn label(self) -> &'static str {
        match self {
            Self::Follows => "关注",
            Self::Popular => "热门",
            Self::Search => "搜索",
            Self::Settings => "设置",
        }
    }
}

fn control(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    active: bool,
) -> Stateful<Div> {
    div()
        .id(id)
        .h_flex()
        .items_center()
        .justify_center()
        .h(px(38.0))
        .px_3()
        .rounded_md()
        .border_1()
        .border_color(rgb(if active { MINT } else { DIVIDER }))
        .bg(rgb(if active { 0x17332d } else { PANEL }))
        .text_color(rgb(if active { MINT } else { TEXT }))
        .hover(|style| style.border_color(rgb(MINT)))
        .cursor_pointer()
        .child(label.into())
}

enum Cover {}

const COVER_CACHE_SIZE: usize = 48;
type CoverEntry = (String, Option<Arc<RenderImage>>);

#[derive(Clone, Default)]
pub(super) struct CoverCache(Rc<RefCell<VecDeque<CoverEntry>>>);

impl CoverCache {
    fn get(&self, url: &String, window: &mut Window, cx: &mut App) -> Option<Arc<RenderImage>> {
        let image = window.use_asset::<Cover>(url, cx).flatten();
        let mut entries = self.0.borrow_mut();
        if let Some(index) = entries.iter().position(|(key, _)| key == url) {
            let entry = entries.remove(index).expect("cover cache index");
            entries.push_back((entry.0, image.clone()));
        } else {
            if entries.len() == COVER_CACHE_SIZE {
                let oldest = entries.pop_front().expect("full cover cache");
                let cache = self.clone();
                window.defer(cx, move |window, cx| {
                    if !cache.0.borrow().iter().any(|(url, _)| *url == oldest.0) {
                        cache_evict(oldest, window, cx);
                    }
                });
            }
            entries.push_back((url.clone(), image.clone()));
        }
        image
    }

    pub(super) fn clear(&self, window: &mut Window, cx: &mut App) {
        for entry in self.0.borrow_mut().drain(..) {
            cache_evict(entry, window, cx);
        }
    }

    pub(super) fn retry_failed(&self, cx: &mut App) {
        self.0.borrow_mut().retain(|(url, _)| {
            let failed = matches!(cx.fetch_asset::<Cover>(url), Some(None));
            if failed {
                cx.remove_asset::<Cover>(url);
            }
            !failed
        });
    }
}

fn cache_evict((url, image): CoverEntry, window: &mut Window, cx: &mut App) {
    cx.remove_asset::<Cover>(&url);
    if let Some(image) = image {
        let _ = window.drop_image(image);
    }
}

impl Asset for Cover {
    type Source = String;
    type Output = Option<Arc<RenderImage>>;

    fn load(source: String, _: &mut App) -> impl Future<Output = Self::Output> + Send + 'static {
        async move {
            let source = if source.starts_with("//") {
                format!("https:{source}")
            } else {
                source
            };
            let uri = url::Url::parse(&source).ok()?;
            if !matches!(uri.scheme(), "http" | "https") {
                return None;
            }
            static HTTP: LazyLock<ureq::Agent> = LazyLock::new(|| {
                ureq::Agent::config_builder()
                    .timeout_global(Some(Duration::from_secs(6)))
                    .max_idle_connections(12)
                    .max_idle_connections_per_host(2)
                    .build()
                    .into()
            });
            static LOADS: LazyLock<async_lock::Semaphore> =
                LazyLock::new(|| async_lock::Semaphore::new(4));
            let _permit = LOADS.acquire().await;
            let bytes = HTTP
                .get(uri.as_str())
                .call()
                .ok()?
                .body_mut()
                .with_config()
                .limit(2 * 1024 * 1024)
                .read_to_vec()
                .ok()?;
            thumbnail(&bytes)
        }
    }
}

fn thumbnail(bytes: &[u8]) -> Option<Arc<RenderImage>> {
    // Bound the transient decode allocation as well as the retained texture.
    static DECODE: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _decode = DECODE.lock().ok()?;
    let mut reader = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .ok()?;
    if !matches!(
        reader.format(),
        Some(image::ImageFormat::Jpeg | image::ImageFormat::Png | image::ImageFormat::WebP)
    ) {
        return None;
    }
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(4096);
    limits.max_image_height = Some(4096);
    limits.max_alloc = Some(48 * 1024 * 1024);
    reader.limits(limits);
    let mut small = reader.decode().ok()?.thumbnail(400, 225).into_rgba8();
    for pixel in small.chunks_exact_mut(4) {
        pixel.swap(0, 2);
    }
    Some(Arc::new(RenderImage::new([image::Frame::new(small)])))
}

#[cfg(test)]
mod tests {
    use super::thumbnail;

    #[test]
    fn retains_only_card_sized_bgra_pixels() {
        let source = image::RgbImage::from_pixel(1600, 900, image::Rgb([210, 30, 15]));
        let mut encoded = std::io::Cursor::new(Vec::new());
        source
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        let thumb = thumbnail(encoded.get_ref()).unwrap();
        let pixels = thumb.as_bytes(0).unwrap();
        assert_eq!(pixels.len(), 400 * 225 * 4);
        assert_eq!(&pixels[..4], &[15, 30, 210, 255]);
    }
}

impl Home {
    pub(super) fn select_pane(&mut self, pane: Pane, window: &mut Window, cx: &mut Context<Self>) {
        if self.content.is_some() {
            return;
        }
        let previous = self.pane;
        self.pane = pane;
        self.platform_cursor = None;
        self.request_id += 1;
        self.room_selection = None;
        self.rooms_scroll = UniformListScrollHandle::new();
        self.status.clear();
        self.show_follows = pane == Pane::Follows;
        match pane {
            Pane::Follows => self.next_follow_check = None,
            Pane::Popular => {
                self.request_rooms(String::new(), window, cx);
            }
            Pane::Search if previous != Pane::Search => self.results.clear(),
            Pane::Settings => {
                self.selected = SETTINGS_ACTIONS[0];
                self.account_tabs_focused = true;
                self.settings_scroll = ScrollHandle::new();
            }
            _ => {}
        }
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn step_pane(&mut self, step: isize, window: &mut Window, cx: &mut Context<Self>) {
        if self.platform_cursor.is_some() && self.pane != Pane::Popular {
            self.move_platform(0, step, cx);
            return;
        }
        if self.content.is_some() {
            self.move_selection(step > 0, cx);
            return;
        }
        let current = Pane::TABS
            .iter()
            .position(|pane| *pane == self.pane)
            .unwrap_or(0);
        let next = (current as isize + step).rem_euclid(Pane::TABS.len() as isize) as usize;
        self.select_pane(Pane::TABS[next], window, cx);
    }

    pub(super) fn go_back(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.content.is_some() || self.active_room.is_some() {
            self.choose(Action::Back, window, cx);
        } else if self.platform_cursor.is_some() && self.pane != Pane::Popular {
            self.platform_cursor = None;
            cx.notify();
        } else if self.pane != Pane::Follows {
            self.select_pane(Pane::Follows, window, cx);
        }
    }

    fn header(&self, cx: &mut Context<Self>) -> Div {
        div()
            .h_flex()
            .h(px(57.0))
            .flex_shrink_0()
            .items_center()
            .px_6()
            .border_b_1()
            .border_color(rgb(DIVIDER))
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .items_center()
                    .min_w(px(120.0))
                    .child(div().text_color(rgb(MINT)).child("▶"))
                    .child(div().font_weight(FontWeight::SEMIBOLD).child("纯粹直播")),
            )
            .child(
                div()
                    .h_flex()
                    .flex_1()
                    .h_full()
                    .justify_center()
                    .gap_2()
                    .children(Pane::TABS.into_iter().enumerate().map(|(index, pane)| {
                        let active = pane == self.pane;
                        div()
                            .id(("tab", index))
                            .h_flex()
                            .h_full()
                            .items_center()
                            .justify_center()
                            .px_4()
                            .border_b_2()
                            .border_color(rgb(if active { MINT } else { BG }))
                            .text_color(rgb(if active { MINT } else { MUTED }))
                            .font_weight(if active {
                                FontWeight::SEMIBOLD
                            } else {
                                FontWeight::NORMAL
                            })
                            .hover(|style| style.text_color(rgb(MINT)))
                            .cursor_pointer()
                            .child(pane.label())
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.select_pane(pane, window, cx)
                            }))
                    })),
            )
            .child(div().h_flex().min_w(px(120.0)).justify_end().child(
                control("settings-tab", "⚙  设置", self.pane == Pane::Settings).on_click(
                    cx.listener(|this, _, window, cx| this.select_pane(Pane::Settings, window, cx)),
                ),
            ))
    }

    fn footer(&self) -> Div {
        let hints: &[(&str, &str)] = if self.pane == Pane::Search && self.platform_cursor.is_some()
        {
            &[("方向键", "筛选平台"), ("Ⓐ", "选择"), ("Ⓑ", "返回")]
        } else if self.platform_cursor.is_some() {
            &[
                ("← / →", "切平台"),
                ("↓", "直播列表"),
                ("Ⓐ", "选择"),
                ("Ⓑ", "返回"),
            ]
        } else if self.pane == Pane::Search {
            &[
                ("Ⓐ", "观看"),
                ("Ⓨ", "关注"),
                ("View / F2", "筛选平台"),
                ("Ⓧ", "输入搜索"),
                ("Ⓑ", "返回"),
            ]
        } else if self.pane == Pane::Settings {
            &[
                ("← / →", "切平台"),
                ("↑ / ↓", "移动"),
                ("Ⓐ", "选择"),
                ("Ⓑ", "返回"),
            ]
        } else if self.pane == Pane::Follows && self.room_selection.is_none() {
            &[
                ("LB / RB", "切换筛选"),
                ("LT / RT", "切换栏目"),
                ("↓", "直播列表"),
                ("Ⓧ", "刷新"),
            ]
        } else if self.pane == Pane::Follows {
            &[
                ("Ⓐ", "观看"),
                ("Ⓨ", "取消关注"),
                ("Ⓧ", "刷新"),
                ("LB / RB", "切换筛选"),
            ]
        } else {
            &[
                ("Ⓐ", "观看"),
                ("Ⓨ", "关注"),
                ("Ⓑ", "返回"),
                ("Ⓧ", "搜索"),
                ("LB / RB", "切换平台"),
                ("LT / RT", "切换栏目"),
            ]
        };
        div()
            .h_flex()
            .h(px(43.0))
            .flex_shrink_0()
            .items_center()
            .justify_center()
            .gap_6()
            .border_t_1()
            .border_color(rgb(DIVIDER))
            .text_sm()
            .text_color(rgb(MUTED))
            .children(hints.iter().copied().map(|(key, text)| {
                div()
                    .h_flex()
                    .gap_2()
                    .items_center()
                    .child(
                        div()
                            .text_color(rgb(MINT))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(key),
                    )
                    .child(text)
            }))
    }

    fn room_card(&self, index: usize, room: &Room, cx: &mut Context<Self>) -> Stateful<Div> {
        let selected = self.room_selection == Some(index);
        let status = room.broadcast_status();
        let followed = self.follows.iter().any(|saved| saved.same_channel(room));
        let platform = self
            .platforms
            .iter()
            .find(|site| site.id == room.platform)
            .map_or(room.platform.as_str(), |site| site.name.as_str())
            .to_owned();
        let cover = room.cover.clone();
        let covers = self.covers.clone();
        let play = room.clone();
        let save = room.clone();
        div()
            .id(("card", index))
            .v_flex()
            .h(px(ROOM_CARD_HEIGHT))
            .min_w_0()
            .rounded_lg()
            .overflow_hidden()
            .border_2()
            .border_color(rgb(if selected { MINT } else { DIVIDER }))
            .bg(rgb(if selected { SURFACE } else { PANEL }))
            .cursor_pointer()
            // Hover must not look like the selection ring: only a dim edge.
            .when(!selected, |card| {
                card.hover(|style| style.border_color(rgb(0x3d5866)))
            })
            .on_click(
                cx.listener(move |this, _, window, cx| this.play_room(play.clone(), window, cx)),
            )
            .child(
                div()
                    .relative()
                    .w_full()
                    .h(px(149.0))
                    .flex_shrink_0()
                    .overflow_hidden()
                    .bg(linear_gradient(
                        130.0,
                        linear_color_stop(rgb(0x203740), 0.0),
                        linear_color_stop(rgb(0x12212d), 1.0),
                    ))
                    .child(
                        div()
                            .absolute()
                            .inset_0()
                            .h_flex()
                            .items_center()
                            .justify_center()
                            .text_2xl()
                            .text_color(rgb(0x52717b))
                            .child("▶"),
                    )
                    .when(!cover.is_empty(), |frame| {
                        frame.child(
                            img(ImageSource::Custom(Arc::new(move |window, cx| {
                                covers.get(&cover, window, cx).map(Ok)
                            })))
                            .absolute()
                            .inset_0()
                            .size_full()
                            .object_fit(ObjectFit::Cover),
                        )
                    })
                    .child(
                        div()
                            .absolute()
                            .top_2()
                            .left_2()
                            .rounded_sm()
                            .px_2()
                            .py_1()
                            .text_xs()
                            .bg(rgba(0x0b131ae8))
                            .text_color(rgb(if status == BroadcastStatus::Live {
                                MINT
                            } else {
                                TEXT
                            }))
                            .child(match status {
                                BroadcastStatus::Live
                                    if self.pane == Pane::Search
                                        && self.search_platform.is_none() =>
                                {
                                    format!("●  {platform}")
                                }
                                BroadcastStatus::Live => "●  直播中".into(),
                                BroadcastStatus::Offline => "未开播".into(),
                                BroadcastStatus::Replay => "回放".into(),
                                BroadcastStatus::Unknown => platform.clone(),
                            }),
                    ),
            )
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .items_center()
                    .px_3()
                    .py_2()
                    .child(
                        div()
                            .v_flex()
                            .min_w_0()
                            .flex_1()
                            .gap_1()
                            .child(
                                div()
                                    .text_sm()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .text_ellipsis()
                                    .child(room.title.clone()),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(rgb(MUTED))
                                    .text_ellipsis()
                                    .child(if room.nick.is_empty() {
                                        platform
                                    } else {
                                        room.nick.clone()
                                    }),
                            ),
                    )
                    .child(
                        div()
                            .id(("card-follow", index))
                            .flex_shrink_0()
                            .size(px(36.0))
                            .h_flex()
                            .items_center()
                            .justify_center()
                            .rounded_md()
                            .cursor_pointer()
                            .hover(|style| style.bg(rgb(SURFACE)))
                            .child(follow_icon(followed, if followed { MINT } else { MUTED }))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                cx.stop_propagation();
                                this.toggle_follow(save.clone(), cx);
                            })),
                    ),
            )
    }

    fn room_grid(&self, row_gap: f32, cx: &mut Context<Self>) -> UniformList {
        uniform_list(
            "room-grid",
            self.room_count().div_ceil(3),
            cx.processor(move |this, rows: Range<usize>, _, cx| {
                rows.map(|row| {
                    let start = row * 3;
                    let end = (start + 3).min(this.room_count());
                    div()
                        .grid()
                        .grid_cols(3)
                        .grid_rows(1)
                        .w_full()
                        .h(px(ROOM_CARD_HEIGHT + row_gap))
                        .gap_3()
                        .pb(px(row_gap))
                        .children((start..end).filter_map(|index| {
                            this.room_at(index)
                                .map(|room| this.room_card(index, room, cx))
                        }))
                })
                .collect()
            }),
        )
        .track_scroll(&self.rooms_scroll)
        .flex_1()
        .min_h_0()
    }

    fn popular_view(&self, cx: &mut Context<Self>) -> Div {
        div()
            .v_flex()
            .flex_1()
            .min_h_0()
            .px_6()
            .pt_3()
            .gap_2()
            .child(
                div()
                    .h_flex()
                    .items_center()
                    .gap_2()
                    .child(self.platform_strip(cx))
                    .child(
                        control("refresh-popular", "刷新", false).on_click(cx.listener(
                            |this, _, window, cx| this.request_rooms(String::new(), window, cx),
                        )),
                    ),
            )
            .when(self.room_count() == 0 && !self.status.is_empty(), |view| {
                view.child(
                    div()
                        .pt_2()
                        .text_sm()
                        .text_color(rgb(MUTED))
                        .child(self.status.clone()),
                )
            })
            .when(self.room_count() != 0, |view| {
                view.child(self.room_grid(8.0, cx))
            })
    }

    fn follow_tabs(&self, cx: &mut Context<Self>) -> Div {
        div().h_flex().justify_center().child(
            div()
                .h_flex()
                .rounded_full()
                .border_1()
                .border_color(rgb(DIVIDER))
                .bg(rgb(PANEL))
                .p(px(2.0))
                .children(
                    FollowFilter::TABS
                        .into_iter()
                        .enumerate()
                        .map(|(index, filter)| {
                            let active = self.follow_filter == filter;
                            div()
                                .id(("follow-filter", index))
                                .h_flex()
                                .items_center()
                                .justify_center()
                                .w(px(90.0))
                                .h(px(32.0))
                                .rounded_full()
                                .text_sm()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(rgb(if active { MINT } else { MUTED }))
                                .when(active, |tab| {
                                    tab.bg(rgb(if self.room_selection.is_none() {
                                        0x244638
                                    } else {
                                        0x17332d
                                    }))
                                })
                                .when(!active, |tab| {
                                    tab.hover(|style| style.text_color(rgb(TEXT)))
                                })
                                .cursor_pointer()
                                .child(filter.label())
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.select_follow_filter(filter, cx)
                                }))
                        }),
                ),
        )
    }

    fn directory_view(&self, cx: &mut Context<Self>) -> Div {
        let site = self
            .search_platform
            .map_or("全部", |index| self.platforms[index].name.as_str());
        let heading = self.pane.label();
        div()
            .v_flex()
            .flex_1()
            .min_h_0()
            .px_6()
            .pt_4()
            .gap_3()
            .child(
                div()
                    .h_flex()
                    .relative()
                    .items_center()
                    .gap_2()
                    .child(div().flex_1().child(if self.pane == Pane::Follows {
                        self.follow_tabs(cx)
                    } else {
                        div()
                            .text_xl()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(heading)
                    }))
                    .when(self.pane != Pane::Follows, |row| {
                        row.child(
                            control("site-select", format!("{site}  ▾"), false).on_click(
                                cx.listener(|this, _, window, cx| {
                                    this.choose(Action::SearchPlatform, window, cx)
                                }),
                            ),
                        )
                    })
                    .when(
                        self.pane == Pane::Follows && !self.follows.is_empty(),
                        |row| {
                            let label = if self.room_status_task.is_some() {
                                "刷新中…"
                            } else {
                                "刷新"
                            };
                            row.child(div().absolute().right_0().top_0().child(
                                control("refresh-follows", label, false).on_click(cx.listener(
                                    |this, _, window, cx| this.refresh_follow_statuses(window, cx),
                                )),
                            ))
                        },
                    )
                    .when(self.pane == Pane::Popular, |row| {
                        row.child(control("refresh", "刷新", false).on_click(cx.listener(
                            |this, _, window, cx| this.request_rooms(String::new(), window, cx),
                        )))
                    }),
            )
            .when(self.pane == Pane::Search, |view| {
                view.child(
                    div()
                        .h_flex()
                        .gap_2()
                        .child(
                            div().flex_1().child(
                                Input::new(&self.query).bg(rgb(PANEL)).text_color(rgb(TEXT)),
                            ),
                        )
                        .child(
                            control("search-button", "搜索", true).on_click(
                                cx.listener(|this, _, window, cx| this.search(window, cx)),
                            ),
                        ),
                )
            })
            .when(self.pane == Pane::Search, |view| {
                view.children(
                    self.dictation
                        .hint()
                        .map(|hint| div().text_sm().text_color(rgb(MUTED)).child(hint)),
                )
            })
            .when(self.room_count() == 0, |view| {
                view.child(
                    div()
                        .v_flex()
                        .flex_1()
                        .items_center()
                        .justify_center()
                        .gap_3()
                        .pb_6()
                        .child(div().text_xl().text_color(rgb(MUTED)).child(
                            if self.pane == Pane::Follows {
                                match self.follow_filter {
                                    FollowFilter::Live => "没有已开播的关注房间",
                                    FollowFilter::All => "还没有关注的直播间",
                                    FollowFilter::Offline => "没有未开播的关注房间",
                                }
                                .to_owned()
                            } else if self.status.is_empty() {
                                "搜索直播间".to_owned()
                            } else {
                                self.status.clone()
                            },
                        ))
                        .when(
                            self.pane == Pane::Follows && self.follows.is_empty(),
                            |empty| {
                                empty.child(control("browse-popular", "浏览热门", true).on_click(
                                    cx.listener(|this, _, window, cx| {
                                        this.select_pane(Pane::Popular, window, cx)
                                    }),
                                ))
                            },
                        ),
                )
            })
            .when(self.room_count() != 0, |view| {
                view.child(self.room_grid(12.0, cx))
            })
    }

    fn settings_view(&self, cx: &mut Context<Self>) -> Div {
        div()
            .v_flex()
            .flex_1()
            .min_h_0()
            .px_6()
            .pt_4()
            .gap_3()
            .child(
                div()
                    .text_xl()
                    .font_weight(FontWeight::SEMIBOLD)
                    .child("设置"),
            )
            .child(
                div()
                    .id("settings-list")
                    .track_scroll(&self.settings_scroll)
                    .overflow_y_scroll()
                    .flex_1()
                    .v_flex()
                    .gap_4()
                    .pb_4()
                    .children(
                        [
                            ("账号", &SETTINGS_ACTIONS[..2]),
                            ("窗口", &SETTINGS_ACTIONS[2..]),
                        ]
                        .into_iter()
                        .map(|(label, actions)| {
                            div()
                                .v_flex()
                                .gap_2()
                                .child(div().text_sm().text_color(rgb(MUTED)).child(label))
                                .when(label == "账号", |group| {
                                    group.child(div().h_flex().flex_wrap().gap_2().children(
                                        account::PLATFORMS.iter().enumerate().map(
                                            |(index, site)| {
                                                control(
                                                    ("account-platform", index),
                                                    site.name,
                                                    self.account_site == index,
                                                )
                                                .on_click(cx.listener(move |this, _, _, cx| {
                                                    this.account_site = index;
                                                    this.account_tabs_focused = true;
                                                    this.selected = Action::Login;
                                                    this.status.clear();
                                                    cx.notify();
                                                }))
                                            },
                                        ),
                                    ))
                                })
                                .children(actions.iter().copied().map(|action| {
                                    let active =
                                        !self.account_tabs_focused && self.selected == action;
                                    let (icon, label) = match action {
                                        Action::Login => ("◉", "登录账号"),
                                        Action::Logout => ("◉", "退出本地登录"),
                                        Action::Minimize => ("−", "最小化"),
                                        Action::Exit => ("×", "退出"),
                                        _ => unreachable!(),
                                    };
                                    div()
                                        .id(("setting", action as usize))
                                        .h_flex()
                                        .items_center()
                                        .gap_3()
                                        .h(px(46.0))
                                        .px_4()
                                        .rounded_md()
                                        .border_1()
                                        .border_color(rgb(if active { MINT } else { DIVIDER }))
                                        .bg(rgb(if active { SURFACE } else { PANEL }))
                                        .hover(|style| style.border_color(rgb(MINT)))
                                        .cursor_pointer()
                                        .child(div().w(px(22.0)).text_color(rgb(MINT)).child(icon))
                                        .child(div().flex_1().child(label))
                                        .when(action == Action::Login, |row| {
                                            row.child(
                                                div().text_sm().text_color(rgb(MUTED)).child(
                                                    self.accounts
                                                        .get(
                                                            account::PLATFORMS[self.account_site]
                                                                .id,
                                                        )
                                                        .map(|account| account.name.clone())
                                                        .unwrap_or_else(|| "未登录".into()),
                                                ),
                                            )
                                        })
                                        .child(div().text_color(rgb(MUTED)).child("›"))
                                        .on_click(cx.listener(move |this, _, window, cx| {
                                            this.choose(action, window, cx)
                                        }))
                                }))
                        }),
                    ),
            )
    }

    fn login_header(&self, site_index: usize, cx: &mut Context<Self>) -> Div {
        div()
            .v_flex()
            .h(px(TOOLBAR))
            .flex_shrink_0()
            .px_5()
            .pt_2()
            .gap_2()
            .border_b_1()
            .border_color(rgb(DIVIDER))
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .items_center()
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .text_ellipsis()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(format!("{}账号登录", account::PLATFORMS[site_index].name)),
                    )
                    .children(
                        [
                            (Action::FinishLogin, "完成登录"),
                            (Action::Back, "返回首页"),
                        ]
                        .map(|(action, label)| {
                            control(("login", action as usize), label, self.selected == action)
                                .on_click(cx.listener(move |this, _, window, cx| {
                                    this.choose(action, window, cx)
                                }))
                        }),
                    ),
            )
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(MUTED))
                    .text_ellipsis()
                    .child(self.status.clone()),
            )
    }

    fn playback_view(&self, cx: &mut Context<Self>) -> Div {
        let video_open = matches!(self.content, Some(Content::Video { .. }));
        let line = self
            .playback
            .options
            .lines
            .iter()
            .position(|choice| Some(choice.id.as_str()) == self.playback.current(ChoiceMenu::Lines))
            .map_or_else(|| "线路".into(), |index| format!("线路 {}", index + 1));
        let quality = self
            .playback
            .options
            .quality_label
            .as_deref()
            .unwrap_or("画质");
        let followed = self
            .active_room
            .as_ref()
            .is_some_and(|room| self.follows.iter().any(|saved| saved.same_channel(room)));
        let labels = [
            if self.playback.paused {
                "▶  播放"
            } else {
                "Ⅱ  暂停"
            }
            .into(),
            "↻  刷新".into(),
            if self.danmaku_enabled {
                "弹幕 · 开"
            } else {
                "弹幕 · 关"
            }
            .into(),
            line,
            quality.into(),
            if followed { "取消关注" } else { "关注" }.into(),
            if self.audio.muted {
                "音量 · 静音".into()
            } else {
                format!("音量 · {}%", self.audio.volume)
            },
            if self.playback.super_chats.entries.is_empty() {
                "SC 历史".into()
            } else {
                format!("SC 历史 · {}", self.playback.super_chats.entries.len())
            },
        ];
        let actions = self.playback.actions();
        div()
            .size_full()
            .v_flex()
            .bg(rgb(0x000000))
            .text_color(rgb(TEXT))
            .child(
                div()
                    .id("playback-picture")
                    .flex_1()
                    .min_h_0()
                    .h_flex()
                    .items_center()
                    .justify_center()
                    .when(!video_open, |view| view.child(self.status.clone()))
                    .on_click(cx.listener(|this, _, window, cx| this.toggle_controls(window, cx))),
            )
            .when_some(self.playback.menu, |view, menu| {
                view.child(match menu {
                    ChoiceMenu::Volume => self.volume_panel(cx),
                    ChoiceMenu::SuperChat => self.super_chat_panel(cx),
                    _ => self.playback_choices(menu, cx),
                })
            })
            .when(
                self.playback.visible() && self.playback.menu.is_none(),
                |view| {
                    view.child(
                        div()
                            .v_flex()
                            .h(px(self.playback.height()))
                            .flex_shrink_0()
                            .px_4()
                            .pt_2()
                            .gap_2()
                            .bg(rgb(BG))
                            .border_t_1()
                            .border_color(rgb(DIVIDER))
                            .children(actions.chunks(4).map(|row| {
                                div()
                                    .h_flex()
                                    .gap_2()
                                    .children(row.iter().copied().map(|index| {
                                        playback_button(
                                            ("playback-control", index),
                                            labels[index].clone(),
                                            self.playback.focus == index,
                                            (index == 2 && self.danmaku_enabled)
                                                || (index == 5 && followed),
                                            (index == 5).then_some(followed),
                                        )
                                        .on_click(
                                            cx.listener(move |this, _, window, cx| {
                                                this.playback_action(index, window, cx)
                                            }),
                                        )
                                    }))
                            }))
                            .child(
                                div()
                                    .h_flex()
                                    .items_center()
                                    .justify_between()
                                    .gap_3()
                                    .text_sm()
                                    .text_color(rgb(MUTED))
                                    .child(
                                        div()
                                            .flex_1()
                                            .min_w_0()
                                            .text_ellipsis()
                                            .child(self.status.clone()),
                                    )
                                    .child(div().flex_shrink_0().child(
                                        if self.active_room.is_some() {
                                            "Ⓐ 确认   Ⓑ 返回   Ⓧ 刷新   Ⓨ 关注"
                                        } else {
                                            "Ⓐ 确认   Ⓑ 返回   Ⓧ 刷新"
                                        },
                                    ))
                                    .child(
                                        div()
                                            .id("leave-playback")
                                            .flex_shrink_0()
                                            .px_2()
                                            .rounded_md()
                                            .cursor_pointer()
                                            .text_color(rgb(TEXT))
                                            .hover(|style| style.bg(rgb(PANEL)))
                                            .child("返回列表")
                                            .on_click(cx.listener(|this, _, window, cx| {
                                                this.leave_playback(window, cx)
                                            })),
                                    ),
                            ),
                    )
                },
            )
    }

    fn playback_panel_header(&self, label: &str, detail: String, cx: &mut Context<Self>) -> Div {
        div()
            .h_flex()
            .items_center()
            .h(px(26.0))
            .gap_3()
            .child(
                div()
                    .flex_1()
                    .font_weight(FontWeight::SEMIBOLD)
                    .child(label.to_owned()),
            )
            .child(div().text_sm().text_color(rgb(MUTED)).child(detail))
            .child(
                control("close-player-panel", "Ⓑ 返回", false)
                    .h(px(26.0))
                    .on_click(cx.listener(|this, _, window, cx| this.playback_back(window, cx))),
            )
    }

    fn volume_panel(&self, cx: &mut Context<Self>) -> Div {
        let volume = self.audio.volume;
        let detail = if self.audio.muted {
            format!("静音 · {volume}%")
        } else {
            format!("{volume}%")
        };
        div()
            .v_flex()
            .h(px(self.playback.height()))
            .flex_shrink_0()
            .px_4()
            .pt_2()
            .gap_2()
            .bg(rgb(PANEL))
            .child(self.playback_panel_header("播放器音量", detail, cx))
            .child(
                div()
                    .h(px(5.0))
                    .w_full()
                    .rounded_md()
                    .overflow_hidden()
                    .bg(rgb(DIVIDER))
                    .child(
                        div()
                            .h_full()
                            .w(relative(f32::from(volume) / 100.0))
                            .bg(rgb(MINT)),
                    ),
            )
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .child(
                        playback_button("volume-down", "←  减小 5%".into(), false, false, None)
                            .on_click(cx.listener(|this, _, window, cx| {
                                this.adjust_volume(-5, window, cx)
                            })),
                    )
                    .child(
                        playback_button(
                            "volume-mute",
                            if self.audio.muted {
                                "Ⓐ 恢复声音".into()
                            } else {
                                "Ⓐ 静音".into()
                            },
                            true,
                            self.audio.muted,
                            None,
                        )
                        .on_click(cx.listener(|this, _, window, cx| this.toggle_mute(window, cx))),
                    )
                    .child(
                        playback_button("volume-up", "→  增大 5%".into(), false, false, None)
                            .on_click(
                                cx.listener(|this, _, window, cx| {
                                    this.adjust_volume(5, window, cx)
                                }),
                            ),
                    ),
            )
    }

    fn super_chat_panel(&self, cx: &mut Context<Self>) -> Div {
        let history = &self.playback.super_chats;
        let current = self.playback.cursor;
        let detail = if history.entries.is_empty() {
            String::new()
        } else {
            format!("{} / {}", current + 1, history.entries.len())
        };
        let message = history
            .error
            .as_deref()
            .or(history.connection)
            .unwrap_or("");
        let body = if let Some(card) = history.entries.get(current) {
            let text = if card.text.is_empty() && card.picture {
                "图片留言".into()
            } else {
                card.text.clone()
            };
            div()
                .v_flex()
                .gap_1()
                .child(
                    div()
                        .h_flex()
                        .items_center()
                        .gap_3()
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .text_ellipsis()
                                .font_weight(FontWeight::SEMIBOLD)
                                .child(card.user.clone()),
                        )
                        .child(
                            div()
                                .text_color(rgb(0xf5c879))
                                .font_weight(FontWeight::SEMIBOLD)
                                .child(card.price.clone()),
                        )
                        .child(
                            div()
                                .text_sm()
                                .text_color(rgb(MUTED))
                                .child(card.time.clone()),
                        ),
                )
                .child(
                    div()
                        .id("sc-message-text")
                        .max_h(px(58.0))
                        .overflow_y_scroll()
                        .child(text),
                )
        } else {
            let empty = if history.loading {
                "正在加载 SC 记录…"
            } else if history.error.is_some() {
                "暂时无法读取平台记录"
            } else {
                "还没有收到醒目留言"
            };
            div()
                .h_flex()
                .items_center()
                .justify_center()
                .size_full()
                .text_color(rgb(MUTED))
                .child(empty)
        };
        div()
            .v_flex()
            .h(px(self.playback.height()))
            .flex_shrink_0()
            .px_4()
            .pt_2()
            .gap_2()
            .bg(rgb(PANEL))
            .child(self.playback_panel_header("SC 历史 · 醒目留言", detail, cx))
            .child(
                div()
                    .flex_1()
                    .min_h_0()
                    .overflow_hidden()
                    .p_2()
                    .rounded_md()
                    .bg(rgb(BG))
                    .child(body),
            )
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .items_center()
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .text_sm()
                            .text_color(rgb(MUTED))
                            .text_ellipsis()
                            .child(message.to_owned()),
                    )
                    .when(current > 0, |row| {
                        row.child(control("sc-prev", "← 较新", false).h(px(42.0)).on_click(
                            cx.listener(|this, _, window, cx| this.move_playback(-1, window, cx)),
                        ))
                    })
                    .when(current + 1 < history.entries.len(), |row| {
                        row.child(control("sc-next", "更早 →", false).h(px(42.0)).on_click(
                            cx.listener(|this, _, window, cx| this.move_playback(1, window, cx)),
                        ))
                    })
                    .child(control("sc-refresh", "Ⓧ 刷新", false).h(px(42.0)).on_click(
                        cx.listener(|this, _, window, cx| this.refresh_super_chats(window, cx)),
                    )),
            )
    }

    fn playback_choices(&self, menu: ChoiceMenu, cx: &mut Context<Self>) -> Div {
        let choices = self.playback.choices(menu);
        let total = choices.len() + 1;
        let start = self.playback.cursor / CHOICES_PER_PAGE * CHOICES_PER_PAGE;
        let end = (start + CHOICES_PER_PAGE).min(total);
        div()
            .v_flex()
            .h(px(CHOICES_HEIGHT))
            .flex_shrink_0()
            .px_4()
            .pt_2()
            .gap_1()
            .bg(rgb(PANEL))
            .child(self.playback_panel_header(
                if menu == ChoiceMenu::Lines {
                    "选择线路"
                } else {
                    "选择画质"
                },
                format!("{} / {}", self.playback.cursor + 1, total),
                cx,
            ))
            .child(
                div()
                    .h_flex()
                    .gap_2()
                    .when(total > CHOICES_PER_PAGE, |row| {
                        row.child(
                            control("choices-prev", "‹", false)
                                .h(px(48.0))
                                .min_w(px(48.0))
                                .on_click(cx.listener(|this, _, window, cx| {
                                    this.page_playback(false, window, cx)
                                })),
                        )
                    })
                    .children((start..end).map(|index| {
                        let choice = index.checked_sub(1).and_then(|index| choices.get(index));
                        let label = choice
                            .map_or("自动", |choice| choice.label.as_str())
                            .to_owned();
                        let active =
                            choice.map(|choice| choice.id.as_str()) == self.playback.current(menu);
                        playback_button(
                            ("playback-choice", index),
                            label,
                            self.playback.cursor == index,
                            active,
                            None,
                        )
                        .on_click(cx.listener(
                            move |this, _, window, cx| {
                                this.apply_playback_choice(index, window, cx)
                            },
                        ))
                    }))
                    .when(total > CHOICES_PER_PAGE, |row| {
                        row.child(
                            control("choices-next", "›", false)
                                .h(px(48.0))
                                .min_w(px(48.0))
                                .on_click(cx.listener(|this, _, window, cx| {
                                    this.page_playback(true, window, cx)
                                })),
                        )
                    }),
            )
    }

    pub(super) fn view(&self, cx: &mut Context<Self>) -> Div {
        if self.in_playback() {
            return self.playback_view(cx);
        }
        let view = div().size_full().v_flex().bg(rgb(BG)).text_color(rgb(TEXT));
        if let Some(Content::Login { site_index, .. }) = &self.content {
            return view.child(self.login_header(*site_index, cx));
        }
        let view = view.child(self.header(cx));
        let view = if self.pane == Pane::Popular {
            view.child(self.popular_view(cx))
        } else if let Some(cursor) = self.platform_cursor {
            view.child(self.platform_picker(cursor, cx))
        } else if self.pane == Pane::Settings {
            view.child(self.settings_view(cx))
                .when(!self.status.is_empty(), |view| {
                    view.child(
                        div()
                            .px_6()
                            .py_2()
                            .text_sm()
                            .text_color(rgb(MUTED))
                            .child(self.status.clone()),
                    )
                })
        } else {
            view.child(self.directory_view(cx))
        };
        view.child(self.footer())
    }
}

fn playback_button(
    id: impl Into<ElementId>,
    label: String,
    focused: bool,
    active: bool,
    follow: Option<bool>,
) -> Stateful<Div> {
    div()
        .id(id)
        .h_flex()
        .flex_1()
        .min_w_0()
        .h(px(48.0))
        .px_2()
        .items_center()
        .justify_center()
        .rounded_md()
        .border_2()
        .border_color(rgb(if focused { MINT } else { DIVIDER }))
        .bg(rgb(if focused { SURFACE } else { PANEL }))
        .text_color(rgb(if focused || active { MINT } else { TEXT }))
        .font_weight(FontWeight::SEMIBOLD)
        .cursor_pointer()
        .hover(|style| style.border_color(rgb(MINT)))
        .when_some(follow, |button, followed| {
            button.gap_1().child(follow_icon(
                followed,
                if focused || active { MINT } else { TEXT },
            ))
        })
        .child(div().min_w_0().text_ellipsis().child(label))
}

fn follow_icon(followed: bool, color: u32) -> impl IntoElement {
    canvas(
        |_, _, _| {},
        move |bounds, _, window, _| {
            let at = |x, y| bounds.origin + point(px(x), px(y));
            let mut path = if followed {
                PathBuilder::fill()
            } else {
                PathBuilder::stroke(px(1.6))
            };
            path.move_to(at(10.0, 5.5));
            path.cubic_bezier_to(at(2.0, 7.0), at(7.0, 0.8), at(2.0, 2.4));
            path.cubic_bezier_to(at(9.3, 16.5), at(2.0, 10.6), at(5.4, 13.6));
            path.curve_to(at(10.7, 16.5), at(10.0, 17.1));
            path.cubic_bezier_to(at(18.0, 7.0), at(14.6, 13.6), at(18.0, 10.6));
            path.cubic_bezier_to(at(10.0, 5.5), at(18.0, 2.4), at(13.0, 0.8));
            path.close();
            if let Ok(path) = path.build() {
                window.paint_path(path, rgb(color));
            }
        },
    )
    .size(px(20.0))
    .flex_shrink_0()
}
