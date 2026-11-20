use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

const CATALOG_DIRECTORY: &str = "plugin-catalog";
const MAX_PACKAGE_SIZE: u64 = 32 * 1024 * 1024;

#[derive(Clone, Copy)]
pub(crate) struct Plugin {
    pub(crate) name: &'static str,
    pub(crate) description: &'static str,
    pub(crate) executable: &'static str,
}

pub(crate) const PLUGINS: [Plugin; 2] = [
    Plugin {
        name: "直播录制",
        description: "将直播音视频保存为 MKV，需要 FFmpeg。",
        executable: "purelive-recording.exe",
    },
    Plugin {
        name: "本地翻译",
        description: "用 Ollama 翻译直播间标题和弹幕。",
        executable: "purelive-translation.exe",
    },
];

impl Plugin {
    pub(crate) fn installed(self, directory: &Path) -> bool {
        directory.join(self.executable).is_file()
    }

    pub(crate) fn package(self, app_directory: &Path) -> Option<PathBuf> {
        std::iter::once(app_directory)
            .chain(app_directory.parent())
            .map(|root| root.join(CATALOG_DIRECTORY).join(self.executable))
            .find(|path| path.symlink_metadata().is_ok_and(|meta| meta.is_file()))
    }

    pub(crate) fn install(self, package: &Path, directory: &Path) -> io::Result<()> {
        let file = File::open(package)?;
        let mut bytes = Vec::new();
        file.take(MAX_PACKAGE_SIZE + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_PACKAGE_SIZE || !bytes.starts_with(b"MZ") {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "插件包无效"));
        }

        fs::create_dir_all(directory)?;
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
        let temporary = directory.join(format!(".plugin-{}-{stamp}.tmp", std::process::id()));
        let mut staged = OpenOptions::new().write(true).create_new(true).open(&temporary)?;
        let written = staged.write_all(&bytes).and_then(|()| staged.sync_all());
        drop(staged);
        // Publish the completed file without replacing another app instance's installation.
        let result = written.and_then(|()| fs::hard_link(&temporary, directory.join(self.executable)));
        let _ = fs::remove_file(temporary);
        result
    }

    pub(crate) fn uninstall(self, directory: &Path) -> io::Result<()> {
        fs::remove_file(directory.join(self.executable)).or_else(|error| {
            if error.kind() == io::ErrorKind::NotFound { Ok(()) } else { Err(error) }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installing_and_removing_a_plugin_preserves_other_files() {
        let root = std::env::temp_dir().join(format!("purelive-catalog-{}", std::process::id()));
        let catalog = root.join(CATALOG_DIRECTORY);
        let installed = root.join("installed");
        fs::create_dir_all(&catalog).unwrap();
        fs::create_dir_all(&installed).unwrap();
        let plugin = PLUGINS[0];
        let source = catalog.join(plugin.executable);
        fs::write(&source, b"invalid").unwrap();
        assert!(plugin.install(&source, &installed).is_err());
        assert!(!plugin.installed(&installed));
        fs::write(&source, b"MZdemo").unwrap();
        fs::write(installed.join("config.json"), b"{}").unwrap();
        let app = root.join("app");
        assert_eq!(plugin.package(&app).as_deref(), Some(source.as_path()));
        plugin.install(&source, &installed).unwrap();
        assert_eq!(fs::read(installed.join(plugin.executable)).unwrap(), b"MZdemo");
        fs::write(&source, b"MZdifferent").unwrap();
        assert_eq!(plugin.install(&source, &installed).unwrap_err().kind(), io::ErrorKind::AlreadyExists);
        plugin.uninstall(&installed).unwrap();
        assert!(!plugin.installed(&installed));
        assert!(installed.join("config.json").is_file());
        fs::remove_dir_all(&root).unwrap();
    }
}
