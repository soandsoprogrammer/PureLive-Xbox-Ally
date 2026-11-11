import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// The platform's [SecretCipher]: the Android Keystore, the Apple Keychain,
/// Windows DPAPI, or on Linux a key file in [dataRoot]. Before 5.4.1 Linux
/// had none and the app could not start there ("No secret store on linux").
SecretCipher platformSecretCipher(Directory dataRoot) {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return NativeChannelCipher();
  if (Platform.isWindows) return WindowsDpapiCipher();
  return KeyFileCipher(File(p.join(dataRoot.path, KeyFileCipher.fileName)));
}

/// AES-256-GCM in native code over channel `pure_live/secret_cipher`: under a
/// non-exportable Android Keystore key (`AppChannelsPlugin.kt`), or under a
/// key kept in the Apple Keychain (`SecretCipher.swift`, iOS and macOS). The
/// secret's name is the associated data.
final class NativeChannelCipher implements SecretCipher {
  /// Creates the cipher over [channel].
  new({this.channel = const MethodChannel('pure_live/secret_cipher')});

  /// The native channel.
  final MethodChannel channel;

  @override
  Future<Uint8List> seal(String ref, String plain) async {
    final sealed = await channel.invokeMethod<Uint8List>('seal', {'ref': ref, 'plain': plain});
    if (sealed == null) throw StateError('Keystore returned nothing');
    return sealed;
  }

  @override
  Future<String> open(String ref, Uint8List sealed) async {
    final plain = await channel.invokeMethod<String>('open', {'ref': ref, 'sealed': sealed});
    if (plain == null) throw StateError('Keystore returned nothing');
    return plain;
  }
}

/// Windows DPAPI (`CryptProtectData`, current user): only this Windows
/// account can open the values; the secret's name is the entropy, so a value
/// cannot be moved to another name.
final class WindowsDpapiCipher implements SecretCipher {
  @override
  Future<Uint8List> seal(String ref, String plain) async =>
      _dpapi(Uint8List.fromList(utf8.encode(plain)), ref, protect: true);

  @override
  Future<String> open(String ref, Uint8List sealed) async => utf8.decode(_dpapi(sealed, ref, protect: false));
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

// CRYPTPROTECT_UI_FORBIDDEN: never show a prompt.
const int _uiForbidden = 0x1;

Uint8List _dpapi(Uint8List input, String ref, {required bool protect}) {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final call = crypt32.lookupFunction<_CryptNative, _CryptDart>(protect ? 'CryptProtectData' : 'CryptUnprotectData');
  final localFree = kernel32
      .lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  final entropyBytes = utf8.encode(ref);
  return using((arena) {
    Pointer<_DataBlob> blob(List<int> bytes) {
      final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      return arena<_DataBlob>()
        ..ref.cbData = bytes.length
        ..ref.pbData = data;
    }

    final output = arena<_DataBlob>();
    final ok = call(blob(input), nullptr, blob(entropyBytes), nullptr, nullptr, _uiForbidden, output);
    if (ok == 0) throw StateError('DPAPI ${protect ? 'protect' : 'unprotect'} failed');
    try {
      return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
    } finally {
      localFree(output.ref.pbData.cast());
    }
  });
}

/// AES-256-GCM through the system's OpenSSL (`libcrypto`) under a random key
/// kept in [keyFile] (only this user may read it), for Linux, which has no
/// key store every desktop shares. The secret's name is the associated data.
/// Sealed values start with a format byte: [_aesGcm], or [_plain] when no
/// `libcrypto` could be loaded — then the values are kept as 3.x kept them,
/// unencrypted, instead of the app not starting.
final class KeyFileCipher implements SecretCipher {
  /// Creates the cipher over [keyFile]; [library] opens `libcrypto` (tests
  /// pass a failing one).
  new(this.keyFile, {DynamicLibrary? Function()? library}) : _library = library ?? _openLibcrypto;

  /// The key file's name in the data folder.
  static const fileName = 'secret.key';

  /// Where the key is kept.
  final File keyFile;

  final DynamicLibrary? Function() _library;
  late final _OpenSsl? _ssl = _sslOf(_library());
  Uint8List? _key;

  static const int _plain = 0;
  static const int _aesGcm = 1;
  static const int _ivLength = 12;
  static const int _tagLength = 16;

  @override
  Future<Uint8List> seal(String ref, String plain) async {
    final bytes = Uint8List.fromList(utf8.encode(plain));
    final ssl = _ssl;
    if (ssl == null) return Uint8List.fromList([_plain, ...bytes]);
    final iv = _random(_ivLength);
    final sealed = ssl.gcm(encrypt: true, key: await _keyBytes(), iv: iv, aad: utf8.encode(ref), input: bytes);
    return Uint8List.fromList([_aesGcm, ...iv, ...sealed]);
  }

  @override
  Future<String> open(String ref, Uint8List sealed) async {
    if (sealed.isEmpty) throw const FormatException('Empty secret');
    switch (sealed.first) {
      case _plain:
        return utf8.decode(sealed.sublist(1));
      case _aesGcm:
        final ssl = _ssl;
        if (ssl == null) throw StateError('libcrypto is not available');
        if (sealed.length < 1 + _ivLength + _tagLength) throw const FormatException('Short secret');
        final iv = sealed.sublist(1, 1 + _ivLength);
        final body = sealed.sublist(1 + _ivLength);
        return utf8.decode(ssl.gcm(encrypt: false, key: await _keyBytes(), iv: iv, aad: utf8.encode(ref), input: body));
      default:
        throw FormatException('Unknown secret format ${sealed.first}');
    }
  }

