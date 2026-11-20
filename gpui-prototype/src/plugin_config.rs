use std::{
    fs, io,
    path::{Path, PathBuf},
};

#[derive(Default, serde::Deserialize, serde::Serialize)]
#[serde(default)]
pub struct RecordingConfig {
    pub directory: Option<PathBuf>,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(default)]
pub struct TranslationConfig {
    pub enabled: bool,
    pub model: String,
    pub target_language: String,
    pub room_titles: bool,
    pub danmaku: bool,
}

impl Default for TranslationConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            model: "qwen2.5:1.5b".into(),
            target_language: "Simplified Chinese".into(),
            room_titles: true,
            danmaku: true,
        }
    }
}

pub fn load<T: Default + serde::de::DeserializeOwned>(path: &Path) -> io::Result<T> {
    match fs::read(path) {
        Ok(bytes) => Ok(serde_json::from_slice(&bytes)?),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(T::default()),
        Err(error) => Err(error),
    }
}
