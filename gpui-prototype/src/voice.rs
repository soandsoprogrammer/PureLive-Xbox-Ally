//! Talking to the search box instead of typing into it.
//!
//! The controller has no keyboard, so the search field also accepts dictation:
//! press A while the field is focused, speak, press A again. The audio stays on
//! the machine: capture through WASAPI (`cpal`) and recognition through a local
//! SenseVoice model (`sherpa-onnx`), the same model the DeepSeek Harness voice
//! input uses.

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

use async_channel::{Receiver, Sender};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use sherpa_onnx::{
    LinearResampler, OfflineRecognizer, OfflineRecognizerConfig, OfflineSenseVoiceModelConfig,
};

/// SenseVoice expects 16 kHz mono audio.
const SAMPLE_RATE: i32 = 16_000;
/// A search query never needs more than this, and the buffer stays small.
const MAX_SECONDS: u32 = 30;

/// What the interface shows while dictation is running.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Idle,
    Listening,
    Recognizing,
}

/// Messages from the recognition thread.
pub enum Report {
    Text(String),
    Failed(String),
}

struct Job {
    samples: Vec<f32>,
    rate: u32,
}

struct Models {
    model: PathBuf,
    tokens: PathBuf,
}

impl Models {
    fn load(&self) -> Result<OfflineRecognizer, String> {
        let mut config = OfflineRecognizerConfig::default();
        config.model_config.sense_voice = OfflineSenseVoiceModelConfig {
            model: Some(self.model.to_string_lossy().into_owned()),
            language: Some("auto".into()),
            use_itn: true,
        };
        config.model_config.tokens = Some(self.tokens.to_string_lossy().into_owned());
        config.model_config.num_threads = 2;
        OfflineRecognizer::create(&config)
            .ok_or_else(|| format!("无法加载语音模型：{}", self.model.display()))
    }
}

struct Capture {
    stream: cpal::Stream,
    samples: Arc<Mutex<Vec<f32>>>,
    rate: u32,
}

impl Capture {
    fn start(failure: Arc<Mutex<Option<String>>>) -> Result<Self, String> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or_else(|| "没有找到麦克风".to_owned())?;
        let supported = device
            .default_input_config()
            .map_err(|error| format!("无法打开麦克风：{error}"))?;
        let format = supported.sample_format();
        let config = supported.config();
        let channels = config.channels as usize;
        let rate = config.sample_rate.0;
        let limit = rate as usize * MAX_SECONDS as usize;
        let samples = Arc::new(Mutex::new(Vec::<f32>::with_capacity(limit)));
        let sink = samples.clone();
        let report = failure.clone();
        let on_error = move |error: cpal::StreamError| {
            if let Ok(mut slot) = report.lock() {
                *slot = Some(format!("麦克风中断：{error}"));
            }
        };
        let stream = match format {
            cpal::SampleFormat::F32 => {
                let sink = sink.clone();
                device.build_input_stream(
                    &config,
                    move |data: &[f32], _: &cpal::InputCallbackInfo| {
                        append(&sink, data, channels, limit)
                    },
                    on_error,
                    None,
                )
            }
            cpal::SampleFormat::I16 => {
                let sink = sink.clone();
                let mut scratch = Vec::<f32>::new();
                device.build_input_stream(
                    &config,
                    move |data: &[i16], _: &cpal::InputCallbackInfo| {
                        scratch.clear();
                        scratch.extend(data.iter().map(|sample| f32::from(*sample) / 32_768.0));
                        append(&sink, &scratch, channels, limit)
                    },
                    on_error,
                    None,
                )
            }
            other => return Err(format!("麦克风格式不支持：{other:?}")),
        }
        .map_err(|error| format!("无法开始录音：{error}"))?;
        stream
            .play()
            .map_err(|error| format!("无法开始录音：{error}"))?;
        Ok(Self {
            stream,
            samples,
            rate,
        })
    }

    /// Stop the stream and hand back everything it captured.
    fn finish(self) -> (Vec<f32>, u32) {
        drop(self.stream);
        let samples = match self.samples.lock() {
            Ok(mut buffer) => std::mem::take(&mut *buffer),
            Err(poisoned) => std::mem::take(&mut *poisoned.into_inner()),
        };
        (samples, self.rate)
    }
}

/// Mix interleaved frames down to mono and keep the first [`MAX_SECONDS`].
fn append(sink: &Arc<Mutex<Vec<f32>>>, interleaved: &[f32], channels: usize, limit: usize) {
    let mut buffer = match sink.lock() {
        Ok(buffer) => buffer,
        Err(poisoned) => poisoned.into_inner(),
    };
    if buffer.len() >= limit {
        return;
    }
    if channels <= 1 {
        let room = limit - buffer.len();
        buffer.extend(interleaved.iter().take(room).copied());
        return;
    }
    for frame in interleaved.chunks(channels) {
        if buffer.len() >= limit {
            break;
        }
        buffer.push(frame.iter().sum::<f32>() / frame.len() as f32);
    }
}

pub struct Dictation {
    phase: Phase,
    models: Result<Models, String>,
    capture: Option<Capture>,
    jobs: Option<Sender<Job>>,
    report: Sender<Report>,
    failure: Arc<Mutex<Option<String>>>,
    notice: Option<String>,
}

impl Dictation {
    /// Build the dictation state and the channel its reports arrive on.
    pub fn new(directory: &Path) -> (Self, Receiver<Report>) {
        let (report, reports) = async_channel::unbounded::<Report>();
        let models = locate_models(directory);
        (
            Self {
                phase: Phase::Idle,
                models,
                capture: None,
                jobs: None,
                report,
                failure: Arc::new(Mutex::new(None)),
                notice: None,
            },
            reports,
        )
    }

