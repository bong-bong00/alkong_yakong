import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medicines/domain/display_policy.dart';
import '../../../onboarding/presentation/screens/first_run_screen.dart';
import 'add_medicine_screen.dart';
import 'manual_medicine_screen.dart';
import '../widgets/fix_name_sheet.dart';

/// 처방전 등록 흐름의 단계.
enum PrescriptionStep {
  /// 07 — 어떻게 넣을지 고르기.
  pickMethod,

  /// 4d — 처방전 촬영.
  capture,

  /// 10 — 손으로 적기.
  manual,

  /// 읽는 중.
  reading,

  /// 4e — 이렇게 읽었어요.
  confirm,

  /// 읽지 못했을 때 (5e 회복 패턴).
  failed,
}

/// 4d · 4e — 처방전 찍기 / 이렇게 읽었어요.
///
/// "처방전 OCR 인식"이라는 말을 쓰지 않는다.
/// 읽지 못했을 때도 사용자를 탓하지 않는다 — "다시 찍어드릴게요".
class PrescriptionScreen extends ConsumerStatefulWidget {
  /// 함께 보는 가족 — "딸 지안 님".
  final String guardianTitle;

  /// 등록이 끝났을 때 부를 콜백.
  final VoidCallback? onCompleted;

  /// 가족에게 부탁한 뒤 오늘 화면으로 돌아갈 때.
  final VoidCallback? onGoHome;

  const PrescriptionScreen({
    super.key,
    this.onCompleted,
    this.onGoHome,
    this.guardianTitle = '딸 지안 님',
  });

  @override
  ConsumerState<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends ConsumerState<PrescriptionScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  PrescriptionStep _step = PrescriptionStep.pickMethod;
  File? _image;
  Map<String, dynamic>? _result;

  /// 촬영 실패 횟수. 3번 실패하면 가족 대행(5g)을 권한다.
  int _failureCount = 0;
  String _failureReason = '';

  List<Map<String, dynamic>> get _items {
    final items = _result?['items'];
    if (items is List && items.isNotEmpty) {
      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(_isOfficialMatchedItem)
          .toList();
    }
    return const [];
  }

  List<String> get _unrecognizedNames {
    final raw = _result?['unrecognized_names'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item.toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static bool _isOfficialMatchedItem(Map<String, dynamic> item) {
    final code = item['medicine_code']?.toString() ?? '';
    if (code.isEmpty || code.toUpperCase().startsWith('OCR-')) {
      return false;
    }
    final status = item['match_status']?.toString().toUpperCase() ?? '';
    return status != 'UNMATCHED';
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) return;
      setState(() {
        _image = File(picked.path);
        _step = PrescriptionStep.capture;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failureCount++;
        _step = PrescriptionStep.failed;
      });
    }
  }

  Future<void> _read() async {
    setState(() => _step = PrescriptionStep.reading);

    try {
      String? base64Image;
      final image = _image;
      if (image != null) {
        base64Image = base64Encode(await image.readAsBytes());
      }

      // 처방전 사진은 CLOVA OCR 처리 시간을 고려해 여유 있게 기다린다.
      final response = await _apiClient.post(
        '/api/v1/prescriptions/ocr',
        body: {
          'user_id': MvpSession.userId.trim().isEmpty
              ? 'mvp-user'
              : MvpSession.userId.trim(),
          'image_data': base64Image,
          'source_type': 'OCR',
        },
        timeout: const Duration(seconds: 90),
      );

      if (!mounted) return;
      final mapped = Map<String, dynamic>.from(response as Map);
      final items = mapped['items'];
      final hasOfficial = items is List && items.isNotEmpty
          ? items
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where(_isOfficialMatchedItem)
                .isNotEmpty
          : false;
      final unreadRaw = mapped['unrecognized_names'];
      final hasUnread = unreadRaw is List && unreadRaw.isNotEmpty;
      if (!hasOfficial && !hasUnread) {
        setState(() {
          _failureCount++;
          _failureReason = '처방전에서 약을 찾지 못했어요.';
          _step = PrescriptionStep.failed;
        });
        return;
      }

      setState(() {
        _result = mapped;
        _failureCount = 0;
        _step = PrescriptionStep.confirm;
      });

      final first = _items.isEmpty ? null : _items.first;
      if (first != null) {
        MvpSession.medicineCode = first['medicine_code']?.toString() ?? '';
      }
    } catch (error) {
      debugPrint('처방전 OCR 실패: $error');
      if (!mounted) return;
      setState(() {
        _failureCount++;
        _failureReason = error.toString();
        _step = PrescriptionStep.failed;
      });
    }
  }

