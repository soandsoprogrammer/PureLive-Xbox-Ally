use std::{
    collections::HashMap,
    sync::{Arc, OnceLock},
};

use super::*;

pub const COLUMNS: usize = 7;

const MINT: u32 = 0x4ff2ba;
const TEXT: u32 = 0xf2f5f7;
const MUTED: u32 = 0xa8b7c1;
const PANEL: u32 = 0x17232c;
const BORDER: u32 = 0x293741;

pub fn move_index(index: usize, x: isize, y: isize, count: usize) -> usize {
    let row = (index / COLUMNS)
        .saturating_add_signed(y)
        .min((count - 1) / COLUMNS);
    let column = (index % COLUMNS).saturating_add_signed(x).min(COLUMNS - 1);
    (row * COLUMNS + column).min(count - 1)
}

fn logo(id: &str) -> Option<Arc<Image>> {
    static ICONS: OnceLock<HashMap<&'static str, Arc<Image>>> = OnceLock::new();
    ICONS
        .get_or_init(|| {
            crate::platform_icons::ICONS
                .iter()
                .map(|(key, bytes)| {
                    (
                        *key,
                        Arc::new(Image::from_bytes(ImageFormat::Png, bytes.to_vec())),
                    )
                })
                .collect()
        })
        .get(id)
        .cloned()
}

fn label(site: &live::Platform) -> &str {
    match site.id.as_str() {
        "steambroadcast" => "Steam",
        "tiktok" => "TikTok",
        "youtube" => "YouTube",
        "bigo" => "Bigo",
        "jdlive" => "京东直播",
        _ => site.name.trim_end_matches("直播").trim_end(),
    }
}

impl Home {
    pub(super) fn platform_strip(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("platform-strip")
            .h_flex()
            .items_center()
            .gap_2()
            .flex_1()
            .min_w_0()
            .overflow_x_scroll()
            .track_scroll(&self.platform_scroll)
            .children(self.platforms.iter().enumerate().map(|(index, site)| {
                // On 热门 the strip is driven by LB/RB, so it never takes the d-pad
                // cursor and never draws a focus ring there; the current platform is
                // still indicated by its background.
                let focused = self.platform_cursor == Some(index) && self.pane != Pane::Popular;
                let selected = self.platform == index;
                div()
                    .id(("platform-tab", index))
                    .h_flex()
                    .items_center()
                    .justify_center()
                    .flex_shrink_0()
                    .h(px(36.0))
                    .gap_2()
                    .px_3()
                    .rounded_md()
                    .border_1()
                    .border_color(rgb(if focused { MINT } else { BORDER }))
                    .bg(rgb(if selected { 0x1b3832 } else { PANEL }))
                    .text_color(rgb(if focused || selected { MINT } else { TEXT }))
                    .text_sm()
                    .cursor_pointer()
                    .hover(|style| style.text_color(rgb(MINT)))
                    .when_some(logo(&site.id), |tile, icon| {
                        tile.child(img(icon).size(px(19.0)).object_fit(ObjectFit::Contain))
                    })
                    .child(label(site).to_owned())
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.select_platform(index, window, cx)
                    }))
            }))
    }

    pub(super) fn open_platform_picker(&mut self) {
        let index = self.search_platform.map_or(0, |platform| platform + 1);
        self.platform_cursor = Some(index);
        self.platform_scroll = ScrollHandle::new();
        self.platform_scroll.scroll_to_item(index / COLUMNS);
    }

    pub(super) fn platform_picker(&self, cursor: usize, cx: &mut Context<Self>) -> Div {
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
                    .gap_3()
                    .child(
                        div()
                            .flex_1()
                            .text_lg()
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("选择平台"),
                    )
                    .child(div().text_sm().text_color(rgb(MUTED)).child(format!(
                            "当前 · {}",
                            self.search_platform
                                .map_or("全部", |index| label(&self.platforms[index]))
                        ))),
            )
            .child(
                div()
                    .id("platform-grid")
                    .flex_1()
                    .min_h_0()
                    .track_scroll(&self.platform_scroll)
                    .overflow_y_scroll()
                    .v_flex()
                    .gap_2()
                    .pb_2()
                    .children(self.platform_rows(Some(cursor), 68.0, cx)),
            )
    }

    pub(super) fn platform_rows(
        &self,
        cursor: Option<usize>,
        height: f32,
        cx: &mut Context<Self>,
    ) -> Vec<Div> {
        let count = self.platforms.len() + 1;
        (0..count)
            .step_by(COLUMNS)
            .map(|start| {
                let end = (start + COLUMNS).min(count);
                div()
                    .h_flex()
                    .gap_2()
                    .flex_shrink_0()
                    .children((start..end).map(|index| {
                        let site = index.checked_sub(1).map(|index| &self.platforms[index]);
                        let focused = Some(index) == cursor;
                        let selected =
                            self.search_platform.map_or(0, |platform| platform + 1) == index;
                        div()
                            .id(("platform-tile", index))
                            .v_flex()
                            .relative()
                            .flex_1()
                            .min_w_0()
                            .h(px(height))
                            .gap_1()
                            .rounded_md()
                            .items_center()
                            .justify_center()
                            .px_1()
                            .border_2()
                            .border_color(rgb(if focused { MINT } else { BORDER }))
                            .bg(rgb(if focused { 0x1b3832 } else { PANEL }))
                            .hover(|style| style.border_color(rgb(MINT)))
                            .cursor_pointer()
                            .when_some(site.and_then(|site| logo(&site.id)), |tile, logo| {
                                tile.child(
                                    img(logo)
                                        .size(px(28.0))
                                        .rounded_sm()
                                        .object_fit(ObjectFit::Contain),
                                )
                            })
                            .child(
                                div()
                                    .w_full()
                                    .text_center()
                                    .text_xs()
                                    .text_ellipsis()
                                    .text_color(rgb(if focused { MINT } else { TEXT }))
                                    .font_weight(if focused {
                                        FontWeight::SEMIBOLD
                                    } else {
                                        FontWeight::NORMAL
                                    })
                                    .child(site.map_or("全部", label).to_owned()),
                            )
                            .when(selected, |tile| {
                                tile.child(
                                    div()
                                        .absolute()
                                        .top_1()
                                        .right_2()
                                        .text_xs()
                                        .text_color(rgb(MINT))
                                        .child("✓"),
                                )
                            })
                            .on_click(cx.listener(move |this, _, window, cx| {
                                this.select_search_platform(index, window, cx)
                            }))
                    }))
                    .children((end - start..COLUMNS).map(|_| div().flex_1().min_w_0()))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::move_index;

    #[test]
    fn direction_moves_within_the_grid() {
        assert_eq!(move_index(6, 1, 0, 35), 6);
        assert_eq!(move_index(7, -1, 0, 35), 7);
        assert_eq!(move_index(6, 0, 1, 35), 13);
        assert_eq!(move_index(13, 0, -1, 35), 6);
        assert_eq!(move_index(34, 0, 1, 35), 34);
        assert_eq!(move_index(13, 0, 1, 17), 16);
    }
}
