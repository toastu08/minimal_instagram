// The settings sheet.
//
// Kept as a plain widget with callbacks rather than reaching into the WebView
// itself. That keeps the destructive action testable without a platform channel,
// and it keeps the "what does this button do" logic next to the screen that owns
// the WebView.
//
// Only actions that exist are listed. The reels preference arrives in M6, when it
// has somewhere to persist.

import 'package:flutter/material.dart';

/// Bottom sheet listing the app's settings.
class SettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const SettingsSheet({super.key, required this.onClearSession});

  /// Deletes cookies and site data, then returns to the login page.
  ///
  /// The sheet only asks for confirmation; the caller performs the deletion,
  /// because only the browser screen has the WebView controller.
  final Future<void> Function() onClearSession;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text('Settings', style: theme.textTheme.titleMedium),
          ),
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
            child: Text('Minimal Instagram', style: theme.textTheme.bodyMedium),
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
    );
  }
}
