import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
class PrescriptionScreen extends StatefulWidget {
  const PrescriptionScreen({super.key});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  PrescriptionStep _step = PrescriptionStep.capture;
  File? _image;
  Map<String, dynamic>? _result;

  /// 촬영 실패 횟수. 3번 실패하면 가족 대행(5g)을 권한다.
  int _failureCount = 0;

  // TODO: 백엔드 OCR이 비어 있을 때 쓰는 데모 약 목록. 연동되면 지운다.
  static const List<Map<String, dynamic>> _fallbackItems = [
    {
      'drug_name': '모사피아정',
      'frequency_per_day': 2,
      'duration_days': 7,
      'easy_explanation': '속이 더부룩할 때 위장 운동을 도와 편안하게 해주는 약이에요.',
    },
    {
      'drug_name': '프로맥정',
      'frequency_per_day': 2,
      'duration_days': 7,
      'easy_explanation': '위벽을 보호하고 손상된 위를 낫게 해주는 약이에요.',
    },
    {
      'drug_name': '니자엑스캡슐150mg',
      'frequency_per_day': 2,
      'duration_days': 7,
      'easy_explanation': '속쓰릴 때 위산을 줄여 속을 편안하게 해주는 약이에요.',
      'uncertain': true,
    },
  ];

  List<Map<String, dynamic>> get _items {
    final items = _result?['items'];
    if (items is List && items.isNotEmpty) {
      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return _fallbackItems.map(Map<String, dynamic>.from).toList();
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

      final response = await _apiClient.post(
        '/api/v1/prescriptions/ocr',
        body: {
          'user_id': MvpSession.userId.trim(),
          'image_data': base64Image,
          'source_type': 'OCR',
        },
      );

      if (!mounted) return;
      setState(() {
        _result = Map<String, dynamic>.from(response as Map);
        _failureCount = 0;
        _step = PrescriptionStep.confirm;
      });

      final first = _items.isEmpty ? null : _items.first;
      if (first != null) {
        MvpSession.medicineCode = first['medicine_code']?.toString() ?? '';
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failureCount++;
        _step = PrescriptionStep.failed;
      });
    }
  }

  Future<void> _register() async {
    MvpSession.latestOcrItems = _items;
    MvpSession.latestOcrRegisteredAt = DateTime.now();

    var hasRisk = false;
    final userId = MvpSession.userId.trim();
    if (userId.isNotEmpty) {
      try {
        // 등록 직후 약 함께먹기 검사를 자동으로 돌린다.
        // 사용자가 찾아가게 하지 않는다.
        final analysis = await _apiClient.post(
          '/api/v1/dur/analyze',
          body: {'user_id': userId, 'medicine_codes': <String>[]},
        );
        if (analysis is Map) {
          final matches = analysis['matches'];
          hasRisk = matches is List && matches.isNotEmpty;
        }
      } catch (error) {
        debugPrint('등록 직후 약 함께먹기 검사 실패: $error');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('약을 등록했어요. 시간에 맞춰 알려드릴게요.')),
    );

    // 위험이 있으면 주의 화면을 바로 띄운다.
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
          // 글자가 커지면 뷰파인더가 줄고, 그래도 모자라면 스크롤된다.
          // 어떤 배율에서도 "사진 찍기"가 화면 밖으로 밀려나면 안 된다.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: kPrimary),
                        const SizedBox(height: 24),
                        Text(
                          '처방전을 분석 중입니다...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_state == OcrState.result) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_rounded, color: Color(0xFFE24B4A), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI가 분석한 결과입니다. 실제 처방전과 일치하는지 반드시 확인해주세요.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC2185B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if ((_resultData?['ocr_text'] ?? '').toString().isNotEmpty) ...[
                  Text(
                    '읽은 원문',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resultData!['ocr_text'].toString(),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: ListView.separated(
                    itemCount: (_resultData?['items'] as List?)?.length ?? 0,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = (_resultData?['items'] as List)[index] as Map;
                      final name = item['drug_name']?.toString() ?? '';
                      final freq = item['frequency_per_day'] ?? 1;
                      final days = item['duration_days'] ?? 7;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.point,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '종이 전체가 보이게 찍어주세요',
                                  style: AppText.cardTitle(
                                    size: 22,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '글씨가 흐리면 다시 찍어드릴게요.',
                                  style: AppText.body(
                                    size: 18,
                                    color: const Color(0xFFC9D2FA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: AppColors.textSecondary,
                                width: 3,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.darkSurface,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '처방전을 이 안에\n맞춰 주세요',
                                  textAlign: TextAlign.center,
                                  style: AppText.label(
                                    size: 19,
                                    color: AppColors.onDarkMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
              '글씨가 흐려서 확인이 필요해요',
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
              reassurance: '글씨가 흐리거나 종이가 잘려 보였어요. ',
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
