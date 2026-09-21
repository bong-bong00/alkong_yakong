import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import 'senior_button.dart';

/// 굴려서 하나를 고르는 창.
///
/// 목록을 화면에 펼쳐 두면 무엇을 고르는 중인지 흐려진다. 가운데 칸 하나만
/// 고른 것으로 읽히게 두고, 확인 단추를 눌러야 정해진다.
///
/// 고른 자리의 번호를 돌려준다. 그만두면 null.
Future<int?> showSeniorWheel({
  required BuildContext context,
  required String title,
  required List<String> options,
  int selectedIndex = 0,
  String subtitle = '위아래로 굴려서 고르세요',
  String confirmLabel = '이걸로 정하기',
  String cancelLabel = '그만두기',

  /// 확인 단추와 그만두기 사이에 끼워 넣을 단추들. 없으면 두지 않는다.
  List<Widget> extraButtons = const [],
}) {
  if (options.isEmpty) return Future<int?>.value();
  return showDialog<int>(
    context: context,
    builder: (_) => SeniorWheelDialog(
      title: title,
      subtitle: subtitle,
      options: options,
      selectedIndex: selectedIndex,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      extraButtons: extraButtons,
    ),
  );
}

class SeniorWheelDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> options;
  final int selectedIndex;
  final String confirmLabel;
  final String cancelLabel;
  final List<Widget> extraButtons;

  const SeniorWheelDialog({
    super.key,
    required this.title,
    required this.options,
    this.subtitle = '위아래로 굴려서 고르세요',
    this.selectedIndex = 0,
    this.confirmLabel = '이걸로 정하기',
    this.cancelLabel = '그만두기',
    this.extraButtons = const [],
  });

  @override
  State<SeniorWheelDialog> createState() => _SeniorWheelDialogState();
}

class _SeniorWheelDialogState extends State<SeniorWheelDialog> {
  /// 굴리는 칸 하나의 높이. 손가락으로 짚을 수 있게 넉넉히 둔다.
  static const double _itemExtent = 66;

