// Tests for persisted app settings.
//
// The store is mocked, so these run without a device. They pin the two promises
// that matter: a fresh install is on "Single reel", and a chosen mode survives a
// reload. A failed read must also fall back to the product default rather than
// silently switching to "Block reels".

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/core/settings/app_settings.dart';
import 'package:minimal_instagram/navigation/url_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a fresh install uses Single reel', () async {
    final AppSettings settings = await AppSettings.load();
    expect(settings.reelPolicy.value, ReelPolicy.allow);
  });

  test('an already-stored block choice is read back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reels_blocked': true,
    });

    final AppSettings settings = await AppSettings.load();
    expect(settings.reelPolicy.value, ReelPolicy.block);
  });

  test('changing the mode updates the notifier and persists it', () async {
    final AppSettings settings = await AppSettings.load();
    int notifications = 0;
    settings.reelPolicy.addListener(() => notifications++);

    await settings.setBlockReels(true);

    expect(settings.reelPolicy.value, ReelPolicy.block);
    expect(notifications, 1);
    expect(
      (await SharedPreferences.getInstance()).getBool('reels_blocked'),
      isTrue,
    );

    // A second, independent load sees the stored value.
    final AppSettings reloaded = await AppSettings.load();
    expect(reloaded.reelPolicy.value, ReelPolicy.block);
  });

  test('setting the same value does not notify again', () async {
    final AppSettings settings = await AppSettings.load();
    int notifications = 0;
    settings.reelPolicy.addListener(() => notifications++);

    await settings.setBlockReels(false);

    expect(notifications, 0);
  });
}
