import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 32 · 복약 알림.
///
/// **소리로 알려주기만 한다.** 말로 대답해서 기록하는 기능은 없다 —
/// 잘못 들으면 그대로 오기록이 되기 때문이다.
class AlarmSettingsScreen extends StatefulWidget {
  final String userName;
  final String guardianTitle;

  const AlarmSettingsScreen({
    super.key,
    this.userName = '복자',
    this.guardianTitle = '딸 지안 님',
  });

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  bool _autoAlarm = true;
  bool _repeatOnce = true;
  bool _tellGuardian = true;

  /// 아침 7~10시, 저녁 5~8시를 돌아가며 고른다.
  int _morningHour = 8;
  int _eveningHour = 18;

  void _cycleMorning() => setState(
        () => _morningHour = _morningHour >= 10 ? 7 : _morningHour + 1,
      );

  void _cycleEvening() => setState(
        () => _eveningHour = _eveningHour >= 20 ? 17 : _eveningHour + 1,
      );

  String _spoken(int hour) {
    final isAfternoon = hour >= 12;
    final display = hour > 12 ? hour - 12 : hour;
    return '${isAfternoon ? '저녁' : '아침'} $display시';
  }

  @override
  Widget build(BuildContext context) {
    final morning = _spoken(_morningHour);
    final evening = _spoken(_eveningHour);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '복약 알림'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 17,
                    ),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            TablerIcons.speakerphone,
                            size: 26,
                            color: _autoAlarm
                                ? AppColors.point
                                : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '약 시간이 되면 자동으로 말해드려요',
                                style: AppText.cardTitle(size: 19),
                              ),
                              Text(
                                _autoAlarm
                                    ? '켜짐 · $morning, $evening에 소리로 알려드려요'
                                    : '꺼짐 · 화면에서 눌러야 들을 수 있어요',
                                style: AppText.caption(size: 17),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SeniorToggle(
                          value: _autoAlarm,
                          semanticLabel: '자동으로 소리 알림',
                          onChanged: (v) => setState(() => _autoAlarm = v),
                        ),
                      ],
                    ),
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
                        Text('알림 시간', style: AppText.cardTitle(size: 20)),
                        const SizedBox(height: 14),
                        _TimeRow(
                          time: morning,
                          medicines: '아스피린 100mg',
                          onChange: _cycleMorning,
                        ),
                        const SeniorDivider(),
                        _TimeRow(
                          time: evening,
                          medicines: '메트포르민 500mg · 암로디핀 5mg',
                          onChange: _cycleEvening,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '이 시간이 되면 화면이 꺼져 있어도 '
                          '전화기가 먼저 말해드려요.',
                          style: AppText.body(size: 16.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SpokenExample(
                    userName: widget.userName,
                    evening: evening,
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        _LadderRow(
                          title: '10분 뒤에 한 번 더',
                          description: '최대 두 번까지 다시 알려드려요',
                          value: _repeatOnce,
                          onChanged: (v) => setState(() => _repeatOnce = v),
                        ),
                        const SeniorDivider(),
                        _LadderRow(
                          title: '30분 지나면 가족에게 알림',
                          description: '${widget.guardianTitle}에게만 전해집니다',
                          value: _tellGuardian,
                          onChanged: (v) => setState(() => _tellGuardian = v),
                        ),
                      ],
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

class _TimeRow extends StatelessWidget {
  final String time;
  final String medicines;
  final VoidCallback onChange;

  const _TimeRow({
    required this.time,
    required this.medicines,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LabelValueRow(
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: AppText.screenTitle(size: 24)),
            Text(medicines, style: AppText.caption(size: 17)),
          ],
        ),
        value: Semantics(
          button: true,
          label: '$time 바꾸기',
          child: GestureDetector(
            onTap: onChange,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.pointTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '바꾸기',
                style: AppText.cardTitle(size: 16.5, color: AppColors.point),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 어떤 말로 알려주는지 그대로 보여준다. 듣기 전에 읽어볼 수 있게.
class _SpokenExample extends StatelessWidget {
  final String userName;
  final String evening;

  const _SpokenExample({required this.userName, required this.evening});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$evening에 이렇게 알려드려요',
            style: AppText.label(size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '$userName 님, $evening예요.\n'
              '흰색 알약 하나와 노란 알약 하나를 물과 함께 드세요.',
              style: AppText.body(
                size: 21,
                color: AppColors.textPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '복약은 알림을 눌러서 기록합니다. 말로 대답하는 기능은 없어요.',
            style: AppText.body(size: 16.5),
          ),
        ],
      ),
    );
  }
}

class _LadderRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LadderRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle(size: 19)),
                Text(description, style: AppText.caption(size: 17)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SeniorToggle(
            value: value,
            semanticLabel: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
