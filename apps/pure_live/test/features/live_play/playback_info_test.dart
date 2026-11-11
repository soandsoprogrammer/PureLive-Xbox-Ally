import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/playback_info.dart';

import '../../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadStrings();
  });

  group('A07.33: playback information', () {
    test('the nine rows show the mpv snapshot and the session values', () {
      final info = playbackInfoOf(
        state: const PlaybackState(
          frameRate: 60,
          line: LivePlayLine('https://cn-zjjh-ct-04-05.bilivideo.com/live/a.flv?token=secret'),
        ),
        stats: const PlaybackStats(
          width: 2560,
          height: 1440,
          videoFormat: 'hevc',
          videoCodec: 'hevc (Main) / H.265',
          encoder: 'obs-output module (libobs version 32.2.1)',
          sampleRate: 48000,
          channels: 2,
          audioBitrate: 160000,
          audioCodec: 'aac (LC)',
          droppedFrames: 2,
          decodedFrames: 503,
          bufferSeconds: 6.4,
          downloadBytesPerSecond: 375000,
          mpvVersion: 'mpv 0.41.0',
          ffmpegVersion: '9.0.2',
        ),
      );
      final values = {for (final row in info.rows) row.id: row.value};
      expect(values, {
        'resolution': '2560 × 1440',
        'frame-rate': '60.0 fps',
        'codec': 'H.265',
        'encoder': 'obs-output module (libobs version 32.2.1)',
        'audio': '48 kHz · 立体声 · 160 kbps',
        'frames': '2 / 503',
        'buffer': '6.40 s',
        'download': '3.0 Mbps',
        'host': 'cn-zjjh-ct-04-05.bilivideo.com',
      });
      expect(info.rows, hasLength(9));
      expect(info.playerCore, 'mpv 0.41.0 · FFmpeg 9.0.2');
      expect(info.rows.firstWhere((row) => row.id == 'encoder').multiline, isTrue);
    });

    test('missing values are “—” and the download override wins', () {
      final info = playbackInfoOf(state: const PlaybackState(), stats: null, downloadBytesPerSecond: 125000);
      final values = {for (final row in info.rows) row.id: row.value};
      expect(values['resolution'], '—');
      expect(values['frame-rate'], '—');
      expect(values['codec'], '—');
      expect(values['encoder'], '—');
      expect(values['audio'], '—');
      expect(values['frames'], '—');
      expect(values['buffer'], '—');
      expect(values['download'], '1.0 Mbps');
      expect(values['host'], '—');
      expect(info.playerCore, isNull);
      expect(info.videoCodec, isNull);
      expect(info.audioCodec, isNull);
    });

    test('formatting covers codecs, sample rates, channels, bitrate and hosts', () {
      expect(formatPlaybackCodec('h264'), 'H.264');
      expect(formatPlaybackCodec('hevc'), 'H.265');
      expect(formatPlaybackCodec('av1'), 'AV1');
      expect(formatPlaybackCodec('mpeg4'), 'MPEG4');
      expect(formatPlaybackCodec(''), '—');
      expect(formatPlaybackSize(0, 1080), '—');
      expect(formatPlaybackFps(59.94), '59.9 fps');
      expect(formatPlaybackFps(0), '—');
      expect(formatPlaybackSampleRate(44100), '44.1 kHz');
      expect(formatPlaybackSampleRate(48000), '48 kHz');
      expect(formatPlaybackChannels(1), '单声道');
      expect(formatPlaybackChannels(2), '立体声');
      expect(formatPlaybackChannels(6), '6 声道');
      expect(formatPlaybackAudioBitrate(160000), '160 kbps');
      expect(formatPlaybackDownload(375000), '3.0 Mbps');
      expect(formatPlaybackDownload(0), '—');
      expect(formatPlaybackBuffer(1.984), '1.98 s');
      expect(formatPlaybackHost(const LivePlayLine('https://a.example/live.flv?token=secret')), 'a.example');
      expect(formatPlaybackHost(const LivePlayLine('http://127.0.0.1:8080/live.flv')), '本机中继');
      expect(formatPlaybackHost(null), '—');
    });

    test('the copied text has no stream address, query, Cookie or header', () {
      final info = playbackInfoOf(
        state: const PlaybackState(frameRate: 60, line: LivePlayLine('https://a.example/live.flv?token=secret')),
        stats: const PlaybackStats(
          width: 1920,
          height: 1080,
          videoFormat: 'h264',
          videoCodec: 'h264 (High)',
          encoder: 'obs-output module',
          sampleRate: 48000,
          channels: 2,
          audioBitrate: 128000,
          audioCodec: 'aac',
          mpvVersion: 'mpv 0.41.0',
        ),
      );
      expect(info.copyText, contains('编码器: obs-output module'));
      expect(info.copyText, contains('视频编码详情: h264 (High)'));
      expect(info.copyText, contains('音频编码详情: aac'));
      expect(info.copyText, contains('播放器内核: mpv 0.41.0'));
      expect(info.copyText, isNot(contains('token')));
      expect(info.copyText, isNot(contains('Cookie')));
      expect(info.copyText, isNot(contains('https://')));
    });
  });
}
