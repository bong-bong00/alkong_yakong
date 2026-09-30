import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../../medication/application/medication_controller.dart';
import '../../application/alarm_preferences.dart';
import '../../application/reminder_notifications.dart';

/// 32 · 복약 알림.
///
/// **소리로 알려주기만 한다.** 말로 대답해서 기록하는 기능은 없다 —
/// 잘못 들으면 그대로 오기록이 되기 때문이다.
///
/// 알림 시각은 몇 개든 둘 수 있다. ＋로 더하고 휴지통으로 지운다.
/// 고른 값은 저장돼서 내 정보 목록의 한 줄과 같이 바뀐다.
class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  /// 휴지통을 누르면 켜진다. 시간 칸이 밀리고 빼기 단추가 나온다.

  Future<void> _addHour(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
  ) async {
    if (prefs.hours.length >= AlarmPreferences.maxHours) {
      showSeniorSnackbar(
        context,
        '알림 시간은 ${AlarmPreferences.maxHours}개까지 둘 수 있어요',
      );
      return;
    }
    final picked = await showSeniorTimeWheel(
      context: context,
      title: '알림 시간을 더할까요?',
      initialHour: 9,
    );
    if (picked == null || !context.mounted) return;
    if (prefs.hours.contains(picked)) {
      showSeniorSnackbar(
        context,
        '이미 ${AlarmPreferences.clock(picked)} 알림이 있어요',
      );
      return;
    }
    notifier.update(prefs.withHour(picked));
  }

  Future<void> _changeHour(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
    int hour,
  ) async {
    final picked = await showSeniorTimeWheel(
      context: context,
      title: '몇 시에 알려드릴까요?',
      initialHour: hour,
    );
    if (picked == null || picked == hour || !context.mounted) return;
    if (prefs.hours.contains(picked)) {
      showSeniorSnackbar(
        context,
        '이미 ${AlarmPreferences.clock(picked)} 알림이 있어요',
      );
      return;
    }
    notifier.update(prefs.replaceHour(hour, picked));
  }


  /// 빼기 단추로 그 자리 시간을 바로 지운다.
  void _removeHour(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
    int hour,
  ) {
    if (prefs.hours.length <= 1) {
      showSeniorSnackbar(context, '알림 시간은 적어도 하나는 있어야 해요');
      return;
    }
    notifier.update(prefs.withoutHour(hour));
    showSeniorSnackbar(context, '${AlarmPreferences.clock(hour)} 알림을 지웠어요');
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final prefs = ref.watch(alarmPreferencesProvider);
    final notifier = ref.read(alarmPreferencesProvider.notifier);
    final notifications = ref.read(reminderNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '복약 알림'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 시안 34 — 시각마다 칸 하나, 오른쪽에 스위치.
                  // 지우지 않고도 잠깐 끌 수 있어야 한다.
                  for (int i = 0; i < prefs.hours.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _TimeCard(
                      time: AlarmPreferences.clock(prefs.hours[i]),
                      on: prefs.autoAlarm && !prefs.isMuted(prefs.hours[i]),
                      onEdit: () =>
                          _changeHour(context, prefs, notifier, prefs.hours[i]),
                      onRemove: prefs.hours.length <= 1
                          ? null
                          : () => _removeHour(
                              context,
                              prefs,
                              notifier,
                              prefs.hours[i],
                            ),
                      onChanged: (v) async {
                        final hour = prefs.hours[i];
                        // 다 꺼 두었다가 하나를 켜면 소리 알림 자체도 켠다.
                        final next = prefs
                            .withMuted(hour, !v)
                            .copyWith(autoAlarm: v ? true : prefs.autoAlarm);
                        notifier.update(next);
                        if (!v) return;
                        final allowed = await notifications.requestPermissions(
                          exactAlarm: true,
                        );
                        if (!allowed) {
                          if (!context.mounted) return;
                          showSeniorSnackbar(
                            context,
                            '전화기 설정에서 알림을 허용해 주세요. 그래야 약 시간에 소리가 나요.',
                            error: true,
                          );
                          return;
                        }
                        await notifications.sync(next);
                      },
                    ),
                  ],
                  if (prefs.hours.length < AlarmPreferences.maxHours) ...[
                    const SizedBox(height: 10),
                    _AddTimeCard(
                      onTap: () => _addHour(context, prefs, notifier),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // 늘 그러한 것은 스위치가 아니라 글로 적는다.
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          TablerIcons.volume,
                          size: 24,
                          color: AppColors.point,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '화면이 꺼져 있어도 소리로 알려드려요.',
                            style: AppText.cardTitle(size: 18),
                          ),
                        ),
                      ],
                    ),
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
                          title: '못 들으셨으면 10분 뒤에 한 번 더',
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

/// 카드 머리의 네모 단추. ＋와 휴지통 둘뿐이라 글자 없이 둔다.
/// 시안 34 — 알림 시각 한 칸. 시각을 크게 적고 오른쪽에 스위치를 둔다.
/// 시각을 누르면 바꾸고, 길게 누르면 지운다.
class _TimeCard extends StatelessWidget {
  final String time;
  final bool on;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;
  final ValueChanged<bool> onChanged;

  const _TimeCard({
    required this.time,
    required this.on,
    required this.onEdit,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 글씨를 키우면 시각만으로 한 줄이 찬다. 스위치와 지우기를 아래로 내린다.
    final stacked = MediaQuery.textScalerOf(context).scale(30) > 44;
    final controls = [
      SeniorToggle(
        value: on,
        semanticLabel: '$time 알림',
        onChanged: onChanged,
      ),
      if (onRemove != null) ...[
        const SizedBox(width: 4),
        _IconBox(
          icon: TablerIcons.trash,
          label: '$time 알림 시간 지우기',
          color: AppColors.danger,
          onTap: onRemove!,
        ),
      ],
    ];

    return SeniorCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 10, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '$time, 누르면 시각을 바꿔요',
              child: GestureDetector(
                onTap: onEdit,
                onLongPress: onRemove,
                child: ExcludeSemantics(
                  child: Container(
                    color: Colors.transparent,
                    constraints: const BoxConstraints(minHeight: 72),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            time,
                            style: AppText.screenTitle(
                              size: 30,
                              color: on
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          TablerIcons.pencil,
                          size: 22,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!stacked) ...[const SizedBox(width: 10), ...controls],
        ],
          ),
          if (stacked) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// "+ 알림 시간 더하기" 한 칸.
class _AddTimeCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTimeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '알림 시간 더하기',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: kCardShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  TablerIcons.plus,
                  size: 26,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '알림 시간 더하기',
                    textAlign: TextAlign.center,
                    style: AppText.cardTitle(size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IconBox({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.strongLine, width: 2),
          ),
          child: ExcludeSemantics(child: Icon(icon, size: 28, color: color)),
        ),
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
