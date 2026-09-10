import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 30 · 기록 저장.
///
/// 무엇이 남았는지 두 가지로만 말한다 — 복약 기록과 심박수 기록.
class SavedScreen extends StatelessWidget {
  final int bpm;
  final String guardianTitle;

  /// 심박수 이상 화면을 거쳐 왔는지. 문구가 달라진다.
  final bool fromAlert;

  /// 오늘 저녁 약을 기록한 상태인지.
  final bool doseTaken;

  final String savedAt;

  /// 기록 탭으로 보내는 길. 없으면 버튼을 그리지 않는다.
  final VoidCallback? onOpenRecord;

  const SavedScreen({
    super.key,
    required this.bpm,
    this.guardianTitle = '딸 지안 님',
    this.fromAlert = false,
    this.doseTaken = true,
    this.savedAt = '오늘 오전 9시 41분',
    this.onOpenRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '기록 저장'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.pointTint,
                        shape: BoxShape.circle,
                      ),
                      child: const ExcludeSemantics(
                        child: Icon(
                          TablerIcons.check,
                          size: 50,
                          color: AppColors.point,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '잘 저장되었어요',
                    textAlign: TextAlign.center,
                    style: AppText.emphasis(size: 27),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$savedAt 기준으로\n아래 두 가지가 남았습니다.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 18.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SavedItem(
                    icon: TablerIcons.pill,
                    title: '복약 기록',
                    description: doseTaken
                        ? '저녁 약 3가지 · 오후 6시 2분에 드신 것으로 남았어요'
                        : '오늘 아침·점심 약 2번이 기록되어 있어요',
                  ),
                  const SizedBox(height: 12),
                  _SavedItem(
                    icon: TablerIcons.activity_heartbeat,
                    title: '심박수 기록',
                    description: fromAlert
                        ? '$bpm회 / 분 · 빠르게 뛴 기록으로 따로 표시했어요'
                        : '$bpm회 / 분 · 1분 동안 잰 결과',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 17,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sunken,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        InitialAvatar(
                          name: guardianTitle,
                          size: 44,
                          background: AppColors.surface,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '$guardianTitle에게도 전해졌어요',
                            style: AppText.label(
                              size: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SeniorButton(
                    label: '확인했어요',
                    minHeight: 74,
                    fontSize: 24,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  if (onOpenRecord != null) ...[
                    const SizedBox(height: 12),
                    SeniorButton(
                      label: '기록 보러 가기',
                      kind: SeniorButtonKind.secondary,
                      minHeight: 66,
                      fontSize: 21,
                      onPressed: onOpenRecord,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SavedItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.pointTint,
              shape: BoxShape.circle,
            ),
            child: ExcludeSemantics(
              child: Icon(icon, size: 28, color: AppColors.point),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle(size: 20)),
                Text(description, style: AppText.caption(size: 17.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.circle_check_filled,
              size: 26,
              color: AppColors.point,
            ),
          ),
        ],
      ),
    );
  }
}
