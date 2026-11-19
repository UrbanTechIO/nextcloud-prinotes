import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/data/font_sizes.dart';

void main() {
  test('sizes written by older web versions ("28px") become the phone form ("28")', () {
    final ops = <Map<String, dynamic>>[
      {'insert': 'Big', 'attributes': {'size': '28px', 'bold': true}},
      {'insert': '\n'},
      {'insert': 'Small', 'attributes': {'size': '12'}},
      {'insert': 'Odd', 'attributes': {'size': '12.5px'}},
      {'insert': {'image': 'x'}},
    ];
    final out = normalizeFontSizes(ops);
    expect(out[0]['attributes'], {'size': '28', 'bold': true}, reason: 'other attributes kept');
    expect(out[2]['attributes'], {'size': '12'}, reason: 'already the phone form');
    expect(out[3]['attributes'], {'size': '12.5'});
    expect(out[1], {'insert': '\n'});
    expect(out[4], {'insert': {'image': 'x'}}, reason: 'embeds untouched');
  });

  test('does not change the original list', () {
    final ops = <Map<String, dynamic>>[
      {'insert': 'Big', 'attributes': {'size': '28px'}}
    ];
    normalizeFontSizes(ops);
    expect(ops[0]['attributes'], {'size': '28px'});
  });
}
