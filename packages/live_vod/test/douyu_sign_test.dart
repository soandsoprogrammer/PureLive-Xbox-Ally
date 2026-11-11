import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

const _fixture = '../../fixtures/douyu/vod/S01-public-sign';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('$_fixture/$name.json').readAsStringSync()) as Map<String, dynamic>;

// Reconstruct only the descriptor's integer-data envelope, without retaining
// or running the original website's JavaScript. The encrypted words, permitted
// mutations and independently computed expectation have recorded provenance.
String _descriptor() {
  final data = _read('body');
  String array(String field) => (data[field] as List).join(',');
  String hex(String field) => '0x${(data[field] as int).toRadixString(16)}';
  final count = (data['words'] as List).length;
  return 'var words=[${array('words')}];function ub98484234(a,b,c){ '
      'var rk=[${array('rounds')}];var k=[${array('key')}];var k2=[${array('xorKey')}];var lk=[${array('lookup')}]; '
      'var v=words.slice(0);for(var O=0;O<$count;O++){v[O]^=${hex('mask')};}'
      '${(data['mutations'] as List).join(';')};'
      'for(var I=0;I<$count;I+=2){}v[0]^=${hex('finalMask')};var strc="";return strc;}';
}

void main() {
  test('data-only daily descriptor matches independent server-checked algorithm vector', () {
    final expected = _read('expected');
    final input = expected['input'] as Map;
    final signer = DouyuVodSigner.fromScript(_descriptor());
    final form = signer.form(
      pointId: input['pointId'] as String,
      videoId: input['videoId'] as String,
      did: input['did'] as String,
      seconds: input['seconds'] as int,
    );
    expect(form, expected['form']);
  });

  test('unknown operations, missing fields and oversized scripts fail without a JS runtime', () {
    final script = _descriptor();
    final injected = script.replaceFirst(RegExp(r'v\[\d+\][+\-^]=lk\[\d+\];'), 'v[0]=fetch();');
    expect(injected, isNot(script));
    for (final source in [injected, 'function ub98484234(){return eval("unknown");}', 'x' * 131073]) {
      expect(() => DouyuVodSigner.fromScript(source), throwsA(isA<ApiChanged>()));
    }
  });
}
