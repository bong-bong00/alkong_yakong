import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../medicines/application/family_medicine_inbox.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medicines/domain/display_policy.dart';
import '../../domain/proxy_target.dart';
import '../../domain/registration_result.dart';

/// 처방전 없이 공식 약 이름을 찾아 등록한다.
class ManualMedicineScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final ValueChanged<Map<String, dynamic>>? onSaved;

  /// 보호자가 어르신 대신 적어 넣는 중이면 그 어르신.
  /// null이면 내 약을 내가 적는 평소 흐름이다.
  final ProxyTarget? proxyTarget;

  const ManualMedicineScreen({
    super.key,
    this.onBack,
    this.onSaved,
    this.proxyTarget,
  });

  @override
  ConsumerState<ManualMedicineScreen> createState() =>
      _ManualMedicineScreenState();
}

class _ManualMedicineScreenState extends ConsumerState<ManualMedicineScreen> {
  final _api = ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl);
  final _query = TextEditingController();

  /// 한 번에 먹는 양. 자판 대신 ±로 고른다.
  double _takeAmount = 1;

  List<Map<String, dynamic>> _hits = const [];
  Map<String, dynamic>? _picked;
  int? _frequency = 1;
  int? _days = 7;
  bool _searching = false;
  bool _saving = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// "1" 또는 "0.5". 뒤에 붙는 0은 떼어 둔다.
  static String _amountText(double amount) =>
      amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(1);

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
    if (_saving) return;
    final picked = _picked;
    final code = picked?['medicine_code']?.toString().trim() ?? '';
    if (code.isEmpty) {
      _showError('목록에서 약을 먼저 골라 주세요.');
      return;
    }
    // ±로 고르므로 빈 값이 나올 수 없지만, 막아 둔다 — 양을 모르는 채로
    // 등록되면 알림이 엉뚱한 개수를 말한다.
    final amount = _takeAmount > 0 ? '${_amountText(_takeAmount)}알' : '';
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
    final proxyId = widget.proxyTarget?.patientId.trim() ?? '';
    final userId = proxyId.isNotEmpty
        ? proxyId
        : (MvpSession.userId.trim().isEmpty
              ? 'mvp-user'
              : MvpSession.userId.trim());
    dynamic response;
    try {
      response = await _api.post(
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
        throw const ApiException('약 등록 결과를 확인하지 못했어요.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('공식 약으로 확인되지 않아 등록하지 못했어요.');
      return;
    }
    // ── 대신 넣기는 여기서 끝난다 ──
    // 뒤따르는 새로고침과 달력은 모두 **내 약** 화면이다.
    final proxyTitle = widget.proxyTarget?.title;
    if (proxyTitle != null) {
      if (!mounted) return;
      showSeniorSnackbar(context, '$proxyTitle 전화기로 보냈어요');
      Navigator.of(context).pop(true);
      return;
    }

    // 내가 손으로 넣은 약이다. "가족이 넣어드렸어요"로 되돌아오지 않게 적어 둔다.
    unawaited(FamilyMedicineInbox.markSeen(userId, [code]));
    MvpSession.rememberPrescriptionSchedules(
      prescriptionId: response['prescription_id']?.toString(),
      confirmResponse: response,
      ocrItems: [
        {'duration_days': _days, 'frequency_per_day': _frequency},
      ],
    );
    var refreshFailed = false;
    try {
      await Future.wait<void>([
        ref.read(medicationProvider.notifier).refreshFromServer(throwOnError: true),
        ref.read(userMedicinesProvider.notifier).refresh(),
      ]);
    } catch (_) {
      refreshFailed = true;
    }
    refreshFailed = refreshFailed || ref.read(userMedicinesProvider).hasError;
    if (!mounted) return;
    if (refreshFailed) {
      showSeniorSnackbar(context, '약은 등록됐지만 목록을 다시 불러와야 해요.');
    }
    final durResult = registrationDurResult(response['dur_result']);
    final onSaved = widget.onSaved;
    if (onSaved != null) {
      onSaved(durResult);
      return;
    }
    if (!registrationDurComplete(durResult) ||
        (durResult['matches'] as List).isNotEmpty) {
      context.push('/dur-analysis',
        extra: {...durResult, 'open_schedule_days': true},
      );
      return;
    }
    context.push('/schedule-days', extra: MvpSession.latestPrescriptionId);
  }

  /// 칩에 적을 짧은 이름.
  static String _hitName(Map<String, dynamic> hit) {
    final raw =
        hit['display_name']?.toString() ??
        hit['product_name']?.toString() ??
        '약';
    return stripExportAlias(raw);
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                // 무엇만 적으면 되는지 먼저 말한다. 칸이 많아 보이면 포기한다.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  decoration: BoxDecoration(
                    color: AppColors.pointTint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '약 이름과 드시는 때만 적으면 돼요',
                        style: AppText.cardTitle(
                          size: 21,
                          color: AppColors.point,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '용량과 남은 날수는 나중에 채워도 됩니다.',
                        style: AppText.body(
                          size: 18,
                          color: AppColors.pointInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SeniorCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('약 이름', style: AppText.cardTitle(size: 21)),
                      const SizedBox(height: 10),
                      SeniorField(
                        controller: _query,
                        hint: '예: 메트포르민',
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        // 돋보기 하나. 스크린리더에는 "약 이름 찾기"로 읽힌다.
                        suffix: Semantics(
                          button: true,
                          label: '약 이름 찾기',
                          child: GestureDetector(
                            onTap: _searching ? null : _search,
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Center(
                                child: _searching
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: AppColors.point,
                                        ),
                                      )
                                    : const ExcludeSemantics(
                                        child: Icon(
                                          TablerIcons.search,
                                          size: 28,
                                          color: AppColors.point,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_hits.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final hit in _hits)
                              SeniorChoiceChip(
                                label: _hitName(hit),
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
                const SizedBox(height: 14),
                SeniorCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SeniorStepper(
                        label: '한 번에 먹는 양',
                        number: _amountText(_takeAmount),
                        unit: '알',
                        onMinus: _takeAmount <= 0.5
                            ? null
                            : () => setState(() => _takeAmount -= 0.5),
                        onPlus: _takeAmount >= 10
                            ? null
                            : () => setState(() => _takeAmount += 0.5),
                        onNumberChanged: (text) {
                          final typed = double.tryParse(text);
                          if (typed == null || typed <= 0 || typed > 10) return;
                          setState(() => _takeAmount = typed);
                        },
                      ),
                      const SizedBox(height: 18),
                      SeniorStepper(
                        label: '하루 복용 횟수',
                        number: '${_frequency ?? 1}',
                        unit: '번',
                        onMinus: (_frequency ?? 1) <= 1
                            ? null
                            : () =>
                                  setState(() => _frequency = (_frequency ?? 1) - 1),
                        onPlus: (_frequency ?? 1) >= 6
                            ? null
                            : () =>
                                  setState(() => _frequency = (_frequency ?? 1) + 1),
                        onNumberChanged: (text) {
                          final typed = int.tryParse(text);
                          if (typed == null || typed < 1 || typed > 6) return;
                          setState(() => _frequency = typed);
                        },
                      ),
                      const SizedBox(height: 18),
                      SeniorStepper(
                        label: '며칠분',
                        number: '${_days ?? 7}',
                        unit: '일',
                        onMinus: (_days ?? 7) <= 1
                            ? null
                            : () => setState(() => _days = (_days ?? 7) - 1),
                        onPlus: (_days ?? 7) >= 365
                            ? null
                            : () => setState(() => _days = (_days ?? 7) + 1),
                        onNumberChanged: (text) {
                          final typed = int.tryParse(text);
                          if (typed == null || typed < 1 || typed > 365) return;
                          setState(() => _days = typed);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: SeniorButton(
                label: _saving ? '등록하고 있어요' : '이 약 등록하기',
                minHeight: 70,
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
