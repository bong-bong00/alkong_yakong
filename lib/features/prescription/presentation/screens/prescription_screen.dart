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
import '../../../onboarding/presentation/screens/first_run_screen.dart';

/// 처방전 등록 흐름의 단계.
enum PrescriptionStep {
  /// 4d — 처방전 촬영.
  capture,

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
  const PrescriptionScreen({super.key});

  @override
  ConsumerState<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends ConsumerState<PrescriptionScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  PrescriptionStep _step = PrescriptionStep.capture;
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
      setState(() => _image = File(picked.path));
      await _read();
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

      // Gemini 비전+구조화는 시간이 더 걸릴 수 있어 OCR만 길게 기다린다.
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

    if (!mounted) return;
    // 홈에 있는 약(코다론)과 방금 찍은 약(아디팜)을 바로 함께먹기 화면에서 본다.
    context.push('/dur-analysis');
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case PrescriptionStep.capture:
        return _CaptureScreen(
          onCamera: () => _pick(ImageSource.camera),
          onGallery: () => _pick(ImageSource.gallery),
          onManual: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('손으로 적기 — 아직 준비 중이에요'))),
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
            _step = PrescriptionStep.capture;
          }),
        );
      case PrescriptionStep.failed:
        return _FailedScreen(
          failureCount: _failureCount,
          failureReason: _failureReason,
          onRetry: () => setState(() {
            _image = null;
            _failureReason = '';
            _step = PrescriptionStep.capture;
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
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onManual;

  const _CaptureScreen({
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
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
                              SeniorButton(
                                label: '사진 찍기',
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

  static String _dosage(Map<String, dynamic> item) {
    final amount = item['dosage']?.toString().trim() ?? '';
    final timesPerTake = item['times_per_take'];
    final perDay = item['frequency_per_day'];
    final days = item['duration_days'];
    final parts = <String>[];
    if (amount.isNotEmpty) {
      parts.add('한 번에 $amount');
    } else if (timesPerTake is num && timesPerTake > 0) {
      parts.add('한 번에 ${timesPerTake.toInt()}알');
    }
    if (perDay is num) {
      parts.add('하루 ${perDay.toInt()}번');
      parts.add(switch (perDay.toInt()) {
        1 => '아침',
        2 => '아침, 저녁',
        3 => '아침, 점심, 저녁',
        _ => '정해진 시간',
      });
    }
    if (days is num) parts.add('${days.toInt()}일');
    return parts.join(' · ');
  }

  static String _shortDrugName(String name) {
    return name.replaceAll(RegExp(r'\(수출명\s*[:：][^)]*\)'), '').trim();
  }

  static String? _seniorExplanation(Map<String, dynamic> item) {
    final raw =
        item['short_explanation']?.toString().trim() ??
        item['easy_explanation']?.toString().trim() ??
        item['easy_category']?.toString().trim() ??
        '';
    if (raw.isEmpty) return null;
    if (raw.contains('약이에요')) return raw;
    return '처방받은 약이에요';
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
    final frequency = item['frequency_per_day'];
    final duration = item['duration_days'];
    final hasAmount =
        amount.isNotEmpty || (timesPerTake is num && timesPerTake > 0);
    final hasFrequency =
        frequency is num && frequency.toInt() >= 1 && frequency.toInt() <= 3;
    final hasDuration =
        duration is num && duration.toInt() >= 1 && duration.toInt() <= 365;
    return hasAmount && hasFrequency && hasDuration;
  }

  bool get _allDosingConfirmed => _editedItems.every(_hasCompleteDosing);

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
                    labelText: '한 번에 먹는 양',
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

  Future<void> _tryRegister() async {
    if (_registering) return;
    if (!_allDosingConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('빨간 약 카드의 복용 정보를 먼저 확인해 주세요.')),
      );
      return;
    }
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
                              ? '약 이름과 복용 정보를 꼭 확인해 주세요.'
                              : '빨간 카드를 눌러 빠진 복용 정보를 확인해 주세요.',
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
                          dosage: _dosage(item),
                          purposeLabel: item['purpose_label']?.toString(),
                          explanation: _seniorExplanation(item),
                          keyCaution: item['key_caution']?.toString(),
                          uncertain: _uncertain(item),
                          needsDosingConfirmation: needsDosingConfirmation,
                          recognitionPct: item['recognition_pct'] is num
                              ? (item['recognition_pct'] as num).round()
                              : null,
                          onEdit: () => _editItem(index),
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
                          : (_allDosingConfirmed
                                ? '이대로 등록하기'
                                : '복용 정보 확인 후 등록하기'),
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
  final String dosage;
  final String? purposeLabel;
  final String? explanation;
  final String? keyCaution;
  final bool uncertain;
  final bool needsDosingConfirmation;
  final int? recognitionPct;
  final VoidCallback onEdit;

  const _DrugCard({
    required this.name,
    required this.dosage,
    required this.purposeLabel,
    required this.explanation,
    required this.keyCaution,
    required this.uncertain,
    required this.needsDosingConfirmation,
    required this.onEdit,
    this.recognitionPct,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
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
              if (recognitionPct != null) ...[
                const SizedBox(width: 8),
                Text(
                  '$recognitionPct%',
                  style: AppText.cardTitle(
                    size: 20,
                    color: (recognitionPct ?? 0) >= 85
                        ? AppColors.point
                        : AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              InkWell(
                onTap: onEdit,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '고치기',
                    style: AppText.cardTitle(size: 18, color: AppColors.point),
                  ),
                ),
              ),
            ],
          ),
          if (dosage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              dosage,
              style: AppText.body(size: 18, color: AppColors.textSecondary),
            ),
          ],
          if ((purposeLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              purposeLabel!,
              style: AppText.label(size: 17.5, color: AppColors.point),
            ),
          ],
          if (explanation != null && explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explanation!,
              style: AppText.body(size: 17, color: AppColors.textSecondary),
            ),
          ],
          if ((keyCaution ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '주의: $keyCaution',
              style: AppText.label(size: 17, color: AppColors.danger),
            ),
          ],
          if (uncertain) ...[
            const SizedBox(height: 10),
            Text(
              '약 이름 인식이 불확실해요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
          ],
          if (needsDosingConfirmation) ...[
            const SizedBox(height: 10),
            Text(
              '복용량·하루 횟수·복용 일수를 확인해 주세요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
          ],
        ],
      ),
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
