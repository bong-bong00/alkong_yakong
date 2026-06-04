import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../drug_explain/drug_explain_screen.dart';
import 'dashboard_screen.dart';

/// 하단 탭바를 4개 탭 전체에서 유지하는 쉘(Shell).
/// 탭 전환은 IndexedStack 인덱스만 바꾸고, Navigator.push 는 쓰지 않는다.
/// (처방전·생체신호·복약안전도 같은 '상세' 화면만 push 로 연다.)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  void _goToTab(int index) => setState(() => _navIndex = index);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(onOpenDrugInfo: () => _goToTab(1)),
      DrugExplainScreen(),
      DashboardScreen(),
      const _MyPageTab(),
    ];

    return Scaffold(
      backgroundColor: kBackground,
      // 4개 탭을 한 곳에 쌓아두고 인덱스만 바꾼다. push 안 함 → 하단바 항상 유지.
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

/// 홈 탭 본문 (기존 HomeScreen 의 내용을 그대로 옮긴 것).
/// 자체 Scaffold(그라데이션 헤더 포함)를 가지며 하단바는 쉘이 담당한다.
class _HomeTab extends StatefulWidget {
  /// '빠른 메뉴 > AI 약물 설명' 을 누르면 약정보 탭으로 전환하기 위한 콜백.
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

  void _onTakeMedicine(int index) {
    setState(() {
      _todayMeds[index]['done'] = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('복약 완료! 폴라 센서 동기화 중...'),
        backgroundColor: kPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [kPrimary, Color(0xFF25B88A)]),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('💊', style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '알콩약콩',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
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
            ),
          ),
        ),
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

            // 폴라 센서 상태 (생체신호 상세 화면은 push 로 연다)
            GestureDetector(
              onTap: () => context.push('/biosignal'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE8F5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFC8B8E0)),
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
                          color: Color(0xFF534AB7),
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
                        ? Container(
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
                          )
                        : GestureDetector(
                            onTap: () => _onTakeMedicine(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [kPrimary, Color(0xFF25B88A)],
                                ),
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
                    // 약정보는 탭이므로 push 대신 탭 전환
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

/// 내 정보 탭 (아직 화면 미구현 → 자리표시자).
class _MyPageTab extends StatelessWidget {
  const _MyPageTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        title: const Text(
          '내 정보',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          '내 정보 화면 준비 중',
          style: TextStyle(fontSize: 15, color: Colors.grey[500]),
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