  /// The key: read from [keyFile], or made and written there (mode 600)
  /// the first time.
  Future<Uint8List> _keyBytes() async {
    final known = _key;
    if (known != null) return known;
    if (keyFile.existsSync()) {
      final bytes = await keyFile.readAsBytes();
      if (bytes.length == 32) return _key = bytes;
      throw StateError('The key file ${keyFile.path} is damaged');
    }
    final key = _random(32);
    await keyFile.parent.create(recursive: true);
    final temporary = File('${keyFile.path}.new');
    await temporary.writeAsBytes(key, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', temporary.path]);
    await temporary.rename(keyFile.path);
    return _key = key;
  }

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < length; i++) random.nextInt(256)]);
  }

  static DynamicLibrary? _openLibcrypto() {
    for (final name in ['libcrypto.so.3', 'libcrypto.so.1.1', 'libcrypto.so']) {
      try {
        return DynamicLibrary.open(name);
      } on Object {
        // The next name.
      }
    }
    return null;
  }

  static _OpenSsl? _sslOf(DynamicLibrary? library) {
    if (library == null) return null;
    try {
      return _OpenSsl(library);
    } on Object {
      return null;
    }
  }
}

typedef _CtxNew = Pointer<Void> Function();
typedef _CtxFreeNative = Void Function(Pointer<Void>);
typedef _CtxFree = void Function(Pointer<Void>);
typedef _Cipher = Pointer<Void> Function();
typedef _InitNative = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>);
typedef _Init = int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>);
typedef _UpdateNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Uint8>, Int32);
typedef _Update = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Uint8>, int);
typedef _FinalNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>);
typedef _Final = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>);
typedef _CtrlNative = Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Void>);
typedef _Ctrl = int Function(Pointer<Void>, int, int, Pointer<Void>);

/// The EVP calls of OpenSSL's AES-256-GCM.
final class _OpenSsl {
  new(DynamicLibrary library)
    : _new = library.lookupFunction<_CtxNew, _CtxNew>('EVP_CIPHER_CTX_new'),
      _free = library.lookupFunction<_CtxFreeNative, _CtxFree>('EVP_CIPHER_CTX_free'),
      _aes256Gcm = library.lookupFunction<_Cipher, _Cipher>('EVP_aes_256_gcm'),
      _encryptInit = library.lookupFunction<_InitNative, _Init>('EVP_EncryptInit_ex'),
      _decryptInit = library.lookupFunction<_InitNative, _Init>('EVP_DecryptInit_ex'),
      _encryptUpdate = library.lookupFunction<_UpdateNative, _Update>('EVP_EncryptUpdate'),
      _decryptUpdate = library.lookupFunction<_UpdateNative, _Update>('EVP_DecryptUpdate'),
      _encryptFinal = library.lookupFunction<_FinalNative, _Final>('EVP_EncryptFinal_ex'),
      _decryptFinal = library.lookupFunction<_FinalNative, _Final>('EVP_DecryptFinal_ex'),
      _ctrl = library.lookupFunction<_CtrlNative, _Ctrl>('EVP_CIPHER_CTX_ctrl');

  final _CtxNew _new;
  final _CtxFree _free;
  final _Cipher _aes256Gcm;
  final _Init _encryptInit;
  final _Init _decryptInit;
  final _Update _encryptUpdate;
  final _Update _decryptUpdate;
  final _Final _encryptFinal;
  final _Final _decryptFinal;
  final _Ctrl _ctrl;

  // EVP_CTRL_GCM_GET_TAG, EVP_CTRL_GCM_SET_TAG.
  static const int _getTag = 0x10;
  static const int _setTag = 0x11;

  /// Encrypts [input] (giving ciphertext and tag) or decrypts it (ciphertext
  /// then tag; throws when the tag does not match).
  Uint8List gcm({
    required bool encrypt,
    required Uint8List key,
    required Uint8List iv,
    required List<int> aad,
    required Uint8List input,
  }) {
    const tagLength = KeyFileCipher._tagLength;
    final body = encrypt ? input : input.sublist(0, input.length - tagLength);
    final ctx = _new();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');
    try {
      return using((arena) {
        Pointer<Uint8> copy(List<int> bytes) {
          final pointer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
          pointer.asTypedList(bytes.length).setAll(0, bytes);
          return pointer;
        }

        void check(int result, String call) {
          if (result != 1) throw StateError('$call failed');
        }

        final length = arena<Int32>();
        final out = arena<Uint8>(body.length + 32);
        final init = encrypt ? _encryptInit : _decryptInit;
        final update = encrypt ? _encryptUpdate : _decryptUpdate;
        check(init(ctx, _aes256Gcm(), nullptr, copy(key), copy(iv)), 'init');
        check(update(ctx, nullptr, length, copy(aad), aad.length), 'aad');
        check(update(ctx, out, length, copy(body), body.length), 'update');
        var written = length.value;
        if (!encrypt) {
          final tag = copy(input.sublist(input.length - tagLength));
          check(_ctrl(ctx, _setTag, tagLength, tag.cast()), 'set tag');
        }
        final finish = encrypt ? _encryptFinal : _decryptFinal;
        if (finish(ctx, out + written, length) != 1) {
          throw StateError(encrypt ? 'final failed' : 'The secret does not match its key or name');
        }
        written += length.value;
        final result = Uint8List.fromList(out.asTypedList(written));
        if (!encrypt) return result;
        final tag = arena<Uint8>(tagLength);
        check(_ctrl(ctx, _getTag, tagLength, tag.cast()), 'get tag');
        return Uint8List.fromList([...result, ...tag.asTypedList(tagLength)]);
      });
    } finally {
      _free(ctx);
    }
  }
}