  Future<void> _register(List<Map<String, dynamic>> editedItems) async {
    final userId = MvpSession.userId.trim().isEmpty
        ? 'mvp-user'
        : MvpSession.userId.trim();
    final confirmItems = editedItems
        .where((item) => (item['medicine_code']?.toString() ?? '').isNotEmpty)
        .map(
          (item) => <String, dynamic>{
            'medicine_code': item['medicine_code'],
            'drug_name': item['drug_name'] ?? item['product_name'] ?? '',
            'ocr_drug_name_raw': item['ocr_drug_name_raw'],
            'ocr_field_confidences': item['ocr_field_confidences'] is Map
                ? item['ocr_field_confidences']
                : <String, dynamic>{},
            'dosage_form': item['dosage_form'],
            'administration_route': item['administration_route'],
            'dosage': item['dosage'],
            'unit': item['unit'],
            'frequency_per_day': item['frequency_per_day'],
            'times_per_take': item['times_per_take'],
            'duration_days': item['duration_days'],
            'administration_times': item['administration_times'] is List
                ? item['administration_times']
                : <String>[],
            'match_status': item['match_status'],
            'easy_explanation': item['easy_explanation'],
            'warning_note': item['warning_note'],
          },
        )
        .toList();

    if (confirmItems.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록할 약을 찾지 못했어요. 다시 찍어 주세요.')),
      );
      return;
    }

    try {
      await _apiClient.post(
        '/api/v1/prescriptions/confirm',
        body: {
          'user_id': userId,
          'items': confirmItems,
          'hospital_name': _result?['hospital_name'],
          'pharmacy_name': _result?['pharmacy_name'],
          'prescribed_date': _result?['prescribed_date'],
          'ocr_text': _result?['ocr_text'],
        },
      );
    } catch (error) {
      debugPrint('처방 확정 등록 실패: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약 등록에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
      return;
    }

    MvpSession.latestOcrItems = editedItems;
    MvpSession.latestOcrRegisteredAt = DateTime.now();
    await ref.read(medicationProvider.notifier).refreshFromServer();
    await ref.read(userMedicinesProvider.notifier).refresh();

    if (!mounted) return;
    final onCompleted = widget.onCompleted;
    if (onCompleted != null) {
      onCompleted();
      return;
    }
    context.push('/dur-analysis');
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case PrescriptionStep.pickMethod:
        return AddMedicineScreen(
          guardianTitle: widget.guardianTitle,
          onGoHome: widget.onGoHome ?? () => Navigator.of(context).maybePop(),
          onPick: (method) {
            switch (method) {
              case AddMedicineMethod.camera:
                _pick(ImageSource.camera);
              case AddMedicineMethod.gallery:
                _pick(ImageSource.gallery);
              case AddMedicineMethod.manual:
                setState(() => _step = PrescriptionStep.manual);
              case AddMedicineMethod.family:
                break;
            }
          },
        );
      case PrescriptionStep.manual:
        return ManualMedicineScreen(
          onBack: () => setState(() => _step = PrescriptionStep.pickMethod),
          onSaved: () {
            final onCompleted = widget.onCompleted;
            if (onCompleted != null) {
              onCompleted();
              return;
            }
            context.push('/dur-analysis');
          },
        );
      case PrescriptionStep.capture:
        return _CaptureScreen(
          image: _image,
          onUse: _read,
          onCamera: () => _pick(ImageSource.camera),
          onGallery: () => _pick(ImageSource.gallery),
          onManual: () => setState(() => _step = PrescriptionStep.manual),
        );
      case PrescriptionStep.reading:
        return _ReadingScreen(image: _image);
      case PrescriptionStep.confirm:
        return _ConfirmScreen(
          items: _items,
          unrecognizedNames: _unrecognizedNames,
          onRegister: _register,
          onRetake: () => setState(() {
            _image = null;
            _step = PrescriptionStep.pickMethod;
          }),
        );
      case PrescriptionStep.failed:
        return _FailedScreen(
          failureCount: _failureCount,
          failureReason: _failureReason,
          onRetry: () => setState(() {
            _image = null;
            _failureReason = '';
            _step = PrescriptionStep.pickMethod;
          }),
          onAskFamily: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FirstRunScreen()),
          ),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  4d — 처방전 촬영
// ════════════════════════════════════════════════════════════════
class _CaptureScreen extends StatelessWidget {
  final File? image;
  final VoidCallback onUse;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onManual;

