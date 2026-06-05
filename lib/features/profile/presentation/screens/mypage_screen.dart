import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/providers/user_role.dart';

/// 환자 '내 정보' 탭. 프로필·보호자·설정은 다음 단계에서 구현.
/// 지금은 자리표시자 + 데모용 역할 전환 버튼만.
class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '내 정보',
          style: TextStyle(
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '프로필(이름·나이·증상/질환) · 폴라 연결 · 보호자 정보 · 설정\n(다음 단계에서 구현)',
              style: TextStyle(fontSize: 14, color: kTextSub, height: 1.5),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                ref.read(userRoleProvider.notifier).state = UserRole.guardian;
              },
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
    );
  }
}
