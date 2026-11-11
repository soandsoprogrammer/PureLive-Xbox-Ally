import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pure_live/shared/net/lan_address.dart';
import 'package:pure_live/shared/phone_bridge.dart';

/// A one-off page on this network for a phone (A17.9 c15): a form whose
/// values come back as [submitted], or a page of text. It answers only at
/// a random path, from this network, and stops after a form is sent or
/// when [close]d.
final class TvPhoneServer {
  new _(this._server, this.url, this._token, {this.form, this.text, this.title = ''});

  /// Starts serving [form] (or [text] under [title]); [address] and [bind]
  /// are for tests.
  static Future<TvPhoneServer> start({
    PhoneInputRequest? form,
    String? text,
    String title = '',
    String? address,
    InternetAddress? bind,
  }) async {
    final server = await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
    final host = address ?? bestLanAddress(await localIpv4Addresses());
    final random = Random.secure();
    final token = [for (var i = 0; i < 8; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    final url = 'http://${host.isEmpty ? '127.0.0.1' : host}:${server.port}/$token';
    final phone = TvPhoneServer._(server, url, token, form: form, text: text, title: title);
    server.listen(phone._handle, onError: (_) {});
    return phone;
  }

  final HttpServer _server;
  final String _token;

  /// The address the phone opens.
  final String url;

  /// The form, if any.
  final PhoneInputRequest? form;

  /// The text shown, if any.
  final String? text;

  /// The text page's title.
  final String title;

  final Completer<Map<String, String>> _submitted = Completer();

  /// The values sent from the phone.
  Future<Map<String, String>> get submitted => _submitted.future;

  /// Whether a phone has opened the page.
  bool opened = false;

  /// Stops answering.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    try {
      if (request.uri.path != '/$_token') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method == 'POST' && form != null && !_submitted.isCompleted) {
        final body = await utf8.decoder.bind(request).join();
        final values = Uri.splitQueryString(body);
        _submitted.complete({for (final field in form!.fields) field.key: values[field.key] ?? ''});
        _page(response, '<p class="done">已发送到电视，可以回到电视上了。</p>');
        unawaited(Future<void>.delayed(const Duration(seconds: 1), close));
        return;
      }
      opened = true;
      if (form case final form?) {
        _page(response, _formHtml(form));
      } else {
        _page(response, '<h1>${_escape(title)}</h1><pre>${_escape(text ?? '')}</pre>');
      }
    } finally {
      await response.close();
    }
  }

  static void _page(HttpResponse response, String body) {
    response.headers.contentType = ContentType.html;
    const style = [
      'body{font:16px/1.5 system-ui,sans-serif;margin:0;padding:16px;background:#111;color:#eee}',
      'h1{font-size:20px}label{display:block;margin:16px 0 6px;color:#bbb}',
      'input,textarea{box-sizing:border-box;width:100%;padding:10px;border-radius:8px;border:1px solid #444;',
      'background:#1c1c1c;color:#eee;font:inherit}textarea{min-height:160px}',
      'button{margin-top:20px;width:100%;padding:12px;border:0;border-radius:24px;background:#2E6FE0;',
      'color:#fff;font:inherit}pre{white-space:pre-wrap;word-break:break-all;font-size:13px}.done{font-size:18px}',
    ];
    response.write(
      [
        '<!doctype html><html lang="zh"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<title>纯粹直播</title><style>${style.join()}</style></head><body>$body</body></html>',
      ].join(),
    );
  }

  static String _formHtml(PhoneInputRequest form) {
    final fields = StringBuffer();
    for (final field in form.fields) {
      final name = _escape(field.key);
      fields.write('<label for="$name">${_escape(field.label)}</label>');
      if (field.multiline) {
        fields.write(
          '<textarea id="$name" name="$name" placeholder="${_escape(field.hint)}">${_escape(field.initial)}</textarea>',
        );
      } else {
        fields.write(
          '<input id="$name" name="$name" value="${_escape(field.initial)}" placeholder="${_escape(field.hint)}">',
        );
      }
    }
    final note = form.note == null ? '' : '<p>${_escape(form.note!)}</p>';
    return '<h1>${_escape(form.title)}</h1>$note<form method="post">$fields<button>发送到电视</button></form>';
  }

  static String _escape(String text) => const HtmlEscape().convert(text);
}
