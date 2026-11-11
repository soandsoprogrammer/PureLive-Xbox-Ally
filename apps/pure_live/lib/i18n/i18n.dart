import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:live_ui/live_ui.dart';

/// The interface languages: 3.x's two (`AppConsts.languages`) and the ones
/// 5.4 added. [displayName] is what the `language` setting stores (3.x's
/// names for the first two), [code] names the translation file.
enum AppLanguage {
  /// Simplified Chinese, 3.x's fallback.
  zh('简体中文', Locale('zh'), 'zh'),

  /// Traditional Chinese (Taiwan's words), made from the Simplified file.
  zhHant('繁體中文', Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 'zh_Hant'),

  /// English.
  en('English', Locale('en'), 'en'),

  /// Japanese.
  ja('日本語', Locale('ja'), 'ja'),

  /// Korean.
  ko('한국어', Locale('ko'), 'ko'),

  /// Spanish.
  es('Español', Locale('es'), 'es'),

  /// French.
  fr('Français', Locale('fr'), 'fr'),

  /// German.
  de('Deutsch', Locale('de'), 'de'),

  /// Portuguese (Brazil's words).
  pt('Português', Locale('pt'), 'pt'),

  /// Russian.
  ru('Русский', Locale('ru'), 'ru'),

  /// Italian.
  it('Italiano', Locale('it'), 'it'),

  /// Vietnamese.
  vi('Tiếng Việt', Locale('vi'), 'vi'),

  /// Thai.
  th('ไทย', Locale('th'), 'th'),

  /// Indonesian.
  id('Bahasa Indonesia', Locale('id'), 'id'),

  /// Turkish.
  tr('Türkçe', Locale('tr'), 'tr');

  new(this.displayName, this.locale, this.code);

  /// The stored name (setting `language`), in the language itself.
  final String displayName;

  /// The locale.
  final Locale locale;

  /// The translation file's name, `assets/translations/<code>.json`.
  final String code;

  /// Simplified or Traditional Chinese: Chinese units (万, 亿) and the
  /// Chinese names the code keeps; every other language takes the English
  /// ones.
  bool get isChinese => this == zh || this == zhHant;

  /// The language stored as [name] (3.x's names, the enum's names or the file
  /// codes; case and spaces ignored), or null.
  static AppLanguage? fromName(String name) {
    final key = name.trim().toLowerCase();
    for (final language in values) {
      if (language.displayName.toLowerCase() == key ||
          language.name.toLowerCase() == key ||
          language.code.toLowerCase() == key) {
        return language;
      }
    }
    return null;
  }

  /// The language of a device [locale], or null: Chinese with the Hant script
  /// or from Taiwan, Hong Kong or Macao is Traditional, other Chinese is
  /// Simplified, the rest go by the language code.
  static AppLanguage? ofLocale(Locale locale) {
    if (locale.languageCode == 'zh') {
      final traditional =
          locale.scriptCode == 'Hant' || const {'TW', 'HK', 'MO'}.contains(locale.countryCode?.toUpperCase());
      return traditional ? zhHant : zh;
    }
    for (final language in values) {
      if (language.locale.languageCode == locale.languageCode) return language;
    }
    return null;
  }

  /// The language to show.
  ///
  /// The user's choice when the `language` setting was written ([stored]);
  /// otherwise the first of the device's [preferred] locales the app speaks,
  /// else Chinese. 3.x started easy_localization from the device locale with
  /// Chinese as the fallback and only wrote its setting when the user picked
  /// a language, so an English phone that never touched the setting showed
  /// English while the setting said 简体中文.
  static AppLanguage resolve({required String? stored, required List<Locale> preferred}) {
    final chosen = stored == null ? null : fromName(stored);
    if (chosen != null) return chosen;
    for (final locale in preferred) {
      final language = ofLocale(locale);
      if (language != null) return language;
    }
    return zh;
  }

  /// The tables a missing key is looked up in after this language's own:
  /// Chinese then English for the Chinese ones, English then Chinese for the
  /// rest.
  List<AppLanguage> get fallbacks => isChinese ? const [zh, en] : const [en, zh];
}

/// The words of one language (3.x `assets/translations/<code>.json`, read
/// through easy_localization).
///
/// A key missing in the language falls back along [AppLanguage.fallbacks],
/// then to the key itself: 3.x's files differ by a few keys (`count_wan` and
/// `videofit_scaleDown` only in Chinese, `count_k` and
/// `double_click_to_exit` only in English), which 3.x showed as raw keys in
/// Chinese.
final class AppStrings {
  /// Creates the words from parsed tables: [table] is the language's own,
  /// [fallbacks] are looked up in order after it.
  new(this.language, Map<String, String> table, {List<Map<String, String>> fallbacks = const []})
    : _tables = [table, ...fallbacks];

