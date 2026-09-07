import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/senior_bottom_nav.dart';
import '../../../profile/presentation/screens/mypage_screen.dart';
import 'medication_record_screen.dart';
import 'patient_home_screen.dart';

/// 환자 쉘 — 탭은 **오늘 · 기록 · 내 정보** 셋뿐이다.
///
/// 기존 4탭(홈·약 정보·기록·내 정보)에서 "약 정보"를 뺐다.
/// 한 화면 = 핵심 행동 하나라는 원칙에 따라, 약 설명은 필요한 자리
/// (처방전 확인, 함께먹기 주의)에서 열리게 하고 상시 탭에서는 내렸다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const List<SeniorNavItem> _tabs = [
    SeniorNavItem(icon: TablerIcons.pill, label: '오늘'),
    SeniorNavItem(icon: TablerIcons.calendar, label: '기록'),
    SeniorNavItem(icon: TablerIcons.user, label: '내 정보'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        index: _index,
        children: [
          PatientHomeScreen(
            onOpenRecord: () => setState(() => _index = 1),
            onOpenHeartbeat: () => context.push('/biosignal'),
          ),
          const MedicationRecordScreen(),
          const MyPageScreen(),
        ],
      ),
      bottomNavigationBar: SeniorBottomNav(
        items: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
      // 어느 탭에 있든 약에 관해 바로 물어볼 수 있게 하단 탭 위에 둔다.
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/drug-explain'),
        child: const Icon(TablerIcons.message_circle),
        tooltip: '약 상담 열기',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
