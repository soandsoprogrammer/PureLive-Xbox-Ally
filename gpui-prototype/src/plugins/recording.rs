use std::{
    io::Write,
    os::windows::process::CommandExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use crate::compat::{Source, configure_network};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_local_files_without_starting_a_recording() {
        let mut recorder = Recorder::new(&Source {
            url: "file:///C:/video.mkv".into(),
            ..Source::default()
        });
        assert!(recorder.toggle(Path::new("."), Path::new(".")).is_err());
        assert!(!recorder.active());
    }
}

pub struct Recorder {
    url: String,
    headers: String,
    job: Option<Job>,
}

struct Job {
    stop: mpsc::Sender<()>,
    result: mpsc::Receiver<String>,
    stopping: bool,
}

impl Recorder {
    pub fn new(source: &Source) -> Self {
        let headers = source
            .headers
            .iter()
            .filter(|(name, value)| {
                !name.contains(['\r', '\n', ':']) && !value.contains(['\r', '\n'])
            })
            .map(|(name, value)| format!("{name}: {value}\r\n"))
            .collect();
        Self {
            url: source.url.clone(),
            headers,
            job: None,
        }
    }

    pub fn active(&self) -> bool {
        self.job.is_some()
    }

    pub fn poll(&mut self) -> Option<String> {
        let message = match self.job.as_ref()?.result.try_recv() {
            Ok(message) => message,
            Err(mpsc::TryRecvError::Empty) => return None,
            Err(mpsc::TryRecvError::Disconnected) => "录制工作线程意外结束".into(),
        };
        self.job = None;
        Some(message)
    }

    pub fn toggle(&mut self, app_dir: &Path, data_dir: &Path) -> Result<String, String> {
        if let Some(job) = &mut self.job {
            if !job.stopping {
                job.stopping = true;
                let _ = job.stop.send(());
            }
            return Ok("正在结束录制…".into());
        }
        let url = url::Url::parse(&self.url).map_err(|_| "当前播放地址不支持录制")?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err("只支持录制 HTTP(S) 直播流".into());
        }
        let directory = std::env::var_os("PURELIVE_RECORDINGS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| data_dir.join("recordings"));
        let bundled = app_dir.join("ffmpeg.exe");
        let ffmpeg = std::env::var_os("PURELIVE_FFMPEG")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                if bundled.is_file() {
                    bundled
                } else {
                    "ffmpeg.exe".into()
                }
            });
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis();
        let output = directory.join(format!("live-{}-{timestamp}.mkv", std::process::id()));
        let mut command = Command::new(ffmpeg);
        configure_network(&mut command);
        command.creation_flags(0x08000000).args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-n",
            "-rw_timeout",
            "8000000",
        ]);
        if !self.headers.is_empty() {
            command.args(["-headers", &self.headers]);
        }
        command
            .args([
                "-protocol_whitelist",
                "http,https,tcp,tls,crypto",
                "-i",
                &self.url,
                "-map",
                "0:v?",
                "-map",
                "0:a?",
                "-c",
                "copy",
                "-f",
                "matroska",
            ])
            .arg(&output)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let (stop, stop_rx) = mpsc::channel();
        let (done, result) = mpsc::channel();
        std::thread::Builder::new()
            .name("purelive-recording".into())
            .spawn(move || {
                let message = (|| -> Result<String, String> {
                    std::fs::create_dir_all(&directory)
                        .map_err(|error| format!("无法创建录制目录：{error}"))?;
                    let mut child = command.spawn().map_err(|error| {
                        format!("无法启动 FFmpeg（请安装或配置 PURELIVE_FFMPEG）：{error}")
                    })?;
                    let mut deadline = None;
                    loop {
                        match child.try_wait() {
                            Ok(Some(status)) if status.success() => {
                                return Ok(format!("录制已保存：{}", output.display()));
                            }
                            Ok(Some(_)) => {
                                return Err("录制失败或直播流中断，请检查录制目录".into());
                            }
                            Ok(None) => {}
                            Err(error) => {
                                let _ = child.kill();
                                let _ = child.wait();
                                return Err(format!("无法检查录制状态：{error}"));
                            }
                        }
                        if let Some(until) = deadline {
                            if Instant::now() >= until {
                                let _ = child.kill();
                                let _ = child.wait();
                                return Err("录制停止超时，已保留可能不完整的文件".into());
                            }
                            std::thread::sleep(Duration::from_millis(100));
                        } else if !matches!(
                            stop_rx.recv_timeout(Duration::from_millis(100)),
                            Err(mpsc::RecvTimeoutError::Timeout)
                        ) {
                            if let Some(mut input) = child.stdin.take() {
                                let _ = input.write_all(b"q\n");
                            }
                            deadline = Some(Instant::now() + Duration::from_secs(10));
                        }
                    }
                })();
                let _ = done.send(message.unwrap_or_else(|error| error));
            })
            .map_err(|error| error.to_string())?;
        self.job = Some(Job {
            stop,
            result,
            stopping: false,
        });
        Ok("正在录制…".into())
    }
}
