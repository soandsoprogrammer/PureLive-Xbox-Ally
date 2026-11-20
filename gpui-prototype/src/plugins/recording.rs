use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::mpsc,
    time::Duration,
};

use crate::{compat::Source, plugin_config::{self, RecordingConfig}};

use super::process::PluginProcess;

pub(crate) struct Recorder {
    executable: Option<PathBuf>,
    url: String,
    headers: BTreeMap<String, String>,
    job: Option<Job>,
}

struct Job {
    stop: Option<mpsc::Sender<()>>,
    result: mpsc::Receiver<String>,
}

impl Recorder {
    pub(crate) fn new(source: &Source, executable: Option<PathBuf>) -> Self {
        Self {
            executable,
            url: source.url.clone(),
            headers: source.headers.clone(),
            job: None,
        }
    }

    pub(crate) fn active(&self) -> bool {
        self.job.is_some()
    }

    pub(crate) fn poll(&mut self) -> Option<String> {
        let message = match self.job.as_ref()?.result.try_recv() {
            Ok(message) => message,
            Err(mpsc::TryRecvError::Empty) => return None,
            Err(mpsc::TryRecvError::Disconnected) => "录制插件意外退出".into(),
        };
        self.job = None;
        Some(message)
    }

    pub(crate) fn toggle(&mut self, data_dir: &Path) -> Result<String, String> {
        if let Some(job) = &mut self.job {
            job.stop.take();
            return Ok("正在结束录制…".into());
        }
        let executable = self.executable.as_ref().ok_or("请先安装录制插件")?;
        let request = serde_json::json!({
            "url": self.url, "headers": self.headers, "data_dir": data_dir,
        });
        let path = data_dir.join("plugins").join("recording.json");
        let config: RecordingConfig = plugin_config::load(&path)
            .map_err(|error| format!("无法读取录制设置：{error}"))?;
        let mut child = PluginProcess::start_with(executable, &request, |command| {
            if let Some(directory) = &config.directory {
                command.env("PURELIVE_RECORDINGS_DIR", directory);
            }
        })
            .map_err(|error| format!("无法启动录制插件：{error}"))?;
        let (stop, stop_rx) = mpsc::channel::<()>();
        let (done, result) = mpsc::channel();
        std::thread::Builder::new()
            .name("purelive-recording-plugin".into())
            .spawn(move || {
                let message = loop {
                    match child.poll::<String>() {
                        Ok(Some(message)) => break message,
                        Err(error) => break format!("录制插件失败：{error}"),
                        Ok(None) => {}
                    }
                    if !matches!(stop_rx.recv_timeout(Duration::from_millis(100)), Err(mpsc::RecvTimeoutError::Timeout)) {
                        child.close_input();
                        break child.wait::<String>(Duration::from_secs(12))
                            .unwrap_or_else(|error| format!("无法结束录制：{error}"));
                    }
                };
                let _ = done.send(message);
            })
            .map_err(|error| error.to_string())?;
        self.job = Some(Job { stop: Some(stop), result });
        Ok("正在录制…".into())
    }
}
