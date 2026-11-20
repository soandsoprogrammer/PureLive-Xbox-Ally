use std::{fs, io::Read, path::Path};

use serde::Deserialize;

use super::{Plugin, Registry, Surface, Text, TextHook};

#[derive(Deserialize)]
struct Manifest {
    version: u32,
    kind: String,
    #[serde(default)]
    platform: Option<String>,
    surfaces: Vec<Surface>,
    rules: Vec<Rule>,
}

#[derive(Deserialize)]
struct Rule {
    from: String,
    to: String,
}

impl Manifest {
    fn valid(&self) -> bool {
        self.version == 1
            && self.kind == "text_rules"
            && !self.surfaces.is_empty()
            && (1..=32).contains(&self.rules.len())
            && self.rules.iter().all(|rule| {
                !rule.from.is_empty()
                    && rule.from.len() <= 256
                    && rule.to.len() <= 256
                    && !rule.to.contains(char::is_control)
            })
    }
}

impl Plugin for Manifest {
    fn register(self, registry: &mut Registry) {
        if self.valid() {
            registry.text(self);
        }
    }
}

impl TextHook for Manifest {
    fn transform(&mut self, input: &Text, current: &str) -> Option<String> {
        if !self.surfaces.contains(&input.surface)
            || self
                .platform
                .as_ref()
                .is_some_and(|platform| platform != &input.platform)
        {
            return None;
        }
        let mut output = current.to_owned();
        for rule in &self.rules {
            output = output.replace(&rule.from, &rule.to);
            if output.len() > 768 {
                return None;
            }
        }
        (!output.trim().is_empty() && output != current).then_some(output)
    }
}

pub(super) fn register_directory(path: &Path, registry: &mut Registry) {
    let Ok(entries) = fs::read_dir(path) else {
        return;
    };
    let mut files: Vec<_> = entries
        .take(256)
        .flatten()
        .filter(|entry| {
            entry.file_type().is_ok_and(|kind| kind.is_file())
                && entry
                    .path()
                    .extension()
                    .is_some_and(|ext| ext.eq_ignore_ascii_case("json"))
        })
        .map(|entry| entry.path())
        .collect();
    files.sort();
    for file in files.into_iter().take(32) {
        let Ok(file) = fs::File::open(file) else {
            continue;
        };
        let mut bytes = Vec::new();
        if file.take(16_385).read_to_end(&mut bytes).is_ok()
            && bytes.len() <= 16_384
            && let Ok(manifest) = serde_json::from_slice::<Manifest>(&bytes)
        {
            manifest.register(registry);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_filters_by_surface_and_platform() {
        let mut manifest: Manifest = serde_json::from_str(
            r#"{
            "version":1,"kind":"text_rules","platform":"test","surfaces":["room_title"],
            "rules":[{"from":"FC","to":"Football Club"}]
        }"#,
        )
        .unwrap();
        assert!(manifest.valid());
        let mut input = Text {
            surface: Surface::RoomTitle,
            platform: "test".into(),
            original: "FC Live".into(),
        };
        assert_eq!(
            manifest.transform(&input, &input.original).as_deref(),
            Some("Football Club Live")
        );
        input.surface = Surface::Danmaku;
        assert_eq!(manifest.transform(&input, &input.original), None);
        input.surface = Surface::RoomTitle;
        input.platform = "other".into();
        assert_eq!(manifest.transform(&input, &input.original), None);
    }
}