  late final FixedExtentScrollController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.selectedIndex.clamp(0, widget.options.length - 1);
    _controller = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 옆 칸을 짚으면 그 칸이 가운데로 굴러온다. 짚자마자 창이 닫히지는 않는다.
  void _rollTo(int index) {
    if (index == _index) return;
    _controller.animateToItem(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: AppText.emphasis(size: 22)),
            const SizedBox(height: 6),
            Text(widget.subtitle, style: AppText.caption(size: 16)),
            const SizedBox(height: 12),
            // 화면이 낮으면 굴림판부터 줄인다. 단추는 끝까지 남아 있어야 한다.
            Flexible(
              child: SizedBox(
                height: _itemExtent * 3,
                child: Stack(
                  children: [
                    // 가운데 칸이 지금 고른 것이다.
                    Center(
                      child: Container(
                        height: _itemExtent,
                        decoration: BoxDecoration(
                          color: AppColors.pointTint,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.point, width: 2),
                        ),
                      ),
                    ),
                    ListWheelScrollView.useDelegate(
                      controller: _controller,
                      itemExtent: _itemExtent,
                      physics: const FixedExtentScrollPhysics(),
                      diameterRatio: 1.8,
                      perspective: 0.002,
                      overAndUnderCenterOpacity: 0.5,
                      onSelectedItemChanged: (index) =>
                          setState(() => _index = index),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: widget.options.length,
                        builder: (context, index) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _rollTo(index),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                widget.options[index],
                                style: AppText.cardTitle(
                                  size: 21,
                                  color: index == _index
                                      ? AppColors.point
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SeniorButton(
              label: widget.confirmLabel,
              minHeight: 64,
              fontSize: 20,
              onPressed: () => Navigator.of(context).pop(_index),
            ),
            for (final button in widget.extraButtons) ...[
              const SizedBox(height: 8),
              button,
            ],
            const SizedBox(height: 8),
            SeniorButton(
              label: widget.cancelLabel,
              kind: SeniorButtonKind.neutral,
              minHeight: 58,
              fontSize: 18,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시각을 고르는 창 — 왼쪽에 오전·오후, 오른쪽에 시.
///
/// 24시간을 한 줄에 늘어놓으면 굴림이 너무 길다. 오전·오후를 먼저 고르면
/// 12칸만 굴리면 된다.
///
/// 24시간제 시각(0~23)을 돌려준다. 그만두면 null.
Future<int?> showSeniorTimeWheel({
  required BuildContext context,
  required String title,
  int initialHour = 8,
  String confirmLabel = '이 시간으로 정하기',
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _TimeWheelDialog(
      title: title,
      initialHour: initialHour.clamp(0, 23),
      confirmLabel: confirmLabel,
    ),
  );
}

class _TimeWheelDialog extends StatefulWidget {
  final String title;
  final int initialHour;
  final String confirmLabel;

  const _TimeWheelDialog({
    required this.title,
    required this.initialHour,
    required this.confirmLabel,
  });

  @override
  State<_TimeWheelDialog> createState() => _TimeWheelDialogState();
}

class _TimeWheelDialogState extends State<_TimeWheelDialog> {
  static const double _itemExtent = 66;
  static const List<String> _meridiems = ['오전', '오후'];

  late final FixedExtentScrollController _meridiemController;
  late final FixedExtentScrollController _hourController;

  /// 0이면 오전, 1이면 오후.
  late int _meridiem;

  /// 1~12로 읽는 시계 숫자.
  late int _clockHour;

  @override
  void initState() {
    super.initState();
    _meridiem = widget.initialHour < 12 ? 0 : 1;
    final twelve = widget.initialHour % 12;
    _clockHour = twelve == 0 ? 12 : twelve;
    _meridiemController = FixedExtentScrollController(initialItem: _meridiem);
    _hourController = FixedExtentScrollController(initialItem: _clockHour - 1);
  }

  @override
  void dispose() {
    _meridiemController.dispose();
    _hourController.dispose();
    super.dispose();
  }

  /// 오전 12시는 밤 0시, 오후 12시는 낮 12시다.
  int get _hour24 {
    if (_meridiem == 0) return _clockHour == 12 ? 0 : _clockHour;
    return _clockHour == 12 ? 12 : _clockHour + 12;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: AppText.emphasis(size: 22)),
            const SizedBox(height: 6),
            Text('위아래로 굴려서 고르세요', style: AppText.caption(size: 16)),
            const SizedBox(height: 12),
            Flexible(
              child: SizedBox(
                height: _itemExtent * 3,
                child: Stack(
                  children: [
                    // 가운데 칸이 지금 고른 시각이다.
                    Center(
                      child: Container(
                        height: _itemExtent,
                        decoration: BoxDecoration(
                          color: AppColors.pointTint,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.point, width: 2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _Wheel(
                            controller: _meridiemController,
                            itemExtent: _itemExtent,
                            count: _meridiems.length,
                            selected: _meridiem,
                            labelOf: (index) => _meridiems[index],
                            onChanged: (index) =>
                                setState(() => _meridiem = index),
                          ),
                        ),
                        Expanded(
                          child: _Wheel(
                            controller: _hourController,
                            itemExtent: _itemExtent,
                            count: 12,
                            selected: _clockHour - 1,
                            labelOf: (index) => '${index + 1}시',
                            onChanged: (index) =>
                                setState(() => _clockHour = index + 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SeniorButton(
              label: widget.confirmLabel,
              minHeight: 64,
              fontSize: 20,
              onPressed: () => Navigator.of(context).pop(_hour24),
            ),
            const SizedBox(height: 8),
            SeniorButton(
              label: '그만두기',
              kind: SeniorButtonKind.neutral,
              minHeight: 58,
              fontSize: 18,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 굴림판 한 줄기.
class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final double itemExtent;
  final int count;
  final int selected;
  final String Function(int index) labelOf;
  final ValueChanged<int> onChanged;

  const _Wheel({
    required this.controller,
    required this.itemExtent,
    required this.count,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: itemExtent,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.8,
      perspective: 0.002,
      overAndUnderCenterOpacity: 0.5,
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.animateToItem(
            index,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          ),
          child: Center(
            child: Text(
              labelOf(index),
              style: AppText.cardTitle(
                size: 22,
                color: index == selected
                    ? AppColors.point
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
