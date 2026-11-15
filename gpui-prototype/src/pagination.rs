use crate::live::{Room, RoomKey};
use std::collections::BTreeSet;

#[derive(Default)]
pub struct Pages {
    pub epoch: u64,
    pub page: u32,
    pub loading: bool,
    pub exhausted: bool,
    pub error: Option<String>,
    pub visible_end: usize,
}

impl Pages {
    pub fn reset(&mut self) -> u64 {
        *self = Self {
            epoch: self.epoch.wrapping_add(1),
            loading: true,
            ..Self::default()
        };
        self.epoch
    }

    pub fn near_end(&self, rooms: usize) -> bool {
        self.page > 0 && rooms > 0 && self.visible_end + 2 >= rooms.div_ceil(3)
    }

    pub fn begin_next(&mut self) -> Option<(u64, u32)> {
        if self.loading || self.exhausted || self.error.is_some() || self.page == 0 {
            return None;
        }
        self.loading = true;
        Some((self.epoch, self.page + 1))
    }

    pub fn complete(&mut self, epoch: u64, page: u32, received: usize, added: usize) {
        if epoch != self.epoch {
            return;
        }
        self.page = page;
        self.loading = false;
        self.error = None;
        // Some sites return fewer than 24 rooms per page. Only stop when the
        // page is empty or repeats rooms, including sites without pagination.
        self.exhausted = received == 0 || added == 0;
    }

    pub fn fail(&mut self, epoch: u64, error: String) {
        if epoch == self.epoch {
            self.loading = false;
            self.error = Some(error);
        }
    }
}

pub fn append_unique(existing: &mut Vec<Room>, rooms: Vec<Room>) -> usize {
    let mut seen: BTreeSet<RoomKey> = existing.iter().map(Room::key).collect();
    let before = existing.len();
    existing.extend(rooms.into_iter().filter(|room| seen.insert(room.key())));
    existing.len() - before
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pagination_short_pages_continue_and_duplicate_pages_stop() {
        let mut pages = Pages::default();
        let epoch = pages.reset();
        pages.complete(epoch, 1, 12, 12);
        assert_eq!(pages.begin_next(), Some((epoch, 2)));
        assert_eq!(pages.begin_next(), None);
        pages.complete(epoch, 2, 12, 0);
        assert!(pages.exhausted);
        assert_eq!(pages.begin_next(), None);
    }

    #[test]
    fn pagination_stale_completion_does_not_unlock_new_platform() {
        let mut pages = Pages::default();
        let old = pages.reset();
        let current = pages.reset();
        pages.complete(old, 2, 24, 24);
        pages.fail(old, "old error".into());
        assert!(pages.loading);
        assert_eq!(pages.page, 0);
        assert!(pages.error.is_none());
        pages.complete(current, 1, 24, 24);
        assert_eq!(pages.begin_next(), Some((current, 2)));
    }

    #[test]
    fn pagination_failure_requires_retry_and_keeps_page_number() {
        let mut pages = Pages::default();
        let epoch = pages.reset();
        pages.complete(epoch, 1, 24, 24);
        pages.begin_next();
        pages.fail(epoch, "network".into());
        assert_eq!(pages.begin_next(), None);
        pages.error = None;
        assert_eq!(pages.begin_next(), Some((epoch, 2)));
    }

    #[test]
    fn pagination_deduplicates_by_platform_and_room_id_preserving_order() {
        let mut rooms = vec![Room::bili(1, "first".into())];
        let mut other = Room::bili(1, "other platform".into());
        other.platform = "douyu".into();
        assert_eq!(append_unique(&mut rooms, vec![
            Room::bili(1, "repeat".into()), Room::bili(2, "second".into()),
            Room::bili(2, "repeat in page".into()), other,
        ]), 2);
        assert_eq!(rooms[0].title, "first");
        assert_eq!(rooms[1].id, "2");
        assert_eq!(rooms[2].platform, "douyu");
    }
}
