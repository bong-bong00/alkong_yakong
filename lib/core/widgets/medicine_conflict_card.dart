import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import 'senior_card.dart';

class MedicineConflictCard extends StatelessWidget {
  final Map<String, dynamic> match;

  const MedicineConflictCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final medicines = _pairMedicines(match);
    final why = _whyEasy(match);
    final source = _sourceLabel(match);

    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      borderColor: AppColors.danger,
      borderWidth: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 시안 22 — 무엇과 무엇이 부딪히는지를 한 문장으로 먼저 말한다.
          // 배지로 "꼭 확인하세요"라고만 하면 무엇을 확인할지가 아래로 밀린다.
          if (medicines.length >= 2)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: medicines[0].name,
                    style: AppText.cardTitle(size: 22, color: AppColors.danger),
                  ),
                  TextSpan(text: '과 ', style: AppText.cardTitle(size: 22)),
                  TextSpan(
                    text: medicines[1].name,
                    style: AppText.cardTitle(size: 22, color: AppColors.danger),
                  ),
                  TextSpan(
                    text: '은 함께 드시는 건 주의해 주세요',
                    style: AppText.cardTitle(size: 22),
                  ),
                ],
              ),
            )
          else
            Text(
              '함께 드실 때 주의가 필요해요',
              style: AppText.cardTitle(size: 22, color: AppColors.danger),
            ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _whyHeadline(why),
              style: AppText.label(size: 19, color: AppColors.textPrimary),
            ),
            if (_whyDetail(why).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_whyDetail(why), style: AppText.body(size: 19)),
            ],
          ],
          if (source.isNotEmpty) ...[
            const SizedBox(height: 12),
            // 출처는 참고용이다. 본문보다 눈에 덜 띄게 둔다.
            Text(source, style: AppText.caption(size: 17)),
          ],
        ],
      ),
    );
  }

  static List<_NamedMedicine> _pairMedicines(Map<String, dynamic> match) {
    final namesA = _namesOf(match['medicine_names_a']);
    final namesB = _namesOf(match['medicine_names_b']);
    final uniqueA = namesA.isEmpty ? '' : namesA.first;
    var uniqueB = namesB.isEmpty ? '' : namesB.first;
    if (uniqueB.isEmpty || uniqueB == uniqueA) {
      final all = [...namesA, ...namesB].where((n) => n.isNotEmpty).toList();
      final unique = <String>[];
      for (final name in all) {
        if (!unique.contains(name)) unique.add(name);
      }
      if (unique.length >= 2) {
        return [_NamedMedicine(unique[0]), _NamedMedicine(unique[1])];
      }
      if (unique.length == 1) {
        return [_NamedMedicine(unique[0])];
      }
      return const [];
    }
    return [_NamedMedicine(uniqueA), _NamedMedicine(uniqueB)];
  }

  static List<String> _namesOf(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if (_shortDrugName(value.toString()).isNotEmpty)
          _shortDrugName(value.toString()),
    ];
  }

  static String _shortDrugName(String name) {
    final trimmed = name.trim();
    final index = trimmed.indexOf('(');
    if (index > 0) return trimmed.substring(0, index).trim();
    return trimmed;
  }

  static String _whyEasy(Map<String, dynamic> match) {
    final why = _trimWhy((match['why_easy'] ?? '').toString());
    if (why.isNotEmpty) return why;
    final count = _pairMedicines(match).length;
    final opener = switch (count) {
      3 => '세 약을 같이 드시면, ',
      4 => '네 약을 같이 드시면, ',
      _ => '두 약을 같이 드시면, ',
    };
    final body = switch ((match['type'] ?? '').toString()) {
      '중복성분' => '같은 성분이 들어 있어서, 양이 겹칩니다.',
      '효능군중복' => '비슷한 일을 해서, 효과가 겹칩니다.',
      _ => '몸에 부담이 겹칠 수 있어요. 약국이나 병원에 한 번 확인해 주세요.',
    };
    return _trimWhy('$opener$body');
  }

  /// 분홍 상자 맨 윗줄. 첫 문장만 굵게 읽힌다.
  static String _whyHeadline(String why) {
    final cut = why.indexOf('. ');
    if (cut < 0) return why;
    return why.substring(0, cut + 1);
  }

  /// 첫 문장 뒤에 남는 설명. 없으면 빈 글자.
  static String _whyDetail(String why) {
    final cut = why.indexOf('. ');
    if (cut < 0) return '';
    return why.substring(cut + 2).trim();
  }

  static String _trimWhy(String raw) {
    var text = raw.trim();
    const openers = [
      '두 약을 같이 드시면, ',
      '세 약을 같이 드시면, ',
      '네 약을 같이 드시면, ',
      '다섯 약을 같이 드시면, ',
    ];
    for (final opener in openers) {
      if (text.startsWith(opener)) {
        text = text.substring(opener.length);
        break;
      }
    }
    text = text.replaceAll('약국이나 병원에 한 번 확인해 주세요.', '').trim();
    return text;
  }

  static String _sourceLabel(Map<String, dynamic> match) {
    final label = (match['source_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    return switch ((match['type'] ?? '').toString()) {
      '병용금기' => '식약처 DUR 병용금기 참조',
      '효능군중복' => '식약처 DUR 효능군중복 참조',
      '중복성분' => '같은 성분 중복 참조',
      _ => '식약처 DUR 참조',
    };
  }
}

class _NamedMedicine {
  final String name;
  const _NamedMedicine(this.name);
}
