import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// 내 정보 탭 공용 설정·지원 메뉴.
/// 환자·보호자 양쪽에서 사용. accent 로 아이콘 색만 구분.
/// 각 항목은 아직 화면이 없어서 누르면 "준비 중" 안내를 띄운다(// TODO).
/// 위치: lib/features/dashboard/presentation/screens/settings_menu.dart
class SettingsMenu extends StatelessWidget {
  final Color accent;
  const SettingsMenu({super.key, this.accent = kPrimary});

  void _todo(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name — 준비 중이에요'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: [
          _row(context, Icons.campaign_outlined, '공지사항'),
          _divider(),
          _row(context, Icons.headset_mic_outlined, '고객센터 · 문의하기'),
          _divider(),
          _row(context, Icons.notifications_none_rounded, '알림 설정'),
          _divider(),
          _row(context, Icons.description_outlined, '이용약관'),
          _divider(),
          _row(context, Icons.privacy_tip_outlined, '개인정보처리방침'),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, indent: 52, endIndent: 16, color: Colors.grey[200]);

  Widget _row(BuildContext context, IconData icon, String label) {
    return InkWell(
      onTap: () => _todo(context, label),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 21, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14.5, color: kText),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }
}
