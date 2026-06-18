import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/rounded_gradient_app_bar.dart';
import '../../../drug_explain/drug_explain_screen.dart';
import 'dashboard_screen.dart';
import 'guardian_home_screen.dart';

/// 하단 탭바를 4개 탭 전체에서 유지하는 쉘(Shell).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  void _goToTab(int index) => setState(() => _navIndex = index);

  void _openGuardian() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const GuardianHomeScreen()))
        .then((_) {
          if (mounted) _goToTab(0);
        });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(onOpenDrugInfo: () => _goToTab(1)),
      DrugExplainScreen(),
      DashboardScreen(),
      _MyPageTab(onSwitchToGuardian: _openGuardian),
    ];

    return Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(index: _navIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
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
                _NavItem(
                  icon: Icons.home_rounded,
                  label: '홈',
                  isSelected: _navIndex == 0,
                  onTap: () => _goToTab(0),
                ),
                _NavItem(
                  icon: Icons.search_rounded,
                  label: '약 정보',
                  isSelected: _navIndex == 1,
                  onTap: () => _goToTab(1),
                ),
                _NavItem(
                  icon: Icons.calendar_month_rounded,
                  label: '기록',
                  isSelected: _navIndex == 2,
                  onTap: () => _goToTab(2),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: '내 정보',
                  isSelected: _navIndex == 3,
                  onTap: () => _goToTab(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final VoidCallback onOpenDrugInfo;

  const _HomeTab({required this.onOpenDrugInfo});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final List<Map<String, dynamic>> _todayMeds = [
    {
      'time': '아침 08:00',
      'pills': ['암로디핀 5mg', '아스피린 100mg'],
      'done': true,
    },
    {
      'time': '점심 12:00',
      'pills': ['메트포르민 500mg'],
      'done': false,
    },
    {
      'time': '저녁 18:00',
      'pills': ['메트포르민 500mg', '암로디핀 5mg'],
      'done': false,
    },
  ];

  void _toggleMedicine(int index) {
    final nowDone = !(_todayMeds[index]['done'] as bool);
    setState(() {
      _todayMeds[index]['done'] = nowDone;
    });
    if (nowDone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('복약 완료! 폴라 센서 동기화 중...'),
          backgroundColor: kPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      // 다른 모든 탭과 동일한 공용 상단바 (로고 + 알림 아이콘만 추가)
      appBar: RoundedGradientAppBar(
        '알콩약콩',
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('💊', style: TextStyle(fontSize: 18)),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '안녕하세요 👋',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: kText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '오늘도 안전한 복약을 도와드릴게요',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),

            // 폴라 센서 상태 (분홍 유지)
            GestureDetector(
              onTap: () => context.push('/biosignal'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFAD4DD)),
                ),
                child: Row(
                  children: [
                    const Text('💓', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '폴라 센서 연결됨 · 심박수 측정 중',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC2185B),
                        ),
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 오늘의 복약
            Row(
              children: [
                const Text('💊', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                const Text(
                  '오늘의 복약',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_todayMeds.where((m) => m['done'] == true).length}/${_todayMeds.length} 완료',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            ...List.generate(_todayMeds.length, (i) {
              final med = _todayMeds[i];
              final done = med['done'] as bool;
              final pills = (med['pills'] as List).join(', ');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            med['time'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pills,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: done ? Colors.grey : kText,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    done
                        ? GestureDetector(
                            onTap: () => _toggleMedicine(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '완료 ✓',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                          )
                        : GestureDetector(
                            onTap: () => _toggleMedicine(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25B88A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '약 먹었어요',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),

            // 빠른 메뉴
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onOpenDrugInfo,
                    child: _QuickMenu(
                      emoji: '🤖',
                      title: 'AI 약물 설명',
                      sub: '내 약 쉽게 알아보기',
                      bgColor: const Color(0xFFE3EEF8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/dur-analysis'),
                    child: _QuickMenu(
                      emoji: '🛡️',
                      title: '복약 안전도',
                      sub: 'LOW',
                      bgColor: const Color(0xFFE8F5E9),
                      isTag: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/prescription'),
                    child: _QuickMenu(
                      emoji: '📋',
                      title: '처방전 등록',
                      sub: 'OCR 자동 추출',
                      bgColor: const Color(0xFFFFF3E0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/biosignal'),
                    child: _QuickMenu(
                      emoji: '💓',
                      title: '생체 신호',
                      sub: '심박수 그래프 확인',
                      bgColor: const Color(0xFFFFEBEE),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 내 정보 탭 — 공용 상단바 + 보호자 전환 버튼(맨 아래).
class _MyPageTab extends StatelessWidget {
  final VoidCallback onSwitchToGuardian;
  const _MyPageTab({required this.onSwitchToGuardian});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: const RoundedGradientAppBar('내 정보'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
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
                          '김복자',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kText,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '환자 · 보호자 1명 연결됨',
                          style: TextStyle(fontSize: 13, color: kTextSub),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSwitchToGuardian,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horiz_rounded, color: kPrimary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '보호자 화면으로 전환 (데모)',
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
      ),
    );
  }
}

class _QuickMenu extends StatelessWidget {
  final String emoji;
  final String title;
  final String sub;
  final Color bgColor;
  final bool isTag;

  const _QuickMenu({
    required this.emoji,
    required this.title,
    required this.sub,
    required this.bgColor,
    this.isTag = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          const SizedBox(height: 2),
          isTag
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                )
              : Text(
                  sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
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
          horizontal: isSelected ? 16 : 12,
          vertical: 10,
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
                  fontSize: 13,
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
