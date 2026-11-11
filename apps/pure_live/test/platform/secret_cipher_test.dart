@TestOn('linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/secret_cipher.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('secret_cipher_test'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('5.4.1: Linux has a secret store (5.0.0–5.4.0 stopped at "No secret store on linux")', () {
    expect(platformSecretCipher(folder), isA<KeyFileCipher>());
  });

  test('the key file cipher seals with AES-GCM, opens again, and the key file is for this user only', () async {
    final keyFile = File('${folder.path}/${KeyFileCipher.fileName}');
    final cipher = KeyFileCipher(keyFile);
    final sealed = await cipher.seal('cookie/bilibili', 'SESSDATA=abc; bili_jct=def');
    expect(sealed.first, 1, reason: 'AES-GCM format byte');
    expect(String.fromCharCodes(sealed), isNot(contains('SESSDATA')));
    expect(await cipher.open('cookie/bilibili', sealed), 'SESSDATA=abc; bili_jct=def');
    expect(keyFile.lengthSync(), 32);
    expect(keyFile.statSync().modeString(), 'rw-------');
    // Another cipher over the same key file (the next start) opens it too.
    expect(await KeyFileCipher(keyFile).open('cookie/bilibili', sealed), 'SESSDATA=abc; bili_jct=def');
  });

  test('a sealed value cannot be moved to another name, nor survive a changed byte', () async {
    final cipher = KeyFileCipher(File('${folder.path}/${KeyFileCipher.fileName}'));
    final sealed = await cipher.seal('cookie/douyu', 'acf_uid=1');
    await expectLater(cipher.open('cookie/huya', sealed), throwsStateError);
    final tampered = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
    await expectLater(cipher.open('cookie/douyu', tampered), throwsStateError);
  });

  test('without libcrypto the values are kept unencrypted (3.x) instead of the app not starting', () async {
    final keyFile = File('${folder.path}/${KeyFileCipher.fileName}');
    final plain = KeyFileCipher(keyFile, library: () => null);
    final sealed = await plain.seal('webdav/home', 'secret');
    expect(sealed.first, 0);
    expect(await plain.open('webdav/home', sealed), 'secret');
    expect(keyFile.existsSync(), isFalse);
    // With libcrypto back, the plain value still opens.
    expect(await KeyFileCipher(keyFile).open('webdav/home', sealed), 'secret');
  });
}
