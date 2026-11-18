// Debug-only diagnostics screen.
//
// Two jobs:
//   1. Let a developer prove the guard works by trying to navigate to forbidden
//      URLs, through both enforcement layers (in-page click, native load).
//   2. Show the guard log and the current URL when something behaves oddly.
//
// It also doubles as a drift detector: "Compare" asks the Dart policy and the
// in-page rule copy what they think of the same URL. If the two disagree, the
// generated rules are stale and the JS guard is lying.
//
// This screen is only reachable from debug builds. It must never be linked from
// a release build.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/logging/guard_log.dart';
import '../../navigation/url_policy.dart';

/// Diagnostics and guard-testing screen.
class DebugScreen extends StatefulWidget {
  /// Creates the screen.
  const DebugScreen({
    super.key,
    required this.controller,
    required this.policy,
    required this.log,
    required this.currentUrl,
  });

  /// The live WebView controller.
  final InAppWebViewController controller;

  /// The policy in force.
  final UrlPolicy policy;

  /// The shared guard log.
  final GuardLog log;

  /// URL the browser was on when this screen opened.
  final String currentUrl;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final TextEditingController _input = TextEditingController();
  String _result = '';
  late String _url = widget.currentUrl;

  /// URLs worth testing by hand. Each one targets a different rule.
  static const List<String> _presets = <String>[
    'https://www.instagram.com/explore/',
    'https://www.instagram.com/reels/',
    'https://www.instagram.com/some_user/',
    'https://www.instagram.com/accounts/edit/',
    'https://www.instagram.com/stories/some_user/1234/',
    'https://www.instagram.com/direct/new/',
    'https://example.com/',
    'instagram://user?username=some_user',
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Builds a JavaScript snippet that clicks a real anchor with [url].
  ///
  /// Using an anchor rather than setting `location.href` means the request goes
  /// through exactly the same path a user tap would take.
  String _clickScript(String url) {
    return '(function(){'
        'var a=document.createElement("a");'
        'a.setAttribute("href", ${jsonEncode(url)});'
        'a.textContent="mi-test";'
        'a.style.display="none";'
        'document.body.appendChild(a);'
        'a.click();'
        'a.remove();'
        '})();';
  }

  Future<void> _accept(String url) async {
    setState(() => _input.text = url);
  }

  /// Asks Dart and the page to judge the same URL and compares the answers.
  Future<void> _compare() async {
    final String url = _input.text.trim();
    if (url.isEmpty) return;

    final UrlDecision dartDecision = widget.policy.decide(Uri.parse(url));
    String jsVerdict = '(no answer)';
    try {
      final Object? raw = await widget.controller.evaluateJavascript(
        source: 'String(window.__miDecide(${jsonEncode(url)}))',
      );
      jsVerdict = raw?.toString() ?? '(null)';
    } catch (error) {
      jsVerdict = 'error: $error';
    }

    final String dartVerdict = switch (dartDecision.verdict) {
      UrlVerdict.allow => 'allow',
      UrlVerdict.block => 'block',
      UrlVerdict.external => 'external',
      UrlVerdict.redirect => 'redirect',
    };

    setState(() {
      _result =
          'Dart: $dartVerdict (${dartDecision.reason})\n'
          'Page: $jsVerdict\n'
          '${dartVerdict == jsVerdict ? 'IN SYNC' : 'MISMATCH'}';
    });
  }

  Future<void> _clickTest() async {
    final String url = _input.text.trim();
    if (url.isEmpty) return;
    try {
      await widget.controller.evaluateJavascript(source: _clickScript(url));
      setState(() => _result = 'Injected an anchor click for:\n$url');
    } catch (error) {
      setState(() => _result = 'Injection failed: $error');
    }
  }

  Future<void> _nativeLoad() async {
    final String url = _input.text.trim();
    if (url.isEmpty) return;
    try {
      await widget.controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      setState(() => _result = 'Requested a native load of:\n$url');
    } catch (error) {
      setState(() => _result = 'Native load failed: $error');
    }
  }

  /// Asks the in-page sanitizer what it injected and which selectors matched.
  ///
  /// The report is the only way to tell "the sanitizer is working" apart from
  /// "the selector silently stopped matching". A count of 0 on a DM page for a
  /// page-specific rule is normal; -1 means the selector itself is invalid.
  Future<void> _sanitizerReport() async {
    try {
      final Object? raw = await widget.controller.evaluateJavascript(
        source:
            'JSON.stringify(window.__miSanitizerReport '
            '? window.__miSanitizerReport() : null)',
      );
      final String text = raw?.toString() ?? 'null';
      if (text == 'null') {
        setState(
          () => _result = 'The sanitizer is not installed on this page.',
        );
        return;
      }
      final Object? decoded = jsonDecode(text);
      setState(() {
        _result =
            'SANITIZER\n'
            '${const JsonEncoder.withIndent('  ').convert(decoded)}';
      });
    } catch (error) {
      setState(() => _result = 'Sanitizer report failed: $error');
    }
  }

  /// Asks the in-page reel guard what it currently sees.
  ///
  /// The in-DM viewer has no URL, so this is the only way to observe it from
  /// outside the page while testing focus mode.
  Future<void> _reelProbe() async {
    try {
      final Object? raw = await widget.controller.evaluateJavascript(
        source:
            'JSON.stringify((function(){try{'
            'return window.__miReelState ? window.__miReelState() : null;'
            '}catch(e){return {error: String(e)};}})())',
      );
      final String text = raw?.toString() ?? 'null';
      if (text == 'null') {
        setState(
          () => _result = 'The reel guard is not installed on this page.',
        );
        return;
      }
      final Object? decoded = jsonDecode(text);
      setState(() {
        _result =
            'REEL GUARD\n'
            '${const JsonEncoder.withIndent('  ').convert(decoded)}';
      });
    } catch (error) {
      setState(() => _result = 'Reel probe failed: $error');
    }
  }

  Future<void> _refreshUrl() async {
    final WebUri? url = await widget.controller.getUrl();
    setState(() => _url = url?.toString() ?? '(none)');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh URL',
            onPressed: _refreshUrl,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: widget.log.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('CURRENT URL', style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          SelectableText(_url, style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          TextField(
            controller: _input,
            decoration: const InputDecoration(
              labelText: 'URL to test',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _compare(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _compare,
                child: const Text('Compare'),
              ),
              FilledButton.tonal(
                onPressed: _clickTest,
                child: const Text('Click test'),
              ),
              FilledButton.tonal(
                onPressed: _nativeLoad,
                child: const Text('Native load'),
              ),
              FilledButton.tonal(
                onPressed: _sanitizerReport,
                child: const Text('Sanitizer'),
              ),
              FilledButton.tonal(
                onPressed: _reelProbe,
                child: const Text('Reel'),
              ),
            ],
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _result,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('PRESETS', style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String preset in _presets)
                ActionChip(
                  label: Text(
                    preset.replaceFirst('https://www.instagram.com', ''),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    _accept(preset);
                    _compare();
                  },
                ),
            ],
          ),
          const Divider(height: 32),
          AnimatedBuilder(
            animation: widget.log,
            builder: (BuildContext context, _) {
              final List<GuardEntry> entries = widget.log.entries.reversed
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'GUARD LOG (${entries.length})',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  if (entries.isEmpty)
                    Text(
                      'Nothing recorded yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  for (final GuardEntry entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
                        entry.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: entry.verdict == UrlVerdict.allow
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
