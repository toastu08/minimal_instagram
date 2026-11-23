// End-to-end tests for the enforcement wiring, on a device, without Instagram.
//
// AGENTS.md §6 requires this shape: the app's real WebView wiring drives a local
// fixture site served by `InAppLocalhostServer`, never the live site, because the
// live site needs a login. Real Instagram is manual-only; this file covers the
// paths that can be automated: an allowed page, a blocked link, a blocked
// history change, a native load that slips past the URL override, the sign-up
// control that has no URL, and both reel modes.
//
// These tests assert on observable app behaviour (URL, banner, snackbar, page
// markers), not on implementation details, so a refactor that keeps the promise
// keeps them green.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:minimal_instagram/core/settings/app_settings.dart';
import 'package:minimal_instagram/navigation/url_policy.dart';
import 'package:minimal_instagram/webview/browser_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port the fixture server listens on. Must match `UrlPolicy.fixtureSite`.
const int _port = 8080;

/// Where the fixture inbox lives.
final Uri _inbox = Uri.parse('http://localhost:$_port/direct/inbox/');

/// One browser instance plus the controller, which is how the test drives the
/// page: Flutter cannot tap or read inside a platform view.
final class _Browser {
  _Browser(this.controller, this.settings);

  final InAppWebViewController controller;
  final AppSettings settings;

  Future<String> url() async {
    final WebUri? current = await controller.getUrl();
    return current?.toString() ?? '';
  }

  Future<String> path() async => Uri.tryParse(await url())?.path ?? '';

  Future<Object?> js(String source) =>
      controller.evaluateJavascript(source: source);

  /// Clicks an element inside the page the way a tap would.
  Future<void> click(String id) async {
    await js("document.getElementById('$id').click();");
  }

  /// The page's own marker, proving which fixture document is on screen.
  Future<String> marker() async {
    final Object? value = await js(
      'document.body ? document.body.getAttribute("data-test") : null',
    );
    return value?.toString() ?? '';
  }

  Future<Map<String, dynamic>> reelState() async {
    final Object? raw = await js('JSON.stringify(window.__miReelState())');
    return jsonDecode(raw?.toString() ?? '{}') as Map<String, dynamic>;
  }
}

/// Pumps until [condition] is true, or fails with [description].
///
/// A WebView load happens outside Flutter's frame loop, so `pumpAndSettle`
/// cannot see it. Polling the page through the controller is the only reliable
/// signal.
Future<void> _waitFor(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    // A page load can invalidate the JavaScript context mid-call, in which case
    // `evaluateJavascript` never answers. Bound every poll so a reload cannot
    // hang the test.
    final bool ready = await condition().timeout(
      const Duration(seconds: 2),
      onTimeout: () => false,
    );
    if (ready) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $description');
}

Future<void> _waitForText(WidgetTester tester, String text) => _waitFor(
  tester,
  () async => find.text(text).evaluate().isNotEmpty,
  description: 'the "$text" notice',
);

Future<void> _waitForMarker(
  WidgetTester tester,
  _Browser browser,
  String marker,
) => _waitFor(
  tester,
  () async => await browser.marker() == marker,
  description: 'the "$marker" fixture page',
);

