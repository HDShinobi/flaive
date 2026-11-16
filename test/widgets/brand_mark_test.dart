import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lossless_music_download/widgets/brand_mark.dart';

void main() {
  testWidgets('BrandMark has the requested size, painter and image semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandMark(size: 48))),
      );

      expect(tester.getSize(find.byType(BrandMark)), const Size(48, 48));
      expect(
        find.descendant(
          of: find.byType(BrandMark),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Flaive')),
        matchesSemantics(label: 'Flaive', isImage: true),
      );
    } finally {
      semantics.dispose();
    }
  });
}
