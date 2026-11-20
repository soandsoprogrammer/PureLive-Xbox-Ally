pub mod recording;
mod text_rules;
mod process;

use std::{
    cell::RefCell,
    collections::{HashMap, VecDeque},
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, serde::Deserialize, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Surface {
    RoomTitle,
    Danmaku,
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct Text {
    pub surface: Surface,
    pub platform: String,
    pub original: String,
}

pub trait Plugin {
    fn register(self, registry: &mut Registry);
}

pub trait TextHook: Send + 'static {
    fn transform(&mut self, input: &Text, current: &str) -> Option<String>;
}

#[derive(Default)]
pub struct Registry {
    hooks: Vec<Box<dyn TextHook>>,
}

impl Registry {
    pub fn text(&mut self, hook: impl TextHook) {
        self.hooks.push(Box::new(hook));
    }

    fn start(mut self) -> Plugins {
        if self.hooks.is_empty() {
            return Plugins(None, InstalledPlugins::default());
        }
        let (requests, jobs) = async_channel::bounded::<Text>(16);
        let (results, replies) = async_channel::bounded(16);
        let worker = std::thread::Builder::new().name("purelive-plugins".into());
        if worker
            .spawn(move || {
                while let Ok(input) = jobs.recv_blocking() {
                    let mut current = input.original.clone();
                    for hook in &mut self.hooks {
                        if let Some(next) = hook.transform(&input, &current) {
                            current = next;
                        }
                    }
                    let output = (current != input.original).then_some(current);
                    if results.send_blocking((input, output)).is_err() {
                        break;
                    }
                }
            })
            .is_err()
        {
            return Plugins(None, InstalledPlugins::default());
        }
        Plugins(
            Some(RefCell::new(Pipeline {
                requests,
                replies,
                cache: HashMap::new(),
                completed: VecDeque::new(),
            })),
            InstalledPlugins::default(),
        )
    }
}

pub struct Plugins(Option<RefCell<Pipeline>>, InstalledPlugins);

#[derive(Default)]
struct InstalledPlugins {
    translation: bool,
    recording: Option<PathBuf>,
}

struct TranslationPlugin {
    executable: PathBuf,
    retry_at: Instant,
}

impl TextHook for TranslationPlugin {
    fn transform(&mut self, input: &Text, current: &str) -> Option<String> {
        if Instant::now() < self.retry_at {
            return None;
        }
        let request = serde_json::json!({"surface": input.surface, "current": current});
        let result = process::PluginProcess::start(&self.executable, &request)
            .and_then(|mut child| {
                child.close_input();
                child.wait::<Option<String>>(Duration::from_secs(15))
            });
        match result {
            Ok(output) => output.filter(|text| {
                !text.trim().is_empty() && text.len() <= 768 && !text.contains(char::is_control)
            }),
            Err(_) => {
                self.retry_at = Instant::now() + Duration::from_secs(15);
                None
            }
        }
    }
}

fn installed_executable(directory: &Path, name: &str) -> Option<PathBuf> {
    let path = directory.join(name);
    path.is_file().then_some(path)
}

enum Entry {
    Pending,
    Ready(String),
    RetryAt(Instant),
}

struct Pipeline {
    requests: async_channel::Sender<Text>,
    replies: async_channel::Receiver<(Text, Option<String>)>,
    cache: HashMap<Text, Entry>,
    completed: VecDeque<Text>,
}

impl Plugins {
    pub fn load(directory: &Path) -> Self {
        let mut registry = Registry::default();
        text_rules::register_directory(directory, &mut registry);
        let translation = installed_executable(directory, "purelive-translation.exe");
        let recording = installed_executable(directory, "purelive-recording.exe");
        let translation_installed = translation.is_some();
        if let Some(executable) = translation {
            registry.text(TranslationPlugin { executable, retry_at: Instant::now() });
        }
        let mut plugins = registry.start();
        plugins.1 = InstalledPlugins { translation: translation_installed, recording };
        plugins
    }

    pub fn translation_installed(&self) -> bool {
        self.1.translation
    }

    pub fn recording_executable(&self) -> Option<&Path> {
        self.1.recording.as_deref()
    }
    pub fn request(&self, surface: Surface, platform: &str, original: &str) -> Option<Text> {
        let mut pipeline = self.0.as_ref()?.borrow_mut();
        let original = original.trim();
        if original.is_empty() || original.len() > 768 {
            return None;
        }
        let input = Text {
            surface,
            platform: platform.into(),
            original: original.into(),
        };
        match pipeline.cache.get(&input) {
            Some(Entry::RetryAt(time)) if *time <= Instant::now() => {}
            Some(_) => return Some(input),
            None => {}
        }
        pipeline.requests.try_send(input.clone()).ok()?;
        pipeline.completed.retain(|key| key != &input);
        pipeline.cache.insert(input.clone(), Entry::Pending);
        Some(input)
    }

    pub fn output(&self, input: &Text) -> Option<String> {
        let pipeline = self.0.as_ref()?.borrow();
        match pipeline.cache.get(input)? {
            Entry::Ready(text) => Some(text.clone()),
            _ => None,
        }
    }

    pub fn poll(&self) -> bool {
        let Some(pipeline) = &self.0 else {
            return false;
        };
        let mut pipeline = pipeline.borrow_mut();
        let mut redraw = false;
        while let Ok((input, output)) = pipeline.replies.try_recv() {
            redraw |= input.surface == Surface::RoomTitle && output.is_some();
            let entry = output.map_or_else(
                || Entry::RetryAt(Instant::now() + Duration::from_secs(60)),
                Entry::Ready,
            );
            pipeline.cache.insert(input.clone(), entry);
            pipeline.completed.push_back(input);
            if pipeline.completed.len() > 512
                && let Some(expired) = pipeline.completed.pop_front()
            {
                pipeline.cache.remove(&expired);
            }
        }
        redraw
    }

    pub fn room_title(&self, platform: &str, title: &str) -> String {
        self.request(Surface::RoomTitle, platform, title)
            .and_then(|input| self.output(&input))
            .map_or_else(|| title.to_owned(), |text| format!("{text} · {title}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Append(&'static str);

    impl TextHook for Append {
        fn transform(&mut self, input: &Text, current: &str) -> Option<String> {
            (input.surface == Surface::RoomTitle).then(|| format!("{current}{}", self.0))
        }
    }

    #[test]
    fn disabled_registry_returns_original_title() {
        assert_eq!(
            Registry::default().start().room_title("test", "original"),
            "original"
        );
    }

    #[test]
    fn hooks_run_in_order_and_only_affect_the_selected_surface() {
        let mut registry = Registry::default();
        registry.text(Append(" first"));
        registry.text(Append(" second"));
        let plugins = registry.start();
        assert_eq!(plugins.room_title("test", "original"), "original");
        let chat = plugins
            .request(Surface::Danmaku, "test", "original")
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            if plugins.poll() {
                break;
            }
            assert!(
                Instant::now() < deadline,
                "plugin worker did not return a title"
            );
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(
            plugins.room_title("test", "original"),
            "original first second · original"
        );
        assert_eq!(plugins.output(&chat), None);
    }
}
