// Guardrails for the cosmetic sanitizer stylesheet.
//
// The stylesheet is the one place Instagram selectors may appear, and the rules
// in AGENTS.md are easy to break by accident: a generated class name such as
// `x1i10hfl` is tempting because it is what devtools shows. These tests fail
// the build instead of waiting for a deploy to break the UI.
//
// They read the stylesheet from disk rather than from the bundle because this is
// a source-level contract, not a rendering behavior.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File file = File('assets/css/hide_instagram_chrome.css');
  final String css = file.readAsStringSync();

  /// Every rule body removed, comments removed, quoted strings blanked out.
  /// What remains is selector text that can be inspected safely.
  String selectorText(String source) {
    final String withoutComments = source.replaceAll(
      RegExp(r'/\*[\s\S]*?\*/'),
      '',
    );
    final String withoutBodies = withoutComments.replaceAll(
      RegExp(r'\{[^}]*\}'),
      '{}',
    );
    // Attribute values may legitimately contain dots and hashes.
    final String withoutStrings = withoutBodies.replaceAll(
      RegExp(r'"[^"]*"'),
      '""',
    );
    return withoutStrings;
  }

  List<String> selectorsOf(String source) {
    final List<String> selectors = <String>[];
    final RegExp rule = RegExp(r'([^{}]+)\{\}');
    for (final RegExpMatch match in rule.allMatches(selectorText(source))) {
      for (final String part in match.group(1)!.split(',')) {
        final String selector = part.trim();
        if (selector.isEmpty || selector.startsWith('@')) continue;
        selectors.add(selector);
      }
    }
    return selectors;
  }

  test('the stylesheet exists and is registered as an asset', () {
    expect(file.existsSync(), isTrue);
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/css/'));
  });

  test('declares a sanitizer version', () {
    expect(
      RegExp(r'sanitizer-version:\s*\d+').hasMatch(css),
      isTrue,
      reason: 'AGENTS.md requires a version comment that gets bumped on change',
    );
  });

  test('uses only semantic attribute selectors', () {
    final List<String> selectors = selectorsOf(css);
    expect(selectors, isNotEmpty);

    for (final String selector in selectors) {
      expect(
        selector,
        matches(RegExp(r'\[(role|aria-|href|name)')),
        reason:
            'selector "$selector" does not target a semantic attribute; '
            'generated class names are not a stable contract',
      );
    }
  });

  test('never uses class or id selectors', () {
    final String text = selectorText(css);
    expect(
      text.contains('.'),
      isFalse,
      reason: 'class selectors are content-hashed by Instagram and change',
    );
    expect(
      text.contains('#'),
      isFalse,
      reason: 'id selectors do not exist in Instagram\'s DOM',
    );
  });

  test('never hides the DM top bar', () {
    final List<String> selectors = selectorsOf(css);
    for (final String selector in selectors) {
      expect(
        selector.contains('[role="navigation"]') ||
            selector.contains("[role='navigation']"),
        isFalse,
        reason:
            'on a DM page this element is Instagram\'s own top bar; see '
            'PROGRESS.md §2.3',
      );
    }
  });

  test('the hidden rule is scoped to the blocked composer', () {
    expect(css, contains('a[href\$="/direct/new/"]'));
  });
}
