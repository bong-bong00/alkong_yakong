import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import 'saved_screen.dart';

/// 29 · 심박수 이상.
///
/// 숫자보다 **지금 무엇을 할지**를 먼저 보여준다.
/// 보호자에게는 이미 연락이 간 상태로 시작한다 — 어르신이 전화를 걸 필요가 없다.
class HrAlertScreen extends StatefulWidget {
  final int bpm;
  final String guardianTitle;
  final String measuredAt;
  final String usualRange;

  const HrAlertScreen({
    super.key,
    required this.bpm,
    this.guardianTitle = '딸 지안 님',
    this.measuredAt = '오늘 오전 9시 40분',
    this.usualRange = '68~78회',
  });

  @override
  State<HrAlertScreen> createState() => _HrAlertScreenState();
}

class _HrAlertScreenState extends State<HrAlertScreen> {
  @override
  void initState() {
    super.initState();
    // 화면에 들어오는 순간 이미 보호자에게 갔다는 사실을 알린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showSeniorSnackbar(context, '${widget.guardianTitle}에게 연락이 갔어요');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            background: AppColors.dangerHeaderBg,
            borderColor: AppColors.dangerHeaderBorder,
            child: Row(
              children: [
                const SeniorBackButton(),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '심박수 이상',
                    style: AppText.screenTitle(
                      size: 24,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              // 아래 스낵바가 가리지 않도록 넉넉히 띄운다.
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 118),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ValueCard(
                    bpm: widget.bpm,
                    measuredAt: widget.measuredAt,
                    usualRange: widget.usualRange,
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '지금 이렇게 해주세요',
                          style: AppText.cardTitle(size: 20),
                        ),
                        const SizedBox(height: 14),
                        const NumberedSteps(
                          boxed: false,
                          danger: true,
                          steps: [
                            '하던 일을 멈추고 앉거나 누우세요',
                            '숨을 천천히 크게 쉬세요',
                            '가슴이 아프거나 숨이 차면 119에 알리세요',
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '지금은 괜찮아졌어요',
                    subLabel: '기록 남기기',
                    icon: TablerIcons.circle_check,
                    minHeight: 80,
                    fontSize: 23,
                    elevated: true,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => SavedScreen(
                          bpm: widget.bpm,
                          guardianTitle: widget.guardianTitle,
                          fromAlert: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  final int bpm;
  final String measuredAt;
  final String usualRange;

  const _ValueCard({
    required this.bpm,
    required this.measuredAt,
    required this.usualRange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(22)),
        border: Border(
          left: BorderSide(color: AppColors.danger, width: 6),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ExcludeSemantics(
                child: Icon(
                  TablerIcons.activity_heartbeat,
                  size: 26,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '방금 잰 심박수',
                style: AppText.cardTitle(size: 19, color: AppColors.danger),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '방금 잰 심박수 $bpm회, 평소보다 많이 빠릅니다',
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$bpm',
                    style: AppText.hero(size: 68, color: AppColors.danger),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '회 / 분',
                      style: AppText.label(
                        size: 22,
                        color: AppColors.dangerMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text('평소보다 많이 빠릅니다', style: AppText.cardTitle(size: 22)),
          const SizedBox(height: 6),
          Text(
            '$measuredAt · 평소 $usualRange',
            textAlign: TextAlign.center,
            style: AppText.body(size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
