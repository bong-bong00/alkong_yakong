import 'package:flutter/foundation.dart';

/// 쉬운 모드에서 지나가는 화면 하나.
///
/// **새 화면을 만들지 않는다.** 일반 모드가 쓰는 화면을 그대로 불러오고,
/// 순서와 버튼만 이 목록이 정한다.
@immutable
class EasyStep {
  /// 단계 제목. 화면 위에 "지금 무엇을 하는 중인지" 알려준다.
  final String title;

  /// 어떤 화면을 부를지.
  final EasyScreen screen;

  /// 다음으로 넘어가는 버튼에 쓸 말.
  /// 마지막 단계면 처음으로 돌아간다.
  final String nextLabel;

  /// 이 단계에서 할 일을 한 줄로 설명. 제목만으로 부족할 때만 쓴다.
  final String? hint;

  const EasyStep({
    required this.title,
    required this.screen,
    required this.nextLabel,
    this.hint,
  });
}

/// 쉬운 모드가 부를 수 있는 화면들. 전부 일반 모드에도 있는 화면이다.
enum EasyScreen { today, prescription, interaction, record, heartbeat, myInfo }

/// 쉬운 모드의 화면 순서.
///
/// 순서를 정한 기준은 **하루에 실제로 일어나는 차례**다.
/// 약을 먹고 → 새 처방전이 생기면 등록하고 → 같이 먹어도 되는지 보고 →
/// 그동안 잘 드셨는지 보고 → 몸 상태를 보고 → 내 정보를 확인한다.
///
/// 순서를 바꾸려면 이 목록만 고치면 된다. 화면 코드는 건드리지 않는다.
const List<EasyStep> kEasyFlow = [
  EasyStep(
    title: '오늘 약 드시기',
    screen: EasyScreen.today,
    nextLabel: '다음 · 약 등록하기',
    hint: '드실 약이 있으면 "먹었어요"를 눌러 주세요',
  ),
  EasyStep(
    title: '약 등록하기',
    screen: EasyScreen.prescription,
    nextLabel: '다음 · 함께 먹어도 되는지 보기',
    hint: '처방전을 찍으면 약이 저장돼요',
  ),
  EasyStep(
    title: '함께 먹어도 되는지 보기',
    screen: EasyScreen.interaction,
    nextLabel: '다음 · 그동안 기록 보기',
  ),
  EasyStep(
    title: '그동안 기록 보기',
    screen: EasyScreen.record,
    nextLabel: '다음 · 심장 박동 보기',
  ),
  EasyStep(
    title: '심장 박동 보기',
    screen: EasyScreen.heartbeat,
    nextLabel: '다음 · 내 정보 보기',
  ),
  EasyStep(
    title: '내 정보 보기',
    screen: EasyScreen.myInfo,
    nextLabel: '처음으로 돌아가기',
  ),
];
