import 'package:flutter/widgets.dart';

/// Edits a settings row's text using the platform's input UI. TV pages
/// provide the remote/system keyboard without putting an inline editor
/// into directional navigation.
class SettingsTextPresenter extends InheritedWidget {
  /// Creates the presenter.
  const new({required this.prompt, required super.child, super.key});

  /// Returns confirmed text, or null when the input is cancelled.
  final Future<String?> Function(BuildContext context, {required String title, required String initial, int? maxLength})
  prompt;

  /// The presenter above [context], if any.
  static SettingsTextPresenter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsTextPresenter>();

  @override
  bool updateShouldNotify(SettingsTextPresenter oldWidget) => oldWidget.prompt != prompt;
}
