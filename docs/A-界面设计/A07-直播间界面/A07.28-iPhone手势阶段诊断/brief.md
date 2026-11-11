# A07.28 接A07.27：iPhone手势阶段诊断

来源：[#41](https://github.com/wzgrx/PureLive/issues/41)。原iPhone 15 Pro Max/iOS18.7.8/5.4.14仍无提示，iPad和Android正常。完整播放界面的横屏安全区、左右拖动与模拟原生调用两项通过，不代替原机验收。

范围：仅player_gestures.dart固定阶段日志及对应回归，不改手势判断、原生音量接口、系统边缘保护或超时。iOS记录attached、enabled-changed、down、start、system-edge、restore-panel、reading、baseline及每次拖动首次update；不含触点、数值、时间差之外的原始输入、房间、账号或媒体地址。实际日志仍按既有应用日志开关和等级处理，不上传。

验证：延迟回读18项、完整房间识别、系统边缘保护与日志隐私/频率回归；原iPhone需导出相邻gesture-input行及短录屏，确认无提示原因后另修复。本任务是诊断补充，#41保持开放。
