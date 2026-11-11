import 'package:pure_live/features/recorder/logic/recorder_view.dart';
import 'package:pure_live/i18n/i18n.dart';

export 'package:pure_live/shared/record/record_texts.dart';

/// The label of a recording centre filter (U.7a c6).
String recorderFilterLabel(RecorderFilter filter) => i18n(switch (filter) {
  RecorderFilter.all => 'recorder_tab_all',
  RecorderFilter.active => 'recorder_filter_active',
  RecorderFilter.waiting => 'recorder_tab_waiting',
  RecorderFilter.saved => 'recorder_filter_saved',
  RecorderFilter.failed => 'recorder_tab_failed',
});
