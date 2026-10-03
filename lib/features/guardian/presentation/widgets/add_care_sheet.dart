import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_sheet.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';

/// 39 · 돌보는 분 추가 시트.
///
/// 초대를 보낸다고 현황이 열리지는 않는다. **받는 분이 수락해야** 열린다.
/// 무엇이 상대에게 보이는지도 보내기 전에 그대로 적어 둔다 —
/// 내 전화번호가 넘어간다는 사실을 나중에 알게 해서는 안 된다.
///
/// 같은 시트를 양쪽이 쓴다. 보호자는 돌볼 어르신을 더하고, 어르신은
/// 나를 돌볼 보호자를 더한다. 묻는 것은 같고 부르는 말만 다르다.
Future<PendingInvite?> showAddCareSheet(
  BuildContext context, {
  bool asPatient = false,
}) {
  return SeniorSheet.show<PendingInvite>(
    context: context,
    builder: (sheetContext) => _AddCareSheet(asPatient: asPatient),
  );
}

class _AddCareSheet extends StatefulWidget {
  /// 어르신이 보호자를 더하는 자리인지. 아니면 보호자가 어르신을 더한다.
  final bool asPatient;

  const _AddCareSheet({this.asPatient = false});

  @override
  State<_AddCareSheet> createState() => _AddCareSheetState();
}

class _AddCareSheetState extends State<_AddCareSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _otherRelation = TextEditingController();

  static const List<String> _careRelations = [
    '어머니',
    '아버지',
    '장모님',
    '장인어른',
    '그 외',
  ];

  /// 어르신이 고르는 말 — 나를 돌볼 사람이 나와 어떤 사이인지.
  static const List<String> _guardianRelations = [
    '아들',
    '딸',
    '배우자',
    '며느리',
    '사위',
    '그 외',
  ];

  List<String> get _relations =>
      widget.asPatient ? _guardianRelations : _careRelations;

  /// 상대를 부르는 말. 보호자가 보면 "어르신", 어르신이 보면 "보호자".
  String get _other => widget.asPatient ? '보호자' : '어르신';

  String? _relation;

  bool get _isOther => _relation == '그 외';

  String get _resolvedRelation =>
      _isOther ? _otherRelation.text.trim() : (_relation ?? '');

  /// 세 항목이 다 채워지기 전에는 보내지 않는다.
  bool get _ready =>
      _name.text.trim().isNotEmpty &&
      _resolvedRelation.isNotEmpty &&
      _phone.text.trim().length >= 10;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _otherRelation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SeniorSheet(
      title: widget.asPatient ? '보호자 추가하기' : '돌보는 분 추가하기',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeniorSheetBody([
            '$_other 전화번호로 초대를 보냅니다. $_other이 ',
            '수락해야',
            widget.asPatient ? ' 내 복약 현황이 보입니다.' : ' 복약 현황이 보입니다.',
          ]),
          const SizedBox(height: 18),
          Text('$_other 성함', style: AppText.label(size: 18)),
          const SizedBox(height: 8),
          SeniorField(
            controller: _name,
            hint: '예: 김복자',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('나와의 관계', style: AppText.label(size: 18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final relation in _relations)
                _RelationChip(
                  label: relation,
                  selected: _relation == relation,
                  onTap: () => setState(() => _relation = relation),
                ),
            ],
          ),
          if (_isOther) ...[
            const SizedBox(height: 10),
            SeniorField(
              controller: _otherRelation,
              hint: '관계를 적어 주세요',
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          Text('$_other 전화번호', style: AppText.label(size: 18)),
          const SizedBox(height: 8),
          SeniorField(
            controller: _phone,
            hint: '010-0000-0000',
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('보내는 내용', style: AppText.label(size: 17.5)),
                const SizedBox(height: 6),
                Text(
                  '이름, 관계, 내 전화번호가 $_other에게 그대로 보입니다. '
                  '$_other이 수락해야 복약 현황이 열립니다.',
                  style: AppText.body(size: 17.5),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SeniorButton(
          label: '초대 보내기',
          minHeight: 68,
          fontSize: 23,
          // 다 채우기 전에는 눌리지 않는다. 눌렀다가 되돌아오는 것보다
          // 아직 못 누른다는 사실이 먼저 보이는 편이 낫다.
          onPressed: _ready
              ? () => Navigator.of(context).pop(
                  PendingInvite(
                    name: _name.text.trim(),
                    relation: _resolvedRelation,
                    phone: _phone.text.trim(),
                  ),
                )
              : null,
        ),
        SeniorButton(
          label: '그만두기',
          kind: SeniorButtonKind.secondary,
          minHeight: 62,
          fontSize: 20,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _RelationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RelationChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointFill : AppColors.sunken,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text(
              label,
              style: AppText.cardTitle(
                size: 17.5,
                color: selected ? Colors.white : AppColors.textBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
