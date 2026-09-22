import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/recovery_view.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../../core/widgets/senior_sheet.dart';
import '../../../medication/application/medication_controller.dart';
import '../../../medicines/application/family_medicine_inbox.dart';
import '../../../medicines/application/user_medicines_controller.dart';
import '../../../medicines/domain/display_policy.dart';
import '../../../onboarding/presentation/screens/first_run_screen.dart';
import 'add_medicine_screen.dart';
import 'manual_medicine_screen.dart';
import '../widgets/fix_name_sheet.dart';
import '../widgets/unread_names_sheet.dart';
import '../../domain/proxy_target.dart';
import '../../domain/registration_result.dart';

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
  final ValueChanged<Map<String, dynamic>?>? onCompleted;

  /// 가족에게 부탁한 뒤 오늘 화면으로 돌아갈 때.
  final VoidCallback? onGoHome;

  /// 약 있는 날 달력으로 갈 때. 쉬운 모드가 화면을 직접 바꿀 때 쓴다.
  final VoidCallback? onOpenScheduleDays;

  /// 보호자가 어르신 대신 넣을 때, 약이 들어갈 어르신.
  ///
  /// null이면 내 약을 내가 넣는 평소 흐름이다. 값이 있으면 방법 고르기를
  /// 건너뛰고 바로 찍기로 들어가며, 등록도 보호자가 아니라 이 어르신 앞으로
  /// 올라간다.
  final ProxyTarget? proxyTarget;

  /// 이미 읽어 둔 처방전 결과. 값이 있으면 찍기를 건너뛰고
  /// 확인 화면부터 시작한다. 서버 없이 화면을 보는 미리보기에 쓴다.
  final Map<String, dynamic>? initialOcrResult;

  const PrescriptionScreen({
    super.key,
    this.onCompleted,
    this.onGoHome,
    this.onOpenScheduleDays,
    this.guardianTitle = '',
    this.proxyTarget,
    this.initialOcrResult,
  });

  @override
  ConsumerState<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends ConsumerState<PrescriptionScreen> {
  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();

  late PrescriptionStep _step = widget.initialOcrResult != null
      ? PrescriptionStep.confirm
      : widget.proxyTarget == null
      // 대신 찍기는 어느 분인지 이미 고르고 들어온다. 방법 고르기를 건너뛴다.
      ? PrescriptionStep.pickMethod
      : PrescriptionStep.capture;
  File? _image;
  late Map<String, dynamic>? _result = widget.initialOcrResult;

  /// 보호자가 어르신 대신 넣는 중인지.
  bool get _isProxy => widget.proxyTarget != null;

  /// 약이 들어갈 사람. 대신 넣는 중이면 어르신, 아니면 나.
  String get _targetUserId {
    final proxyId = widget.proxyTarget?.patientId.trim() ?? '';
    if (proxyId.isNotEmpty) return proxyId;
    final mine = MvpSession.userId.trim();
    return mine.isEmpty ? 'mvp-user' : mine;
  }

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

  static bool _hasPairConflict(Map<String, dynamic>? durResult) {
    const pairTypes = {'병용금기', '중복성분', '효능군중복'};
    final matches = durResult?['matches'];
    if (matches is! List) return false;
    return matches.any(
      (item) => item is Map && pairTypes.contains(item['type']?.toString()),
    );
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
          'user_id': _targetUserId,
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

      // 대신 넣는 중이라면 내 세션(보호자 자신의 약)은 건드리지 않는다.
      final first = _items.isEmpty || _isProxy ? null : _items.first;
      if (first != null) {
        MvpSession.medicineCode = first['medicine_code']?.toString() ?? '';
      }
    } catch (error) {
      debugPrint(
        '[PRESCRIPTION_DIAG] OCR failed error_type=${error.runtimeType}',
      );
      if (!mounted) return;
      setState(() {
        _failureCount++;
        _failureReason = error.toString();
        _step = PrescriptionStep.failed;
      });
    }
  }

  Future<void> _register(List<Map<String, dynamic>> editedItems) async {
    final userId = _targetUserId;
    final confirmItems = editedItems
        .where(_isOfficialMatchedItem)
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
            'dose_amount': item['dose_amount'],
            'dose_unit': item['dose_unit'],
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
      showSeniorSnackbar(context, '등록할 약을 찾지 못했어요. 다시 찍어 주세요.', error: true);
      return;
    }

    for (final item in confirmItems) {
      final administrationTimes = item['administration_times'];
      debugPrint(
        '[PRESCRIPTION_DIAG] '
        'duration_days=${item['duration_days'] ?? 'null'} '
        'frequency_per_day=${item['frequency_per_day'] ?? 'null'} '
        'administration_times_count='
        '${administrationTimes is List ? administrationTimes.length : 0}',
      );
    }

    Map<String, dynamic>? durResult;
    try {
      final response = await _apiClient.post(
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
      if (response is Map && response['registered'] == true) {
        final prescriptionId = response['prescription_id']?.toString().trim();
        debugPrint(
          '[PRESCRIPTION_DIAG] '
          'prescription_id_present=${prescriptionId?.isNotEmpty == true} '
          'schedule_count=${response['schedule_count'] ?? 'unknown'}',
        );
        // 대신 넣는 중이면 이 처방전은 어르신 것이다. 보호자 세션에
        // "방금 등록한 처방전"으로 남기면 보호자의 달력이 남의 약을 그린다.
        if (!_isProxy) {
          MvpSession.rememberPrescriptionSchedules(
            prescriptionId: prescriptionId,
            confirmResponse: response,
            ocrItems: editedItems,
          );
        }
        durResult = registrationDurResult(response['dur_result']);
      } else {
        throw const ApiException('약 등록 결과를 확인하지 못했어요.');
      }
    } catch (error) {
      debugPrint(
        '[PRESCRIPTION_DIAG] confirm failed error_type=${error.runtimeType}',
      );
      if (!mounted) return;
      showSeniorSnackbar(context, '약 등록에 실패했어요. 잠시 후 다시 시도해 주세요.', error: true);
      return;
    }

    // ── 대신 넣기는 여기서 끝난다 ──
    // 뒤따르는 새로고침·달력·함께먹기 확인은 모두 **내 약** 화면이다.
    // 보호자 앞에 어르신 약을 펼치지 않고, 무엇이 어디로 갔는지만 알린다.
    if (_isProxy) {
      if (!mounted) return;
      final onCompleted = widget.onCompleted;
      if (onCompleted != null) {
        onCompleted(durResult);
        return;
      }
      // 스낵바는 앱 전체 메신저에 붙으므로 이 화면을 닫아도 남는다.
      showSeniorSnackbar(context, '${widget.proxyTarget!.title} 전화기로 보냈어요');
      Navigator.of(context).pop(true);
      return;
    }

    // 내가 넣은 약이다. 다음에 홈을 열 때 "가족이 넣어드렸어요"가 뜨면 안 된다.
    unawaited(
      FamilyMedicineInbox.markSeen(
        userId,
        confirmItems.map((item) => item['medicine_code']?.toString() ?? ''),
      ),
    );

    MvpSession.latestOcrItems = editedItems;
    MvpSession.latestOcrRegisteredAt = DateTime.now();
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
    if (ref.read(userMedicinesProvider).hasError) {
      refreshFailed = true;
    }
    if (!mounted) return;
    if (refreshFailed) {
      showSeniorSnackbar(context, '약은 등록됐어요. 목록은 잠시 후 홈에서 다시 불러 주세요.');
    }

    void openScheduleDays() {
      final onOpenScheduleDays = widget.onOpenScheduleDays;
      if (onOpenScheduleDays != null) {
        onOpenScheduleDays();
        return;
      }
      context.push('/schedule-days', extra: MvpSession.latestPrescriptionId);
    }

    if (registrationDurComplete(durResult) && !_hasPairConflict(durResult)) {
      openScheduleDays();
      return;
    }

    final onCompleted = widget.onCompleted;
    if (onCompleted != null) {
      onCompleted(durResult);
      return;
    }
    context.push(
      '/dur-analysis',
      extra: {...durResult, 'open_schedule_days': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case PrescriptionStep.pickMethod:
        return AddMedicineScreen(
          guardianTitle: resolveGuardianTitle(context, widget.guardianTitle),
          onGoHome: widget.onGoHome ?? () => Navigator.of(context).maybePop(),
          onPick: (method) {
            switch (method) {
              case AddMedicineMethod.camera:
                setState(() {
                  _image = null;
                  _step = PrescriptionStep.capture;
                });
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
          proxyTarget: widget.proxyTarget,
          onBack: () => setState(
            () => _step = _isProxy
                ? PrescriptionStep.capture
                : PrescriptionStep.pickMethod,
          ),
          onSaved: (result) {
            final onCompleted = widget.onCompleted;
            if (onCompleted != null) {
              onCompleted(result);
              return;
            }
            if (!registrationDurComplete(result) || _hasPairConflict(result)) {
              context.push(
                '/dur-analysis',
                extra: {...result, 'open_schedule_days': true},
              );
              return;
            }
            final onOpenScheduleDays = widget.onOpenScheduleDays;
            if (onOpenScheduleDays != null) {
              onOpenScheduleDays();
              return;
            }
            context.push(
              '/schedule-days',
              extra: MvpSession.latestPrescriptionId,
            );
          },
        );
      case PrescriptionStep.capture:
        return _CaptureScreen(
          image: _image,
          proxyTitle: widget.proxyTarget?.title,
          onBack: () {
            // 대신 찍기는 어느 분인지 고르고 들어온다. 돌아갈 방법 고르기가
            // 없으므로 흐름에서 나간다.
            if (_isProxy) {
              if (_image != null) {
                setState(() => _image = null);
                return;
              }
              Navigator.of(context).maybePop();
              return;
            }
            setState(() {
              _image = null;
              _step = PrescriptionStep.pickMethod;
            });
          },
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
          proxyTitle: widget.proxyTarget?.title,
          onRetake: () => setState(() {
            _image = null;
            _step = _isProxy
                ? PrescriptionStep.capture
                : PrescriptionStep.pickMethod;
          }),
        );
      case PrescriptionStep.failed:
        return _FailedScreen(
          failureCount: _failureCount,
          failureReason: _failureReason,
          onRetry: () => setState(() {
            _image = null;
            _failureReason = '';
            _step = _isProxy
                ? PrescriptionStep.capture
                : PrescriptionStep.pickMethod;
          }),
          // 대신 찍는 중이라면 가족이 이미 찍고 있다. 다시 부탁할 곳이 없다.
          onAskFamily: _isProxy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FirstRunScreen(),
                  ),
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

  /// 대신 넣어드리는 중이면 "어머니 · 김복자". 맨 위에 띠로 붙는다.
  final String? proxyTitle;

  final VoidCallback onBack;
  final VoidCallback onUse;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  /// 대신 찍기에서는 손으로 적는 길을 내지 않는다 — 처방전 사진 없이
  /// 남의 약을 적어 넣는 길은 열지 않는다.
  final VoidCallback? onManual;

  const _CaptureScreen({
    required this.image,
    this.proxyTitle,
    required this.onBack,
    required this.onUse,
    required this.onCamera,
    required this.onGallery,
    this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cameraBg,
      body: Column(
        children: [
          SeniorBackHeader(title: '처방전 찍기', onDark: true, onBack: onBack),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        if (proxyTitle case final String title)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                            child: ProxyBanner(title: title),
                          ),
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
                                    '이렇게 찍어 주세요',
                                    style: AppText.emphasis(
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _CaptureTip(
                                    number: '1',
                                    text: '밝은 곳에 처방전이\n잘 보이게 펼쳐 놓으세요',
                                  ),
                                  const _CaptureTipArrow(),
                                  _CaptureTip(
                                    number: '2',
                                    text: '종이 네 모서리가\n사진에 다 나오게 하세요',
                                  ),
                                  const _CaptureTipArrow(),
                                  _CaptureTip(
                                    number: '3',
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
                                icon: TablerIcons.camera,
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
                              if (onManual != null)
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
  final String text;

  const _CaptureTip({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.point,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AppText.button(size: 22, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
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
    // 번호 아래가 아니라 글줄 사이에 둔다 — 1번 다음에 2번이라는 뜻이지,
    // 번호 동그라미에 딸린 표시가 아니다.
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: Center(
          child: Icon(
            TablerIcons.arrow_narrow_down,
            size: 48,
            color: AppColors.onDarkMuted,
          ),
        ),
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

  /// 보호자가 어르신 대신 넣는 중이면 그 어르신 이름 — "어머니 · 김복자".
  /// null이면 내 약을 내가 넣는 평소 흐름이다.
  final String? proxyTitle;

  const _ConfirmScreen({
    required this.items,
    required this.unrecognizedNames,
    required this.onRegister,
    required this.onRetake,
    this.proxyTitle,
  });

  @override
  State<_ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<_ConfirmScreen> {
  late final List<Map<String, dynamic>> _editedItems = [
    for (final item in widget.items) Map<String, dynamic>.from(item),
  ];
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    // 빠뜨린 약이 있다는 사실은 목록을 훑기 전에 먼저 말한다.
    // 조용히 빼 두면 그 약을 등록했다고 믿고 안 드신다.
    if (widget.unrecognizedNames.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tellUnread());
    }
  }

  Future<void> _tellUnread() async {
    final retake = await showUnreadNamesSheet(
      context,
      names: widget.unrecognizedNames,
    );
    if (retake && mounted) widget.onRetake();
  }

  static String _frequencyLabel(Map<String, dynamic> item) {
    final value = item['frequency_per_day'];
    return value is num && value > 0 ? '${value.toInt()}회' : '확인 필요';
  }

  static String _durationLabel(Map<String, dynamic> item) {
    final value = item['duration_days'];
    return value is num && value > 0 ? '${value.toInt()}일' : '확인 필요';
  }

  static String _takeAmountLabel(Map<String, dynamic> item) {
    final canonicalAmount = item['dose_amount']?.toString().trim() ?? '';
    final canonicalUnit = item['dose_unit']?.toString().trim() ?? '';
    final raw = canonicalAmount.isNotEmpty
        ? canonicalAmount
        : item['dosage']?.toString().trim() ?? '';
    final unit = canonicalUnit.isNotEmpty
        ? canonicalUnit
        : item['unit']?.toString().trim() ?? '';
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
      final normalized = half.group(1) == '알' ? '정' : half.group(1)!;
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
    if (number == null) return '';
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
      'T' || 'TAB' || '정' || '알' => '정',
      'C' || 'CAP' || '캡슐' => '캡슐',
      'PKG' || '포' => '포',
      'EA' || '개' => '개',
      'ML' || '밀리리터' => 'mL',
      '방울' => '방울',
      _ => '',
    };
    return normalizedUnit.isEmpty
        ? '$amount · 단위 확인 필요'
        : '$amount$normalizedUnit';
  }

  static String _shortDrugName(String name) {
    return stripExportAlias(name);
  }

  /// "혈당을 낮춰 주는 약이에요." 없으면 null.
  static String? _seniorExplanation(Map<String, dynamic> item) {
    final raw =
        item['short_explanation']?.toString().trim() ??
        item['easy_explanation']?.toString().trim() ??
        item['easy_category']?.toString().trim() ??
        '';
    if (raw.isEmpty || raw == '처방받은 약이에요') return null;
    return raw;
  }

  /// "주성분: 메트포르민염산염 · 500mg". 못 읽었으면 빈 문자열.
  static String _ingredientLine(Map<String, dynamic> item) {
    final ingredient =
        item['ingredient_name']?.toString() ??
        item['ingredient']?.toString() ??
        '';
    if (ingredient.trim().isEmpty) return '';
    final parts = [
      compactIngredientSummary(ingredient),
      item['ingredient_strength']?.toString() ?? '',
    ].where((value) => value.trim().isNotEmpty);
    return '주성분: ${parts.join(' · ')}';
  }

  static bool _uncertain(Map<String, dynamic> item) {
    if (item['uncertain'] == true) return true;
    if (item['match_status']?.toString() == 'UNMATCHED') return true;
    final confidence = item['confidence'];
    return confidence is num && confidence < 0.7;
  }

  static List<Map<String, String>> _interactionConflicts(
    Map<String, dynamic> item,
  ) {
    final raw = item['interaction_conflicts'];
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map)
          {
            'other_name': _shortDrugName(row['other_name']?.toString() ?? ''),
            'reason': row['reason']?.toString() ?? '',
          },
    ].where((row) => row['other_name']!.isNotEmpty).toList();
  }

  /// 복용 정보 고치기 — 자판 대신 ±로 올리고 내린다.
  ///
  /// 숫자 입력은 어르신에게 오타가 가장 잦은 자리이고, 오타 하나가 곧
  /// 잘못된 복약 알림이 된다.
  Future<void> _editItem(int index) async {
    final item = _editedItems[index];
    final unit = _editableDoseUnit(
          item['dose_unit']?.toString() ?? item['unit']?.toString() ?? '',
        ) ??
        '정';

    var amount = _startingAmount(item);
    var frequency = _startingCount(item['frequency_per_day'], fallback: 1);
    var days = _startingCount(item['duration_days'], fallback: 7);

    final saved = await SeniorSheet.show<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SeniorSheet(
          title: '복용 정보 고치기',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _shortDrugName(item['drug_name']?.toString() ?? '약'),
                style: AppText.cardTitle(size: 21, color: AppColors.point),
              ),
              const SizedBox(height: 18),
              SeniorStepper(
                label: '한 번에 몇 알',
                number: _amountText(amount),
                unit: unit,
                onMinus: amount <= 0.5
                    ? null
                    : () => setSheetState(() => amount -= 0.5),
                onPlus: amount >= 10
                    ? null
                    : () => setSheetState(() => amount += 0.5),
                onNumberChanged: (text) {
                  final typed = double.tryParse(text);
                  if (typed == null || typed <= 0 || typed > 10) return;
                  setSheetState(() => amount = typed);
                },
              ),
              const SizedBox(height: 18),
              SeniorStepper(
                label: '하루 몇 번',
                number: '$frequency',
                unit: '번',
                onMinus: frequency <= 1
                    ? null
                    : () => setSheetState(() => frequency -= 1),
                onPlus: frequency >= 6
                    ? null
                    : () => setSheetState(() => frequency += 1),
                onNumberChanged: (text) {
                  final typed = int.tryParse(text);
                  if (typed == null || typed < 1 || typed > 6) return;
                  setSheetState(() => frequency = typed);
                },
              ),
              const SizedBox(height: 18),
              SeniorStepper(
                label: '며칠분',
                number: '$days',
                unit: '일',
                onMinus: days <= 1 ? null : () => setSheetState(() => days -= 1),
                onPlus: days >= 365
                    ? null
                    : () => setSheetState(() => days += 1),
                onNumberChanged: (text) {
                  final typed = int.tryParse(text);
                  if (typed == null || typed < 1 || typed > 365) return;
                  setSheetState(() => days = typed);
                },
              ),
            ],
          ),
          actions: [
            SeniorButton(
              label: '이 정보로 하기',
              minHeight: 70,
              fontSize: 23,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    setState(() {
      _editedItems[index] = {
        ...item,
        'dose_amount': _amountText(amount),
        'dose_unit': unit,
        'dosage': '${_amountText(amount)}$unit',
        'unit': unit,
        'times_per_take': null,
        'frequency_per_day': frequency,
        'duration_days': days,
      };
    });
  }

  /// "1" 또는 "0.5". 뒤에 붙는 0은 떼어 둔다.
  static String _amountText(double amount) =>
      amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(1);

  /// 읽어 둔 1회 투약량. 못 읽었으면 1알에서 시작한다.
  static double _startingAmount(Map<String, dynamic> item) {
    for (final raw in [item['dose_amount'], item['dosage']]) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
      final value = double.tryParse(match?.group(0) ?? '');
      if (value != null && value > 0) return value;
    }
    return 1;
  }

  static int _startingCount(dynamic raw, {required int fallback}) {
    final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return value != null && value > 0 ? value : fallback;
  }

  static String? _editableDoseUnit(String raw) {
    return switch (raw.trim().toUpperCase()) {
      'T' || 'TAB' || '정' || '알' => '정',
      'C' || 'CAP' || '캡슐' => '캡슐',
      'PKG' || '포' => '포',
      'ML' || '밀리리터' => 'mL',
      '방울' => '방울',
      'EA' || '개' => '개',
      _ => null,
    };
  }

  Future<void> _fixMedicineName(int index) async {
    final item = _editedItems[index];
    final current =
        item['ocr_drug_name_raw']?.toString().trim().isNotEmpty == true
        ? item['ocr_drug_name_raw'].toString()
        : item['drug_name']?.toString() ?? '';
    final officialName =
        item['official_product_name']?.toString().trim() ??
        item['drug_name']?.toString().trim() ??
        '';
    final medicineCode = item['medicine_code']?.toString().trim() ?? '';
    final query = await showFixNameSheet(
      context,
      current: current,
      provenance: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (current.trim().isNotEmpty) ...[
            _DetailLine(label: '사진에서 읽은 이름', value: current),
            const SizedBox(height: 10),
          ],
          if (officialName.isNotEmpty) ...[
            _DetailLine(label: '공식 제품명', value: officialName),
            const SizedBox(height: 10),
          ],
          if (medicineCode.isNotEmpty)
            _DetailLine(label: '공식 의약품 코드', value: medicineCode),
        ],
      ),
    );
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
        showSeniorSnackbar(context, '공식 의약품 목록에서 해당 이름을 찾지 못했어요.', error: true);
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
      });
    } catch (_) {
      if (!mounted) return;
      showSeniorSnackbar(
        context,
        '공식 약을 찾지 못했어요. 잠시 후 다시 시도해 주세요.',
        error: true,
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
    if (!await _confirmPartialRegistration()) return;
    setState(() => _registering = true);
    try {
      await widget.onRegister(_editedItems);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
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
                  if (widget.proxyTitle case final String title) ...[
                    ProxyBanner(title: title),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pointTint,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.point, width: 2),
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
                          _editedItems.isEmpty
                              ? '글자는 읽었는데, 공식 약과 아직 못 맞췄어요'
                              : '틀린 곳이 있으면 눌러서 고쳐주세요.',
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
                        // 대신 등록도 같은 카드를 쓴다. 보호자가 보는
                        // 내용과 어르신이 보는 내용이 달라지면 안 된다.
                        return _DrugCard(
                          name: _shortDrugName(
                            item['drug_name']?.toString() ?? '이름을 못 읽었어요',
                          ),
                          ingredientLine: _ingredientLine(item),
                          explanation: _seniorExplanation(item),
                          doseAmount: _takeAmountLabel(item),
                          frequencyPerDay: _frequencyLabel(item),
                          durationDays: _durationLabel(item),
                          uncertain: _uncertain(item),
                          conflicts: _interactionConflicts(item),
                          onFixName: () => _fixMedicineName(index),
                          onEditDosing: () => _editItem(index),
                        );
                      },
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
                      label: widget.proxyTitle == null
                          ? (_registering ? '등록하고 있어요' : '이대로 등록하기')
                          : (_registering ? '보내고 있어요' : '어르신께 보내기'),
                      minHeight: 70,
                      onPressed: _registering ? null : _tryRegister,
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

  /// "주성분: 메트포르민염산염 · 500mg". 빈 문자열이면 그리지 않는다.
  final String ingredientLine;

  /// "혈당을 낮춰 주는 약이에요."
  final String? explanation;

  /// "1정" · "2회" · "30일". 못 읽었으면 "확인 필요".
  final String doseAmount;
  final String frequencyPerDay;
  final String durationDays;

  /// 사진이 흐려 읽은 이름이 미덥지 않을 때.
  final bool uncertain;

  /// 이미 드시는 약과 함께 먹으면 주의가 필요한 경우.
  final List<Map<String, String>> conflicts;

  /// 사진에서 읽은 이름이 미덥지 않을 때만 내미는 길.
  final VoidCallback onFixName;

  final VoidCallback onEditDosing;

  const _DrugCard({
    required this.name,
    this.ingredientLine = '',
    this.explanation,
    required this.doseAmount,
    required this.frequencyPerDay,
    required this.durationDays,
    required this.uncertain,
    this.conflicts = const [],
    required this.onFixName,
    required this.onEditDosing,
  });

  @override
  Widget build(BuildContext context) {
    final flagged = uncertain || conflicts.isNotEmpty;
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      borderColor: flagged ? AppColors.dangerBorder : null,
      borderWidth: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (uncertain) ...[
            Text(
              '글씨가 흐려서 확실하지 않아요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
            const SizedBox(height: 6),
          ],
          Text(name, style: AppText.cardTitle(size: 22)),
          if (ingredientLine.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              ingredientLine,
              style: AppText.caption(size: 17, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (explanation case final String easy when easy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              easy,
              style: AppText.body(
                size: 19,
                color: AppColors.textPrimary,
                weight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _DoseInfoRow(
            label: '1회 투약량',
            value: doseAmount.isEmpty ? '확인 필요' : doseAmount,
            needsConfirmation:
                doseAmount.isEmpty || doseAmount.contains('확인 필요'),
          ),
          const SizedBox(height: 7),
          _DoseInfoRow(
            label: '1일 투여횟수',
            value: frequencyPerDay,
            needsConfirmation: frequencyPerDay == '확인 필요',
          ),
          const SizedBox(height: 7),
          _DoseInfoRow(
            label: '투약일수',
            value: durationDays,
            needsConfirmation: durationDays == '확인 필요',
          ),
          const SizedBox(height: 10),
          // 붉게 쓰지 않는다. 늘 붙어 있는 붉은 글씨는 배경이 되어
          // 진짜 경고를 묻는다.
          Text(
            '처방전과 같은 약이 맞는지 한 번 더 확인해 주세요',
            style: AppText.label(size: 17.5, color: AppColors.textPrimary),
          ),
          for (final conflict in conflicts) ...[
            const SizedBox(height: 8),
            Text(
              '${conflict['other_name']}과 함께 먹으면 주의가 필요해요',
              style: AppText.label(size: 17.5, color: AppColors.danger),
            ),
            if ((conflict['reason'] ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                conflict['reason']!,
                style: AppText.body(size: 17, color: AppColors.danger),
              ),
            ],
          ],
          const SizedBox(height: 14),
          if (uncertain) ...[
            SeniorButton(
              label: '약 이름 고치기',
              kind: SeniorButtonKind.secondary,
              minHeight: 62,
              fontSize: 21,
              onPressed: onFixName,
            ),
            const SizedBox(height: 10),
          ],
          SeniorButton(
            label: '복용 정보 고치기',
            kind: SeniorButtonKind.secondary,
            minHeight: 62,
            fontSize: 21,
            onPressed: onEditDosing,
          ),
        ],
      ),
    );
  }
}

/// "1회 투약량        1정" 한 줄. 못 읽은 칸은 붉게 "확인 필요".
class _DoseInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool needsConfirmation;

  const _DoseInfoRow({
    required this.label,
    required this.value,
    this.needsConfirmation = false,
  });

  @override
  Widget build(BuildContext context) {
    return LabelValueRow(
      label: Text(
        label,
        style: AppText.label(size: 18, color: AppColors.textSecondary),
      ),
      value: Text(
        value,
        textAlign: TextAlign.right,
        style: AppText.cardTitle(
          size: 19,
          color: needsConfirmation ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
    );
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
          style: AppText.label(size: 17, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(value, style: AppText.body(size: 19)),
      ],
    );
  }
}

/// 읽지 못했을 때 — 5e 회복 패턴. 3번 실패하면 가족 대행을 권한다.
class _FailedScreen extends StatelessWidget {
  final int failureCount;
  final String failureReason;
  final VoidCallback onRetry;

  /// 대신 찍는 중이면 null — 가족이 이미 찍고 있으니 부탁할 곳이 없다.
  final VoidCallback? onAskFamily;

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
              helperText: tooManyTries && onAskFamily != null
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
