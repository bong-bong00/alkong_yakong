import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_sheet.dart';

/// 가족에게 처방전 등록을 부탁할 때 띄우는 안내 (어르신 화면).
///
/// 어르신 전화기에서는 할 일이 없다 — 자녀분이 **보호자 앱**에서 넣어 준다.
/// 그 말을 화면을 옮기지 않고 그 자리에서 알려 준다.
Future<void> showFamilyRequestSheet(
  BuildContext context, {
  required String guardianTitle,
}) {
  final family = guardianTitle.trim().isEmpty ? '가족' : guardianTitle.trim();
  return SeniorSheet.show<void>(
    context: context,
    builder: (sheetContext) => SeniorSheet(
      title: '$family이 보호자 앱에서 넣어드려요',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '어르신 전화기에서 하실 일은 없어요. 자녀분께 이렇게 전해 주세요.',
            style: AppText.body(size: 19),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.pointFill,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppText.cardTitle(size: 17, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _steps[i],
                    style: AppText.label(
                      size: 19,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '다 넣으시면 어르신 전화기에 "약이 들어왔어요" 알림이 옵니다.',
            style: AppText.body(size: 18),
          ),
        ],
      ),
      actions: [
        SeniorButton(
          label: '알겠어요',
          icon: TablerIcons.check,
          minHeight: 70,
          fontSize: 23,
          onPressed: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    ),
  );
}

const List<String> _steps = [
  '보호자 앱을 엽니다',
  '"돌보는 분"에서 어르신을 고릅니다',
  '"처방전 대신 찍기"를 눌러 처방전을 찍습니다',
];
