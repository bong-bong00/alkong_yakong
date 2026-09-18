import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medicines/application/user_medicines_controller.dart';

/// 처방전 없이 공식 약 이름을 찾아 등록한다.
class ManualMedicineScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSaved;

  /// 사진으로 넣는 쪽으로 갈아타기. 손으로 적다 막히면 여기로 나간다.
  final VoidCallback? onUseCamera;

  const ManualMedicineScreen({
    super.key,
    this.onBack,
    this.onSaved,
    this.onUseCamera,
  });

  @override
  ConsumerState<ManualMedicineScreen> createState() =>
      _ManualMedicineScreenState();
}

class _ManualMedicineScreenState extends ConsumerState<ManualMedicineScreen> {
  final _api = ApiClient();
  final _query = TextEditingController();
  final _amount = TextEditingController();

  List<Map<String, dynamic>> _hits = const [];
  Map<String, dynamic>? _picked;
  int? _frequency;
  int? _days;

  /// 드시는 때. 이게 없으면 알림 시각을 정할 수 없다.
  final Set<String> _slots = <String>{};
  bool _searching = false;
  bool _saving = false;

  @override
  void dispose() {
    _query.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// 오류는 버튼 아래에 끼워 넣지 않고 스낵바로 알린다.
  void _showError(String message) =>
      showSeniorSnackbar(context, message, error: true);

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      _showError('약 이름을 두 글자 이상 적어 주세요.');
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _searching = true;
      _picked = null;
    });
    try {
      final response = await _api.get(
        '/api/v1/medicines/lookup?q=${Uri.encodeQueryComponent(q)}',
      );
      if (!mounted) return;
      final items = response is Map ? response['items'] : null;
      final hits = items is List
          ? items
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _hits = hits;
        _searching = false;
      });
      if (hits.isEmpty) {
        _showError('공식 약 이름을 찾지 못했어요. 처방전 사진으로 등록해 주세요.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _searching = false);
      _showError('약 이름을 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _save() async {
    final picked = _picked;
    final code = picked?['medicine_code']?.toString().trim() ?? '';
    if (code.isEmpty) {
      _showError('목록에서 약을 먼저 골라 주세요.');
      return;
    }
    if (_slots.isEmpty) {
      _showError('드시는 때를 한 개 이상 골라 주세요.');
      return;
    }
    // 용량과 날수는 나중에 채워도 된다. 여기서 다 물으면 대부분 포기한다.
    final amount = _amount.text.trim();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _saving = true);
    final userId = MvpSession.userId.trim().isEmpty
        ? 'mvp-user'
        : MvpSession.userId.trim();
    try {
      final response = await _api.post(
        '/api/v1/prescriptions/confirm',
        body: {
          'user_id': userId,
          'items': [
            {
              'medicine_code': code,
              'drug_name':
                  picked?['display_name'] ?? picked?['product_name'] ?? '',
              'dosage': amount,
              'frequency_per_day': _frequency ?? _slots.length,
              'times_per_take': 1,
              'duration_days': _days,
              'administration_times': _slots.toList(),
              'match_status': 'MATCHED',
            },
          ],
        },
      );
      if (response is Map) {
        MvpSession.rememberPrescriptionSchedules(
          prescriptionId: response['prescription_id']?.toString(),
          confirmResponse: response,
          ocrItems: [
            {
              'duration_days': _days,
              'frequency_per_day': _frequency ?? _slots.length,
            },
          ],
        );
      }
      await ref.read(medicationProvider.notifier).refreshFromServer();
      await ref.read(userMedicinesProvider.notifier).refresh();
      if (!mounted) return;
      final onSaved = widget.onSaved;
      if (onSaved != null) {
        onSaved();
        return;
      }
      context.push(
        '/schedule-days',
        extra: MvpSession.latestPrescriptionId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('공식 약으로 확인되지 않아 등록하지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorBackHeader(
            title: '손으로 적기',
            onBack: widget.onBack ?? () => context.pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                const SizedBox(height: 16),
                TextField(
                  controller: _query,
                  style: AppText.body(size: 20),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: '약 이름',
                    hintText: '예: 부루펜',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SeniorButton(
                  label: _searching ? '찾는 중…' : '약 이름 찾기',
                  kind: SeniorButtonKind.secondary,
                  onPressed: _searching ? () {} : _search,
                ),
                for (final hit in _hits) ...[
                  const SizedBox(height: 10),
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    onTap: () => setState(() => _picked = hit),
                    borderColor:
                        _picked?['medicine_code'] == hit['medicine_code']
                        ? AppColors.point
                        : null,
                    child: Text(
                      hit['display_name']?.toString() ??
                          hit['product_name']?.toString() ??
                          '약',
                      style: AppText.cardTitle(),
                    ),
                  ),
                ],
                if (_picked != null) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _amount,
                    style: AppText.body(size: 20),
                    decoration: const InputDecoration(
                      labelText: '한 번에 먹는 양',
                      hintText: '예: 1알 또는 0.5정',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: _frequency,
                    style: AppText.body(size: 20, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '하루 복용 횟수',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('하루 1번')),
                      DropdownMenuItem(value: 2, child: Text('하루 2번')),
                      DropdownMenuItem(value: 3, child: Text('하루 3번')),
                    ],
                    onChanged: (value) {
                      setState(() => _frequency = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: _days,
                    style: AppText.body(size: 20, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '며칠분',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('3일')),
                      DropdownMenuItem(value: 7, child: Text('7일')),
                      DropdownMenuItem(value: 14, child: Text('14일')),
                      DropdownMenuItem(value: 30, child: Text('30일')),
                    ],
                    onChanged: (value) {
                      setState(() => _days = value);
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '드시는 때 (여러 개 고를 수 있어요)',
                    style: AppText.cardTitle(size: 20),
                  ),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < _slotLabels.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _SlotChip(
                              label: _slotLabels[i],
                              selected: _slots.contains(_slotLabels[i]),
                              onTap: () => setState(() {
                                if (!_slots.remove(_slotLabels[i])) {
                                  _slots.add(_slotLabels[i]);
                                }
                              }),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SeniorButton(
                    label: _saving ? '등록 중…' : '이 약 등록하기',
                    onPressed: _saving ? () {} : _save,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// 드시는 때 후보. 한 번에 여러 개를 고를 수 있다.
const List<String> _slotLabels = ['아침', '점심', '저녁'];

/// 3분할 칩. 고르면 파랑으로 채워진다.
class _SlotChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label ${selected ? '고름' : '고르지 않음'}',
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
                color: selected
                    ? AppColors.pointBorder
                    : AppColors.strongBorder,
                width: 2,
              ),
            ),
            child: Text(
              label,
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
