use std::{
    collections::VecDeque,
    time::{Duration, Instant},
};

use crate::{
    emotes::{self, Segment},
    hardware_player::HardwarePlayer,
    native_danmaku::{Lane, Part},
    plugins::{self, Plugins},
};

const SPEED: f32 = 210.0;
const PENDING_LIMIT: usize = 48;
const PENDING_MAX_WAIT: Duration = Duration::from_secs(5);

#[derive(Default)]
pub(super) struct Overlay {
    messages: [Option<Message>; 5],
    pending: VecDeque<Message>,
}

struct Message {
    parts: Vec<Segment>,
    translation: Option<plugins::Text>,
    width: i32,
    time: Instant,
    duration: Duration,
}

impl Overlay {
    pub fn active(&self) -> bool {
        self.messages.iter().any(Option::is_some)
    }

    pub fn advance(&mut self, now: Instant, plugins: &Plugins) -> bool {
        let mut changed = false;
        for message in &mut self.messages {
            if message.as_ref().is_some_and(|message| now.duration_since(message.time) >= message.duration) {
                *message = None;
                changed = true;
            }
        }
        while self.pending.front().is_some_and(|message| now.duration_since(message.time) > PENDING_MAX_WAIT) {
            self.pending.pop_front();
        }
        for message in self.messages.iter_mut().flatten().chain(self.pending.iter_mut()) {
            if let Some(input) = &message.translation
                && let Some(translated) = plugins.output(input)
            {
                message.translation = None;
                let part = Segment::Text(format!(" · {translated}"));
                let extra_width = part.width();
                message.duration += message.duration.mul_f32(extra_width as f32 / (1280.0 + message.width as f32));
                message.width += extra_width;
                message.parts.push(part);
                changed = true;
            }
        }
        for lane in self.messages.iter_mut().filter(|lane| lane.is_none()) {
            let Some(mut message) = self.pending.pop_front() else { break };
            message.time = now;
            *lane = Some(message);
            changed = true;
        }
        changed
    }

    pub fn push(
        &mut self,
        now: Instant,
        platform: &str,
        text: &str,
        remote: &[emotes::RemoteEmote],
        plugins: &Plugins,
        pictures: &mut Vec<emotes::Source>,
    ) -> bool {
        let lane = self.messages.iter_mut().find(|lane| lane.is_none());
        if lane.is_none() && self.pending.len() >= PENDING_LIMIT {
            return false;
        }
        let parts = emotes::segments(platform, text, remote);
        if parts.is_empty() {
            return false;
        }
        for part in &parts {
            if let Segment::Picture { source, .. } = part {
                pictures.push(source.clone());
            }
        }
        let width = parts.iter().map(Segment::width).sum::<i32>();
        let message = Message {
            translation: plugins.request(plugins::Surface::Danmaku, platform, text),
            parts,
            width,
            time: now,
            duration: Duration::from_secs_f32(((1280.0 + width as f32) / SPEED).clamp(4.0, 14.0)),
        };
        if let Some(lane) = lane {
            *lane = Some(message);
            return true;
        }
        self.pending.push_back(message);
        false
    }

    pub fn draw(&self, player: &HardwarePlayer, cache: &emotes::Cache) {
        let lanes = self.messages.iter().enumerate().filter_map(|(lane, message)| {
            let message = message.as_ref()?;
            let mut offset = 0.0;
            let parts = message.parts.iter().map(|segment| {
                let part = match segment {
                    Segment::Text(text) => Part::Text(text.encode_utf16().collect()),
                    Segment::Picture { source, alt } => cache.get(source).map_or_else(
                        || Part::Text(alt.encode_utf16().collect()),
                        |bitmap| Part::Image(bitmap.clone()),
                    ),
                };
                let positioned = (offset, part);
                offset += segment.width() as f32;
                positioned
            }).collect();
            Some(Lane {
                started: message.time,
                duration: message.duration,
                width: message.width as f32,
                y: 30.0 + 39.0 * lane as f32,
                parts,
            })
        }).collect();
        player.set_danmaku(lanes);
    }
}