  const _CaptureScreen({
    required this.image,
    required this.onUse,
    required this.onCamera,
    required this.onGallery,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cameraBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 찍기', onDark: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        if (image != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: AspectRatio(
                                aspectRatio: 3 / 4,
                                child: Image.file(image!, fit: BoxFit.contain),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                22,
                                22,
                                22,
                                20,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSurface,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '📸 이렇게 찍어 주세요',
                                    style: AppText.emphasis(
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _CaptureTip(
                                    number: '1',
                                    emoji: '☀️',
                                    text: '밝은 곳에 처방전이\n잘 보이게 펼쳐 놓으세요',
                                  ),
                                  const _CaptureTipArrow(),
                                  _CaptureTip(
                                    number: '2',
                                    emoji: '📄',
                                    text: '종이 네 모서리가\n사진에 다 나오게 하세요',
                                  ),
                                  const _CaptureTipArrow(),
                                  _CaptureTip(
                                    number: '3',
                                    emoji: '📱',
                                    text: '두 손으로 잡고\n흔들리지 않게, 흐리지 않게 찍으세요',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                          child: Column(
                            children: [
                              if (image != null) ...[
                                SeniorButton(
                                  label: '이 사진 사용하기',
                                  minHeight: 74,
                                  fontSize: 25,
                                  onPressed: onUse,
                                ),
                                const SizedBox(height: 14),
                              ],
                              SeniorButton(
                                label: image == null ? '사진 찍기' : '다시 찍기',
                                minHeight: 74,
                                fontSize: 25,
                                onPressed: onCamera,
                              ),
                              const SizedBox(height: 14),
                              SeniorButton(
                                label: '앨범에서 고르기',
                                kind: SeniorButtonKind.dark,
                                minHeight: 62,
                                fontSize: 20,
                                onPressed: onGallery,
                              ),
                              SeniorTextButton(
                                label: '직접 손으로 입력하기',
                                onPressed: onManual,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SafeArea(top: false, child: SizedBox(height: 12)),
        ],
      ),
    );
  }
}

class _CaptureTip extends StatelessWidget {
  final String number;
  final String emoji;
  final String text;

  const _CaptureTip({
    required this.number,
    required this.emoji,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.point,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            number,
            style: AppText.button(size: 22, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '$emoji  $text',
            style: AppText.body(
              size: 22,
              color: Colors.white,
              weight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _CaptureTipArrow extends StatelessWidget {
  const _CaptureTipArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '↓',
        style: AppText.emphasis(size: 28, color: AppColors.onDarkMuted),
      ),
    );
  }
}

class _ReadingScreen extends StatelessWidget {
  final File? image;
  const _ReadingScreen({required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 읽는 중'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: AppColors.point,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '처방전을 읽고 있어요',
                      textAlign: TextAlign.center,
                      style: AppText.emphasis(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '잠시만 기다려 주세요. 다 읽으면 약 이름을 보여드릴게요.',
                      textAlign: TextAlign.center,
                      style: AppText.body(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4e — 이렇게 읽었어요
// ════════════════════════════════════════════════════════════════
class _ConfirmScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<String> unrecognizedNames;
  final Future<void> Function(List<Map<String, dynamic>> items) onRegister;
  final VoidCallback onRetake;

  const _ConfirmScreen({
    required this.items,
    required this.unrecognizedNames,
    required this.onRegister,
    required this.onRetake,
  });

  @override
  State<_ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<_ConfirmScreen> {
  late final List<Map<String, dynamic>> _editedItems = [
    for (final item in widget.items) Map<String, dynamic>.from(item),
  ];
  bool _registering = false;
  final Set<int> _expandedItems = <int>{};

  static String _dosage(Map<String, dynamic> item) {
    final amount = _takeAmountLabel(item);
    final timesPerTake = item['times_per_take'];
    final perDay = item['frequency_per_day'];
    final days = item['duration_days'];
    final administrationTimes = item['administration_times'];
    final parts = <String>[];
    final action = _doseAction(item);
    if (amount.isNotEmpty) {
      parts.add('한 번에 $action 양 $amount');
    } else if (timesPerTake is num && timesPerTake > 0) {
      parts.add('1회 사용량 확인 필요');
    }
    if (perDay is num) {
      parts.add('하루 ${perDay.toInt()}번');
    }
    if (administrationTimes is List && administrationTimes.isNotEmpty) {
      parts.add(administrationTimes.map((value) => '$value').join(', '));
    }
    if (days is num) parts.add('${days.toInt()}일');
    return parts.join(' · ');
  }

  static String _doseAction(Map<String, dynamic> item) {
    final form = item['dosage_form']?.toString() ?? '';
    final route = item['administration_route']?.toString() ?? '';
    final value = '$form $route';
    if (value.contains('점안')) return '눈에 넣는';
    if (value.contains('연고') || value.contains('크림') || value.contains('외용')) {
      return '바르는';
    }
    if (value.contains('패치') || value.contains('패취')) return '붙이는';
    if (value.contains('흡입')) return '들이마시는';
    return '먹는';
  }

  static String _takeAmountLabel(Map<String, dynamic> item) {
    final raw = item['dosage']?.toString().trim() ?? '';
    final unit = item['unit']?.toString().trim() ?? '';
    if (RegExp(
      r'(mg|ml|g|%|밀리그램|밀리그람)(?:\s*$|[),/])',
      caseSensitive: false,
    ).hasMatch(raw)) {
      return '';
    }
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final half = RegExp(
      r'^반(알|정|캡슐|포|개)$',
      caseSensitive: false,
    ).firstMatch(compact);
    if (half != null) {
      final normalized = half.group(1) == '정' ? '알' : half.group(1)!;
      return '0.5$normalized';
    }
    final fraction = RegExp(
      r'^(\d+)/(\d+)(알|정|캡슐|포|개|mL|ml|방울|T|TAB|C|CAP|PKG|EA)$',
      caseSensitive: false,
    ).firstMatch(compact);
    if (fraction != null) {
      final denominator = int.tryParse(fraction.group(2)!);
      final numerator = int.tryParse(fraction.group(1)!);
      if (denominator != null && denominator != 0 && numerator != null) {
        final normalizedItem = Map<String, dynamic>.from(item)
          ..['dosage'] = (numerator / denominator).toString()
          ..['unit'] = fraction.group(3);
        return _takeAmountLabel(normalizedItem);
      }
    }
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)(알|정|캡슐|포|개|mL|ml|방울|T|TAB|C|CAP|PKG|EA)$',
      caseSensitive: false,
    ).firstMatch(compact);
    final number =
        match?.group(1) ?? (double.tryParse(compact) != null ? compact : null);
    final rawUnit = match?.group(2) ?? unit;
    if (number == null || rawUnit.isEmpty) return '';
    final parsed = double.tryParse(number);
    final amount = parsed == null
        ? number
        : parsed == parsed.roundToDouble()
        ? parsed.toInt().toString()
        : parsed
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    final normalizedUnit = switch (rawUnit.toUpperCase()) {
      'T' || 'TAB' || '정' || '알' => '알',
      'C' || 'CAP' || '캡슐' => '캡슐',
      'PKG' || '포' => '포',
      'EA' || '개' => '개',
      'ML' || '밀리리터' => 'mL',
      '방울' => '방울',
      _ => '',
    };
    return normalizedUnit.isEmpty ? '' : '$amount$normalizedUnit';
  }

  static String _shortDrugName(String name) {
    return stripExportAlias(name);
  }

  static String? _seniorExplanation(Map<String, dynamic> item) {
    final raw =
        item['short_explanation']?.toString().trim() ??
        item['easy_explanation']?.toString().trim() ??
        item['easy_category']?.toString().trim() ??
        '';
    if (raw.isEmpty || raw == '처방받은 약이에요') return null;
    return raw;
  }

  static Map<String, int> _fieldConfidences(Map<String, dynamic> item) {
    final raw = item['ocr_field_confidences'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num)
          entry.key.toString(): (entry.value as num).round(),
    };
  }

  static String _matchStatusLabel(Map<String, dynamic> item) {
    final status = item['match_status']?.toString().toUpperCase() ?? '';
    return switch (status) {
      'MATCHED' || 'MFDS' => '공식 약 확인됨',
      'REVIEW_REQUIRED' => '약 확인 필요',
      _ => '공식 약을 찾지 못함',
    };
  }

  static bool _uncertain(Map<String, dynamic> item) {
    if (item['uncertain'] == true) return true;
    if (item['match_status']?.toString() == 'UNMATCHED') return true;
    final confidence = item['confidence'];
    return confidence is num && confidence < 0.7;
  }

  static bool _hasCompleteDosing(Map<String, dynamic> item) {
    final amount = item['dosage']?.toString().trim() ?? '';
    final timesPerTake = item['times_per_take'];
    final unit = item['unit']?.toString().trim() ?? '';
    final frequency = item['frequency_per_day'];
    final duration = item['duration_days'];
    final amountWithUnit = RegExp(
      r'^(?:\d+(?:\.\d+)?|\d+/\d+|반)\s*(알|정|캡슐|포|개|mL|ml|방울|T|TAB|C|CAP|PKG|EA)$',
      caseSensitive: false,
    ).hasMatch(amount);
    final knownUnit = RegExp(
      r'^(알|정|캡슐|포|개|mL|ml|방울|T|TAB|C|CAP|PKG|EA)$',
      caseSensitive: false,
    ).hasMatch(unit);
    final numericAmount = double.tryParse(amount) != null;
    final hasAmount =
        amountWithUnit ||
        (numericAmount && knownUnit) ||
        (timesPerTake is num && timesPerTake > 0 && knownUnit);
    final hasFrequency =
        frequency is num && frequency.toInt() >= 1 && frequency.toInt() <= 3;
    final hasDuration =
        duration is num && duration.toInt() >= 1 && duration.toInt() <= 365;
    return hasAmount && hasFrequency && hasDuration;
  }

  bool get _allDosingConfirmed => _editedItems.every(_hasCompleteDosing);
  int get _missingDosingCount =>
      _editedItems.where((item) => !_hasCompleteDosing(item)).length;

  Future<void> _editItem(int index) async {
    final item = _editedItems[index];
    final existingAmount = item['dosage']?.toString().trim() ?? '';
    final timesPerTake = item['times_per_take'];
    final amountController = TextEditingController(
      text: existingAmount.isNotEmpty
          ? existingAmount
          : (timesPerTake is num && timesPerTake > 0
                ? '${timesPerTake.toInt()}알'
                : ''),
    );
    final duration = item['duration_days'];
    final durationController = TextEditingController(
      text: duration is num && duration > 0 ? duration.toInt().toString() : '',
    );
    final rawFrequency = item['frequency_per_day'];
    int? frequency =
        rawFrequency is num &&
            rawFrequency.toInt() >= 1 &&
            rawFrequency.toInt() <= 3
        ? rawFrequency.toInt()
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              22,
              22,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _shortDrugName(item['drug_name']?.toString() ?? '약'),
                  style: AppText.emphasis(size: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  '처방전에 적힌 내용 그대로 확인해 주세요.',
                  style: AppText.body(size: 17, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: amountController,
                  textInputAction: TextInputAction.next,
                  style: AppText.body(size: 20),
                  decoration: const InputDecoration(
                    labelText: '한 번에 사용하는 양',
                    hintText: '예: 1알 또는 0.5정',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: frequency,
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
                  onChanged: (value) => setSheetState(() => frequency = value),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  style: AppText.body(size: 20),
                  decoration: const InputDecoration(
                    labelText: '복용 일수',
                    hintText: '예: 7',
                    suffixText: '일',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SeniorButton(
                  label: '확인했어요',
                  minHeight: 66,
                  onPressed: () {
                    final amount = amountController.text.trim();
                    final days = int.tryParse(durationController.text.trim());
                    if (amount.isEmpty ||
                        frequency == null ||
                        days == null ||
                        days < 1 ||
                        days > 365) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(
                          content: Text('복용량, 하루 횟수, 복용 일수를 모두 확인해 주세요.'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _editedItems[index] = {
                        ...item,
                        'dosage': amount,
                        'times_per_take': null,
                        'frequency_per_day': frequency,
                        'duration_days': days,
                      };
                    });
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    amountController.dispose();
    durationController.dispose();
  }

  Future<void> _fixMedicineName(int index) async {
    final item = _editedItems[index];
    final current =
        item['ocr_drug_name_raw']?.toString().trim().isNotEmpty == true
        ? item['ocr_drug_name_raw'].toString()
        : item['drug_name']?.toString() ?? '';
    final query = await showFixNameSheet(context, current: current);
    if (!mounted || query == null) return;

    try {
      final response = await ApiClient().get(
        '/api/v1/medicines/lookup?q=${Uri.encodeQueryComponent(query)}',
      );
      if (!mounted) return;
      final rawItems = response is Map ? response['items'] : null;
      final hits = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((value) => Map<String, dynamic>.from(value))
                .toList()
          : <Map<String, dynamic>>[];
      if (hits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공식 의약품 목록에서 해당 이름을 찾지 못했어요.')),
        );
        return;
      }
      final picked = await _pickOfficialMedicine(hits);
      if (!mounted || picked == null) return;
      final displayName =
          picked['display_name']?.toString() ??
          picked['product_name']?.toString() ??
          query;
      setState(() {
        _editedItems[index] = {
          ...item,
          'medicine_code': picked['medicine_code'],
          'drug_name': displayName,
          'display_name': displayName,
          'official_product_name':
              picked['product_name']?.toString() ?? displayName,
          'ingredient_name':
              picked['ingredient_name']?.toString() ??
              picked['ingredient']?.toString() ??
              '',
          'ocr_drug_name_raw': current,
          'match_status': 'MATCHED',
        };
        _expandedItems.add(index);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공식 약을 찾지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  Future<Map<String, dynamic>?> _pickOfficialMedicine(
    List<Map<String, dynamic>> hits,
  ) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('공식 약을 골라 주세요', style: AppText.emphasis(size: 24)),
              const SizedBox(height: 6),
              Text(
                '제품명과 주성분을 처방전과 비교해 주세요.',
                style: AppText.body(size: 17, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final hit = hits[index];
                    final name =
                        hit['display_name']?.toString() ??
                        hit['product_name']?.toString() ??
                        '약';
                    final ingredient =
                        hit['ingredient_name']?.toString() ??
                        hit['ingredient']?.toString() ??
                        '';
                    return SeniorCard(
                      onTap: () => Navigator.of(sheetContext).pop(hit),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppText.cardTitle(size: 20)),
                          if (ingredient.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '주성분: $ingredient',
                              style: AppText.caption(
                                size: 17,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmPartialRegistration() async {
    if (widget.unrecognizedNames.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('확인하지 못한 약이 있어요'),
            content: const Text(
              '제외한 약은 함께 먹기 확인에서도 빠져요. 처방전과 비교한 뒤 제외하고 등록해 주세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('다시 확인하기'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('제외하고 등록'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _tryRegister() async {
    if (_registering) return;
    if (!_allDosingConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('빨간 약 카드의 복용 정보를 먼저 확인해 주세요.')),
      );
      return;
    }
    if (!await _confirmPartialRegistration()) return;
    setState(() => _registering = true);
    await widget.onRegister(_editedItems);
    if (mounted) setState(() => _registering = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '이렇게 읽었어요'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                          _editedItems.isEmpty
                              ? '글자는 읽었는데, 공식 약과 아직 못 맞췄어요'
                              : '약 ${_editedItems.length}가지를 찾았어요',
                          style: AppText.cardTitle(color: AppColors.point),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _allDosingConfirmed
                              ? '공식 약 ${_editedItems.length}개 확인 · 복용 정보 누락 없음'
                              : '공식 약 ${_editedItems.length}개 확인 · 복용 정보 누락 $_missingDosingCount개',
                          style: AppText.caption(
                            color: const Color(0xFF3A4590),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (int index = 0; index < _editedItems.length; index++) ...[
                    Builder(
                      builder: (context) {
                        final item = _editedItems[index];
                        final needsDosingConfirmation = !_hasCompleteDosing(
                          item,
                        );
                        return _DrugCard(
                          name: _shortDrugName(
                            item['drug_name']?.toString() ?? '이름을 못 읽었어요',
                          ),
                          ingredient:
                              item['ingredient_name']?.toString() ??
                              item['ingredient']?.toString() ??
                              '',
                          ingredientStrength:
                              item['ingredient_strength']?.toString() ?? '',
                          rawOcrName:
                              item['ocr_drug_name_raw']?.toString() ??
                              item['drug_name']?.toString() ??
                              '',
                          officialName:
                              item['official_product_name']?.toString() ??
                              item['drug_name']?.toString() ??
                              '',
                          medicineCode: item['medicine_code']?.toString() ?? '',
                          dosage: _dosage(item),
                          purposeLabel: item['purpose_label']?.toString(),
                          explanation: _seniorExplanation(item),
                          keyCaution: item['key_caution']?.toString(),
                          fieldConfidences: _fieldConfidences(item),
                          matchStatusLabel: _matchStatusLabel(item),
                          uncertain: _uncertain(item),
                          needsDosingConfirmation: needsDosingConfirmation,
                          expanded: _expandedItems.contains(index),
                          onToggle: () => setState(() {
                            if (!_expandedItems.remove(index)) {
                              _expandedItems.add(index);
                            }
                          }),
                          onFixName: () => _fixMedicineName(index),
                          onEditDosing: () => _editItem(index),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.unrecognizedNames.isNotEmpty) ...[
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      borderColor: AppColors.dangerBorder,
                      borderWidth: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '사진 인식률이 낮아 읽지 못한 이름이 있어요',
                            style: AppText.cardTitle(
                              size: 20,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '이 이름들은 등록에서 빼 두었어요. 밝은 곳에서 흔들리지 않게 다시 찍으면 인식률이 올라가요.',
                            style: AppText.body(
                              size: 17,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final name in widget.unrecognizedNames)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '· $name  (못 읽음)',
                                style: AppText.body(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  if (_editedItems.isNotEmpty) ...[
                    SeniorButton(
                      label: _registering
                          ? '등록하고 있어요'
                          : (!_allDosingConfirmed
                                ? '복용 정보 확인 후 등록하기'
                                : (widget.unrecognizedNames.isNotEmpty
                                      ? '미확인 약 확인 후 등록하기'
                                      : '이대로 등록하기')),
                      minHeight: 70,
                      onPressed: _registering ? null : _tryRegister,
                    ),
                    SeniorTextButton(
                      label: '다시 찍기',
                      onPressed: widget.onRetake,
                    ),
                  ] else
                    SeniorButton(
                      label: '다시 찍어드릴게요',
                      minHeight: 70,
                      onPressed: widget.onRetake,
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

class _DrugCard extends StatelessWidget {
  final String name;
  final String ingredient;
  final String ingredientStrength;
  final String rawOcrName;
  final String officialName;
  final String medicineCode;
  final String dosage;
  final String? purposeLabel;
  final String? explanation;
  final String? keyCaution;
  final Map<String, int> fieldConfidences;
  final String matchStatusLabel;
  final bool uncertain;
  final bool needsDosingConfirmation;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onFixName;
  final VoidCallback onEditDosing;

  const _DrugCard({
    required this.name,
    required this.ingredient,
    required this.ingredientStrength,
    required this.rawOcrName,
    required this.officialName,
    required this.medicineCode,
    required this.dosage,
    required this.purposeLabel,
    required this.explanation,
    required this.keyCaution,
    required this.fieldConfidences,
    required this.matchStatusLabel,
    required this.uncertain,
    required this.needsDosingConfirmation,
    required this.expanded,
    required this.onToggle,
    required this.onFixName,
    required this.onEditDosing,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      onTap: onToggle,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      borderColor: uncertain || needsDosingConfirmation
          ? AppColors.dangerBorder
          : null,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: AppText.cardTitle(size: 21))),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Icon(
                  expanded ? Icons.expand_less : Icons.chevron_right,
                  color: AppColors.textTertiary,
                  size: 30,
                ),
              ),
            ],
          ),
          if (ingredient.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '주성분: ${[
                compactIngredientSummary(ingredient),
                ingredientStrength,
              ].where((value) => value.trim().isNotEmpty).join(' · ')}',
              style: AppText.caption(size: 17, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (explanation != null && explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explanation!,
              style: AppText.body(size: 17, color: AppColors.textSecondary),
              maxLines: expanded ? null : 2,
              overflow: expanded ? null : TextOverflow.ellipsis,
            ),
          ],
          if (dosage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              dosage,
              style: AppText.body(size: 18, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                matchStatusLabel,
                style: AppText.label(
                  size: 16.5,
                  color: uncertain ? AppColors.danger : AppColors.point,
                ),
              ),
              if (fieldConfidences['drug_name'] case final int confidence)
                Text(
                  '글자 인식률 $confidence%',
                  style: AppText.label(
                    size: 16.5,
                    color: confidence >= 85
                        ? AppColors.point
                        : AppColors.danger,
                  ),
                ),
            ],
          ),
          if (uncertain) ...[
            const SizedBox(height: 10),
            Text(
              '약 이름을 다시 확인해 주세요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
          ],
          if (needsDosingConfirmation) ...[
            const SizedBox(height: 10),
            Text(
              '복용량·단위·하루 횟수·복용 일수를 확인해 주세요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
          ],
          if (expanded) ...[
            const SizedBox(height: 16),
            const SeniorDivider(),
            const SizedBox(height: 14),
            _DetailLine(label: '사진에서 읽은 이름', value: rawOcrName),
            const SizedBox(height: 8),
            _DetailLine(label: '공식 제품명', value: officialName),
            if (medicineCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailLine(label: '공식 의약품 코드', value: medicineCode),
            ],
            if ((purposeLabel ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '사용될 수 있는 주요 목적',
                style: AppText.label(size: 17, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                purposeLabel!,
                style: AppText.label(size: 18, color: AppColors.point),
              ),
              const SizedBox(height: 4),
              Text(
                '실제 처방 이유는 의사나 약사에게 확인해 주세요.',
                style: AppText.caption(
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if ((keyCaution ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '주의: $keyCaution',
                style: AppText.label(size: 17, color: AppColors.danger),
              ),
            ],
            if (fieldConfidences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '항목별 글자 인식률',
                style: AppText.label(size: 17, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                _confidenceSummary(fieldConfidences),
                style: AppText.caption(
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onFixName,
                    child: const Text('약 이름 다시 확인'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEditDosing,
                    child: const Text('복용 정보 고치기'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              '자세히 확인하기',
              style: AppText.label(size: 17, color: AppColors.point),
            ),
          ],
        ],
      ),
    );
  }

  static String _confidenceSummary(Map<String, int> values) {
    const labels = {
      'drug_name': '약 이름',
      'dose_amount': '1회량',
      'frequency_per_day': '하루 횟수',
      'duration_days': '복용 일수',
    };
    return values.entries
        .where((entry) => labels.containsKey(entry.key))
        .map((entry) => '${labels[entry.key]} ${entry.value}%')
        .join(' · ');
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.caption(size: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(value, style: AppText.body(size: 17)),
      ],
    );
  }
}

/// 읽지 못했을 때 — 5e 회복 패턴. 3번 실패하면 가족 대행을 권한다.
class _FailedScreen extends StatelessWidget {
  final int failureCount;
  final String failureReason;
  final VoidCallback onRetry;
  final VoidCallback onAskFamily;

  const _FailedScreen({
    required this.failureCount,
    required this.failureReason,
    required this.onRetry,
    required this.onAskFamily,
  });

  @override
  Widget build(BuildContext context) {
    final tooManyTries = failureCount >= 3;
    final connectionFail =
        failureReason.contains('연결') ||
        failureReason.contains('Socket') ||
        failureReason.contains('Timeout') ||
        failureReason.contains('timeout');
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 찍기'),
          Expanded(
            child: RecoveryView(
              title: '지금은 처방전을\n읽지 못하고 있어요',
              reassurance: connectionFail
                  ? '서버에 연결하지 못했어요. 같은 와이파이인지, 서버가 켜져 있는지 봐 주세요. '
                  : (failureReason.isEmpty
                        ? '흐리거나 흔들리면 약 이름이 잘려 버려질 수 있어요. '
                        : '$failureReason '),
              reassuranceEmphasis: '잘못 찍으신 게 아니니 걱정하지 마세요.',
              steps: const [
                '밝은 곳에 처방전을 펼쳐 놓으세요',
                '종이 네 귀퉁이가 다 보이게 하세요',
                '전화기를 두 손으로 잡고 흔들리지 않게 찍으세요',
                '다시 찍기, 앨범에서 고르기, 직접 입력 중에서 고를 수 있어요',
              ],
              actionLabel: '다시 찍어드릴게요',
              onAction: onRetry,
              stillWorksTitle: '지금 드시는 약은 그대로예요',
              stillWorksBody: '이미 등록된 약과 알림은 아무 영향이 없어요.',
              helperText: tooManyTries ? '어려우시면\n가족이 대신 찍어드릴 수 있어요' : null,
              onCallHelper: tooManyTries ? onAskFamily : null,
            ),
          ),
        ],
      ),
    );
  }
}
