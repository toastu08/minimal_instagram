// Tests for the app's security boundary.
//
// Every URL in SPEC.md §4.3 gets both a positive and a near-miss case: an
// allowed route must be allowed, and a lookalike must not sneak through. These
// are the highest-value tests in the project because `UrlPolicy` is what makes
// the product's promise true.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/navigation/instagram_routes.dart';
import 'package:minimal_instagram/navigation/url_policy.dart';

void main() {
  const UrlPolicy defaultPolicy = UrlPolicy();
  const UrlPolicy reelsAllowed = UrlPolicy(reelPolicy: ReelPolicy.allow);

  UrlDecision decide(String url, [UrlPolicy policy = defaultPolicy]) =>
      policy.decide(Uri.parse(url));

  void expectVerdict(String url, UrlVerdict verdict, {UrlPolicy? policy}) {
    expect(
      decide(url, policy ?? defaultPolicy).verdict,
      verdict,
      reason: 'expected $verdict for $url',
    );
  }

  group('allowed routes', () {
    const List<String> allowed = <String>[
      'https://www.instagram.com/direct/inbox/',
      'https://www.instagram.com/direct/inbox',
      'https://www.instagram.com/direct/requests/',
      'https://www.instagram.com/direct/t/115950719795361/',
      'https://www.instagram.com/direct/t/115950719795361',
      // Sign-in and recovery, including the 2FA hand-off observed in M0.
      'https://www.instagram.com/accounts/login/',
      'https://www.instagram.com/accounts/login/?next=%2Fdirect%2Finbox%2F',
      'https://www.instagram.com/accounts/password/reset/',
      'https://www.instagram.com/accounts/two_factor/',
      'https://www.instagram.com/accounts/onetap/',
      'https://www.instagram.com/auth_platform/?apc=AbC123',
      'https://www.instagram.com/auth_platform/codeentry/?apc=AbC123',
      // The 2FA step was renamed from `codeentry` to `afad` between M0 and
      // 2026-11-23; the whole `/auth_platform/` subtree is allowed (see B1).
      'https://www.instagram.com/auth_platform/afad/?apc=AbC123',
      // Security checkpoint: without it a flagged login can never finish.
      'https://www.instagram.com/challenge/1234567890/abc/',
      // Cookie consent interstitial, seen on a cold start (2026-11-23).
      'https://www.instagram.com/consent/?flow=user_cookie_choice_v2&source=pft_user_cookie_choice',
      'https://www.instagram.com/consent/',
      // A single post is one item by nature.
      'https://www.instagram.com/p/CxAbC123xyZ/',
      // Alternate Instagram hosts are the same app.
      'https://instagram.com/direct/inbox/',
      'https://m.instagram.com/direct/inbox/',
    ];

    for (final String url in allowed) {
      test(url, () => expectVerdict(url, UrlVerdict.allow));
    }
  });

  group('landing redirects', () {
    final UrlDecision root = decide('https://www.instagram.com/');
    test('root redirects to the inbox', () {
      expect(root.verdict, UrlVerdict.redirect);
      expect(root.target, InstagramRoutes.inbox);
    });

    test('root ignores the post-login query string (?deoia=1)', () {
      expect(
        decide('https://www.instagram.com/?deoia=1').verdict,
        UrlVerdict.redirect,
      );
    });

    test('root ignores a fragment', () {
      expect(
        decide('https://www.instagram.com/#x').verdict,
        UrlVerdict.redirect,
      );
    });

    test('legacy /direct/ redirects to the inbox', () {
      final UrlDecision decision = decide('https://www.instagram.com/direct/');
      expect(decision.verdict, UrlVerdict.redirect);
      expect(decision.target, InstagramRoutes.inbox);
    });
  });

  group('blocked routes', () {
    final Map<String, String> blocked = <String, String>{
      'https://www.instagram.com/explore/': 'explore feed',
      'https://www.instagram.com/explore/tags/cats/': 'tag feed',
      'https://www.instagram.com/reels/': 'reels feed',
      'https://www.instagram.com/toastu_/': 'profile',
      'https://www.instagram.com/toastu_/reels/': 'profile reels tab',
      'https://www.instagram.com/accounts/edit/': 'profile editing',
      'https://www.instagram.com/accounts/logout/':
          'Instagram-initiated logout',
      'https://www.instagram.com/accounts/signup/': 'sign up',
      'https://www.instagram.com/accounts/emailsignup/': 'sign up',
      'https://www.instagram.com/accounts/activity/': 'activity',
      'https://www.instagram.com/your_activity/': 'activity',
      'https://www.instagram.com/settings/': 'settings',
      'https://www.instagram.com/stories/highlights/1234/': 'story highlight',
      'https://www.instagram.com/stories/toastu_/1234/': 'story',
      'https://www.instagram.com/direct/new/': 'new-message composer',
      'https://www.instagram.com/direct/t/': 'thread with no id',
      'https://www.instagram.com/direct/t/abc/extra/': 'thread with extra path',
      'https://www.instagram.com/direct/reels/': 'DM reels surface',
      'https://www.instagram.com/consent-notice/': 'consent look-alike',
      'https://www.instagram.com/consent/extra/': 'consent sub-path',
      'https://www.instagram.com/auth_platform.evil/':
          'auth platform look-alike',
      'https://www.instagram.com/auth_platformx/': 'auth platform look-alike',
      'https://www.instagram.com/api/v1/users/': 'navigated API call',
      'https://example.com/direct/inbox/': 'off-site host',
      'https://www.instagram.com.evil.com/direct/inbox/': 'host suffix spoof',
      'https://www.instagram.com@evil.com/direct/inbox/': 'userinfo spoof',
      'https://l.instagram.com/?u=https%3A%2F%2Fexample.com': 'link shim',
      // Fail closed on unexpected casing and traversal.
      'https://www.instagram.com/Direct/Inbox/': 'wrong case',
      'https://www.instagram.com/accounts/../explore/': 'path traversal',
    };

    blocked.forEach((String url, String why) {
      test('$why — $url', () => expectVerdict(url, UrlVerdict.block));
    });

    test('a non-standard port is refused even on Instagram', () {
      expectVerdict(
        'https://www.instagram.com:8443/direct/inbox/',
        UrlVerdict.block,
      );
    });
  });

  group('reel permalinks', () {
    test('blocked by default', () {
      expectVerdict(
        'https://www.instagram.com/reel/CxAbC123xyZ/',
        UrlVerdict.block,
      );
      expectVerdict(
        'https://www.instagram.com/reels/CxAbC123xyZ/',
        UrlVerdict.block,
      );
    });

    test('allowed only when the policy permits it', () {
      expectVerdict(
        'https://www.instagram.com/reel/CxAbC123xyZ/',
        UrlVerdict.allow,
        policy: reelsAllowed,
      );
      expectVerdict(
        'https://www.instagram.com/reels/CxAbC123xyZ/',
        UrlVerdict.allow,
        policy: reelsAllowed,
      );
    });

    test(
      'the audio feed is not a single item, even when reels are allowed',
      () {
        expectVerdict(
          'https://www.instagram.com/reels/audio/1387594766486254/',
          UrlVerdict.block,
          policy: reelsAllowed,
        );
      },
    );
  });

  group('other applications', () {
    const List<String> foreign = <String>[
      'intent://instagram.com/#Intent;scheme=instagram;package=com.instagram.android;end',
      'instagram://user?username=toastu_',
      'fb://profile/123',
      'market://details?id=com.instagram.android',
      'mailto:someone@example.com',
      'tel:+15551234567',
      'whatsapp://send?text=hi',
      'about:blank',
      'javascript:alert(1)',
      'file:///etc/passwd',
    ];

    for (final String url in foreign) {
      test(url, () => expectVerdict(url, UrlVerdict.external));
    }
  });

  test('every URL the app builds is allowed by its own policy', () {
    final Map<String, Uri> built = <String, Uri>{
      'login': InstagramRoutes.login,
      'inbox': InstagramRoutes.inbox,
      'requests': InstagramRoutes.requests,
      'thread': InstagramRoutes.thread('115950719795361'),
      'post': InstagramRoutes.post('CxAbC123xyZ'),
    };

    built.forEach((String name, Uri uri) {
      final UrlDecision decision = defaultPolicy.decide(uri);
      expect(
        decision.verdict,
        UrlVerdict.allow,
        reason: 'the app must be able to navigate to its own $name URL',
      );
    });
  });

  test('decisions with the same outcome are equal', () {
    expect(
      const UrlDecision.block('blocked route: /explore'),
      const UrlDecision.block('blocked route: /explore'),
    );
    expect(const UrlDecision.block('a'), isNot(const UrlDecision.block('b')));
  });

  group('the in-page rule set is generated from the policy', () {
    final Map<String, dynamic> rules =
        jsonDecode(defaultPolicy.toGuardRulesJson()) as Map<String, dynamic>;

    test('carries the same hosts', () {
      expect(
        rules['hosts'],
        containsAll(<String>[
          'www.instagram.com',
          'instagram.com',
          'm.instagram.com',
        ]),
      );
    });

    test('carries the standard ports only', () {
      expect(rules['ports'], containsAll(<int>[80, 443]));
      expect(rules['ports'], hasLength(2));
    });

    test('carries the inbox the app starts at', () {
      expect(rules['inbox'], InstagramRoutes.inbox.toString());
    });

    test('carries the same allowed paths', () {
      expect(rules['allowedPaths'], contains('/direct/inbox'));
    });

    test('carries the auth platform prefix', () {
      expect(rules['authPlatformPrefix'], '/auth_platform');
    });

    test('carries the same patterns', () {
      expect(
        RegExp(rules['threadPattern'] as String)
            .hasMatch('/direct/t/115950719795361'),
        isTrue,
      );
      expect(
        RegExp(rules['postPattern'] as String).hasMatch('/p/CxAbC123xyZ'),
        isTrue,
      );
    });

    test('reflects the reel policy', () {
      expect(rules['reelPolicy'], 'block');
      final Map<String, dynamic> allowed =
          jsonDecode(reelsAllowed.toGuardRulesJson()) as Map<String, dynamic>;
      expect(allowed['reelPolicy'], 'allow');
    });
  });

  group('fixture site policy (integration tests only)', () {
    final UrlPolicy fixture = UrlPolicy.fixtureSite(port: 8080);

    test('allows the fixture inbox and conversation', () {
      expectVerdict(
        'http://localhost:8080/direct/inbox/',
        UrlVerdict.allow,
        policy: fixture,
      );
      expectVerdict(
        'http://127.0.0.1:8080/direct/t/115950719795361/',
        UrlVerdict.allow,
        policy: fixture,
      );
    });

    test('keeps the route rules: blocked surfaces stay blocked', () {
      expectVerdict(
        'http://localhost:8080/explore/',
        UrlVerdict.block,
        policy: fixture,
      );
      expectVerdict(
        'http://localhost:8080/accounts/emailsignup/',
        UrlVerdict.block,
        policy: fixture,
      );
    });

    test('only the configured port is reachable', () {
      expectVerdict(
        'http://localhost:8081/direct/inbox/',
        UrlVerdict.block,
        policy: fixture,
      );
    });

    test('other hosts are still refused', () {
      expectVerdict(
        'http://evil.example:8080/direct/inbox/',
        UrlVerdict.block,
        policy: fixture,
      );
      expectVerdict(
        'https://www.instagram.com/direct/inbox/',
        UrlVerdict.block,
        policy: fixture,
      );
    });

    test('the production policy cannot reach the fixture site', () {
      expectVerdict('http://localhost:8080/direct/inbox/', UrlVerdict.block);
    });

    test('the root redirects to the fixture inbox', () {
      final UrlDecision decision = fixture.decide(
        Uri.parse('http://localhost:8080/'),
      );
      expect(decision.verdict, UrlVerdict.redirect);
      expect(decision.target, Uri.parse('http://localhost:8080/direct/inbox/'));
      expect(fixture.home, Uri.parse('http://localhost:8080/direct/inbox/'));
    });

    test('the generated rules describe the fixture origin', () {
      final Map<String, dynamic> json =
          jsonDecode(fixture.toGuardRulesJson()) as Map<String, dynamic>;
      expect(json['hosts'], containsAll(<String>['localhost', '127.0.0.1']));
      expect(json['ports'], <int>[8080]);
      expect(json['inbox'], 'http://localhost:8080/direct/inbox/');
    });

    test('changing the reel mode preserves host and port rules', () {
      final UrlPolicy allowed = fixture.withReelPolicy(ReelPolicy.allow);
      expect(allowed.reelPolicy, ReelPolicy.allow);
      expectVerdict(
        'http://localhost:8080/direct/inbox/',
        UrlVerdict.allow,
        policy: allowed,
      );
      expectVerdict(
        'http://localhost:8081/direct/inbox/',
        UrlVerdict.block,
        policy: allowed,
      );
      expectVerdict(
        'http://localhost:8080/reel/CxAbC123xyZ/',
        UrlVerdict.allow,
        policy: allowed,
      );
    });

    test('the production policy still defaults to its own inbox', () {
      expect(defaultPolicy.home, InstagramRoutes.inbox);
    });
  });
}
