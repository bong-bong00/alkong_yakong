import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// Show only notification channels that the app actually supports.
class GuardianAlertPrefsScreen extends StatelessWidget {
  const GuardianAlertPrefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '알림 안내', alignStart: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('보호자가 확인할 수 있는 것', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  SeniorCard(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      '앱을 열어 돌보는 분의 복약 상태와 심박 기록을 확인할 수 있어요. '
                      '돌보는 분 화면을 보는 동안 새 정보를 주기적으로 조회합니다.',
                      style: AppText.body(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('현재 지원 범위', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  SeniorCard(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      '환자 휴대폰의 복약 시간 알림과 앱 안의 기록·알림을 지원해요. '
                      '보호자에게 문자나 앱 종료 중 푸시를 보내지는 않아요. '
                      '밤 시간 소리 설정도 아직 지원하지 않아요.',
                      style: AppText.body(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