  /// The asset of [language]'s file.
  static String assetOf(AppLanguage language) => 'assets/translations/${language.code}.json';

  /// Loads [language] (with its fallbacks) from [bundle].
  static Future<AppStrings> load(AppLanguage language, AssetBundle bundle) async {
    Future<Map<String, String>> read(AppLanguage which) async {
      final decoded = jsonDecode(await bundle.loadString(assetOf(which), cache: false));
      return {
        if (decoded is Map)
          for (final MapEntry(:key, :value) in decoded.entries)
            if (value is String) '$key': value,
      };
    }

    final own = await read(language);
    return AppStrings(
      language,
      own,
      fallbacks: [
        for (final fallback in language.fallbacks)
          if (fallback != language) await read(fallback),
      ],
    );
  }

  /// The language.
  final AppLanguage language;

  final List<Map<String, String>> _tables;

  /// Whether [key] has a text in this language or a fallback.
  bool contains(String key) => _tables.any((table) => table.containsKey(key));

  /// The text of [key] with `{name}` placeholders filled from [args]
  /// (easy_localization's named arguments).
  String tr(String key, {Map<String, String>? args}) {
    var text = key;
    for (final table in _tables) {
      final found = table[key];
      if (found != null) {
        text = found;
        break;
      }
    }
    if (args != null) {
      for (final MapEntry(:key, :value) in args.entries) {
        text = text.replaceAll('{$key}', value);
      }
    }
    return text;
  }

  /// The shared widgets' words (live_ui) in this language.
  LiveUiStrings get ui => LiveUiStrings(
    emptyTitle: tr('status_empty_title'),
    emptySubtitle: tr('status_empty_subtitle'),
    errorTitle: tr('status_error_title'),
    errorSubtitle: tr('status_error_subtitle'),
    retry: tr('status_retry_button'),
    audiencePopularity: tr('audience_popularity'),
    audienceOnline: tr('audience_online'),
    audienceTotal: tr('audience_total'),
    audienceFollowers: tr('audience_followers'),
    audienceCount: tr('audience_count'),
    audienceWaiting: tr('audience_waiting'),
    replay: tr('replay'),
    verifying: tr('favorite_status_verifying'),
    delete: tr('delete'),
    offline: tr('offline_room_title'),
    cancel: tr('cancel'),
    close: tr('close'),
    gotIt: tr('got_it'),
    refreshPull: tr('refresh_pull_to_refresh'),
    refreshRelease: tr('refresh_release_to_refresh'),
    refreshRefreshing: tr('refresh_refreshing'),
    refreshSucceeded: tr('refresh_succeeded'),
    refreshFailed: tr('refresh_failed'),
    refreshLastTime: tr('refresh_last_updated_at'),
    loading: tr('refresh_loading'),
    loadFailed: tr('refresh_load_failed'),
    offlineTitle: tr('status_offline_title'),
    offlineSubtitle: tr('status_offline_subtitle'),
    restrictedTitle: tr('login_required_title'),
    restrictedSubtitle: tr('login_required_subtitle'),
    login: tr('go_to_login'),
    details: tr('details'),
    copy: tr('copy'),
    copied: tr('copied_to_clipboard'),
    followed: tr('followed'),
  );
}

AppStrings? _current;

/// The words in use; the app sets them before the first frame and whenever
/// the language changes.
AppStrings? get currentStrings => _current;

set currentStrings(AppStrings? strings) => _current = strings;

/// The text of [key] in the current language (3.x `i18n` from
/// `plugins/locale_helper.dart`; same name and arguments so pages port
/// call by call). Before the words are loaded it answers [key].
String i18n(String key, {Map<String, String>? args}) => _current?.tr(key, args: args) ?? key;

/// [i18n], or [fallback] while the key has no text (3.x `i18nOr`).
String i18nOr(String key, String fallback, {Map<String, String>? args}) =>
    i18nExists(key) ? i18n(key, args: args) : fallback;

/// Whether the current language is Chinese (Simplified or Traditional; also
/// before the words are loaded): the words the code keeps in Chinese and
/// English, and Chinese units, follow it.
bool get i18nChinese => _current?.language.isChinese ?? true;

/// Whether [key] has a text (3.x `i18nExists`).
bool i18nExists(String key) => _current?.contains(key) ?? false;
