import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The saved playlists, read again after every write to the IPTV tables;
/// none when IPTV is not set up. For pages outside the IPTV page (热门 →
/// 网络's playlist row, V02.9).
final StreamProvider<List<IptvPlaylist>> iptvPlaylistsProvider = StreamProvider.autoDispose<List<IptvPlaylist>>((ref) {
  final library = ref.watch(appServicesProvider).iptvImporter?.library;
  if (library == null) return Stream.value(const []);
  return ref.watch(storeProvider).database.watch(IptvTables.all, library.playlists);
});

/// The display name of [playlist]: the built-in list's name `hot` reads as
/// "热门频道（内置）".
String iptvPlaylistName(IptvPlaylist playlist) => playlist.isHot ? i18n('iptv_hot_playlist') : playlist.name;
