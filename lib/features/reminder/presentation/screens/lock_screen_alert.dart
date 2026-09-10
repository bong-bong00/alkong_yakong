import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../medication/domain/medication_models.dart';

/// 5b — 잠금화면 알림.
///
/// 앱을 열지 않고 복약을 완료한다. 시니어에게 앱 진입은 그 자체가 장벽이다.
///
/// 이 위젯은 알림의 **모양과 문구를 확정한 미리보기**다. 실제 잠금화면에는
/// 아래 플랫폼 구현으로 같은 내용을 그린다.
// TODO: iOS Notification Content Extension + Actionable Notification,
//       Android Notification Action + custom layout.
//       액션을 누르면 앱을 띄우지 않고 백그라운드로 기록되어야 한다.
class LockScreenAlert extends StatelessWidget {
  final DoseEntry dose;
  final DateTime now;
  final VoidCallback onTake;
  final VoidCallback onSnooze;

  const LockScreenAlert({
    super.key,
    required this.dose,
    required this.now,
    required this.onTake,
    required this.onSnooze,
  });

  static const List<String> _weekdays = [
    '월요일',
    '화요일',
    '수요일',
    '목요일',
    '금요일',
    '토요일',
    '일요일',
  ];

  @override
  Widget build(BuildContext context) {
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: AppColors.lockBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}',
                  style: AppText.body(
                    size: 22,
                    color: const Color(0xFFB6B8C4),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '$hour12:$minute',
                  style: AppText.hero(size: 82, color: Colors.white),
                ),
              ),
              const SizedBox(height: 44),

              // ── 알림 카드 ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const AppLogo(size: 30, radius: 9),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('알콩약콩', style: AppText.label(size: 17)),
                        ),
                        Text(
                          '지금',
                          style: AppText.label(
                            size: 17,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${dose.slot.label} 약 드실 시간이에요',
                      style: AppText.screenTitle(size: 26),
                    ),
                    const SizedBox(height: 14),
                    // 이름보다 생김새가 먼저다. 잠결에는 "메트포르민"보다
                    // "흰색 알약 하나"가 빨리 읽힌다.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final medicine in dose.medicines)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _PillDot(color: medicine.pillColor),
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final medicine in dose.medicines)
                                Text(
                                  medicine.shapePhrase,
                                  style: AppText.label(
                                    size: 18.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SeniorButton(
                      label: '먹었어요',
                      minHeight: 68,
                      fontSize: 23,
                      onPressed: onTake,
                    ),
                    const SizedBox(height: 10),
                    SeniorButton(
                      label: '30분 뒤에 다시',
                      kind: SeniorButtonKind.neutral,
                      minHeight: 58,
                      fontSize: 20,
                      onPressed: onSnooze,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '앱을 열지 않아도 여기서 끝낼 수 있어요',
                  style: AppText.caption(color: const Color(0xFF8A8CA0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 알약 미리보기 동그라미. 사진이 붙기 전까지는 색으로 대신한다.
class _PillDot extends StatelessWidget {
  final Color color;

  const _PillDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 2),
      ),
    );
  }
}
