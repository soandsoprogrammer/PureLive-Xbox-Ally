use super::*;
use plugin_config::{RecordingConfig, TranslationConfig};
use plugins::catalog::PluginKind;

pub(super) struct Editor {
    pub fields: Fields,
    pub cursor: usize,
    pub picking: bool,
}

pub(super) enum Fields {
    Recording {
        directory: Entity<InputState>,
    },
    Translation {
        model: Entity<InputState>,
        language: Entity<InputState>,
        enabled: bool,
        room_titles: bool,
        danmaku: bool,
    },
}

impl Fields {
    fn count(&self) -> usize {
        match self {
            Self::Recording { .. } => 4,
            Self::Translation { .. } => 6,
        }
    }

    fn input(&self, cursor: usize) -> Option<&Entity<InputState>> {
        match (self, cursor) {
            (Self::Recording { directory }, 0) => Some(directory),
            (Self::Translation { model, .. }, 0) => Some(model),
            (Self::Translation { language, .. }, 1) => Some(language),
            _ => None,
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Self::Recording { .. } => "直播录制设置",
            Self::Translation { .. } => "本地翻译设置",
        }
    }
}

impl Home {
    pub(super) fn open_plugin_settings(
        &mut self,
        index: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(dialog) = &mut self.plugin_dialog else { return };
        if dialog.pending || dialog.editor.is_some() {
            return;
        }
        let Some(&plugin) = plugins::catalog::PLUGINS.get(index) else { return };
        let directory = self.follows_path.with_file_name("plugins");
        if !plugin.installed(&directory) {
            return;
        }
        dialog.selected = index;
        let fields = match plugin.kind {
            PluginKind::MultiView => return,
            PluginKind::Recording => {
                let config: RecordingConfig = match plugin_config::load(&directory.join("recording.json")) {
                    Ok(config) => config,
                    Err(error) => {
                        dialog.notice = format!("无法读取录制设置：{error}");
                        cx.notify();
                        return;
                    }
                };
                let default = std::env::var_os("PURELIVE_RECORDINGS_DIR")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| self.follows_path.with_file_name("recordings"));
                let value = config.directory.map(|path| path.to_string_lossy().into_owned()).unwrap_or_default();
                let field = cx.new(|cx| {
                    InputState::new(window, cx)
                        .placeholder(default.to_string_lossy().into_owned())
                        .default_value(value)
                });
                Fields::Recording { directory: field }
            }
            PluginKind::Translation => {
                let config: TranslationConfig = match plugin_config::load(&directory.join("translation.json")) {
                    Ok(config) => config,
                    Err(error) => {
                        dialog.notice = format!("无法读取翻译设置：{error}");
                        cx.notify();
                        return;
                    }
                };
                let model = cx.new(|cx| InputState::new(window, cx).default_value(config.model));
                let language = cx.new(|cx| InputState::new(window, cx).default_value(config.target_language));
                Fields::Translation {
                    model, language, enabled: config.enabled,
                    room_titles: config.room_titles, danmaku: config.danmaku,
                }
            }
        };
        dialog.editor = Some(Editor { fields, cursor: 0, picking: false });
        dialog.notice.clear();
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn close_plugin_settings(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(dialog) = &mut self.plugin_dialog else { return };
        if dialog.editor.as_ref().is_some_and(|editor| editor.picking) {
            return;
        }
        dialog.editor = None;
        dialog.notice.clear();
        self.focus.focus(window, cx);
        cx.notify();
    }

    pub(super) fn focus_plugin_option(&mut self, cursor: usize, window: &mut Window, cx: &mut Context<Self>) {
        let Some(editor) = self.plugin_dialog.as_mut().and_then(|dialog| dialog.editor.as_mut()) else { return };
        if editor.picking {
            return;
        }
        editor.cursor = cursor % editor.fields.count();
        if let Some(input) = editor.fields.input(editor.cursor) {
            input.read(cx).focus_handle(cx).focus(window, cx);
        } else {
            self.focus.focus(window, cx);
        }
        cx.notify();
    }

    pub(super) fn step_plugin_option(&mut self, forward: bool, window: &mut Window, cx: &mut Context<Self>) {
        let Some(editor) = self.plugin_dialog.as_ref().and_then(|dialog| dialog.editor.as_ref()) else { return };
        let count = editor.fields.count();
        let offset = if forward { 1 } else { count - 1 };
        self.focus_plugin_option((editor.cursor + offset) % count, window, cx);
    }

