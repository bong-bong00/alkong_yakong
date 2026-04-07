import 'package:flutter/material.dart';
// [참조] 공통 색상 및 분리된 화면들 가져오기
import '../../../../core/constants/app_colors.dart';
import 'patient_home_screen.dart';
import 'guardian_home_screen.dart';

// ════════════════════════════════════════════════════
//  [메인화면] 환자/보호자 탭 전환 화면 (관리자 역할)
// ════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // [탭컨트롤러] 환자/보호자 탭 전환 담당
  late TabController _tabController;
  // [네비게이션-현재인덱스] 0=홈 1=검색 2=카메라 3=기록 4=메뉴
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    // [탭초기화] 탭 개수 2개 (환자, 보호자)
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,

      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        title: const Text(
          '알콩약콩',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            // [앱바-제목폰트] 상단 '알콩약콩' 글자 크기
            fontSize: 20,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          // [탭-밑줄두께] 선택된 탭 하단 흰색 밑줄 두께
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            // [탭-글자크기] '환자' '보호자' 탭 글자 크기
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          tabs: const [
            Tab(text: '환자'),
            Tab(text: '보호자'),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: const [
          // [연결] 분리된 환자 탭 화면 (patient_home_screen.dart)
          PatientHomeScreen(),
          // [연결] 분리된 보호자 탭 화면 (guardian_home_screen.dart)
          GuardianHomeScreen(),
        ],
      ),

      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

// ════════════════════════════════════════════════════
//  [네비게이션바] 하단 홈/검색/카메라/기록/메뉴
// ════════════════════════════════════════════════════
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            // [수정] withOpacity 대신 withValues 사용
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          // [네비게이션바-높이] 바 전체 높이
          height: 64,
          child: Stack(
            // [네비게이션바-클립] Clip.none = 카메라 버튼 허용
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // [네비게이션바-탭목록]
              Row(
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: '홈',
                    isSelected: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _NavItem(
                    icon: Icons.search_outlined,
                    activeIcon: Icons.search,
                    label: '검색',
                    isSelected: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  // [네비게이션바-카메라자리]
                  const Expanded(child: SizedBox()),
                  _NavItem(
                    icon: Icons.history_outlined,
                    activeIcon: Icons.history,
                    label: '기록',
                    isSelected: currentIndex == 3,
                    onTap: () => onTap(3),
                  ),
                  _NavItem(
                    icon: Icons.menu_outlined,
                    activeIcon: Icons.menu,
                    label: '메뉴',
                    isSelected: currentIndex == 4,
                    onTap: () => onTap(4),
                  ),
                ],
              ),

              // ── [카메라버튼] ──────────────────────────
              Positioned(
                // [카메라버튼-위치]
                top: -(110 - 64) / 2,
                child: GestureDetector(
                  onTap: () => onTap(2),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: kPrimary,
                      shape: BoxShape.circle,
                      // [카메라버튼-테두리두께]
                      border: Border.all(color: Colors.white, width: 5),
                      boxShadow: [
                        BoxShadow(
                          // [수정] withOpacity 대신 withValues 사용
                          color: kPrimary.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      // [카메라버튼-아이콘크기]
                      size: 46,
                    ),
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

// ════════════════════════════════════════════════════
//  [네비게이션아이템] 홈/검색/기록/메뉴 각각의 탭
// ════════════════════════════════════════════════════
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? kPrimary : Colors.grey[500],
              // [네비게이션아이템-아이콘크기]
              size: 26,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                // [네비게이션아이템-라벨폰트]
                fontSize: 11,
                color: isSelected ? kPrimary : Colors.grey[500],
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}