import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/todo/presentation/todo_screen.dart';

void main() {
  test('a task shows the note indicator only when its note has real text', () {
    expect(todoHasNote(null), isFalse);
    expect(todoHasNote(''), isFalse);
    expect(todoHasNote('   \n '), isFalse);
    expect(todoHasNote('Ask about the boiler'), isTrue);
  });
}
