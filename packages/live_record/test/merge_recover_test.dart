// H01.4: a process killed while recording leaves the segment being written
// without its journal row (FFmpeg writes a row when a segment is finished).
// Recovery joins it anyway; when FFmpeg refuses its cut-off end, it joins
// the finished segments and leaves that one next to the MP4. Outside
// recovery a missing row still fails closed.
import 'dart:io';

import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('merge_recover'));
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  String path(String name) => '${directory.path}/$name';
  void segment(int index, int bytes) =>
      File(path(SegmentClock.segmentName('p', index))).writeAsBytesSync(List.filled(bytes, 1));
  void journal(List<String> rows) =>
      File(path(SegmentClock.journalName('p'))).writeAsStringSync(rows.map((row) => '$row\n').join());
  List<String> names() => [for (final entity in directory.listSync()) entity.uri.pathSegments.last]..sort();

  const finished = ['p_000000.clock-v1.ts,0.000000,300.140000', 'p_000001.clock-v1.ts,300.167000,600.140000'];

  test('recovery joins the segment the kill left without a row, from where the last row ended', () async {
    segment(0, 1000);
    segment(1, 1000);
    segment(2, 500);
    journal(finished);
    final ffmpeg = FakeFfmpeg();
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p', openTail: true);
    expect(result.ok, isTrue);
    final manifest = ffmpeg.joinManifests.single;
    expect(manifest, contains('p_000002.clock-v1.ts'));
    // The second segment lasts up to the end of its row; the open one has
    // no duration (it plays to its own end).
    expect(manifest, contains('duration 299.973000'));
    expect(RegExp('duration').allMatches(manifest), hasLength(2));
    expect(names(), ['p.mp4']);
  });

  test('outside recovery a missing row still fails closed', () async {
    segment(0, 1000);
    segment(1, 1000);
    segment(2, 500);
    journal(finished);
    final result = await RecordMerger(FakeFfmpeg()).merge(directory: directory.path, filePrefix: 'p');
    expect(result.failure, MergeFailure.segmentClock);
  });

  test('killed in the first segment, before any row: the one segment joins', () async {
    segment(0, 1000);
    journal(const []);
    final ffmpeg = FakeFfmpeg();
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p', openTail: true);
    expect(result.ok, isTrue);
    expect(ffmpeg.joinManifests.single, contains('p_000000.clock-v1.ts'));
  });

  test('FFmpeg refusing the cut-off segment: the finished ones join and it stays', () async {
    segment(0, 1000);
    segment(1, 1000);
    segment(2, 500);
    journal(finished);
    final ffmpeg = FakeFfmpeg()..joinFails = (manifest) => manifest.contains('p_000002');
    final result = await RecordMerger(ffmpeg).merge(directory: directory.path, filePrefix: 'p', openTail: true);
    expect(result.ok, isTrue);
    expect(ffmpeg.joinManifests, hasLength(2));
    expect(ffmpeg.joinManifests.last, isNot(contains('p_000002')));
    expect(names(), ['p.mp4', 'p_000002.clock-v1.ts']);
  });

  test('more than one segment without a row is not a kill: it fails closed', () async {
    segment(0, 1000);
    segment(1, 1000);
    segment(2, 500);
    journal([finished.first]);
    final result = await RecordMerger(FakeFfmpeg()).merge(directory: directory.path, filePrefix: 'p', openTail: true);
    expect(result.ok, isFalse);
  });
}
