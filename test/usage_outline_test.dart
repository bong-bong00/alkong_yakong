import 'package:flutter_test/flutter_test.dart';
import 'package:alkong_yakong/features/medicines/domain/display_policy.dart';
import 'package:alkong_yakong/features/medicines/domain/official_usage_display.dart';

const _adipam =
    '○ 성인 1. 정신과 영역 2. 피부과 영역 고령자 이 약은 가능한 최단 기간 동안 최소 유효 용량으로 투여해야 한다. '
    '성인: 1일 50㎎을 3회 분할(12.5mg, 12.5mg, 25mg) 경구 투여한다. 성인에서 최대용량은 1일 100mg이다. '
    '성인: 1일 30-60㎎을 2-3회 분할 경구 투여한다. 연령, 증상에 따라 적절히 증감한다.';

void main() {
  test('앞에 몰린 빈 목차를 떼고 성인 용법에 칸 이름을 붙인다', () {
    final result = untangleUsageOutline(_adipam);
    expect(result.startsWith('고령자: 이 약은'), isTrue);
    expect(result, contains('성인(정신과 영역): 1일 50㎎'));
    expect(result, contains('성인(피부과 영역): 1일 30-60㎎'));
    expect(result, isNot(contains('1. 정신과 영역')));
  });

  test('목차와 내용 수가 어긋나면 원문을 그대로 둔다', () {
    const text = '○ 성인 1. 정신과 영역 2. 피부과 영역 성인: 1일 50㎎을 경구 투여한다.';
    expect(untangleUsageOutline(text), text);
    expect(untangleUsageOutline('성인 : 1회 5 mg 1일 2회'), '성인 : 1회 5 mg 1일 2회');
  });

  test('화면 정리까지 거치면 첫 줄부터 내용이 나온다', () {
    final shown = dropLoneAdultHeading(
      orderOfficialUsageSections(formatOfficialUsage(untangleUsageOutline(_adipam))),
    );
    expect(shown.split('\n').first, '고령자: 이 약은 가능한 최단 기간 동안 최소 유효 용량으로 투여해야 한다.');
  });
}
