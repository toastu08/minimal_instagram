// The settings sheet.
//
// Kept as a plain widget with callbacks rather than reaching into the WebView
// itself. That keeps both the destructive action and the reels preference
// testable without a platform channel, and it keeps the "what does this button
// do" logic next to the screen that owns the WebView.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../navigation/url_policy.dart';

/// Bottom sheet listing the app's settings.
class SettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const SettingsSheet({
    super.key,
    required this.reelPolicy,
    required this.onReelPolicyChanged,
    required this.onClearSession,
    required this.version,
  });

  /// The live reels preference. A listenable so the control updates itself when
  /// the choice changes, without turning the sheet into a stateful widget.
  final ValueListenable<ReelPolicy> reelPolicy;

  /// Applies a new reels preference. Persistence belongs to the caller.
  final ValueChanged<ReelPolicy> onReelPolicyChanged;

  /// Deletes cookies and site data, then returns to the login page.
  ///
  /// The sheet only asks for confirmation; the caller performs the deletion,
  /// because only the browser screen has the WebView controller.
  final Future<void> Function() onClearSession;

  /// Shown in the About block.
  final String version;

  Future<void> _confirmClearSession(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear session?'),
        content: const Text(
          'This signs you out of Instagram in this app and deletes its stored '
          'data. You will need to sign in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    // Close the sheet first: the caller is about to replace the page, and a
    // sheet floating over a login form looks like a bug.
    Navigator.of(context).pop();
    await onClearSession();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Text('Settings', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text('Reels', style: theme.textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                '“Single reel” opens a shared reel on its own. “Block reels” '
                'never opens one; use it if the single-reel viewer misbehaves.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ValueListenableBuilder<ReelPolicy>(
                valueListenable: reelPolicy,
                builder: (BuildContext context, ReelPolicy value, Widget? _) {
                  return SegmentedButton<ReelPolicy>(
                    segments: const <ButtonSegment<ReelPolicy>>[
                      ButtonSegment<ReelPolicy>(
                        value: ReelPolicy.allow,
                        label: Text('Single reel'),
                        icon: Icon(Icons.filter_none_rounded),
                      ),
                      ButtonSegment<ReelPolicy>(
                        value: ReelPolicy.block,
                        label: Text('Block reels'),
                        icon: Icon(Icons.block_rounded),
                      ),
                    ],
                    selected: <ReelPolicy>{value},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<ReelPolicy> selection) {
                      onReelPolicyChanged(selection.first);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Clear session'),
              subtitle: const Text(
                'Sign out and delete this app\'s Instagram data.',
              ),
              onTap: () => _confirmClearSession(context),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                'Minimal Instagram $version',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Text(
                'An unofficial viewer that shows only Instagram messages. It is '
                'not affiliated with Instagram or Meta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
