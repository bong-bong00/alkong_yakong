import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
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
  final ValueChanged<Map<String, dynamic>?>? onSaved;

  const ManualMedicineScreen({super.key, this.onBack, this.onSaved});

  @override
  ConsumerState<ManualMedicineScreen> createState() =>
      _ManualMedicineScreenState();
}

class _ManualMedicineScreenState extends ConsumerState<ManualMedicineScreen> {
  final _api = ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl);
  final _query = TextEditingController();
  final _amount = TextEditingController();

  List<Map<String, dynamic>> _hits = const [];
  Map<String, dynamic>? _picked;
  int? _frequency;
  int? _days;
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
      _hits = const [];
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
    final amount = _amount.text.trim();
    if (amount.isEmpty) {
      _showError('한 번에 먹는 양을 적어 주세요.');
      return;
    }
    if (_frequency == null || _days == null) {
      _showError('하루 복용 횟수와 복용 일수를 확인해 주세요.');
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _saving = true);
    final userId = MvpSession.userId.trim().isEmpty
        ? 'mvp-user'
        : MvpSession.userId.trim();
    Map<String, dynamic> mapped;
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
              'frequency_per_day': _frequency,
              'times_per_take': 1,
              'duration_days': _days,
              'administration_times': <String>[],
              'match_status': 'MATCHED',
            },
          ],
        },
      );
      if (response is! Map || response['registered'] != true) {
        throw const ApiException('약 등록 완료를 확인하지 못했어요.');
      }
      mapped = Map<String, dynamic>.from(response);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('공식 약으로 확인되지 않아 등록하지 못했어요.');
      return;
    }

    MvpSession.rememberPrescriptionSchedules(
      prescriptionId: mapped['prescription_id']?.toString(),
      confirmResponse: mapped,
      ocrItems: [
        {'duration_days': _days, 'frequency_per_day': _frequency},
      ],
    );
    final durRaw = mapped['dur_result'];
    final durResult = durRaw is Map ? Map<String, dynamic>.from(durRaw) : null;
    var refreshFailed = false;
    try {
      await Future.wait<void>([
        ref.read(medicationProvider.notifier).refreshFromServer(),
        ref.read(userMedicinesProvider.notifier).refresh(),
      ]);
    } catch (_) {
      refreshFailed = true;
    }
    if (ref.read(userMedicinesProvider).hasError) {
      refreshFailed = true;
    }
    if (!mounted) return;
    if (refreshFailed) {
      showSeniorSnackbar(context, '약은 등록됐어요. 목록은 홈에서 다시 불러와 주세요.');
    }
    final onSaved = widget.onSaved;
    if (onSaved != null) {
      onSaved(durResult);
      return;
    }
    if (_hasPairConflict(durResult)) {
      context.push(
        '/dur-analysis',
        extra: {...?durResult, 'open_schedule_days': true},
      );
      return;
    }
    context.push('/schedule-days', extra: MvpSession.latestPrescriptionId);
  }

  static bool _hasPairConflict(Map<String, dynamic>? durResult) {
    const pairTypes = {'병용금기', '중복성분', '효능군중복'};
    final matches = durResult?['matches'];
    if (matches is! List) return false;
    return matches.any(
      (item) => item is Map && pairTypes.contains(item['type']?.toString()),
    );
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
                Text(
                  '처방전에 적힌 약 이름을 찾아 등록해요.',
                  style: AppText.body(color: AppColors.textSecondary),
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
                  SeniorButton(
                    label: _saving ? '등록 중…' : '이 약 등록하기',
                    onPressed: _saving ? () {} : _save,
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
