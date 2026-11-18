// A rolling in-memory record of every navigation decision.
//
// Purpose: when the app blocks something the user expected to work, or lets
// something through that it should not, we need evidence. Nothing here is ever
// sent anywhere; the log lives in memory and dies with the process.
//
// Debug builds only in practice (the debug screen is the only reader), but the
// class itself stays available so controllers do not need conditional logging.

import 'package:flutter/foundation.dart';

import '../../navigation/url_policy.dart';

/// One navigation decision.
@immutable
class GuardEntry {
  /// Creates an entry.
  const GuardEntry({
    required this.time,
    required this.url,
    required this.verdict,
    required this.reason,
    this.source = 'unknown',
  });

  /// When the decision was made.
  final DateTime time;

  /// The URL being judged.
  final String url;

  /// What the policy decided.
  final UrlVerdict verdict;

  /// Why the policy decided it.
  final String reason;

  /// Which enforcement layer produced this entry: `navigation`, `history`,
  /// `js`, `load` or `debug`.
  final String source;

  @override
  String toString() {
    final String stamp = time.toIso8601String().substring(11, 19);
    return '$stamp [$source] ${verdict.name} $url — $reason';
  }
}

/// Bounded, in-memory list of recent decisions.
class GuardLog extends ChangeNotifier {
  /// Creates a log holding at most [capacity] entries.
  GuardLog({this.capacity = 200});

  /// Maximum number of entries kept. Oldest are dropped first.
  final int capacity;

  final List<GuardEntry> _entries = <GuardEntry>[];

  /// Recent entries, oldest first.
  List<GuardEntry> get entries => List<GuardEntry>.unmodifiable(_entries);

  /// Whether anything has been recorded.
  bool get isEmpty => _entries.isEmpty;

  /// Records a decision. Allowed navigations are recorded too: knowing what the
  /// app *did* let through is as useful as knowing what it stopped.
  void add({
    required String url,
    required UrlVerdict verdict,
    required String reason,
    required String source,
  }) {
    _entries.add(
      GuardEntry(
        time: DateTime.now(),
        url: url,
        verdict: verdict,
        reason: reason,
        source: source,
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  /// Records a decision, skipping an identical repeat.
  ///
  /// Instagram fires the same navigation callback several times per transition
  /// (observed 3x in M0), which would otherwise drown the log.
  void addDeduplicated({
    required String url,
    required UrlVerdict verdict,
    required String reason,
    required String source,
  }) {
    if (_entries.isNotEmpty) {
      final GuardEntry last = _entries.last;
      if (last.url == url && last.verdict == verdict) return;
    }
    add(url: url, verdict: verdict, reason: reason, source: source);
  }

  /// Empties the log.
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
