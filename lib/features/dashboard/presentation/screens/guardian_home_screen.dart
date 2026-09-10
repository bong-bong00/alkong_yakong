import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../biosignal/presentation/screens/heart_screen.dart';
import '../../../guardian/data/alert_repository.dart';
import '../../../guardian/presentation/screens/care_family_screen.dart';
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
    SeniorNavItem(icon: TablerIcons.users, label: '돌보는 분'),
    SeniorNavItem(icon: TablerIcons.heart, label: '현황'),
    SeniorNavItem(icon: TablerIcons.bell, label: '알림'),
    SeniorNavItem(icon: TablerIcons.user, label: '내 정보'),
  ];

  PatientData get _patient => DemoPatients.all[_patientIndex];

  /// 돌보는 분 목록에서 한 분을 고르면 현황 탭으로 넘어간다.
  void _openPatient(int index) {
    setState(() {
      _patientIndex = index;
      _index = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          CareFamilyScreen(onOpenPatient: _openPatient),
          GuardianStatusTab(
            patient: _patient,
            position: _patientIndex + 1,
            total: DemoPatients.all.length,
            onBackToFamily: () => setState(() => _index = 0),
            onOpenAlerts: () => setState(() => _index = 2),
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

  /// 목록에서 몇 번째 분인지. "3명 중 1번째"로 읽힌다.
  final int position;
  final int total;

  final VoidCallback onBackToFamily;
  final VoidCallback onOpenAlerts;

  const GuardianStatusTab({
    super.key,
    required this.patient,
    required this.position,
    required this.total,
    required this.onBackToFamily,
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
              SeniorBackButton(onTap: onBackToFamily),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '보호자 화면 · $total명 중 $position번째',
                      style: AppText.label(size: 17),
                    ),
                    Text(
                      '${patient.relation} · ${patient.name}',
                      style: AppText.screenTitle(size: 26),
                    ),
                  ],
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
                      IconTitle(
                        icon: TablerIcons.pill,
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
                      builder: (_) => HeartScreen(
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
                            const Icon(
                              TablerIcons.alert_triangle_filled,
                              size: 21,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 9),
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
                      IconTitle(
                        icon: TablerIcons.clock,
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
                        icon: TablerIcons.file_text,
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
                        icon: TablerIcons.bell,
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

  /// 알림을 읽어 올 곳. 없으면 이 탭이 하나 만들어 쓴다.
  final AlertRepository? repository;

  const GuardianAlertsTab({
    super.key,
    required this.patient,
    this.repository,
  });

  @override
  State<GuardianAlertsTab> createState() => _GuardianAlertsTabState();
}

class _GuardianAlertsTabState extends State<GuardianAlertsTab> {
  final Set<int> _acknowledged = <int>{};

  late final AlertRepository _repository =
      widget.repository ?? AlertRepository();

  List<AlertItem>? _loaded;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final loaded = await _repository.fetch(MvpSession.userId);
    if (!mounted || loaded == null) return;
    // 읽어온 것이 있으면 그것만 보여준다. 데모와 섞지 않는다.
    setState(() => _loaded = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _loaded ?? widget.patient.alerts;
    return Column(
      children: [
        const SeniorTitleHeader(title: '알림'),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: alerts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == alerts.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '"확인했어요"는 읽음 처리만 합니다.\n'
                    '어르신 쪽 재알림은 계속 진행돼요.',
                    textAlign: TextAlign.center,
                    style: AppText.caption(size: 17),
                  ),
                );
              }
              return _AlertCard(
                alert: alerts[index],
                patientName: widget.patient.name,
                acknowledged: _acknowledged.contains(index),
                onAcknowledge: () => setState(() => _acknowledged.add(index)),
              );
            },
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

  bool get _isDanger =>
      alert.type == 'miss' ||
      alert.type == 'alert' ||
      alert.type == 'refill';

  IconData get _icon {
    switch (alert.type) {
      case 'miss':
      case 'alert':
        return TablerIcons.alert_triangle_filled;
      case 'refill':
        return TablerIcons.pill;
      case 'shared':
        return TablerIcons.message_2;
      case 'prescription':
        return TablerIcons.file_text;
      case 'past':
        return TablerIcons.heart;
      default:
        return TablerIcons.circle_check_filled;
    }
  }

  Color get _barColor {
    if (_isDanger) return AppColors.danger;
    // 지난 것은 회색으로 뒤로 물린다. 지우지는 않는다.
    if (alert.type == 'past') return AppColors.strongLine;
    return AppColors.point;
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
                child: IconTitle(
                  icon: _icon,
                  color: _barColor,
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
