// A full-screen failure state for the browser.
//
// Deliberately plain: the user is here because something went wrong, so the
// screen explains what and offers exactly one action.

import 'package:flutter/material.dart';

/// What kind of failure the browser is showing.
enum FailureKind {
  /// The device appears to be offline or the host is unreachable.
  network,

  /// Instagram answered, but with a server error.
  server,
}

/// Explains a failure and offers a retry.
class ErrorView extends StatelessWidget {
  /// Creates the view.
  const ErrorView({
    super.key,
    required this.kind,
    required this.onRetry,
    this.detail,
  });

  /// Which failure to describe.
  final FailureKind kind;

  /// Called when the user taps Retry.
  final VoidCallback onRetry;

  /// Optional technical detail, shown small. Debug builds only in practice.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool offline = kind == FailureKind.network;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                offline ? 'No connection' : 'Instagram is unavailable',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                offline
                    ? 'Check your network and try again.'
                    : 'Instagram returned an error. Try again in a moment.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (detail != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
