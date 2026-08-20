import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medication/domain/medication_models.dart';
import '../../../medication/presentation/widgets/dose_guard_sheets.dart';

/// 음성으로 알아들어야 하는 표현.
///
/// 읽기·타이핑 대신 듣기·말하기. 시니어가 카카오톡에서 음성 메시지를
/// 쓰는 것과 같은 이유다.
abstract final class VoiceIntents {
  static const List<String> taken = [
    '먹었어',
    '먹었어요',
    '다 먹었다',
    '다 먹었어요',
    '네',
    '응',
  ];

  static const List<String> later = ['나중에', '아직', '이따가'];

  static const List<String> whatToTake = ['뭐 먹어야 해', '무슨 약', '어떤 약'];

  /// 인식된 말을 뜻으로 바꾼다. 못 알아들으면 null.
  static VoiceIntent? parse(String heard) {
    final text = heard.trim();
    if (taken.any(text.contains)) return VoiceIntent.taken;
    if (later.any(text.contains)) return VoiceIntent.later;
    if (whatToTake.any(text.contains)) return VoiceIntent.whatToTake;
    return null;
  }
}

enum VoiceIntent { taken, later, whatToTake }

/// 5d — 음성으로 듣고 대답하기.
///
/// TTS는 시스템 음성을 쓰고 속도는 기본보다 10% 느리게.
/// STT는 온디바이스를 우선한다(네트워크 없이 동작해야 한다).
// TODO: 온디바이스 STT/TTS 플러그인 연결. 지금은 흐름과 문구를 확정한 껍데기다.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;
  bool _listening = false;
  String? _heard;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  String _speech(TodayMedication today) {
    final next = today.nextDose;
    if (next == null) return '오늘 드실 약은 다 드셨어요. 잘하셨어요.';
    final names = next.medicines.map((m) => m.spoken).join(', ');
    return '${next.slot.spokenTime}예요. $names 드시면 돼요.';
  }

  Future<void> _handle(VoiceIntent intent, DoseEntry dose) async {
    final controller = ref.read(medicationProvider.notifier);
    switch (intent) {
      case VoiceIntent.taken:
        final outcome = controller.take(dose.slot);
        if (outcome == DoseCheckOutcome.alreadyTaken && mounted) {
          await showDuplicateDoseSheet(
            context: context,
            dose: ref.read(medicationProvider).doseOf(dose.slot),
            onUndo: () => controller.undo(dose.slot),
          );
        }
      case VoiceIntent.later:
        controller.snooze(dose.slot);
      case VoiceIntent.whatToTake:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(medicationProvider);
    final next = today.nextDose;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          SeniorTitleHeader(
            title: '듣고 말하기',
            trailing: SeniorTextButton(
              label: '끄기',
              expand: false,
              color: AppColors.point,
              fontSize: 17,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 읽어주기 카드 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('앱이 이렇게 말해요', style: AppText.label(size: 18)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            _speech(today),
                            style: AppText.label(
                              size: 21,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SeniorButton(
                          label: '다시 읽어주세요',
                          minHeight: 66,
                          fontSize: 22,
                          onPressed: () => ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(
                            const SnackBar(content: Text('천천히 다시 읽어드릴게요')),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── 듣는 중 카드 ──
                  SeniorCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    borderColor: _listening ? AppColors.point : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Dot(size: 12),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _listening ? '듣고 있어요' : '누르면 듣기 시작해요',
                                style: AppText.cardTitle(
                                  size: 18,
                                  color: AppColors.point,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 64,
                          child: AnimatedBuilder(
                            animation: _wave,
                            builder: (context, _) => _Waveform(
                              progress: _listening ? _wave.value : 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _heard ?? '말씀해 주세요',
                          textAlign: TextAlign.center,
                          style: AppText.cardTitle(size: 23),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '"먹었어요" 하고 말씀하시면 기록해 드려요.',
                          textAlign: TextAlign.center,
                          style: AppText.caption(),
                        ),
                        const SizedBox(height: 14),
                        SeniorButton(
                          label: _listening ? '그만 듣기' : '말하기',
                          minHeight: 66,
                          fontSize: 22,
                          onPressed: next == null
                              ? null
                              : () => _toggleListening(next),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  SeniorButton(
                    label: '손으로 누를게요',
                    kind: SeniorButtonKind.outline,
                    minHeight: 64,
                    fontSize: 20,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// STT 플러그인이 붙기 전까지는 "먹었어요"를 알아들은 것으로 흉내낸다.
  void _toggleListening(DoseEntry dose) {
    if (_listening) {
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _heard = null;
    });
    Timer(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;
      const heard = '먹었어요';
      setState(() {
        _listening = false;
        _heard = heard;
      });
      final intent = VoiceIntents.parse(heard);
      if (intent != null) await _handle(intent, dose);
    });
  }
}

/// 파형 — 막대 7개. 진폭이 클수록 포인트색에 가까워진다.
class _Waveform extends StatelessWidget {
  final double progress;
  const _Waveform({required this.progress});

  static const List<Color> _shades = [
    Color(0xFFC7CEF7),
    Color(0xFF8C9BF0),
    AppColors.point,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Builder(
            builder: (context) {
              final phase = math.sin((progress + i / 7) * math.pi * 2).abs();
              final height = 12 + 52 * phase;
              final shade = _shades[(phase * 2.99).floor().clamp(0, 2)];
              return Container(
                width: 9,
                height: height,
                decoration: BoxDecoration(
                  color: progress == 0 ? AppColors.chartPast : shade,
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
