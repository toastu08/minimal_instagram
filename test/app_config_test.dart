// The About/version block reads `AppConfig.version` rather than the pubspec at
// runtime (which would need another plugin). This test keeps the two honest.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/core/config/app_config.dart';

void main() {
  test('AppConfig.version matches the pubspec version', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec must declare a version');
    expect(AppConfig.version, match!.group(1));
  });
}
