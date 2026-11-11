// K01.3: every platform with an account entry signs in on its own page in
// the app (Bilibili has its own pages); the sign-in cookies decide when the
// login is taken.
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/platform_web_login.dart';
import 'package:pure_live/shared/in_app_web.dart';

void main() {
  test('every account platform but Bilibili has an official sign-in page, over https', () {
    for (final platform in accountPlatforms) {
      if (platform.id == SiteIds.bilibili) {
        expect(platformWebLogins.containsKey(platform.id), isFalse, reason: 'its own QR and web pages');
        continue;
      }
      final login = platformWebLogins[platform.id];
      expect(login, isNotNull, reason: platform.id);
      expect(login!.page.scheme, 'https', reason: platform.id);
      expect(login.domains, isNotEmpty, reason: platform.id);
      for (final domain in login.domains) {
        expect(siteDomain(domain.host), siteDomain(login.page.host), reason: '${platform.id}: ${domain.host}');
      }
    }
  });

  test("a sign-in cookie takes the login; a visitor's cookies do not", () {
    final douyu = platformWebLogins[SiteIds.douyu]!;
    expect(douyu.signedIn(['acf_did', 'dy_did']), isFalse);
    expect(douyu.signedIn(['acf_did', 'acf_auth']), isTrue);
    expect(platformWebLogins[SiteIds.douyin]!.signedIn(['ttwid', 'sessionid']), isTrue);
    expect(platformWebLogins[SiteIds.douyin]!.signedIn(['ttwid', '__ac_nonce']), isFalse);
    expect(platformWebLogins[SiteIds.twitch]!.signedIn(['unique_id', 'auth-token']), isTrue);
    // The pages whose sign-in opens from their header's "登录".
    expect(
      [
        for (final MapEntry(:key, :value) in platformWebLogins.entries)
          if (value.tapSignIn) key,
      ],
      [SiteIds.huya, SiteIds.douyin, SiteIds.cc],
    );
    // CC: only "已登录，保存".
    expect(platformWebLogins[SiteIds.cc]!.signedIn(['NTES_SESS']), isFalse);
  });

  test("the cookies of a whole site are cleared, not only the sign-in host's", () {
    expect(siteDomain('passport.douyu.com'), 'douyu.com');
    expect(siteDomain('www.huya.com'), 'huya.com');
    expect(siteDomain('aq.yy.com'), 'yy.com');
    expect(siteDomain('login.sooplive.co.kr'), 'sooplive.co.kr');
    expect(siteDomain('www.163.com'), '163.com');
    expect(siteDomain('douyu.com'), 'douyu.com');
  });

  test('without an in-app browser there is no official sign-in (Linux, tests)', () {
    InAppWeb.available = false;
    expect(hasPlatformWebLogin(SiteIds.douyu), isFalse);
    InAppWeb.available = true;
    addTearDown(() => InAppWeb.available = false);
    expect(hasPlatformWebLogin(SiteIds.douyu), isTrue);
    expect(hasPlatformWebLogin(SiteIds.bilibili), isFalse);
    expect(hasPlatformWebLogin('acfun'), isFalse);
  });
}
