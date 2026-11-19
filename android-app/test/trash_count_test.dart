import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/core/widgets/app_sidebar.dart';

void main() {
  Widget bar(int count) => MaterialApp(
        home: Scaffold(
          body: SidebarBar(items: [
            SidebarBarItem(Icons.delete_outline_rounded, 'Trash', () {}, count: count),
            SidebarBarItem(Icons.settings_outlined, 'Settings', () {}),
          ]),
        ),
      );

  testWidgets('trash shows how many notes it holds', (tester) async {
    await tester.pumpWidget(bar(7));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('an empty trash shows no number', (tester) async {
    await tester.pumpWidget(bar(0));
    expect(find.text('0'), findsNothing);
  });
}
