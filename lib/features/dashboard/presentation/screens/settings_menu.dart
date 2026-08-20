import 'package:flutter/material.dart';

import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 내 정보 탭의 도움말·약관 목록.
///
/// 아이콘 단독 사용을 금지했으므로 아이콘을 걷어내고 한글 라벨만 남겼다.
/// 행 높이는 상하 패딩 17px로 최소 56px를 넘긴다.
class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key});

  void _todo(BuildContext context, String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name — 아직 준비 중이에요')));
  }

  @override
  Widget build(BuildContext context) {
    const labels = <String>[
      '도움이 필요할 때',
      '알려드릴 소식',
      '이용약관',
      '개인정보처리방침',
    ];

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SeniorDivider(),
            SeniorListRow(
              label: labels[i],
              trailing: const SeniorChevron(),
              onTap: () => _todo(context, labels[i]),
            ),
          ],
        ],
      ),
    );
  }
}
