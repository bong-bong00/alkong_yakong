import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/session/auth_session.dart';
import '../../../../core/widgets/rounded_gradient_app_bar.dart';
import 'profile_edit_screen.dart';
import 'medication_record_screen.dart';
import 'settings_menu.dart';
import 'biosignal_event_screen.dart';
import 'biosignal_live_screen.dart';
import 'patient_data.dart';

// ════════════════════════════════════════════════════════════════
//  [보호자홈] 환자 선택 → 현황·기록·알림 탭이 모두 그 환자로 전환된다.
//  선택된 환자(_patientIndex)를 이 위젯이 들고, 탭들에 넘긴다.
// ════════════════════════════════════════════════════════════════
class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _index = 0; // 하단 탭
  int _patientIndex = 0; // 선택된 환자

  List<PatientData> get _patients => DemoPatients.all;
  PatientData get _patient => _patients[_patientIndex];

  void _selectPatient(int i) => setState(() => _patientIndex = i);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _PatientStatusTab(
        patient: _patient,
        patients: _patients,
        selectedIndex: _patientIndex,
        onSelect: _selectPatient,
      ),
      MedicationRecordScreen(
        accent: kGuardian,
        patientName: _patient.name,
        records: _patient.records,
      ),
      _AlertsTab(patient: _patient),
      _GuardianMyPage(patients: _patients),
    ];

    return Scaffold(
      backgroundColor: kBackground,
      body: tabs[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _GNavItem(
                  icon: Icons.monitor_heart_rounded,
                  label: '현황',
                  isSelected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _GNavItem(
                  icon: Icons.calendar_today_rounded,
                  label: '기록',
                  isSelected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
                _GNavItem(
                  icon: Icons.notifications_rounded,
                  label: '알림',
                  isSelected: _index == 2,
                  onTap: () => setState(() => _index = 2),
                ),
                _GNavItem(
                  icon: Icons.person_rounded,
                  label: '내 정보',
                  isSelected: _index == 3,
                  onTap: () => setState(() => _index = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 환자 현황 ────────────────────────────────────────────────
class _PatientStatusTab extends StatelessWidget {
  final PatientData patient;
  final List<PatientData> patients;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _PatientStatusTab({
    required this.patient,
    required this.patients,
    required this.selectedIndex,
    required this.onSelect,
  });

  // 환자 선택 바텀시트
  void _openPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              '환자 선택',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < patients.length; i++)
              ListTile(
                leading: Text(
                  patients[i].emoji,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(
                  '${patients[i].name} · ${patients[i].relation}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                trailing: i == selectedIndex
                    ? const Icon(Icons.check_circle_rounded, color: kGuardian)
                    : null,
                onTap: () {
                  onSelect(i);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('환자 현황'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 환자 선택 칩 ("보는 중: 김복자 ▾") ──
            GestureDetector(
              onTap: () => _openPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: kGuardianLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kGuardian.withValues(alpha: 0.20)),
                ),
                child: Row(
                  children: [
                    Text(patient.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(
                      '보는 중: ${patient.name}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kGuardian,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: kGuardian,
                      size: 20,
                    ),
                    const Spacer(),
                    Text(
                      '환자 ${patients.length}명',
                      style: const TextStyle(fontSize: 12, color: kGuardian),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 환자 요약 카드 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _card(),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: kGuardianLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            patient.emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${patient.name} (${patient.relation})',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${patient.age}세 · 마지막 동기화 ${patient.syncedAgo}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: kTextSub,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: patient.okToday
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFE6A100),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: patient.okToday
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF6E5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          patient.okToday ? '✅' : '⚠️',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            patient.okToday
                                ? '오늘 이상 없음 · 심박 정상'
                                : '오늘 확인이 필요해요',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: patient.okToday
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF8A6100),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 복약 / 심박 카드 ──
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    emoji: '💊',
                    label: '오늘 복약',
                    value: '${patient.takenCount}/${patient.totalCount}',
                    sub: patient.nextDose,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BiosignalLiveScreen(
                          accent: kGuardian,
                          patientName: patient.name,
                          baseHr: patient.currentHr,
                        ),
                      ),
                    ),
                    child: _StatCard(
                      emoji: '💓',
                      label: '현재 심박',
                      value: '${patient.currentHr}',
                      sub: '실시간 보기 ›',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '최근 활동',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: _card(),
              child: Column(
                children: [
                  for (int i = 0; i < patient.activities.length; i++) ...[
                    _ActivityRow(
                      emoji: patient.activities[i].emoji,
                      text: patient.activities[i].text,
                      time: patient.activities[i].time,
                    ),
                    if (i != patient.activities.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 알림 ─────────────────────────────────────────────────────
class _AlertsTab extends StatelessWidget {
  final PatientData patient;
  const _AlertsTab({required this.patient});

  @override
  Widget build(BuildContext context) {
    final alerts = patient.alerts;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('알림'),
      body: alerts.isEmpty
          ? const Center(
              child: Text(
                '알림이 없어요',
                style: TextStyle(color: kTextSub, fontSize: 14),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final a = alerts[i];
                Color c;
                IconData icon;
                switch (a.type) {
                  case 'miss':
                    c = const Color(0xFFE6A100);
                    icon = Icons.warning_amber_rounded;
                    break;
                  case 'alert':
                    c = const Color(0xFFE24B4A);
                    icon = Icons.priority_high_rounded;
                    break;
                  default:
                    c = kGuardian;
                    icon = Icons.check_circle_rounded;
                }
                final card = Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _card(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, color: c, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: kText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              a.desc,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),
                            if (a.tappable) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    '심박 추이 보기',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: c,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 11,
                                    color: c,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        a.time,
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                );
                if (!a.tappable) return card;
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BiosignalEventScreen(
                        accent: kGuardian,
                        patientName: patient.name,
                      ),
                    ),
                  ),
                  child: card,
                );
              },
            ),
    );
  }
}

// ── 내 정보 ──────────────────────────────────────────────────
class _GuardianMyPage extends StatelessWidget {
  final List<PatientData> patients;

  const _GuardianMyPage({required this.patients});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('내 정보'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 보호자 본인 — 누르면 정보 수정 화면
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const ProfileEditScreen(isGuardian: true),
                          ),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: _card(),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text(
                                    '👩',
                                    style: TextStyle(fontSize: 26),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '김지안',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: kText,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '보호자 · 연결된 환자 ${patients.length}명',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: kTextSub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const SettingsMenu(accent: kGuardian),
                      const Spacer(),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _confirmWithdraw(context),
                              child: Text(
                                '탈퇴하기',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 0.5,
                            height: 14,
                            color: Colors.grey[400],
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () async {
                                await AuthSession.logout();
                                if (context.mounted) context.go('/login');
                              },
                              child: Text(
                                '로그아웃',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmWithdraw(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '정말 탈퇴하시겠어요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '탈퇴하면 등록한 정보가 모두 삭제되고\n되돌릴 수 없어요.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // TODO: 백엔드 회원 탈퇴 API 연동.
              await AuthSession.logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text(
              '탈퇴하기',
              style: TextStyle(
                color: Color(0xFFE24B4A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 공용 위젯 ────────────────────────────────────────────────
PreferredSizeWidget _gAppBar(String title) =>
    RoundedGradientAppBar(title, color: kGuardian);

BoxDecoration _card() => BoxDecoration(
  color: kCard,
  borderRadius: BorderRadius.circular(18),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

class _StatCard extends StatelessWidget {
  final String emoji, label, value, sub;
  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final String emoji, text, time;
  const _ActivityRow({
    required this.emoji,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: kText),
            ),
          ),
          Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }
}

class _GNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _GNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 10,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? kGuardianLight : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? kGuardian : kTextSub, size: 22),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: kGuardian,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
