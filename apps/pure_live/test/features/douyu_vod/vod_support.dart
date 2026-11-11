import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';

/// Synthetic video metadata; media URLs never reach a network in tests.
const firstVideo = DouyuVodVideo(id: 'Replay0000000001', title: '第一场录像', authorId: 'Author0001', authorName: '测试主播');

/// Another segment.
const secondVideo = DouyuVodVideo(id: 'Replay0000000002', title: '第二场录像', authorId: 'Author0001');

/// Data-only descriptor fixture, shared with the pure Dart signer tests.
DouyuVodSigner testSigner() {
  final data = jsonDecode(File('../../fixtures/douyu/vod/S01-public-sign/body.json').readAsStringSync()) as Map;
  String array(String field) => (data[field] as List).join(',');
  String hex(String field) => '0x${(data[field] as int).toRadixString(16)}';
  final count = (data['words'] as List).length;
  return DouyuVodSigner.fromScript(
    'var words=[${array('words')}];function ub98484234(a,b,c){ '
    'var rk=[${array('rounds')}];var k=[${array('key')}];var k2=[${array('xorKey')}];var lk=[${array('lookup')}]; '
    'var v=words.slice(0);for(var O=0;O<$count;O++){v[O]^=${hex('mask')};}'
    '${(data['mutations'] as List).join(';')};'
    'for(var I=0;I<$count;I+=2){}v[0]^=${hex('finalMask')};var strc="";return strc;}',
  );
}

/// Deterministic source, with optional delayed details for replacement tests.
final class FakeVodSource implements DouyuVodSource {
  /// Creates the fake using recorded algorithm data only.
  new(this.signer);
  final DouyuVodSigner signer;
  final calls = <String>[];
  final details = <String, Completer<DouyuVodDetail>>{};
  int renewals = 0;
  bool failComments = false;
  @override
  Future<DouyuVodPage> home({CancelToken? cancel}) async {
    calls.add('home');
    return const DouyuVodPage(videos: [firstVideo], hasMore: false);
  }

  @override
  Future<DouyuVodPage> search(
    String keyword, {
    bool replay = true,
    int page = 1,
    int limit = 20,
    CancelToken? cancel,
  }) async {
    calls.add('search:$keyword:$replay:$page');
    return DouyuVodPage(videos: [if (page == 1) firstVideo else secondVideo], hasMore: page == 1);
  }

  @override
  Future<DouyuVodPage> author(
    String id, {
    bool replay = true,
    int page = 1,
    int limit = 10,
    CancelToken? cancel,
  }) async {
    calls.add('author:$id:$replay:$page');
    return const DouyuVodPage(videos: [secondVideo], hasMore: false);
  }

  @override
  Future<DouyuVodDetail> detail(String id, {CancelToken? cancel}) async {
    calls.add('detail:$id');
    if (details[id] case final response?) return await response.future;
    return DouyuVodDetail(video: id == firstVideo.id ? firstVideo : secondVideo, signer: signer);
  }

  @override
  Future<List<DouyuVodVideo>> replaySegments(DouyuVodVideo video, {CancelToken? cancel}) async => [
    firstVideo,
    secondVideo,
  ];
  @override
  Future<List<DouyuVodQuality>> qualities(DouyuVodDetail detail, {CancelToken? cancel}) async {
    renewals++;
    return [
      for (final (id, label, level) in [('super', '超清', 3), ('high', '高清', 2), ('normal', '标清', 1)])
        DouyuVodQuality(
          id: id,
          label: label,
          level: level,
          url: 'https://cdn.example/${detail.video.id}/$id-$renewals.mp4',
          playable: id != 'super',
        ),
    ];
  }

  @override
  Future<DouyuVodDanmakuChunk> danmaku(String id, Duration start, {CancelToken? cancel}) async {
    if (failComments) throw StateError('comments offline');
    return const DouyuVodDanmakuChunk(messages: [], next: null);
  }
}
