// A17.9 c15: "扫码到手机", the one-off page on the network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/net/lan_address.dart';
import 'package:pure_live/shared/phone_bridge.dart';
import 'package:pure_live/tv/phone/tv_phone_server.dart';

Future<(int, String)> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  return (response.statusCode, await utf8.decoder.bind(response).join());
}

void main() {
  test('the address a phone reaches: private networks first, no loopback or link-local', () {
    expect(bestLanAddress(['127.0.0.1', '169.254.3.4', '172.20.0.5', '10.0.0.2', '192.168.1.9']), '192.168.1.9');
    expect(bestLanAddress(['127.0.0.1', '10.1.2.3']), '10.1.2.3');
    expect(bestLanAddress(['127.0.0.1', 'fe80::1']), '');
    expect(isIpv4('192.168.1.1'), isTrue);
    expect(isIpv4('192.168.1'), isFalse);
  });

  test('a form: only its random path answers; the phone sends the values once, escaped on the page', () async {
    final server = await TvPhoneServer.start(
      form: const PhoneInputRequest(
        title: '哔哩哔哩 · Cookie',
        fields: [PhoneInputField(key: 'cookie', label: 'Cookie', initial: 'a=<b>', multiline: true)],
      ),
      address: '127.0.0.1',
      bind: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    expect(server.url, matches(RegExp(r'^http://127\.0\.0\.1:\d+/[0-9a-f]{16}$')));
    final root = Uri.parse(server.url).replace(path: '/');
    expect((await _get(client, root.toString())).$1, HttpStatus.notFound);
    expect(server.opened, isFalse);

    final (status, page) = await _get(client, server.url);
    expect(status, HttpStatus.ok);
    expect(server.opened, isTrue);
    expect(page, contains('哔哩哔哩 · Cookie'));
    expect(page, contains('a=&lt;b&gt;'), reason: 'escaped');
    expect(page, contains('发送到电视'));

    final post = await client.postUrl(Uri.parse(server.url));
    post.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    post.write('cookie=${Uri.encodeQueryComponent('SESSDATA=x; bili_jct=y')}');
    final answer = await post.close();
    expect(await utf8.decoder.bind(answer).join(), contains('已发送到电视'));
    expect(await server.submitted, {'cookie': 'SESSDATA=x; bili_jct=y'});
  });

  test('a page of text shows it escaped', () async {
    final server = await TvPhoneServer.start(
      text: 'line 1\n<script>',
      title: '日志管理',
      address: '127.0.0.1',
      bind: InternetAddress.loopbackIPv4,
    );
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final (_, page) = await _get(client, server.url);
    expect(page, contains('日志管理'));
    expect(page, contains('line 1\n&lt;script&gt;'));
    expect(page, isNot(contains('<form')));
  });
}