    pub(super) fn activate_plugin_option(&mut self, cursor: usize, window: &mut Window, cx: &mut Context<Self>) {
        let Some(dialog) = &mut self.plugin_dialog else { return };
        let Some(editor) = &mut dialog.editor else { return };
        if editor.picking {
            return;
        }
        editor.cursor = cursor;
        match (&mut editor.fields, cursor) {
            (Fields::Recording { .. }, 0) | (Fields::Translation { .. }, 0 | 1) => {
                self.focus_plugin_option(cursor, window, cx);
            }
            (Fields::Recording { .. }, 1) => self.choose_recording_directory(window, cx),
            (Fields::Recording { directory }, 2) => {
                directory.update(cx, |input, cx| input.set_value("", window, cx));
                self.focus.focus(window, cx);
                cx.notify();
            }
            (Fields::Recording { .. }, 3) | (Fields::Translation { .. }, 5) => {
                self.save_plugin_settings(window, cx)
            }
            (Fields::Translation { enabled, room_titles, danmaku, .. }, 2..=4) => {
                let value = match cursor {
                    2 => enabled,
                    3 => room_titles,
                    _ => danmaku,
                };
                *value = !*value;
                self.focus.focus(window, cx);
                cx.notify();
            }
            _ => {}
        }
    }

    fn choose_recording_directory(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(editor) = self.plugin_dialog.as_mut().and_then(|dialog| dialog.editor.as_mut()) else { return };
        let Fields::Recording { directory } = &editor.fields else { return };
        let input = directory.clone();
        editor.picking = true;
        let choice = cx.prompt_for_paths(PathPromptOptions {
            files: false,
            directories: true,
            multiple: false,
            prompt: Some("选择".into()),
        });
        cx.spawn_in(window, async move |entity, cx| {
            let result = choice.await;
            let _ = entity.update_in(cx, |this, window, cx| {
                let Some(dialog) = &mut this.plugin_dialog else { return };
                let Some(editor) = &mut dialog.editor else { return };
                editor.picking = false;
                match result {
                    Ok(Ok(Some(paths))) => {
                        if let Some(path) = paths.first() {
                            let value = path.to_string_lossy().into_owned();
                            input.update(cx, |state, cx| state.set_value(value, window, cx));
                            dialog.notice.clear();
                        }
                    }
                    Ok(Err(error)) => dialog.notice = format!("无法选择文件夹：{error}"),
                    _ => {}
                }
                cx.notify();
            });
        }).detach();
    }

    pub(super) fn save_plugin_settings(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(dialog) = &mut self.plugin_dialog else { return };
        let Some(editor) = &dialog.editor else { return };
        if editor.picking {
            return;
        }
        let directory = self.follows_path.with_file_name("plugins");
        let result = match &editor.fields {
            Fields::Recording { directory: field } => {
                let value = field.read(cx).value();
                let value = value.trim();
                let path = PathBuf::from(value);
                if !value.is_empty() && (!path.is_absolute() || path.is_file()) {
                    dialog.notice = "请选择文件夹，或输入完整的文件夹路径。".into();
                    cx.notify();
                    return;
                }
                let config = RecordingConfig { directory: (!value.is_empty()).then_some(path) };
                playback::save_preference(&directory.join("recording.json"), &config)
            }
            Fields::Translation { model, language, enabled, room_titles, danmaku } => {
                let model = model.read(cx).value().trim().to_owned();
                let target_language = language.read(cx).value().trim().to_owned();
                if model.is_empty() || target_language.is_empty() || model.len() > 128 || target_language.len() > 128 {
                    dialog.notice = "请填写模型和目标语言，每项最多 128 字节。".into();
                    cx.notify();
                    return;
                }
                let config = TranslationConfig {
                    enabled: *enabled, model, target_language,
                    room_titles: *room_titles, danmaku: *danmaku,
                };
                playback::save_preference(&directory.join("translation.json"), &config)
            }
        };
        match result {
            Ok(()) => {
                dialog.editor = None;
                dialog.notice = "插件设置已保存".into();
                self.plugins = plugins::Plugins::load(&directory);
                self.focus.focus(window, cx);
            }
            Err(error) => dialog.notice = format!("无法保存插件设置：{error}"),
        }
        cx.notify();
    }
}
