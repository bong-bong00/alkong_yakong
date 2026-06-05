import 'package:flutter/material.dart';
<<<<<<< Updated upstream
import '../../../../core/constants/app_colors.dart';

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});
  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('보호자 모드 👀', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 2),
          Text('가족의 복약 상태를 확인하세요', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          const SizedBox(height: 20),

          // [환자 선택]
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PatientChip(name: '김영수', emoji: '👴', isSelected: _selected == 0, onTap: () => setState(() => _selected = 0)),
                const SizedBox(width: 10),
                _PatientChip(name: '박순이', emoji: '👵', isSelected: _selected == 1, onTap: () => setState(() => _selected = 1)),
                const SizedBox(width: 10),
                _AddChip(),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // [오늘 복용약]
          _PillList(title: '오늘 복용약', badge: '2/3 완료', badgeColor: kPrimary, items: const [
            _PillItem(name: '암로디핀 5mg · 아침', status: 1),
            _PillItem(name: '메트포르민 500mg · 점심', status: 1),
            _PillItem(name: '메트포르민 500mg · 저녁', status: -1),
          ]),
          const SizedBox(height: 14),

          // [내일 복용약]
          _PillList(title: '내일 복용약', items: const [
            _PillItem(name: '암로디핀 5mg · 아침', status: 0),
            _PillItem(name: '메트포르민 500mg · 아침/점심/저녁', status: 0),
            _PillItem(name: '아스피린 100mg · 아침', status: 0),
          ]),
          const SizedBox(height: 14),

          // [생체 신호 상태]
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: kGreenLight, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: Text('💚', style: TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('생체 신호', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                    Text('오늘 측정 완료 · 정상 범위', style: TextStyle(fontSize: 12, color: kGreen)),
                  ],
                )),
                const Icon(Icons.chevron_right_rounded, color: kTextSub),
              ],
            ),
          ),
        ],
=======
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/user_role.dart';

/// 보호자용 4탭 쉘: 환자 현황 / 복약 기록 / 알림 / 내정보
/// 연결된 환자(김복자)의 데이터를 모니터링한다. (더미 데이터)
class GuardianShell extends ConsumerStatefulWidget {
  const GuardianShell({super.key});

  @override
  ConsumerState<GuardianShell> createState() => _GuardianShellState();
}

class _GuardianShellState extends ConsumerState<GuardianShell> {
  int _navIndex = 0;
  void _goToTab(int index) => setState(() => _navIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _PatientStatusTab(),
      const _PatientRecordTab(),
      const _AlertsTab(),
      _GuardianMyPage(
        onSwitchToPatient: () =>
            ref.read(userRoleProvider.notifier).state = UserRole.patient,
      ),
    ];

    return Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(index: _navIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _GNavItem(
                  icon: Icons.monitor_heart_rounded,
                  label: '환자 현황',
                  isSelected: _navIndex == 0,
                  onTap: () => _goToTab(0),
                ),
                _GNavItem(
                  icon: Icons.calendar_month_rounded,
                  label: '복약 기록',
                  isSelected: _navIndex == 1,
                  onTap: () => _goToTab(1),
                ),
                _GNavItem(
                  icon: Icons.notifications_rounded,
                  label: '알림',
                  isSelected: _navIndex == 2,
                  onTap: () => _goToTab(2),
                ),
                _GNavItem(
                  icon: Icons.person_rounded,
                  label: '내 정보',
                  isSelected: _navIndex == 3,
                  onTap: () => _goToTab(3),
                ),
              ],
            ),
          ),
        ),
>>>>>>> Stashed changes
      ),
    );
  }
}

<<<<<<< Updated upstream
class _PatientChip extends StatelessWidget {
  final String name; final String emoji; final bool isSelected; final VoidCallback onTap;
  const _PatientChip({required this.name, required this.emoji, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryLight : kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isSelected ? kPrimary : kBorder, width: isSelected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
=======
// ── 환자 현황 ──────────────────────────────────────────────
class _PatientStatusTab extends StatelessWidget {
  const _PatientStatusTab();

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
            // 환자 카드 + 상태
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
                          color: kPrimaryLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text('🧓', style: TextStyle(fontSize: 26)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '김복자 (어머니)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kText,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '72세 · 마지막 동기화 방금 전',
                            style: TextStyle(fontSize: 12, color: kTextSub),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Text('✅', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '오늘 이상 없음 · 심박 정상',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
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

            // 오늘 복약 / 현재 심박
            Row(
              children: const [
                Expanded(
                  child: _StatCard(
                    emoji: '💊',
                    label: '오늘 복약',
                    value: '2/3',
                    sub: '저녁 18:00 예정',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    emoji: '💓',
                    label: '현재 심박',
                    value: '78',
                    sub: '정상 범위',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 최근 활동
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
                children: const [
                  _ActivityRow(emoji: '✅', text: '점심 약 복용 완료', time: '12:04'),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  _ActivityRow(
                    emoji: '💓',
                    text: '복약 후 심박 정상 (80 bpm)',
                    time: '12:14',
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16),
                  _ActivityRow(emoji: '✅', text: '아침 약 복용 완료', time: '08:10'),
                ],
              ),
            ),
>>>>>>> Stashed changes
          ],
        ),
      ),
    );
  }
}

<<<<<<< Updated upstream
class _AddChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded, size: 28, color: kTextSub),
          const SizedBox(height: 4),
          Text('추가', style: TextStyle(fontSize: 11, color: kTextSub)),
        ],
