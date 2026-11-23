import 'package:live_core/live_core.dart';
import 'package:test/test.dart';
import 'package:live_media/live_media.dart';

import '../bin/handheld_platforms.dart';

void main() {
  const qualities = [
    LivePlayQuality(quality: '原画', id: 'original'),
    LivePlayQuality(quality: '超清', id: 'hd4k'),
    LivePlayQuality(quality: '高清', id: 'hd'),
    LivePlayQuality(quality: '标清', id: 'sd'),
  ];
  List<Object?> ids(String platform, String? selected, [List<LivePlayQuality> list = qualities]) =>
      playbackQualityCandidates(platform, list, selected).map((q) => q.selectionId).toList();

  test('SOOP starts with HD while preserving manual original and SD choices', () {
    expect(ids('soop', null).first, 'hd');
    expect(ids('soop', null)[1], 'sd');
    expect(ids('soop', 'original'), ['original']);
    expect(ids('soop', 'sd'), ['sd']);
    expect(ids('soop', 'missing'), isEmpty);
  });

  test('other platforms and rooms without HD retain their available qualities', () {
    expect(ids('huya', null), ['original', 'hd4k', 'hd']);
    expect(ids('soop', null, qualities.take(1).toList()), ['original']);
    expect(ids('soop', null, []), isEmpty);
    expect(qualities.first.selectionId, 'original');
  });

  test('SOOP prefers the GS web CDN and falls back when it is absent', () {
    final lines = [
      LivePlayLine('https://example.com/primary.m3u8', lineId: 'gcp_cdn'),
      LivePlayLine('https://example.com/global.m3u8', lineId: 'gs_cdn_pc_web'),
    ];
    expect(initialLineIndex('soop', lines), 1);
    expect(initialLineIndex('soop', lines.take(1).toList()), 0);
    expect(initialLineIndex('huya', lines), 0);
  });

  test('forced HLS uses an owned loopback input while ordinary HLS stays direct', () async {
    final opener = MediaOpener();
    final source = LineSource(LivePlayLine('https://example.com/live.m3u8', format: StreamFormat.hls));
    final direct = await opener.open(source, site: 'soop');
    expect(direct.private, isFalse);
    final relayed = await opener.open(source, site: 'soop', forceHlsRelay: true);
    expect(relayed.private, isTrue);
    expect(relayed.uri.host, '127.0.0.1');
    expect(relayed.route, MediaRoute.hlsRelay);
    await direct.close();
    await relayed.close();
    await opener.close();
  });
}
