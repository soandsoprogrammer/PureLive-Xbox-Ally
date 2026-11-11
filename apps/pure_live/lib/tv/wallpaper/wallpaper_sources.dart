import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:live_net/live_net.dart';

// Where TV backgrounds come from (A17.8 h1). The library uses two public,
// documented sources — Bing's daily pictures and Wallhaven's API, safe for
// work only — instead of pure_live_TV's iTab endpoints, which answer only a
// request posing as iTab's browser extension. The random APIs are
// pure_live_TV's list without the "性感美女" group and the sources of the
// same kind (D-032).

/// The `site` of these requests (the app log, the proxy rules).
const String tvWallpaperSite = 'wallpaper';

/// One picture offered.
@immutable
final class TvWallpaperItem {
  /// Creates the item.
  const new({required this.url, String? thumb, this.title = ''}) : thumb = thumb ?? url;

  /// The full picture (an address, or a `file://` of one fetched already).
  final String url;

  /// A smaller one for the grid.
  final String thumb;

  /// What it shows (Bing's caption), may be empty.
  final String title;
}

/// One category of a library.
@immutable
final class TvWallpaperCategory {
  /// Creates the category.
  const new(this.id, this.nameKey);

  /// Its id.
  final String id;

  /// Its words' key.
  final String nameKey;
}

/// A library of pictures in categories, a page at a time.
abstract interface class TvWallpaperLibrary {
  /// Its id.
  String get id;

  /// Its words' key.
  String get nameKey;

  /// Its categories.
  List<TvWallpaperCategory> get categories;

  /// Page [page] (from 1) of [category]; empty past the end.
  Future<List<TvWallpaperItem>> items(LiveHttp http, String category, int page);
}

/// Bing's pictures of the day (the last two weeks, two pages of eight).
final class BingWallpapers implements TvWallpaperLibrary {
  /// Creates the library.
  const new();

  @override
  String get id => 'bing';

  @override
  String get nameKey => 'tv_wallpaper_bing';

  @override
  List<TvWallpaperCategory> get categories => const [TvWallpaperCategory('daily', 'tv_wallpaper_bing_daily')];

  @override
  Future<List<TvWallpaperItem>> items(LiveHttp http, String category, int page) async {
    if (page > 2) return const [];
    final json = await http.getJson(
      tvWallpaperSite,
      Uri.https('www.bing.com', '/HPImageArchive.aspx'),
      query: {'format': 'js', 'idx': '${(page - 1) * 8}', 'n': '8', 'mkt': 'zh-CN'},
    );
    final images = json is Map<String, Object?> ? json['images'] : null;
    if (images is! List<Object?>) return const [];
    return [
      for (final image in images)
        if (image case {'urlbase': final String base}) ...[
          TvWallpaperItem(
            url: 'https://www.bing.com${base}_1920x1080.jpg',
            thumb: 'https://www.bing.com${base}_400x240.jpg',
            title: image['copyright'] is String ? image['copyright']! as String : '',
          ),
        ],
    ];
  }
}

/// Wallhaven's public API: general and anime pictures, safe for work only
/// (`purity=100`), at least 1920 × 1080.
final class WallhavenWallpapers implements TvWallpaperLibrary {
  /// Creates the library.
  const new();

  @override
  String get id => 'wallhaven';

  @override
  String get nameKey => 'tv_wallpaper_wallhaven';

  @override
  List<TvWallpaperCategory> get categories => const [
    TvWallpaperCategory('toplist', 'tv_wallpaper_top'),
    TvWallpaperCategory('latest', 'tv_wallpaper_latest'),
    TvWallpaperCategory('landscape', 'tv_wallpaper_landscape'),
    TvWallpaperCategory('anime', 'tv_wallpaper_anime'),
    TvWallpaperCategory('random', 'tv_wallpaper_random'),
  ];

  /// The query of [category].
  static Map<String, String> queryOf(String category, int page) => {
    'purity': '100',
    'atleast': '1920x1080',
    'page': '$page',
    ...switch (category) {
      'latest' => {'categories': '110', 'sorting': 'date_added'},
      'landscape' => {'categories': '100', 'sorting': 'toplist', 'q': 'landscape'},
      'anime' => {'categories': '010', 'sorting': 'toplist'},
      'random' => {'categories': '110', 'sorting': 'random'},
      _ => {'categories': '110', 'sorting': 'toplist'},
    },
  };

  @override
  Future<List<TvWallpaperItem>> items(LiveHttp http, String category, int page) async {
    final json = await http.getJson(
      tvWallpaperSite,
      Uri.https('wallhaven.cc', '/api/v1/search'),
      query: queryOf(category, page),
    );
    final data = json is Map<String, Object?> ? json['data'] : null;
    if (data is! List<Object?>) return const [];
    return [
      for (final item in data)
        if (item case {'path': final String path, 'purity': 'sfw'})
          TvWallpaperItem(
            url: path,
            thumb: switch (item['thumbs']) {
              {'large': final String large} => large,
              _ => path,
            },
          ),
    ];
  }
}

/// The libraries, in order.
const List<TvWallpaperLibrary> tvWallpaperLibraries = [BingWallpapers(), WallhavenWallpapers()];

/// How a random API hands over its picture (pure_live_TV's measurements).
enum TvRandomKind {
  /// The address streams a picture (after redirects).
  direct,

  /// It answers JSON (or HTML unless JSON is asked for) with the picture's
  /// address.
  json,
}