=======
// ── 복약 기록 ──────────────────────────────────────────────
class _PatientRecordTab extends StatelessWidget {
  const _PatientRecordTab();

  @override
  Widget build(BuildContext context) {
    final days = [
      {'date': '6월 5일 (오늘)', 'status': '진행 중 2/3', 'ok': true},
      {'date': '6월 4일', 'status': '복약 완료', 'ok': true},
      {'date': '6월 3일', 'status': '저녁 미복약', 'ok': false},
      {'date': '6월 2일', 'status': '복약 완료', 'ok': true},
      {'date': '6월 1일', 'status': '복약 완료', 'ok': true},
    ];
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('복약 기록'),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final d = days[i];
          final ok = d['ok'] as bool;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: ok ? kPrimary : const Color(0xFFE6A100),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    d['date'] as String,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                ),
                Text(
                  d['status'] as String,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ok ? Colors.grey[600] : const Color(0xFFE6A100),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
>>>>>>> Stashed changes
      ),
    );
  }
}

<<<<<<< Updated upstream
class _PillItem {
  final String name; final int status; // 1=완료, -1=미완료, 0=예정
  const _PillItem({required this.name, required this.status});
}

class _PillList extends StatelessWidget {
  final String title; final String? badge; final Color? badgeColor; final List<_PillItem> items;
  const _PillList({required this.title, this.badge, this.badgeColor, required this.items});
=======
// ── 알림 ───────────────────────────────────────────────────
class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context) {
    final alerts = [
      {
        'type': 'done',
        'title': '복약 완료',
        'desc': '김복자님이 점심 약을 복용했어요 (심박 80)',
        'time': '12:04',
      },
      {
        'type': 'done',
        'title': '복약 완료',
        'desc': '김복자님이 아침 약을 복용했어요',
        'time': '08:10',
      },
      {
        'type': 'miss',
        'title': '미복약 알림',
        'desc': '6/3 저녁 약을 복용하지 않았어요',
        'time': '어제',
      },
    ];
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('알림'),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        itemCount: alerts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = alerts[i];
          final type = a['type'];
          Color c;
          IconData icon;
          switch (type) {
            case 'miss':
              c = const Color(0xFFE6A100);
              icon = Icons.warning_amber_rounded;
              break;
            case 'alert':
              c = const Color(0xFFE24B4A);
              icon = Icons.priority_high_rounded;
              break;
            default:
              c = kPrimary;
              icon = Icons.check_circle_rounded;
          }
          return Container(
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
                        a['title'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a['desc'] as String,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  a['time'] as String,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── 내 정보 ────────────────────────────────────────────────
class _GuardianMyPage extends StatelessWidget {
  final VoidCallback onSwitchToPatient;
  const _GuardianMyPage({required this.onSwitchToPatient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('내 정보'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
                      child: Text('👩', style: TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '김지안',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: kText,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '보호자 · 연결된 환자 1명',
                        style: TextStyle(fontSize: 13, color: kTextSub),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _card(),
              child: const Row(
                children: [
                  Text('🧓', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '연결된 환자: 김복자 (어머니)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onSwitchToPatient,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: kPrimaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: kPrimary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '환자 화면으로 전환 (데모)',
                      style: TextStyle(
                        color: kPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 공용 위젯 ──────────────────────────────────────────────
PreferredSizeWidget _gAppBar(String title) => AppBar(
  backgroundColor: kPrimary,
  elevation: 0,
  centerTitle: false,
  title: Text(
    title,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 20,
    ),
  ),
  flexibleSpace: Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [kPrimary, Color(0xFF25B88A)]),
    ),
  ),
);

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
>>>>>>> Stashed changes

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
<<<<<<< Updated upstream
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
              if (badge != null) Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor)),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(item.name, style: const TextStyle(fontSize: 13, color: kText))),
                if (item.status == 1) const Icon(Icons.check_circle_rounded, color: kPrimary, size: 20),
                if (item.status == -1) const Icon(Icons.cancel_rounded, color: kPink, size: 20),
              ],
            ),
          )),
=======
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
>>>>>>> Stashed changes
        ],
      ),
    );
  }
}
<<<<<<< Updated upstream
=======

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
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? kPrimary : kTextSub, size: 22),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: kPrimary,
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
>>>>>>> Stashed changes
