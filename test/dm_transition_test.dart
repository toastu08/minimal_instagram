// Tests for the inbox <-> conversation transition classifier.
//
// The motion layer only animates when this returns forward or back; everything
// else must be none, so a reload, a sibling surface or a refusal never plays a
// slide. The final group pins the path shapes to UrlPolicy so the classifier
// cannot drift from the route table.

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_instagram/navigation/dm_transition.dart';
import 'package:minimal_instagram/navigation/url_policy.dart';

void main() {
  DmTransition classify(String from, String to) =>
      classifyDmTransition(Uri.parse(from), Uri.parse(to));

  group('forward: inbox-level -> conversation', () {
    const List<List<String>> pairs = <List<String>>[
      <String>[
        'https://www.instagram.com/direct/inbox/',
        'https://www.instagram.com/direct/t/115950719795361/',
      ],
      <String>[
        'https://www.instagram.com/direct/requests/',
        'https://www.instagram.com/direct/t/115950719795361/',
      ],
      // Instagram omits the trailing slash; query and fragment are ignored.
      <String>[
        'https://www.instagram.com/direct/inbox',
        'https://www.instagram.com/direct/t/115950719795361?foo=1',
      ],
    ];

    for (final List<String> pair in pairs) {
      test('${pair[0]} -> ${pair[1]}', () {
        expect(classify(pair[0], pair[1]), DmTransition.forward);
      });
    }
  });

  group('back: conversation -> inbox-level', () {
    const List<List<String>> pairs = <List<String>>[
      <String>[
        'https://www.instagram.com/direct/t/115950719795361/',
        'https://www.instagram.com/direct/inbox/',
      ],
      <String>[
        'https://www.instagram.com/direct/t/115950719795361',
        'https://www.instagram.com/direct/requests/?x=1',
      ],
    ];

    for (final List<String> pair in pairs) {
      test('${pair[0]} -> ${pair[1]}', () {
        expect(classify(pair[0], pair[1]), DmTransition.back);
      });
    }
  });

  group('none: everything else', () {
    const List<List<String>> pairs = <List<String>>[
      // Same level.
      <String>[
        'https://www.instagram.com/direct/inbox/',
        'https://www.instagram.com/direct/inbox/',
      ],
      <String>[
        'https://www.instagram.com/direct/inbox/',
        'https://www.instagram.com/direct/requests/',
      ],
      <String>[
        'https://www.instagram.com/direct/t/111/',
        'https://www.instagram.com/direct/t/222/',
      ],
      // A reload of either surface must not play.
      <String>[
        'https://www.instagram.com/direct/t/115950719795361/',
        'https://www.instagram.com/direct/t/115950719795361/',
      ],
      // Another surface.
      <String>[
        'https://www.instagram.com/direct/t/115950719795361/',
        'https://www.instagram.com/p/CxAbC123xyZ/',
      ],
      <String>[
        'https://www.instagram.com/accounts/login/',
        'https://www.instagram.com/direct/inbox/',
      ],
      // Cold start: there is no previous page.
      <String>['', 'https://www.instagram.com/direct/inbox/'],
    ];

    for (final List<String> pair in pairs) {
      test('${pair[0].isEmpty ? '(empty)' : pair[0]} -> ${pair[1]}', () {
        expect(classify(pair[0], pair[1]), DmTransition.none);
      });
    }
  });

  group('agrees with UrlPolicy so the route shapes cannot drift', () {
    const UrlPolicy policy = UrlPolicy();
    const String thread = 'https://www.instagram.com/direct/t/115950719795361/';
    const String inbox = 'https://www.instagram.com/direct/inbox/';

    const List<String> inboxPaths = <String>[
      '/direct/inbox',
      '/direct/inbox/',
      '/direct/requests/',
    ];
    for (final String path in inboxPaths) {
      test('$path is inbox-level and allowed', () {
        final Uri uri = Uri.parse('https://www.instagram.com$path');
        expect(policy.decide(uri).verdict, UrlVerdict.allow, reason: path);
        expect(
          classifyDmTransition(uri, Uri.parse(thread)),
          DmTransition.forward,
          reason: path,
        );
      });
    }

    const List<String> threadPaths = <String>[
      '/direct/t/115950719795361/',
      '/direct/t/115950719795361',
    ];
    for (final String path in threadPaths) {
      test('$path is thread-level and allowed', () {
        final Uri uri = Uri.parse('https://www.instagram.com$path');
        expect(policy.decide(uri).verdict, UrlVerdict.allow, reason: path);
        expect(
          classifyDmTransition(Uri.parse(inbox), uri),
          DmTransition.forward,
          reason: path,
        );
      });
    }
  });
}
