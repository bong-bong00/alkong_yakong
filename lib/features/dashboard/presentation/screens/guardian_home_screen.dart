import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/session/auth_session.dart';
import '../../../../core/widgets/rounded_gradient_app_bar.dart';
import 'profile_edit_screen.dart';

// ════════════════════════════════════════════════════════════════
//  [보호자홈] 실시간 복약 모니터링 (보호자 색: kGuardian)
//  4개 탭 모두 동일한 공용 상단바(RoundedGradientAppBar)를 쓴다.
// ════════════════════════════════════════════════════════════════
class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _index = 0;

  void _handleSwitchToPatient() {
    // 환자 데모에서 push로 들어온 경우 pop, 보호자 계정으로 바로 진입한 경우 환자 홈으로.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const _PatientStatusTab(),
      const _PatientRecordTab(),
      const _AlertsTab(),
      _GuardianMyPage(onSwitchToPatient: _handleSwitchToPatient),
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
          ],
        ),
      ),
    );
  }
}

// ── 복약 기록 ────────────────────────────────────────────────
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
                  color: ok ? kGuardian : const Color(0xFFE6A100),
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
      ),
    );
  }
}

// ── 알림 ─────────────────────────────────────────────────────
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
              c = kGuardian;
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

// ── 내 정보 ──────────────────────────────────────────────────
class _GuardianMyPage extends StatelessWidget {
  final VoidCallback onSwitchToPatient;
  const _GuardianMyPage({required this.onSwitchToPatient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: _gAppBar('내 정보'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 보호자 본인 정보 — 누르면 정보 수정 화면
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
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
                          child: Text('👩', style: TextStyle(fontSize: 26)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
              const Spacer(),
              GestureDetector(
                onTap: onSwitchToPatient,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: kGuardianLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kGuardian.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        color: kGuardian,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '환자 화면으로 전환',
                        style: TextStyle(
                          color: kGuardian,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                  Container(width: 0.5, height: 14, color: Colors.grey[400]),
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
// 환자 화면과 100% 동일한 공용 상단바. 색만 보호자 색(kGuardian)으로.
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
