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

  /// 글자 인식률 % 결과.
  readiness,

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
  int _readinessPct = 0;
  String _readinessLabel = 'fair';
  String _readinessSummary = '';
  List<String> _missingHints = const [];

  /// 촬영 실패 횟수. 3번 실패하면 가족 대행(5g)을 권한다.
  int _failureCount = 0;

  List<Map<String, dynamic>> get _items {
    final items = _result?['items'];
    if (items is List && items.isNotEmpty) {
      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
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
      final hasItems = items is List && items.isNotEmpty;
      if (!hasItems) {
        setState(() {
          _failureCount++;
          _step = PrescriptionStep.failed;
        });
        return;
      }

      final pctRaw =
          mapped['recognition_pct'] ?? mapped['user_readiness_pct'];
      final pct = pctRaw is num ? pctRaw.round() : 0;
      final hints = mapped['missing_hints'];
      setState(() {
        _result = mapped;
        _failureCount = 0;
        _readinessPct = pct.clamp(0, 100);
        _readinessLabel =
            mapped['recognition_label']?.toString() ??
            mapped['readiness_label']?.toString() ??
            'fair';
        _readinessSummary =
            mapped['recognition_summary']?.toString() ??
            mapped['readiness_summary']?.toString() ??
            '글자 인식을 마쳤어요.';
        _missingHints = hints is List
            ? hints.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : const [];
        _step = PrescriptionStep.readiness;
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
        _step = PrescriptionStep.failed;
      });
    }
  }

  Future<void> _register() async {
    final userId = MvpSession.userId.trim().isEmpty
        ? 'mvp-user'
        : MvpSession.userId.trim();
    final confirmItems = _items
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

    MvpSession.latestOcrItems = _items;
    MvpSession.latestOcrRegisteredAt = DateTime.now();
    await ref.read(medicationProvider.notifier).refreshFromServer();

    var hasRisk = false;
    var durFailed = false;
    try {
      final analysisBody = <String, dynamic>{
        'user_id': userId,
        'medicine_codes': <String>[],
      };
      if (MvpSession.isPregnant != null) {
        analysisBody['is_pregnant'] = MvpSession.isPregnant;
      }
      final analysis = await _apiClient.post(
        '/api/v1/dur/analyze',
        body: analysisBody,
      );
      if (analysis is Map) {
        if (analysis['has_risk'] == true) {
          hasRisk = true;
        } else {
          final matches = analysis['matches'];
          hasRisk = matches is List && matches.isNotEmpty;
        }
      }
    } catch (error) {
      durFailed = true;
      debugPrint('등록 직후 약 함께먹기 검사 실패: $error');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          durFailed
              ? '약은 등록했어요. 함께먹기 검사는 나중에 다시 확인해 주세요.'
              : '약을 등록했어요. 시간에 맞춰 알려드릴게요.',
        ),
      ),
    );

    if (hasRisk) {
      context.push('/dur-analysis');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case PrescriptionStep.capture:
        return _CaptureScreen(
          onCamera: () => _pick(ImageSource.camera),
          onGallery: () => _pick(ImageSource.gallery),
          onManual: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('손으로 적기 — 아직 준비 중이에요')),
          ),
        );
      case PrescriptionStep.reading:
        return _ReadingScreen(image: _image);
      case PrescriptionStep.readiness:
        return _ReadinessScreen(
          pct: _readinessPct,
          label: _readinessLabel,
          summary: _readinessSummary,
          missingHints: _missingHints,
          onNext: () => setState(() => _step = PrescriptionStep.confirm),
          onRetake: () => setState(() {
            _image = null;
            _result = null;
            _step = PrescriptionStep.capture;
          }),
        );
      case PrescriptionStep.confirm:
        return _ConfirmScreen(
          items: _items,
          onRegister: _register,
          onRetake: () => setState(() {
            _image = null;
            _step = PrescriptionStep.capture;
          }),
        );
      case PrescriptionStep.failed:
        return _FailedScreen(
          failureCount: _failureCount,
          onRetry: () => setState(() {
            _image = null;
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
                                  text: '두 손으로 잡고\n흔들리지 않게 찍으세요',
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
            style: AppText.body(size: 22, color: Colors.white, weight: FontWeight.w500),
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

/// 촬영 후 글자 인식률을 보여 준 뒤 확인 화면으로 보냄.
class _ReadinessScreen extends StatelessWidget {
  final int pct;
  final String label;
  final String summary;
  final List<String> missingHints;
  final VoidCallback onNext;
  final VoidCallback onRetake;

  const _ReadinessScreen({
    required this.pct,
    required this.label,
    required this.summary,
    required this.missingHints,
    required this.onNext,
    required this.onRetake,
  });

  Color get _accent {
    if (label == 'good' || pct >= 85) return AppColors.point;
    if (label == 'poor' || pct < 60) return AppColors.danger;
    return const Color(0xFFC9A227);
  }

  String get _title {
    if (pct >= 85) return '글자 인식이 좋아요';
    if (pct >= 60) return '일부 글자 인식이 불완전해요';
    return '글자 인식률이 낮아요';
  }

  @override
  Widget build(BuildContext context) {
    final emphasizeRetake = pct < 60;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '인식 결과'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                children: [
                  Text('글자 인식률', style: AppText.cardTitle()),
                  const SizedBox(height: 8),
                  Text(
                    '$pct%',
                    style: AppText.hero(size: 72, color: _accent),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: AppText.emphasis(color: _accent),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: AppText.body(),
                  ),
                  if (missingHints.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SeniorCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('인식이 약한 항목', style: AppText.cardTitle(size: 18)),
                          const SizedBox(height: 8),
                          for (final hint in missingHints)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('· $hint', style: AppText.body()),
                            ),
                        ],
                      ),
                    ),
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
                  if (!emphasizeRetake) ...[
                    SeniorButton(
                      label: '다음',
                      minHeight: 70,
                      onPressed: onNext,
                    ),
                    SeniorTextButton(label: '다시 찍기', onPressed: onRetake),
                  ] else ...[
                    SeniorButton(
                      label: '다시 찍어드릴게요',
                      minHeight: 70,
                      onPressed: onRetake,
                    ),
                    SeniorTextButton(label: '그래도 다음', onPressed: onNext),
                  ],
                ],
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
class _ConfirmScreen extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onRegister;
  final VoidCallback onRetake;

  const _ConfirmScreen({
    required this.items,
    required this.onRegister,
    required this.onRetake,
  });

  static String _dosage(Map<String, dynamic> item) {
    final perDay = item['frequency_per_day'];
    final days = item['duration_days'];
    final parts = <String>[];
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
    return parts.isEmpty ? '복용법을 확인해 주세요' : parts.join(' · ');
  }

  static bool _uncertain(Map<String, dynamic> item) {
    if (item['uncertain'] == true) return true;
    if (item['match_status']?.toString() == 'UNMATCHED') return true;
    final confidence = item['confidence'];
    return confidence is num && confidence < 0.7;
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
                          '약 ${items.length}가지를 찾았어요',
                          style: AppText.cardTitle(color: AppColors.point),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '틀린 곳이 있으면 눌러서 고쳐주세요.',
                          style: AppText.caption(
                            color: const Color(0xFF3A4590),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final item in items) ...[
                    _DrugCard(
                      name: item['drug_name']?.toString() ?? '이름을 못 읽었어요',
                      dosage: _dosage(item),
                      explanation: item['easy_explanation']?.toString(),
                      uncertain: _uncertain(item),
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
                  SeniorButton(
                    label: '이대로 등록하기',
                    minHeight: 70,
                    onPressed: onRegister,
                  ),
                  SeniorTextButton(label: '다시 찍기', onPressed: onRetake),
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
  final String? explanation;
  final bool uncertain;

  const _DrugCard({
    required this.name,
    required this.dosage,
    required this.explanation,
    required this.uncertain,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      borderColor: uncertain ? AppColors.dangerBorder : null,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: AppText.cardTitle(size: 21))),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('고치기 — 아직 준비 중이에요')),
                ),
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
          const SizedBox(height: 6),
          Text(
            dosage,
            style: AppText.body(size: 18, color: AppColors.textSecondary),
          ),
          if (explanation != null && explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(explanation!, style: AppText.caption()),
          ],
          if (uncertain) ...[
            const SizedBox(height: 10),
            Text(
              '약 이름 인식이 불확실해요',
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
  final VoidCallback onRetry;
  final VoidCallback onAskFamily;

  const _FailedScreen({
    required this.failureCount,
    required this.onRetry,
    required this.onAskFamily,
  });

  @override
  Widget build(BuildContext context) {
    final tooManyTries = failureCount >= 3;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 찍기'),
          Expanded(
            child: RecoveryView(
              title: '지금은 처방전을\n읽지 못하고 있어요',
              reassurance: '글자 인식에 실패했어요. ',
              reassuranceEmphasis: '잘못 찍으신 게 아니니 걱정하지 마세요.',
              steps: const [
                '밝은 곳에 처방전을 펼쳐 놓으세요',
                '종이 네 귀퉁이가 다 보이게 하세요',
                '전화기를 두 손으로 잡고 찍으세요',
              ],
              actionLabel: '다시 찍어드릴게요',
              onAction: onRetry,
              stillWorksTitle: '지금 드시는 약은 그대로예요',
              stillWorksBody: '이미 등록된 약과 알림은 아무 영향이 없어요.',
              helperText: tooManyTries
                  ? '어려우시면\n가족이 대신 찍어드릴 수 있어요'
                  : null,
              onCallHelper: tooManyTries ? onAskFamily : null,
            ),
          ),
        ],
      ),
    );
  }
}