    pub fn phase(&self) -> Phase {
        self.phase
    }

    /// One line under the search field: what dictation is doing right now.
    pub fn hint(&self) -> Option<String> {
        match self.phase {
            Phase::Listening => Some("🎙 正在聆听…说完再按 A".to_owned()),
            Phase::Recognizing => Some("正在识别…".to_owned()),
            Phase::Idle => {
                if let Ok(failure) = self.failure.lock() {
                    if let Some(failure) = failure.clone() {
                        return Some(failure);
                    }
                }
                self.notice.clone()
            }
        }
    }

    /// Begin listening. Returns the message to show when it cannot start.
    pub fn start(&mut self) -> Result<(), String> {
        if self.phase != Phase::Idle {
            return Ok(());
        }
        if let Some(message) = self.models.as_ref().err().cloned() {
            self.notice = Some(message.clone());
            return Err(message);
        }
        self.ensure_worker()?;
        if let Ok(mut failure) = self.failure.lock() {
            *failure = None;
        }
        match Capture::start(self.failure.clone()) {
            Ok(capture) => {
                self.capture = Some(capture);
                self.phase = Phase::Listening;
                self.notice = None;
                Ok(())
            }
            Err(message) => {
                self.notice = Some(message.clone());
                Err(message)
            }
        }
    }

    /// Stop listening and queue the recording for recognition.
    pub fn stop(&mut self) {
        let Some(capture) = self.capture.take() else {
            return;
        };
        let (samples, rate) = capture.finish();
        if samples.len() < (rate as usize) / 3 {
            self.phase = Phase::Idle;
            self.notice = Some("录音太短，说完整再按 A".to_owned());
            return;
        }
        let queued = match &self.jobs {
            Some(jobs) => jobs.try_send(Job { samples, rate }).is_ok(),
            None => false,
        };
        if !queued {
            self.phase = Phase::Idle;
            self.notice = Some("语音识别还没准备好，再说一次".to_owned());
            return;
        }
        self.phase = Phase::Recognizing;
        self.notice = None;
    }

    /// Drop the recording without recognizing it. Returns whether it cancelled
    /// anything, so the caller can tell a cancel from an ordinary back press.
    pub fn cancel(&mut self) -> bool {
        if self.phase != Phase::Listening {
            return false;
        }
        self.capture = None;
        self.phase = Phase::Idle;
        self.notice = None;
        true
    }

    /// The worker answered, successfully or not: dictation is idle again.
    pub fn settle(&mut self) {
        self.phase = Phase::Idle;
    }

    /// Start the recognition thread on first use; it keeps the model in memory.
    fn ensure_worker(&mut self) -> Result<(), String> {
        if self.jobs.is_some() {
            return Ok(());
        }
        let models = match &self.models {
            Ok(models) => Models {
                model: models.model.clone(),
                tokens: models.tokens.clone(),
            },
            Err(message) => return Err(message.clone()),
        };
        let (jobs, queue) = async_channel::bounded::<Job>(2);
        let report = self.report.clone();
        std::thread::Builder::new()
            .name("purelive-dictation".into())
            .spawn(move || {
                let engine = match models.load() {
                    Ok(engine) => engine,
                    Err(message) => {
                        let _ = report.send_blocking(Report::Failed(message));
                        return;
                    }
                };
                while let Ok(job) = queue.recv_blocking() {
                    let text = recognize(&engine, job);
                    if report.send_blocking(Report::Text(text)).is_err() {
                        break;
                    }
                }
            })
            .map_err(|error| format!("无法启动语音线程：{error}"))?;
        self.jobs = Some(jobs);
        Ok(())
    }
}

fn recognize(engine: &OfflineRecognizer, job: Job) -> String {
    let samples = if job.rate as i32 == SAMPLE_RATE {
        job.samples
    } else {
        match LinearResampler::create(job.rate as i32, SAMPLE_RATE) {
            Some(resampler) => resampler.resample(&job.samples, true),
            None => job.samples,
        }
    };
    let stream = engine.create_stream();
    stream.accept_waveform(SAMPLE_RATE, &samples);
    engine.decode(&stream);
    stream
        .get_result()
        .map(|result| result.text)
        .unwrap_or_default()
}

/// Where the model lives: next to the executable first, then the copy the
/// DeepSeek Harness voice input downloaded on this machine.
fn locate_models(directory: &Path) -> Result<Models, String> {
    let mut roots = vec![
        directory.join("models/sensevoice"),
        directory.join("models"),
    ];
    if let Some(home) = std::env::var_os("USERPROFILE") {
        roots.push(
            PathBuf::from(home).join(".dsh/speech-to-text/sensevoice/models/sensevoice-onnx"),
        );
    }
    if let Some(home) = std::env::var_os("DSH_HOME") {
        roots.push(PathBuf::from(home).join("speech-to-text/sensevoice/models/sensevoice-onnx"));
    }
    for root in &roots {
        let model = root.join("model.int8.onnx");
        let tokens = root.join("tokens.txt");
        if model.is_file() && tokens.is_file() {
            return Ok(Models { model, tokens });
        }
    }
    Err(format!(
        "没有找到语音模型：把 model.int8.onnx 和 tokens.txt 放进 {}，或先用 DeepSeek Harness 的语音输入下载一次",
        roots[0].display()
    ))
}
