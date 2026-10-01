import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../application/alarm_preferences.dart';
import '../../application/reminder_notifications.dart';

/// 32 · 복약 알림.
///
/// **소리로 알려주기만 한다.** 말로 대답해서 기록하는 기능은 없다 —
/// 잘못 들으면 그대로 오기록이 되기 때문이다.
///
/// 처음 알림은 홈의 "약 드시는 시간"(아침·점심·저녁)대로 걸린다. 그 뒤로는
/// 여기서 따로 고친다 — 시각을 더하고 지워도 **홈의 아침·점심·저녁은
/// 그대로다.** 한 때에 두 번 울리거나, 약과 상관없는 시각을 둘 수도 있다.
class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  /// 굴림판에서 "이 시간 지우기"를 눌렀다는 표시. 시각이 될 수 없는 값이다.
  static const int _deleteTime = -1;

  Future<void> _addTime(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
  ) async {
    if (prefs.times.length >= AlarmPreferences.maxTimes) {
      showSeniorSnackbar(
        context,
        '알림 시간은 ${AlarmPreferences.maxTimes}개까지 둘 수 있어요',
      );
      return;
    }
    final picked = await showSeniorClockWheel(
      context: context,
      title: '몇 시에 더 알려드릴까요?',
      initialMinutes: 9 * 60,
    );
    if (picked == null || !context.mounted) return;
    if (prefs.times.contains(picked)) {
      showSeniorSnackbar(
        context,
        '이미 ${AlarmPreferences.clock(picked)} 알림이 있어요',
      );
      return;
    }
    notifier.update(prefs.withTime(picked));
    if (!context.mounted) return;
    showSeniorSnackbar(context, '${AlarmPreferences.clock(picked)} 알림을 더했어요');
  }

  /// 시각을 바꾸거나, 그 자리에서 지운다.
  Future<void> _changeTime(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
    int time,
  ) async {
    final picked = await showSeniorClockWheel(
      context: context,
      title: '몇 시에 알려드릴까요?',
      initialMinutes: time,
      extraButtons: prefs.times.length <= 1
          ? const []
          : [
              SeniorButton(
                label: '이 시간 지우기',
                kind: SeniorButtonKind.dangerQuiet,
                minHeight: 62,
                fontSize: 20,
                onPressed: () => Navigator.of(context).pop(_deleteTime),
              ),
            ],
    );
    if (!context.mounted) return;
    if (picked == _deleteTime) {
      _removeTime(context, prefs, notifier, time);
      return;
    }
    if (picked == null || picked == time) return;
    if (prefs.times.contains(picked)) {
      showSeniorSnackbar(
        context,
        '이미 ${AlarmPreferences.clock(picked)} 알림이 있어요',
      );
      return;
    }
    notifier.update(prefs.replaceTime(time, picked));
  }

  void _removeTime(
    BuildContext context,
    AlarmPreferences prefs,
    AlarmPreferencesController notifier,
    int time,
  ) {
    if (prefs.times.length <= 1) {
      showSeniorSnackbar(context, '알림 시간은 적어도 하나는 있어야 해요');
      return;
    }
    notifier.update(prefs.withoutTime(time));
    showSeniorSnackbar(context, '${AlarmPreferences.clock(time)} 알림을 지웠어요');
  }

  @override
  Widget build(BuildContext context) {
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
                  // 시각마다 칸 하나, 오른쪽에 스위치.
                  // 지우지 않고도 잠깐 끌 수 있어야 한다.
                  for (int i = 0; i < prefs.times.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _TimeCard(
                      time: AlarmPreferences.clock(prefs.times[i]),
                      on: prefs.autoAlarm && !prefs.isMuted(prefs.times[i]),
                      onEdit: () =>
                          _changeTime(context, prefs, notifier, prefs.times[i]),
                      onChanged: (v) async {
                        final time = prefs.times[i];
                        // 다 꺼 두었다가 하나를 켜면 소리 알림 자체도 켠다.
                        final next = prefs
                            .withMuted(time, !v)
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
                  if (prefs.times.length < AlarmPreferences.maxTimes) ...[
                    const SizedBox(height: 14),
                    _AddTimeCard(
                      onTap: () => _addTime(context, prefs, notifier),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: _LadderRow(
                      title: '못 들으셨으면 10분 뒤에 한 번 더',
                      description: '최대 두 번까지 다시 알려드려요',
                      value: prefs.repeatOnce,
                      onChanged: (v) =>
                          notifier.update(prefs.copyWith(repeatOnce: v)),
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

/// 알림 시각 한 칸. 시각을 크게 적고 오른쪽에 스위치를 둔다.
/// 시각을 누르면 바꾸거나 지운다.
class _TimeCard extends StatelessWidget {
  final String time;
  final bool on;
  final VoidCallback onEdit;
  final ValueChanged<bool> onChanged;

  const _TimeCard({
    required this.time,
    required this.on,
    required this.onEdit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 글씨를 키우면 시각만으로 한 줄이 찬다. 스위치를 아래로 내린다.
    final stacked = MediaQuery.textScalerOf(context).scale(30) > 44;
    final toggle = SeniorToggle(
      value: on,
      semanticLabel: '$time 알림',
      onChanged: onChanged,
    );

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
                    child: ExcludeSemantics(
                      child: Container(
                        color: Colors.transparent,
                        constraints: const BoxConstraints(minHeight: 64),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  time,
                                  maxLines: 1,
                                  style: AppText.screenTitle(
                                    size: 32,
                                    color: on
                                        ? AppColors.textPrimary
                                        : AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.edit_rounded,
                              size: 24,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!stacked) ...[const SizedBox(width: 10), toggle],
            ],
          ),
          if (stacked) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [toggle]),
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
            constraints: const BoxConstraints(minHeight: 58),
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
