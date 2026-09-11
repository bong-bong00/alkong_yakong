import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../domain/heart_data.dart';

/// 26 · 한 달 기록.
///
/// **주 단위로 묶어 보여준다.** 30일 × 2회를 막대 60개로 그리지 않는다.
/// 대신 "며칠째 정상인가"와 "이상했던 날 하나"를 앞세운다.
class MonthlyHeartScreen extends StatefulWidget {
  final HeartData data;
  final String guardianTitle;

  const MonthlyHeartScreen({
    super.key,
    required this.data,
    this.guardianTitle = '딸 지안 님',
  });

  @override
  State<MonthlyHeartScreen> createState() => _MonthlyHeartScreenState();
}

class _MonthlyHeartScreenState extends State<MonthlyHeartScreen> {
  /// 눌러서 펼친 날짜. 없으면 안내 문장을 보여준다.
  HeartMonthDay? _picked;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SeniorBackButton(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '심박수 관리',
                        style: AppText.screenTitle(size: 24),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SeniorSegmented(
                  labels: const ['이번 주', '한 달'],
                  index: 1,
                  onChanged: (i) {
                    if (i == 0) Navigator.of(context).maybePop();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StreakCard(data: data),
                  if (data.anomaly != null) ...[
                    const SizedBox(height: 12),
                    _AnomalyCard(
                      anomaly: data.anomaly!,
                      guardianTitle: widget.guardianTitle,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _DayGrid(
                    days: data.month,
                    picked: _picked,
                    onPick: (d) => setState(
                      () => _picked = _picked?.day == d.day ? null : d,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SharedNote(guardianTitle: widget.guardianTitle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 며칠째 정상인지 — 이 화면의 주인공.
class _StreakCard extends StatelessWidget {
  final HeartData data;
  const _StreakCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Text(
            '지금까지',
            style: AppText.label(size: 19, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: '심박수가 ${data.streakDays}일째 계속 정상이에요',
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${data.streakDays}',
                    style: AppText.hero(size: 72, color: AppColors.point),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('일째', style: AppText.cardTitle(size: 24)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '심박수가\n계속 정상이에요',
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 21),
          ),
          const SizedBox(height: 16),
          _StreakBars(streak: data.streakDays),
          const SizedBox(height: 12),
          Text(
            '가장 길었던 기록은 ${data.bestStreakDays}일이에요',
            style: AppText.caption(size: 17.5),
          ),
        ],
      ),
    );
  }
}

/// 최근 열흘. 첫 칸이 이상했던 날, 나머지가 정상인 날.
class _StreakBars extends StatelessWidget {
  final int streak;
  const _StreakBars({required this.streak});

  @override
  Widget build(BuildContext context) {
    const total = 10;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: 16,
              height: 34,
              decoration: BoxDecoration(
                color: i < total - streak ? AppColors.danger : AppColors.point,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 한 번 빠르게 뛴 날.
class _AnomalyCard extends StatelessWidget {
  final HeartAnomaly anomaly;
  final String guardianTitle;

  const _AnomalyCard({required this.anomaly, required this.guardianTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(22)),
        border: Border(left: BorderSide(color: AppColors.danger, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('한 번 빠른 날이 있었어요', style: AppText.cardTitle(size: 19.5)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: AppText.body(size: 18),
              children: [
                TextSpan(
                  text: '8월 ${anomaly.day}일 ${anomaly.slotLabel}, 약 먹기 전 ',
                ),
                TextSpan(
                  text: '${anomaly.before}회',
                  style: AppText.body(
                    size: 18,
                    color: AppColors.danger,
                    weight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: '였어요. 그날 $guardianTitle에게도 알려드렸습니다.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 날짜별 격자. 먹은 뒤 수치만 보여주고, 누르면 전·후를 함께 편다.
class _DayGrid extends StatelessWidget {
  final List<HeartMonthDay> days;
  final HeartMonthDay? picked;
  final ValueChanged<HeartMonthDay> onPick;

  const _DayGrid({
    required this.days,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('날짜별로 보기', style: AppText.cardTitle())),
              SeniorBadge(
                label: '먹은 후 수치',
                fontSize: 16.5,
                radius: 11,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 칸 높이를 계산하지 않고 내용에 맡긴다.
          // 글자 배율이 커지면 칸도 같이 자라야 잘리지 않는다.
          for (int row = 0; row < (days.length / 5).ceil(); row++) ...[
            if (row > 0) const SizedBox(height: 7),
            // 한 줄 안의 칸은 키를 맞춘다. 세로 스크롤 안이라 stretch만으로는
            // 높이가 무한이 되므로 IntrinsicHeight로 묶는다.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int col = 0; col < 5; col++) ...[
                    if (col > 0) const SizedBox(width: 7),
                    Expanded(
                      child: row * 5 + col < days.length
                          ? _DayCell(
                              day: days[row * 5 + col],
                              selected: picked?.day == days[row * 5 + col].day,
                              onTap: () => onPick(days[row * 5 + col]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (picked == null)
            Text(
              '날짜를 누르면 그날 먹기 전 수치까지 보여드려요',
              style: AppText.caption(size: 17.5),
            )
          else
            _PickedDetail(day: picked!),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final HeartMonthDay day;
  final bool selected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final after = day.pair.after;
    final missing = day.isMissing;
    final Color background = missing ? AppColors.bg : AppColors.sunken;
    final Color valueColor = missing
        ? AppColors.chevron
        : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: missing ? '8월 ${day.day}일 재지 못했어요' : '8월 ${day.day}일 먹은 후 $after회',
      child: GestureDetector(
        onTap: missing ? null : onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: AppColors.point, width: 2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${day.day}',
                  style: AppText.label(
                    size: 14.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  after?.toString() ?? '–',
                  style: AppText.cardTitle(size: 21, color: valueColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickedDetail extends StatelessWidget {
  final HeartMonthDay day;
  const _PickedDetail({required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text('8월 ${day.day}일', style: AppText.cardTitle(size: 19)),
          const Spacer(),
          Text('전 ${day.pair.before ?? '–'}', style: AppText.label(size: 18)),
          const SizedBox(width: 10),
          const Text('→'),
          const SizedBox(width: 10),
          Text(
            '후 ${day.pair.after ?? '–'}',
            style: AppText.label(size: 18, color: AppColors.point),
          ),
        ],
      ),
    );
  }
}

class _SharedNote extends StatelessWidget {
  final String guardianTitle;
  const _SharedNote({required this.guardianTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
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
              '이 기록은 $guardianTitle도 같이 보고 있어요',
              style: AppText.label(size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
