import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import 'senior_button.dart';
import 'senior_sheet.dart';

/// 예 / 아니요를 세로로 묻는 상태 안내창.
Future<bool> showSeniorYesNoDialog({
  required BuildContext context,
  required String title,
  String? message,
  String yesLabel = '예',
  String noLabel = '아니요',
}) async {
  final confirmed = await SeniorSheet.show<bool>(
    context: context,
    builder: (sheetContext) => SeniorSheet(
      title: title,
      body: (message == null || message.isEmpty)
          ? null
          : Text(message, style: AppText.body()),
      actions: [
        SeniorButton(
          label: yesLabel,
          minHeight: 66,
          fontSize: 22,
          onPressed: () => Navigator.of(sheetContext).pop(true),
        ),
        SeniorButton(
          label: noLabel,
          kind: SeniorButtonKind.secondary,
          minHeight: 62,
          fontSize: 21,
          onPressed: () => Navigator.of(sheetContext).pop(false),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// OCR 이름 수정 화면이 사용하는 기존 오류 안내.
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

/// 스낵바.
///
/// **보호자에게 연락한 결과는 이것으로만 알린다.** 어르신 화면에는 전화 걸기
/// 버튼을 두지 않고, 앱이 대신 보낸 뒤 여기서 "보냈어요"라고 말해 준다.
///
/// 입력이 틀렸거나 요청이 실패한 것도 [error]로 여기서 알린다. 화면 안에
/// 오류 박스를 끼워 넣으면 버튼 위에 붙어 버튼을 밀어낸다.
///
/// 화면 아래에 고정된 버튼이 있으면 그 높이를 [bottom]으로 넘겨 가리지 않게 한다.
void showSeniorSnackbar(
  BuildContext context,
  String message, {
  bool error = false,
  double bottom = 0,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: AppColors.snackbarBg,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, 26 + bottom),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              error
                  ? TablerIcons.alert_circle_filled
                  : TablerIcons.circle_check_filled,
              size: 24,
              color: error ? AppColors.dangerBorder : AppColors.snackbarCheck,
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

  /// 글자를 다듬는 규칙. 휴대폰 번호 하이픈 같은 것.
  final List<TextInputFormatter>? inputFormatters;

  /// 자판의 "완료"를 눌렀을 때.
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

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
    this.inputFormatters,
    this.onSubmitted,
    this.textInputAction,
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
                  inputFormatters: inputFormatters,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  onChanged: onChanged,
                  style: AppText.label(size: 21, color: AppColors.textPrimary),
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

/// 몇 개 중 하나를 고르는 칩 — 하루 복용 횟수, 며칠분, 나와의 관계.
///
/// 드롭다운을 쓰지 않는다. 목록이 접혀 있으면 지금 무엇이 골라져 있는지
/// 보이지 않고, 펼치는 동작이 한 번 더 든다.
class SeniorChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SeniorChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 62, minWidth: 92),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointTint : AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.point : AppColors.border,
                width: 2,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 20,
                color: selected ? AppColors.point : AppColors.textBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 값을 하나씩 올리고 내리는 스테퍼 — 한 번에 몇 알, 하루 몇 번, 며칠분.
///
/// ±로 한 칸씩 옮기는 길과, 숫자를 눌러 바로 적는 길을 **둘 다** 연다.
/// ±만 두면 30일을 맞추는 데 스물아홉 번을 눌러야 하고, 적는 칸만 두면
/// 자판이 어려운 분이 막힌다.
class SeniorStepper extends StatefulWidget {
  final String label;

  /// 숫자만 — "1", "0.5", "30".
  final String number;

  /// 숫자 뒤에 붙는 말 — "정", "번", "일".
  final String unit;

  /// 더 내릴 수 없으면 null. 버튼이 흐려진다.
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  /// 눌러서 직접 적었을 때. 적힌 글자 그대로 온다.
  final ValueChanged<String> onNumberChanged;

  const SeniorStepper({
    super.key,
    required this.label,
    required this.number,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    required this.onNumberChanged,
  });

  @override
  State<SeniorStepper> createState() => _SeniorStepperState();
}

class _SeniorStepperState extends State<SeniorStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.number,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(SeniorStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 적는 중에는 건드리지 않는다. ±로 바뀐 값만 칸에 되비친다.
    if (!_focus.hasFocus && widget.number != _controller.text) {
      _controller.text = widget.number;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: AppText.label(size: 18)),
        const SizedBox(height: 8),
        // 셋을 한 덩어리로 묶는다. 양 끝으로 밀어 두면 값과 버튼이 서로
        // 다른 것처럼 읽히고, 누를 곳을 눈으로 찾아가야 한다.
        // 작은 화면에서 글자를 키우면 셋이 한 줄에 안 들어간다. 그때는
        // 덩어리째 줄인다 — 버튼을 양 끝으로 밀어 떼어 놓지 않는다.
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepperButton(
                  icon: TablerIcons.minus,
                  semanticLabel: '${widget.label} 줄이기',
                  onPressed: widget.onMinus,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  // 칸처럼 그리지 않는다. 값은 그냥 글씨로 두고,
                  // 눌렀을 때만 자판이 올라온다.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        // 글자 폭만 차지하게 둔다. 고정폭 칸에 넣으면
                        // 값이 버튼 사이 가운데가 아니라 한쪽으로 쏠린다.
                        IntrinsicWidth(
                          child: Semantics(
                            label: '${widget.label} 직접 적기',
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              onChanged: widget.onNumberChanged,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                              style: AppText.bigTime(size: 24),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(widget.unit, style: AppText.bigTime(size: 24)),
                      ],
                    ),
                  ),
                ),
                _StepperButton(
                  icon: TablerIcons.plus,
                  semanticLabel: '${widget.label} 늘리기',
                  onPressed: widget.onPlus,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          // 테두리 없는 동그라미로 감싼다. 네모에 테두리까지 두면 값보다
          // 버튼이 먼저 눈에 들어온다. 누르는 자리는 원보다 넉넉히 둔다.
          child: SizedBox(
            width: 56,
            height: 52,
            child: Center(
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.secondaryFill,
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: Icon(icon, size: 24, color: AppColors.textBody),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "어머니 · 김복자 대신 등록" — 대신 넣어드리는 중임을 화면 맨 위에 붙인다.
///
/// 여러 어르신을 함께 보는 보호자가 엉뚱한 분에게 약을 넣는 일이 가장
/// 무섭다. 그래서 찍기·확인 화면마다 이 띠를 계속 달고 다닌다.
class ProxyBanner extends StatelessWidget {
  /// "어머니 · 김복자".
  final String title;

  const ProxyBanner({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    // 파랑 채움은 **누르는 것**에만 쓴다. 이 띠는 읽는 것이라 색을 뺀다.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ExcludeSemantics(
            child: Icon(
              TablerIcons.users,
              size: 26,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text('$title 대신 등록', style: AppText.cardTitle(size: 21)),
          ),
        ],
      ),
    );
  }
}
