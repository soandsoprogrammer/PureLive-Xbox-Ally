import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true);
  Map<String, Object> fields(Object rounds, {bool special = false}) => {
    'key': 'synthetic-key',
    'rand_str': 'synthetic-seed',
    'enc_data': 'synthetic-data',
    'enc_time': rounds,
    'expire_at': 1790003600,
    'is_special': special ? 1 : 0,
  };

  test('issue 15: larger signing rounds match independent Python MD5 vectors', () {
    // Expected hashes were generated with Python hashlib, not this signer.
    for (final (rounds, special, auth) in [
      (1, false, 'db531768f4f5fb04ac055e087c056389'),
      (1, true, '58c718e8c7665f6809f8bb56ea8baa22'),
      (16, false, '610e861708d55cc6078717fc3440f33f'),
      (16, true, 'ee5606fb40f8a303beceffbdc282a356'),
      (17, false, 'd149e79960528dcc2622c46ff9941e1b'),
      (17, true, '2660d9590f0c402237e664c0db4a7801'),
      (1000, false, 'ed67143ca0ebc66ed4ae01113773f555'),
      (1000, true, '4fd67eb495a371af171bf006e5b367a7'),
      (4096, false, '05ac066e51434c834cccd5d6ba523c1a'),
      (4096, true, '7640f4ab25bd81a3de865f50faeaed67'),
    ]) {
      final descriptor = DouyuApi.descriptor(
        jsonEncode({'error': 0, 'data': fields(rounds, special: special)}),
        now: now,
      );
      expect(descriptor.encTime, rounds);
      expect(descriptor.auth('24422', 1790000000), auth, reason: '$rounds / special=$special');
      expect(DouyuApi.signedForm(descriptor, roomId: '24422', tt: 1790000000, did: 'synthetic-device')['auth'], auth);
    }
  });

  test('issue 15: larger signing rounds accept integer strings and keep safety validation', () {
    final accepted = DouyuDescriptor.fromJson(fields('1000'));
    expect(accepted?.encTime, 1000);
    for (final rounds in [-1, 0, 4097, 1000000000]) {
      expect(
        () => DouyuApi.descriptor(jsonEncode({'error': 0, 'data': fields(rounds)}), now: now),
        throwsA(isA<ApiChanged>().having((failure) => failure.code, 'code', ApiFailureCode.douyuDescriptorRounds)),
      );
    }
    expect(DouyuDescriptor.fromJson(fields(1)..remove('key')), isNull);
    expect(DouyuDescriptor.fromJson(fields(1000)..remove('rand_str')), isNull);
    expect(
      () => DouyuApi.descriptor(jsonEncode({'error': 0, 'data': fields(1000)..['expire_at'] = 1790000000}), now: now),
      throwsA(isA<ApiChanged>().having((failure) => failure.code, 'code', ApiFailureCode.douyuDescriptorExpiry)),
    );
  });
}
