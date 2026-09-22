import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_sheet.dart';

/// 못 읽은 약 이름이 있을 때 먼저 알리는 시트.
///
/// **사용자를 탓하지 않는다** — "고장이 아니에요"로 시작한다. 그리고 못 읽은
/// 이름을 등록에서 빼 두었다는 사실을 먼저 말한다. 조용히 빼 두면 어르신은
/// 그 약을 등록했다고 믿고 안 드신다.
///
/// 다시 찍기를 고르면 true, 이대로 계속하면 false.
Future<bool> showUnreadNamesSheet(
  BuildContext context, {
  required List<String> names,
}) async {
  final retake = await SeniorSheet.show<bool>(
    context: context,
    builder: (sheetContext) => SeniorSheet(
      title: '못 읽은 이름이 있어요',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            names.length == 1
                ? '고장이 아니에요. 사진이 흐려서 이름 하나를 못 읽었어요. '
                      '아래 약은 등록에서 빼 두었습니다.'
                : '고장이 아니에요. 사진이 흐려서 이름 ${names.length}개를 못 읽었어요. '
                      '아래 약은 등록에서 빼 두었습니다.',
            style: AppText.body(size: 19),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.dangerBgSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.dangerBorder, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < names.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Text(
                    '· ${names[i]} (못 읽음)',
                    style: AppText.label(size: 18.5, color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        SeniorButton(
          label: '밝은 곳에서 다시 찍기',
          icon: TablerIcons.camera,
          minHeight: 70,
          fontSize: 23,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
        SeniorButton(
          label: '이대로 계속하기',
          kind: SeniorButtonKind.secondary,
          minHeight: 64,
          fontSize: 21,
          onPressed: () => Navigator.of(sheetContext).pop(false),
        ),
      ],
    ),
  );
  return retake ?? false;
}