/// One random-picture API.
@immutable
final class TvRandomSource {
  /// Creates the source.
  const new(this.name, this.url, {this.kind = TvRandomKind.direct, this.apiKey});

  /// Its name (a brand, not translated).
  final String name;

  /// The address.
  final String url;

  /// How it answers.
  final TvRandomKind kind;

  /// A key some JSON APIs want (`type=json&apiKey=`).
  final String? apiKey;
}

/// A family of random APIs.
@immutable
final class TvRandomGroup {
  /// Creates the group.
  const new(this.id, this.nameKey, this.sources);

  /// Its id.
  final String id;

  /// Its words' key.
  final String nameKey;

  /// Its sources.
  final List<TvRandomSource> sources;
}

const String _alcy = 'https://t.alcy.cc/';
const List<String> _alcyCategories = ['ycy', 'moez', 'ysz', 'ys', 'mp', 'moemp', 'ysmp', 'tx', 'lai', 'xhl', 'bd'];
const String _apizero = 'https://v1.apizero.cn/api/wallpaper?resolution=1920x1080&count=1&category=';

/// The random APIs (pure_live_TV's, without "性感美女" and the sources of
/// that kind, D-032), in order.
final List<TvRandomGroup> tvRandomGroups = [
  const TvRandomGroup('bing', 'tv_wallpaper_api_bing', [
    TvRandomSource('必应随机 Biturl', 'https://bing.biturl.top/?resolution=1920x1080&format=image&index=random'),
    TvRandomSource('必应随机 Jason Zeng', 'https://bingw.jasonzeng.dev/?resolution=1920x1080&index=random'),
    TvRandomSource('必应随机 UAPI', 'https://uapis.cn/api/v1/image/bing-daily?random=true&resolution=1080'),
    TvRandomSource('必应随机 YingJoy', 'https://api.1314.cool/bingimg'),
    TvRandomSource('必应 W3H5', 'https://bz.w3h5.com/img/rand_fhd'),
  ]),
  TvRandomGroup('alcy', 'tv_wallpaper_api_alcy', [
    for (final category in _alcyCategories) TvRandomSource('栗次元 · $category', '$_alcy$category'),
  ]),
  const TvRandomGroup('wuming', 'tv_wallpaper_api_wuming', [
    TvRandomSource(
      '无铭动漫壁纸',
      'https://jkapi.com/api/dm_wallpaper',
      kind: TvRandomKind.json,
      apiKey: '95e3a0e608a8b1bed6d513346f929202',
    ),
    TvRandomSource(
      '无铭必应每日壁纸',
      'https://jkapi.com/api/bing_img',
      kind: TvRandomKind.json,
      apiKey: '0f57c17bca42966996d6a8bc28594858',
    ),
  ]),
  const TvRandomGroup('uapi', 'tv_wallpaper_api_uapi', [
    TvRandomSource('UAPI 全部随机', 'https://uapis.cn/api/v1/random/image'),
    TvRandomSource('UAPI 二次元', 'https://uapis.cn/api/v1/random/image?category=acg&type=pc'),
    TvRandomSource('UAPI 风景', 'https://uapis.cn/api/v1/random/image?category=landscape'),
    TvRandomSource('UAPI 电脑壁纸', 'https://uapis.cn/api/v1/random/image?category=pc_wallpaper'),
    TvRandomSource('UAPI 动漫', 'https://uapis.cn/api/v1/random/image?category=general_anime'),
  ]),
  TvRandomGroup('360', 'tv_wallpaper_api_360', [
    for (final category in ['风景', '游戏', '影视', '汽车', '萌宠', '清新', '体育', '动漫', '日历', '格言'])
      TvRandomSource('360 壁纸 · $category', '$_apizero$category', kind: TvRandomKind.json),
  ]),
  const TvRandomGroup('misc', 'tv_wallpaper_api_misc', [
    TvRandomSource('小晓 API', 'https://v2.xxapi.cn/api/wallpaper', kind: TvRandomKind.json),
    TvRandomSource('mtyqx', 'https://api.mtyqx.cn/tapi/random.php'),
    TvRandomSource('picsum', 'https://picsum.photos/1920/1080'),
    TvRandomSource('dmoe', 'https://www.dmoe.cc/random.php'),
    TvRandomSource('loliApi', 'https://www.loliapi.com/bg/'),
  ]),
];

/// The picture's address in a JSON answer of a random API: `data` (a
/// string, or an object or list holding one), `url`, `image_url`, `imgurl`
/// or `content`; null when there is none.
String? randomPictureUrl(Object? json) {
  if (json is String) return json.startsWith('http') ? json : null;
  if (json is List<Object?>) {
    for (final item in json) {
      if (randomPictureUrl(item) case final url?) return url;
    }
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  for (final key in ['data', 'url', 'image_url', 'imgurl', 'img', 'content', 'pic']) {
    if (randomPictureUrl(json[key]) case final url?) return url;
  }
  return null;
}

/// The address to ask [source] for one picture: the JSON ones are asked for
/// JSON (with their key); the alcy root picks one of its categories.
Uri randomRequestUrl(TvRandomSource source, {Random? random}) {
  if (source.url == _alcy) {
    return Uri.parse('$_alcy${_alcyCategories[(random ?? Random()).nextInt(_alcyCategories.length)]}');
  }
  final url = Uri.parse(source.url);
  if (source.kind != TvRandomKind.json || source.apiKey == null) return url;
  return url.replace(queryParameters: {...url.queryParameters, 'type': 'json', 'apiKey': ?source.apiKey});
}
