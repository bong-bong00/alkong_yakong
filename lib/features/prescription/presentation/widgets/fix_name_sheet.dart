import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_sheet.dart';

/// 09 · 잘못 읽은 약 이름 고치기.
///
/// 처방전 사진은 자주 흐리게 찍힌다. "틀린 곳이 있으면 눌러서 고쳐주세요"라고
/// 적어 놓고 고칠 방법이 없으면, 어르신은 틀린 약을 그대로 등록하거나
/// 등록을 포기한다.
///
/// 고친 이름을 돌려준다. 그만두면 null.
Future<String?> showFixNameSheet(
  BuildContext context, {
  required String current,
}) {
  return SeniorSheet.show<String>(
    context: context,
    builder: (sheetContext) => _FixNameSheet(current: current),
  );
}

class _FixNameSheet extends StatefulWidget {
  final String current;

  const _FixNameSheet({required this.current});

  @override
  State<_FixNameSheet> createState() => _FixNameSheetState();
}

class _FixNameSheetState extends State<_FixNameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.current);

  String? _error;

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
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return SeniorSheet(
      title: '약 이름 고치기',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SeniorSheetBody([
            '처방전 봉투나 약 봉지에 적힌 이름을 ',
            '그대로',
            ' 적어 주세요.',
          ]),
          const SizedBox(height: 18),
          SeniorField(
            controller: _name,
            hint: '예: 메트포르민 500mg',
            hasError: _error != null,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SeniorErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          Text(
            '읽은 이름 · ${widget.current}',
            style: AppText.caption(size: 17),
          ),
        ],
      ),
      actions: [
        SeniorButton(
          label: '이 이름으로 고치기',
          minHeight: 68,
          fontSize: 23,
          onPressed: _save,
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
