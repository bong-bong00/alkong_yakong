import 'package:alkong_yakong/core/widgets/senior_card.dart';
import 'package:alkong_yakong/features/medicines/domain/user_medicine_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('내 약 응답의 사진 주소를 유지한다', () {
    final medicine = UserMedicine.fromJson({
      'medicine_code': '123',
      'product_name': '테스트정',
      'image_url': 'https://example.org/pill.png',
    });
    expect(medicine.imageUrl, 'https://example.org/pill.png');
  });

  testWidgets('주소가 없거나 잘못되면 기존 사진 자리를 유지한다', (tester) async {
    for (final url in <String?>[null, '', 'javascript:bad']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PillPhoto(size: 56, imageUrl: url)),
        ),
      );
      expect(find.text('사진'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    }
  });

  testWidgets('공식 이미지 연결 실패 시 기존 사진 자리로 돌아간다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PillPhoto(size: 56, imageUrl: 'https://example.org/pill.png'),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://example.org/pill.png');
    await tester.pumpAndSettle();
    expect(find.text('사진'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
