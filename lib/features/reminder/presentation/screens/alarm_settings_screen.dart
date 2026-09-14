import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../profile/application/current_user_controller.dart';
import '../../application/alarm_preferences.dart';
import '../../application/reminder_notifications.dart';

/// 32 · 복약 알림.
///
/// **소리로 알려주기만 한다.** 말로 대답해서 기록하는 기능은 없다 —
/// 잘못 들으면 그대로 오기록이 되기 때문이다.
///
/// 고른 값은 저장돼서 내 정보 목록의 한 줄과 같이 바뀐다.
class AlarmSettingsScreen extends ConsumerWidget {
  const AlarmSettingsScreen({super.key});

  static String _namesFor(TodayMedication today, DoseSlot slot) {
    final names = [
      for (final med in today.doseOf(slot).medicines)
        if (med.displayName.trim().isNotEmpty) med.displayName.trim(),
    ];
    if (names.isEmpty) return '등록된 약이 없어요';
    return names.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationProvider);
    final prefs = ref.watch(alarmPreferencesProvider);
    final userName = ref.watch(currentUserNameProvider);
    final notifier = ref.read(alarmPreferencesProvider.notifier);
    final notifications = ref.read(reminderNotificationsProvider);

    final morning = AlarmPreferences.spoken(prefs.morningHour);
    final evening = AlarmPreferences.spoken(prefs.eveningHour);
    final morningNames = _namesFor(today, DoseSlot.morning);
    final eveningNames = today.doseOf(DoseSlot.dinner).medicines.isNotEmpty
        ? _namesFor(today, DoseSlot.dinner)
        : _namesFor(today, DoseSlot.lunch);

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
                            color: prefs.autoAlarm
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
                                prefs.autoAlarm
                                    ? '켜짐 · $morning, $evening에 소리로 알려드려요'
                                    : '꺼짐 · 화면에서 눌러야 들을 수 있어요',
                                style: AppText.caption(size: 17),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SeniorToggle(
                          value: prefs.autoAlarm,
                          semanticLabel: '자동으로 소리 알림',
                          onChanged: (v) async {
                            final next = prefs.copyWith(autoAlarm: v);
                            notifier.update(next);
                            if (!v) return;
                            // 켜는 순간에 묻는다. 무엇을 허락하는지 알고 누르게.
                            final allowed = await notifications
                                .requestPermissions(exactAlarm: true);
                            if (!allowed) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '전화기 설정에서 알림을 허용해 주세요. '
                                    '그래야 약 시간에 소리가 나요.',
                                  ),
                                ),
                              );
                              return;
                            }
                            // 정확한 알람을 방금 허락받았을 수 있으니 다시 맞춘다.
                            await notifications.sync(next);
                          },
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
                        // 아침 7~10시, 저녁 5~8시를 돌아가며 고른다.
                        _TimeRow(
                          time: morning,
                          medicines: morningNames,
                          onChange: () => notifier.update(
                            prefs.copyWith(
                              morningHour: prefs.morningHour >= 10
                                  ? 7
                                  : prefs.morningHour + 1,
                            ),
                          ),
                        ),
                        const SeniorDivider(),
                        _TimeRow(
                          time: evening,
                          medicines: eveningNames,
                          onChange: () => notifier.update(
                            prefs.copyWith(
                              eveningHour: prefs.eveningHour >= 20
                                  ? 17
                                  : prefs.eveningHour + 1,
                            ),
                          ),
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
                  _SpokenExample(userName: userName, evening: evening),
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
                          value: prefs.repeatOnce,
                          onChanged: (v) =>
                              notifier.update(prefs.copyWith(repeatOnce: v)),
                        ),
                        const SeniorDivider(),
                        _LadderRow(
                          title: '30분 지나면 가족에게 알림',
                          description: today.hasGuardian
                              ? '${today.guardianTitle}에게만 전해집니다'
                              : '등록된 가족이 없어요 · 내 정보에서 초대할 수 있어요',
                          value: prefs.tellGuardian,
                          onChanged: (v) =>
                              notifier.update(prefs.copyWith(tellGuardian: v)),
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
    final greeting = userName.trim().isEmpty ? '' : '${userName.trim()} 님, ';
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
              '$greeting$evening예요.\n'
              '지금 드실 약을 물과 함께 드세요.',
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
