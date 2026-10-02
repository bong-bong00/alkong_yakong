import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';
import '../../domain/registration_result.dart';
import '../../../../core/theme/medicine_preserved_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../../dashboard/application/medication_history_provider.dart';
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

  /// 굴림판에서 고른 한 번에 먹는 양. 안 골랐으면 null.
  String? _amount;

  List<Map<String, dynamic>> _hits = const [];
  Map<String, dynamic>? _picked;
  int? _frequency;
  int? _days;

  /// 드시는 때. 이게 없으면 알림 시각을 정할 수 없다.
  final Set<String> _slots = <String>{};
  bool _searching = false;
  bool _saving = false;

  /// 글자를 멈추면 알아서 찾는다. 버튼을 하나 더 누르게 하지 않는다.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// 한 번에 먹는 양 · 하루 몇 번 · 며칠분을 굴림판으로 고른다.
  /// 숫자를 자판으로 적게 하면 잘못 눌러도 알아채기 어렵다.
  Future<void> _pickAmount() async {
    const options = ['0.5알', '1알', '1.5알', '2알', '3알'];
    final index = await showSeniorWheel(
      context: context,
      title: '한 번에 먹는 양',
      options: options,
      selectedIndex: _amount == null
          ? 1
          : options.indexOf(_amount!).clamp(0, 4),
    );
    if (index == null || !mounted) return;
    setState(() => _amount = options[index]);
  }

  Future<void> _pickFrequency() async {
    final options = [for (final count in _frequencyOptions) '$count번'];
    final index = await showSeniorWheel(
      context: context,
      title: '하루 복용 횟수',
      options: options,
      selectedIndex: _frequency == null
          ? 1
          : _frequencyOptions.indexOf(_frequency!).clamp(0, options.length - 1),
    );
    if (index == null || !mounted) return;
    setState(() => _frequency = _frequencyOptions[index]);
  }

  Future<void> _pickDays() async {
    final options = [for (final days in _dayOptions) '$days일'];
    final index = await showSeniorWheel(
      context: context,
      title: '며칠분',
      options: options,
      selectedIndex: _days == null
          ? 1
          : _dayOptions.indexOf(_days!).clamp(0, options.length - 1),
    );
    if (index == null || !mounted) return;
    setState(() => _days = _dayOptions[index]);
  }

  /// 오류는 버튼 아래에 끼워 넣지 않고 스낵바로 알린다.
  void _showError(String message) =>
      showSeniorSnackbar(context, message, error: true);

  void _searchLater() {
    _debounce?.cancel();
    if (_query.text.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _search(quiet: true),
    );
  }

  Future<void> _search({bool quiet = false}) async {
    _debounce?.cancel();
    final q = _query.text.trim();
    if (q.length < 2) {
      if (!quiet) _showError('약 이름을 두 글자 이상 적어 주세요.');
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
      if (hits.isEmpty && !quiet) {
        _showError('공식 약 이름을 찾지 못했어요. 처방전 사진으로 등록해 주세요.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _searching = false);
      if (!quiet) _showError('약 이름을 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
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
    final amount = _amount ?? '';
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
              'frequency_per_day': _frequency ?? _slots.length,
              'times_per_take': 1,
              'duration_days': _days,
              'administration_times': _slots.toList(),
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
        {
          'duration_days': _days,
          'frequency_per_day': _frequency ?? _slots.length,
        },
      ],
    );
    // 함께먹기 검사가 끝나지 않았으면 "안전"으로 읽지 않는다.
    final durResult = registrationDurResult(mapped['dur_result']);
    var refreshFailed = false;
    try {
      await Future.wait<void>([
        ref
            .read(medicationProvider.notifier)
            .refreshFromServer(throwOnError: true),
        ref.read(userMedicinesProvider.notifier).refresh(),
      ]);
    } catch (_) {
      refreshFailed = true;
    }
    ref.invalidate(medicationHistoryProvider);
    if (ref.read(userMedicinesProvider).hasError) {
      refreshFailed = true;
    }
    if (!mounted) return;
    if (refreshFailed) {
      showSeniorSnackbar(context, '약은 등록됐지만 목록을 다시 불러와야 해요.');
    }
    final onSaved = widget.onSaved;
    if (onSaved != null) {
      onSaved(durResult);
      return;
    }
    // 부딪히는 약이 있으면 그것부터 보여주고, 아니면 약 있는 날로 간다.
    if (_hasPairConflict(durResult)) {
      context.push(
        '/dur-analysis',
        extra: {...durResult, 'open_schedule_days': true},
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
      backgroundColor: AppColors.pageBg,
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
                SeniorCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SeniorField(
                        label: '약 이름',
                        controller: _query,
                        hint: '예: 메트포르민',
                        onCard: true,
                        onChanged: (_) => _searchLater(),
                      ),
                      if (_searching) ...[
                        const SizedBox(height: 12),
                        Text(
                          '약 이름을 찾는 중이에요…',
                          style: AppText.caption(size: 16),
                        ),
                      ],
                      if (_hits.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final hit in _hits)
                              _NameChip(
                                label:
                                    hit['display_name']?.toString() ??
                                    hit['product_name']?.toString() ??
                                    '약',
                                selected:
                                    _picked?['medicine_code'] ==
                                    hit['medicine_code'],
                                onTap: () => setState(() => _picked = hit),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SeniorCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PickRow(
                        label: '한 번에 먹는 양',
                        value: _amount,
                        onTap: _pickAmount,
                      ),
                      const SizedBox(height: 14),
                      _PickRow(
                        label: '하루 복용 횟수',
                        value: _frequency == null ? null : '$_frequency번',
                        onTap: _pickFrequency,
                      ),
                      const SizedBox(height: 14),
                      _PickRow(
                        label: '며칠분',
                        value: _days == null ? null : '$_days일',
                        onTap: _pickDays,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SeniorCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('드시는 때', style: AppText.cardTitle(size: 20)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '(여러 개 고를 수 있어요)',
                              style: AppText.caption(size: 16),
                            ),
                          ),
                        ],
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SeniorButton(
                  label: _saving ? '등록 중…' : '이 약 등록하기',
                  onPressed: _saving ? () {} : _save,
                ),
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

/// 하루 몇 번, 며칠분. 목록을 펼치게 하지 않고 눌러서 고른다.
const List<int> _frequencyOptions = [1, 2, 3];
const List<int> _dayOptions = [3, 7, 14, 30];

/// 찾은 약 이름 한 알. 고르면 파란 테두리가 생긴다.
class _NameChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NameChip({
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
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.pointFill : AppColors.pointRing,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: AppText.cardTitle(
              size: 18,
              color: selected ? Colors.white : AppColors.pointBorder,
            ),
          ),
        ),
      ),
    );
  }
}

/// 숫자 하나를 고르는 칸. 고른 것만 파랗게 채운다 (명세서 28).
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
              color: selected ? AppColors.pointFill : AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 20,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 굴림판으로 고르는 줄 (손으로 적기).
///
/// 숫자를 자판으로 적게 하지 않는다 — 잘못 눌러도 알아채기 어렵다.
/// 카드 안이라 흰 면 대신 #F0F1F5로 채워 카드와 구별한다.
class _PickRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _PickRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value == null;
    return Semantics(
      button: true,
      label: '$label ${value ?? '고르지 않음'}, 고르기',
      child: ExcludeSemantics(
        // 이름줄까지 눌러도 굴림판이 열린다 — 짚을 자리가 넓어야 한다.
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.label(size: 18)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.sunken,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? '고르기',
                        style: AppText.cardTitle(
                          size: 21,
                          color: empty
                              ? AppColors.chevron
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      size: 26,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
