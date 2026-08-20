import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../biosignal/presentation/screens/heartbeat_screen.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_data.dart';

/// 보호자 쉘 — 탭은 **현황 · 알림 · 내 정보** 셋뿐이다.
///
/// 보호자 전용 남색 액센트는 폐기했다. 환자와 같은 파란 규칙을 쓰고,
/// 역할 구분은 탭 라벨과 상단 "보호자 화면" 라벨로만 한다.
class GuardianHomeScreen extends ConsumerStatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  ConsumerState<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends ConsumerState<GuardianHomeScreen> {
  int _index = 0;
  int _patientIndex = 0;

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: Icons.favorite_rounded, label: '현황'),
    SeniorNavItem(icon: Icons.notifications_rounded, label: '알림'),
    SeniorNavItem(icon: Icons.person_rounded, label: '내 정보'),
  ];

  PatientData get _patient => DemoPatients.all[_patientIndex];

  Future<void> _switchPatient() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('누구를 보실까요?', style: AppText.emphasis()),
                const SizedBox(height: 16),
                for (int i = 0; i < DemoPatients.all.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SeniorButton(
                      label:
                          '${DemoPatients.all[i].relation} · '
                          '${DemoPatients.all[i].name}',
                      kind: i == _patientIndex
                          ? SeniorButtonKind.primary
                          : SeniorButtonKind.secondary,
                      minHeight: 64,
                      fontSize: 21,
                      onPressed: () => Navigator.of(sheetContext).pop(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _patientIndex = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          GuardianStatusTab(
            patient: _patient,
            onSwitchPatient: _switchPatient,
            onOpenAlerts: () => setState(() => _index = 1),
          ),
          GuardianAlertsTab(patient: _patient),
          const MyPageScreen(isGuardian: true),
        ],
      ),
      bottomNavigationBar: SeniorBottomNav(
        items: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4j — 부모님 현황
// ════════════════════════════════════════════════════════════════

/// 보호자가 할 수 있는 일: 조회 · 처방전 등록 대행 · 전화 · 알림 확인.
/// **대신 복약 체크는 할 수 없다** — 오기록을 막기 위해서다.
class GuardianStatusTab extends StatelessWidget {
  final PatientData patient;
  final VoidCallback onSwitchPatient;
  final VoidCallback onOpenAlerts;

  const GuardianStatusTab({
    super.key,
    required this.patient,
    required this.onSwitchPatient,
    required this.onOpenAlerts,
  });

  bool get _needsAttention => patient.takenCount < patient.totalCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SeniorHeader(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('보호자 화면', style: AppText.label(size: 17)),
                    Text(
                      '${patient.relation} · ${patient.name}',
                      style: AppText.screenTitle(size: 26),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: onSwitchPatient,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '바꾸기',
                    style: AppText.cardTitle(size: 17, color: AppColors.point),
                  ),
                ),
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
                // ── 오늘 복약 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 17,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmojiTitle(
                        emoji: '💊',
                        text: '오늘 복약',
                        style: AppText.label(
                          size: 19,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${patient.takenCount} / ${patient.totalCount}',
                            style: AppText.hero(size: 44),
                          ),
                          Text(
                            _needsAttention ? '저녁 약 남음' : '다 드셨어요',
                            style: AppText.label(
                              size: 19,
                              color: AppColors.point,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (int i = 0; i < patient.totalCount; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _SlotChip(
                                label: const ['아침', '점심', '저녁'][i],
                                done: i < patient.takenCount,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 지표 분할 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HeartbeatScreen(
                        guardianTitle: '${patient.relation} ${patient.name} 님',
                      ),
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: '심장 박동',
                            value: '${patient.currentHr}',
                            note: patient.hrNormal ? '정상' : '확인 필요',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 52,
                          color: AppColors.divider,
                        ),
                        const Expanded(
                          child: _Metric(
                            label: '이번 주',
                            value: '94%',
                            note: '잘 지키고 계세요',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── 확인 필요 ──
                if (_needsAttention) ...[
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    borderColor: AppColors.dangerBorder,
                    borderWidth: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Dot(color: AppColors.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '확인이 필요해요',
                                style: AppText.cardTitle(
                                  size: 18,
                                  color: AppColors.danger,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${patient.nextDose}\n아직 기록이 오지 않았어요',
                          style: AppText.cardTitle(size: 21),
                        ),
                        const SizedBox(height: 14),
                        SeniorButton(
                          label: '전화 드리기',
                          minHeight: 62,
                          fontSize: 21,
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${patient.name} 님에게 전화를 겁니다'),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── 최근 있었던 일 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmojiTitle(
                        emoji: '🕐',
                        text: '오늘 있었던 일',
                        style: AppText.cardTitle(size: 19),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < patient.activities.length; i++) ...[
                        if (i > 0) ...[
                          const SizedBox(height: 12),
                          const SeniorDivider(),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                patient.activities[i].text,
                                style: AppText.body(
                                  size: 18.5,
                                  color: AppColors.textBody,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              patient.activities[i].time,
                              style: AppText.label(
                                size: 17,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 약 목록 · 처방전 ──
                SeniorCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      SeniorListRow(
                        label: '약 목록 · 처방전',
                        emoji: '📋',
                        trailing: const SeniorChevron(),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MedicationRecordScreen(
                              patientName: patient.name,
                              showBack: true,
                              records: patient.records,
                            ),
                          ),
                        ),
                      ),
                      const SeniorDivider(),
                      SeniorListRow(
                        label: '지난 알림 보기',
                        emoji: '🔔',
                        trailing: const SeniorChevron(),
                        onTap: onOpenAlerts,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '보호자는 대신 복약 체크를 할 수 없어요.\n'
                  '어르신이 직접 누르신 기록만 남습니다.',
                  textAlign: TextAlign.center,
                  style: AppText.caption(size: 17),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String label;
  final bool done;
  const _SlotChip({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: done ? AppColors.pointTint : AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: done
            ? null
            : Border.all(color: AppColors.strongBorder, width: 2),
      ),
      child: Text(
        label,
        style: AppText.label(
          size: 18,
          color: done ? AppColors.point : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String note;

  const _Metric({
    required this.label,
    required this.value,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppText.label(size: 18)),
        const SizedBox(height: 4),
        Text(value, style: AppText.bigTime(size: 36)),
        const SizedBox(height: 4),
        Text(
          note,
          textAlign: TextAlign.center,
          style: AppText.caption(size: 17),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4k — 알림
// ════════════════════════════════════════════════════════════════

/// "확인했어요"는 알림을 읽음 처리할 뿐 **삭제하지 않는다**.
/// 어르신 쪽 재알림 사다리도 계속 진행된다.
class GuardianAlertsTab extends StatefulWidget {
  final PatientData patient;
  const GuardianAlertsTab({super.key, required this.patient});

  @override
  State<GuardianAlertsTab> createState() => _GuardianAlertsTabState();
}

class _GuardianAlertsTabState extends State<GuardianAlertsTab> {
  final Set<int> _acknowledged = <int>{};

  @override
  Widget build(BuildContext context) {
    final alerts = widget.patient.alerts;
    return Column(
      children: [
        const SeniorTitleHeader(title: '알림'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: alerts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _AlertCard(
              alert: alerts[index],
              patientName: widget.patient.name,
              acknowledged: _acknowledged.contains(index),
              onAcknowledge: () => setState(() => _acknowledged.add(index)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertItem alert;
  final String patientName;
  final bool acknowledged;
  final VoidCallback onAcknowledge;

  const _AlertCard({
    required this.alert,
    required this.patientName,
    required this.acknowledged,
    required this.onAcknowledge,
  });

  bool get _isDanger => alert.type == 'miss' || alert.type == 'alert';

  Color get _barColor {
    if (_isDanger) return AppColors.danger;
    if (alert.type == 'done') return AppColors.point;
    return AppColors.strongBorder;
  }

  @override
  Widget build(BuildContext context) {
    // 좌측 6px 컬러 바. BoxDecoration의 한쪽 테두리는 둥근 모서리와
    // 함께 쓸 수 없어서, 잘라낸 카드 안에 색 막대를 세운다.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: _barColor),
            Expanded(child: _content(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: EmojiTitle(
                  emoji: _isDanger ? '⚠️' : '✅',
                  text: alert.title,
                  style: AppText.cardTitle(size: 18, color: _barColor),
                ),
              ),
              Text(
                alert.time,
                style: AppText.label(
                  size: 17,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.desc,
            style: AppText.label(size: 20.5, color: AppColors.textPrimary),
          ),
          if (_isDanger) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SeniorButton(
                    label: '전화 드리기',
                    minHeight: 56,
                    fontSize: 19,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$patientName 님에게 전화를 겁니다')),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SeniorButton(
                    label: acknowledged ? '확인함' : '확인했어요',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 56,
                    fontSize: 19,
                    onPressed: acknowledged ? null : onAcknowledge,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