/// Builds the browser against the fixture site.
///
/// [blockReels] flips the persisted setting before the screen exists, because
/// the policy and the document-start guard are both generated from it.
Future<_Browser> _pumpBrowser(
  WidgetTester tester, {
  bool blockReels = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final AppSettings settings = await AppSettings.load();
  if (blockReels) await settings.setBlockReels(true);

  final Completer<InAppWebViewController> ready =
      Completer<InAppWebViewController>();
  await tester.pumpWidget(
    MaterialApp(
      home: BrowserScreen(
        settings: settings,
        startUrl: _inbox,
        policy: UrlPolicy.fixtureSite(port: _port),
        onControllerReady: ready.complete,
      ),
    ),
  );

  // The screen loads the guard bundle asynchronously and only then builds the
  // WebView, and the live binding needs frames for that setState to take effect.
  await _waitFor(
    tester,
    () async => ready.isCompleted,
    description: 'the WebView to be created',
  );
  final InAppWebViewController controller = await ready.future;
  final _Browser browser = _Browser(controller, settings);
  await _waitForMarker(tester, browser, 'inbox');
  return browser;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final InAppLocalhostServer server = InAppLocalhostServer(
    port: _port,
    documentRoot: 'assets/test_site',
  );

  setUpAll(() async {
    await server.start();
  });

  tearDownAll(() async {
    await server.close();
  });

  testWidgets('the fixture inbox loads and the sanitizer hides new-message', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    expect(await browser.path(), '/direct/inbox/');
    expect(find.text('Not available in Minimal Instagram'), findsNothing);

    // The sanitizer runs from the same document-start bundle as the guard; this
    // proves the CSS reached the page.
    final Object? display = await browser.js(
      'getComputedStyle(document.getElementById("new-message")).display',
    );
    expect(display?.toString(), 'none');
  });

  testWidgets('an in-page link to a blocked surface is refused', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    await browser.click('explore');
    await _waitForText(tester, 'Not available in Minimal Instagram');

    // The URL never changed and the blocked document never rendered.
    expect(await browser.path(), '/direct/inbox/');
    expect(await browser.marker(), 'inbox');
  });

  testWidgets('a blocked history change is vetoed inside the page', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    await browser.js("history.pushState({}, '', '/explore/');");
    await _waitForText(tester, 'Not available in Minimal Instagram');

    expect(await browser.path(), '/direct/inbox/');
    expect(await browser.marker(), 'inbox');
  });

  testWidgets('a blocked native load is recovered from, not displayed', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    // An app-initiated load can bypass the URL-override callback; `onLoadStop`
    // is the last-resort guard and must put the user back on the inbox. The
    // wait covers the short window where the blocked document is loading.
    await browser.controller.loadUrl(
      urlRequest: URLRequest(url: WebUri('http://localhost:$_port/explore/')),
    );

    await _waitFor(
      tester,
      () async =>
          await browser.path() == '/direct/inbox/' &&
          await browser.marker() == 'inbox',
      description: 'the inbox to be restored',
    );
    expect(await browser.path(), '/direct/inbox/');
  });

  testWidgets('the sign-up backstop reloads the login page', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    // The fixture injects the sign-up markers once, then remembers it, so the
    // guard's reload lands on a clean login page instead of looping.
    await browser.js("sessionStorage.removeItem('mi-fixture-surface');");
    await browser.controller.loadUrl(
      urlRequest: URLRequest(
        url: WebUri('http://localhost:$_port/accounts/login/?surface=1'),
      ),
    );

    await _waitFor(
      tester,
      () async {
        final Object? flag = await browser.js(
          "sessionStorage.getItem('mi-fixture-surface')",
        );
        final Object? marker = await browser.js(
          'document.querySelector(\'input[type="tel"][aria-label="Mobile '
          'Number"]\') !== null',
        );
        return flag?.toString() == '1' && marker == false;
      },
      description:
          'the login page to reload after the sign-up markers appeared',
    );

    expect(await browser.path(), '/accounts/login/');
    expect(await browser.marker(), 'login');
  });

  testWidgets('the sign-up control is refused before the page handles it', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    await browser.click('login');
    await _waitForMarker(tester, browser, 'login');

    await browser.click('signup');
    await _waitForText(tester, 'Not available in Minimal Instagram');

    // The fixture reveals its sign-up form on click. It must stay hidden, and
    // the URL must not change: the flow has no URL of its own.
    final Object? hidden = await browser.js(
      'document.getElementById("signup-surface").hidden',
    );
    expect(hidden, isTrue);
    expect(await browser.path(), '/accounts/login/');
  });

  testWidgets('single-reel mode freezes the viewer and offers Close', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester);

    await browser.click('thread');
    await _waitForMarker(tester, browser, 'thread');

    await browser.click('open-reel');
    await _waitFor(
      tester,
      () async => find.text('Single reel').evaluate().isNotEmpty,
      description: 'the Single reel banner',
    );

    final Map<String, dynamic> state = await browser.reelState();
    expect(state['open'], isTrue);
    expect(state['policy'], 'allow');
    expect(state['frozen'], isTrue);
    expect(state['hiddenSlides'], 2);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await _waitForMarker(tester, browser, 'thread');
    await _waitFor(
      tester,
      () async => find.text('Single reel').evaluate().isEmpty,
      description: 'the banner to disappear',
    );
  });

  testWidgets('block-reels mode refuses the viewer and stays in the thread', (
    WidgetTester tester,
  ) async {
    final _Browser browser = await _pumpBrowser(tester, blockReels: true);

    expect(browser.settings.reelPolicy.value, ReelPolicy.block);

    await browser.click('thread');
    await _waitForMarker(tester, browser, 'thread');

    await browser.click('open-reel');
    await _waitForText(tester, 'Reels aren\'t available in this mode');

    // The viewer was closed by reloading the conversation, and the thread is
    // still the page on screen.
    await _waitForMarker(tester, browser, 'thread');
    expect(await browser.path(), '/direct/t/115950719795361/');
    expect(find.text('Single reel'), findsNothing);
  });
}
