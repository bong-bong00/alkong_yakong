import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';

/// 스낵바.
///
/// **보호자에게 연락한 결과는 이것으로만 알린다.** 어르신 화면에는 전화 걸기
/// 버튼을 두지 않고, 앱이 대신 보낸 뒤 여기서 "보냈어요"라고 말해 준다.
void showSeniorSnackbar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: AppColors.snackbarBg,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 26),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      content: Row(
        children: [
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.circle_check_filled,
              size: 24,
              color: AppColors.snackbarCheck,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              message,
              style: AppText.label(size: 18.5, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 세그먼트 컨트롤 — 이번 주 / 한 달, 일반 / 쉬운 화면.
class SeniorSegmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const SeniorSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 54),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.point : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: AppText.cardTitle(
                        size: 18.5,
                        color: i == index
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 번호를 붙인 안내 단계. **항상 3단계 이내.**
///
/// 회복 절차, 측정 안내, 센서 착용법에 쓴다.
class NumberedSteps extends StatelessWidget {
  final List<String> steps;

  /// 위험 맥락이면 번호 원이 붉어진다.
  final bool danger;

  /// 카드 안에 넣을 때는 회색 블록으로 감싼다.
  final bool boxed;

  const NumberedSteps({
    super.key,
    required this.steps,
    this.danger = false,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    assert(steps.length <= 3, '지시는 3단계 이내로 둔다');
    final color = danger ? AppColors.danger : AppColors.point;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${i + 1}',
                  style: AppText.cardTitle(size: 16, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    steps[i],
                    style: AppText.label(
                      size: 18.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (!boxed) return column;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: column,
    );
  }
}

/// 입력 필드. 라벨은 필드 위에 둔다.
class SeniorField extends StatelessWidget {
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  /// 오류가 있으면 테두리가 붉어진다.
  final bool hasError;

  const SeniorField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: AppText.label(size: 18)),
          const SizedBox(height: 8),
        ],
        Container(
          constraints: const BoxConstraints(minHeight: 66),
          decoration: BoxDecoration(
            color: AppColors.sunken,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError ? AppColors.danger : AppColors.strongLine,
              width: 2,
            ),
          ),
          padding: EdgeInsets.only(left: 20, right: suffix == null ? 20 : 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: AppText.label(
                    size: 21,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: hint,
                    hintStyle: AppText.label(
                      size: 21,
                      color: AppColors.chevron,
                    ),
                  ),
                ),
              ),
              ?suffix,
            ],
          ),
        ),
      ],
    );
  }
}

/// 오류 안내 블록. 붉은 연한 면에 붉은 글씨.
class SeniorErrorBox extends StatelessWidget {
  final String message;
  const SeniorErrorBox(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: AppText.cardTitle(size: 18, color: AppColors.danger),
      ),
    );
  }
}
