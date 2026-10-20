import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/profile/domain/app_documents.dart';

void main() {
  final text = kPrivacyPolicy.sections.expand((s) => s.paragraphs).join('\n');

  test('AI 안내에는 관련 건강정보와 최근 대화 전달이 포함된다', () {
    final google = kPrivacyPolicy.sections
        .firstWhere((s) => s.title.startsWith('8.'))
        .paragraphs
        .join('\n');
    expect(google, contains('질환·과거력·알레르기·흡연·음주'));
    expect(google, contains('최근 대화'));
  });

  test('Neon은 실제 전환 빌드에서만 활성 보관 업체로 안내한다', () {
    expect(text.contains('현재 운영 DB는 Render의 SQLite'), !kNeonDatabaseActive);
    expect(text.contains('Neon: PostgreSQL 데이터베이스 보관'), kNeonDatabaseActive);
  });

  test('동의나 백업 자동 삭제를 구현된 기능처럼 주장하지 않는다', () {
    expect(text, contains('별도 민감정보 동의'));
    expect(text, contains('운영 전에 확정'));
    expect(text, isNot(contains('백업이 새로 쌓이면서 함께 지워집니다')));
    expect(text, contains('로그아웃만으로 모두 삭제되는 것은 아니며'));
  });

  test('운영자 정보를 임의로 만들어 넣지 않는다', () {
    if (kPrivacyOperator.isEmpty) {
      expect(text, contains('운영 전 확정 필요'));
    }
    if (kPrivacyContact.isEmpty) {
      expect(text, contains('실제 문의 연락처: 운영 전 확정 필요'));
    }
  });
}
