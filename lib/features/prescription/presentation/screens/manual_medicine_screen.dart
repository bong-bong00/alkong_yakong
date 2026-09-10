import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/domain/medication_models.dart';

/// 10 · 손으로 적기.
///
/// 처방전이 없어도 약을 넣을 수 있는 길. **약 이름과 드시는 때만** 받는다.
/// 용량과 남은 날수까지 물으면 여기서 대부분 포기한다.
class ManualMedicineScreen extends StatefulWidget {
  /// 등록을 마쳤을 때. 이름과 고른 시간대를 넘긴다.
  final void Function(String name, Set<DoseSlot> slots)? onSave;

  /// 사진으로 넣는 쪽으로 갈아타기.
  final VoidCallback? onUseCamera;

  const ManualMedicineScreen({super.key, this.onSave, this.onUseCamera});

  @override
  State<ManualMedicineScreen> createState() => _ManualMedicineScreenState();
}

class _ManualMedicineScreenState extends State<ManualMedicineScreen> {
  final TextEditingController _name = TextEditingController();
  final Set<DoseSlot> _slots = <DoseSlot>{};

  /// 어느 쪽이 비었는지. 두 가지를 한꺼번에 나무라지 않는다.
  String? _error;

  static const List<String> _suggestions = ['메트포르민', '암로디핀', '아스피린'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '약 이름을 적어 주세요.');
      return;
    }
    if (_slots.isEmpty) {
      setState(() => _error = '드시는 때를 한 개 이상 골라 주세요.');
      return;
    }
    setState(() => _error = null);
    widget.onSave?.call(name, _slots);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '손으로 적기'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pointTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '약 이름과 드시는 때만 적으면 돼요',
                          style: AppText.cardTitle(
                            size: 20,
                            color: AppColors.point,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '용량과 남은 날수는 나중에 채워도 됩니다.',
                          style: AppText.body(
                            size: 17.5,
                            color: AppColors.pointInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('약 이름', style: AppText.cardTitle(size: 20)),
                        const SizedBox(height: 12),
                        SeniorField(
                          controller: _name,
                          hint: '예: 메트포르민',
                          hasError: _error == '약 이름을 적어 주세요.',
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final suggestion in _suggestions)
                              _SuggestionChip(
                                label: suggestion,
                                onTap: () => setState(() {
                                  _name.text = suggestion;
                                  _error = null;
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '드시는 때 (여러 개 고를 수 있어요)',
                          style: AppText.cardTitle(size: 20),
                        ),
                        const SizedBox(height: 12),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (int i = 0;
                                  i < DoseSlot.values.length;
                                  i++) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _SlotChip(
                                    slot: DoseSlot.values[i],
                                    selected:
                                        _slots.contains(DoseSlot.values[i]),
                                    onTap: () => setState(() {
                                      final slot = DoseSlot.values[i];
                                      if (!_slots.remove(slot)) {
                                        _slots.add(slot);
                                      }
                                      _error = null;
                                    }),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    SeniorErrorBox(_error!),
                  ],
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: '이 약 등록하기',
                    minHeight: 74,
                    fontSize: 24,
                    elevated: true,
                    onPressed: _save,
                  ),
                  const SizedBox(height: 12),
                  SeniorButton(
                    label: '사진으로 넣기',
                    icon: TablerIcons.camera,
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 20,
                    onPressed: widget.onUseCamera,
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

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Text(
            label,
            style: AppText.cardTitle(size: 17.5, color: AppColors.textBody),
          ),
        ),
      ),
    );
  }
}

/// 아침·점심·저녁 3분할. 고르면 파랑으로 채워진다.
class _SlotChip extends StatelessWidget {
  final DoseSlot slot;
  final bool selected;
  final VoidCallback onTap;

  const _SlotChip({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${slot.label} ${selected ? '고름' : '고르지 않음'}',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 70),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.point : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.pointBorder : AppColors.strongBorder,
                width: 2,
              ),
            ),
            child: Text(
              slot.label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 19,
                color: selected ? Colors.white : AppColors.textBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
