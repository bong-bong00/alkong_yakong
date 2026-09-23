import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../auth/presentation/screens/login_screen.dart'
    show PhoneNumberFormatter;
import '../../../profile/application/current_user_controller.dart';
import '../../application/guardians_provider.dart';
import '../../data/proxy_signup_repository.dart';
import '../../domain/proxy_signup.dart';

/// 가족이 대신 회원가입 — 1/3 어르신 정보 · 2/3 확인번호 · 3/3 다 됐어요.
///
/// **자녀분 전화기에서 돌아가는 화면이다.** 어르신은 문자로 온 숫자 6자리만
/// 불러주면 된다 — 어르신이 혼자 가입에서 막히는 것이 첫 이탈 지점이라
/// 가입하는 일 자체를 자녀분 쪽으로 옮긴다.
class ProxySignupScreen extends ConsumerStatefulWidget {
  /// 계정을 다 만든 뒤 "처방전 대신 찍어드리기"를 눌렀을 때.
  final ValueChanged<ProxySignupResult>? onCapturePrescription;

  /// 요청을 보낼 곳. 없으면 이 화면이 하나 만들어 쓴다.
  final ProxySignupRepository? repository;

  const ProxySignupScreen({
    super.key,
    this.onCapturePrescription,
    this.repository,
  });

  @override
  ConsumerState<ProxySignupScreen> createState() => _ProxySignupScreenState();
}

class _ProxySignupScreenState extends ConsumerState<ProxySignupScreen> {
  late final ProxySignupRepository _repository =
      widget.repository ?? ProxySignupRepository();

  /// 0 · 어르신 정보 / 1 · 확인번호 / 2 · 다 됐어요.
  int _step = 0;

  /// 아래 버튼 영역. 스낵바를 이 높이만큼 올려 버튼을 가리지 않는다.
  final _actionsKey = GlobalKey();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _otherRelation = TextEditingController();
  final _code = TextEditingController();

  static const List<String> _relations = ['어머니', '아버지', '그 밖'];

  /// 확인번호를 받은 뒤 자녀분이 할 일. **셋을 넘기지 않는다.**
  static const List<String> _codeSteps = [
    '어르신께 전화를 걸어 주세요.',
    '문자에 온 숫자 6자리를 불러달라고 하세요.',
    '아래에 그 숫자를 적으세요.',
  ];

  String? _relation;

  ProxyVerification? _verification;
  ProxySignupResult? _result;
  bool _sending = false;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _otherRelation.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _isOtherRelation => _relation == '그 밖';

  String get _resolvedRelation =>
      _isOtherRelation ? _otherRelation.text.trim() : (_relation ?? '');

  ProxyElderDraft get _draft => ProxyElderDraft(
    name: _name.text.trim(),
    phone: _phone.text.trim(),
    relation: _resolvedRelation,
  );

  /// 아래 버튼을 가리지 않도록 그 높이만큼 올려 띄운다.
  void _say(String message, {bool error = false}) => showSeniorSnackbar(
    context,
    message,
    error: error,
    bottom: _actionsKey.currentContext?.size?.height ?? 0,
  );

  void _error(String message) => _say(message, error: true);

  /// 1/3 — 확인번호를 어르신 전화기로 보낸다.
  Future<void> _sendCode({bool again = false}) async {
    final draft = _draft;
    if (draft.name.isEmpty) {
      _error('어르신 성함을 적어주세요');
      return;
    }
    if (draft.phoneDigits.length < 10) {
      _error('어르신 전화번호를 적어주세요');
      return;
    }
    if (draft.relation.isEmpty) {
      _error('나와의 관계를 골라주세요');
      return;
    }
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final verification = await _repository.sendCode(draft);
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _code.clear();
        _step = 1;
      });
      // 문자 창구가 없는 동안 번호는 2/3 화면 안에 적어 둔다 — 아래 [_codeStep].
      // 스낵바로 띄우면 4초 동안 아래 버튼을 덮어 다음으로 못 넘어간다.
      if (again && !ProxySignupRepository.showsCodeOnDevice) {
        _say('확인번호를 다시 보냈어요');
      }
    } on ApiException catch (error) {
      if (mounted) _error(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 2/3 — 번호를 맞춰 보고 계정을 만든다.
  Future<void> _createAccount() async {
    final verification = _verification;
    if (verification == null) {
      _error('확인번호를 먼저 보내주세요');
      return;
    }
    if (verification.isExpired) {
      _error('확인번호가 지났어요. 다시 보내주세요');
      return;
    }
    if (!verification.matches(_code.text)) {
      _error('확인번호가 맞지 않아요. 다시 확인해 주세요');
      return;
    }
    if (_creating) return;

    setState(() => _creating = true);
    try {
      // 어르신에게 붙일 보호자는 지금 로그인한 자녀분이다.
      // 아직 안 읽혔으면 여기서 기다린다 — 누구를 붙일지 모른 채
      // 어르신 계정만 덩그러니 만들지 않는다.
      final guardian = await ref.read(currentUserProvider.future);
      if (guardian == null) {
        if (mounted) _error('내 정보를 아직 못 읽었어요. 잠시 후 다시 해주세요');
        return;
      }
      final result = await _repository.createAccount(
        draft: _draft,
        verification: verification,
        guardian: guardian,
      );
      if (!mounted) return;
      // 돌보는 분 목록이 새 어르신을 바로 보게 한다.
      ref.invalidate(careOverviewProvider);
      setState(() {
        _result = result;
        _step = 2;
      });
      if (!result.guardianLinked) {
        _error('계정은 만들어졌어요. 보호자 연결만 다시 해주세요');
      }
    } on ApiException catch (error) {
      if (mounted) _error(error.message);
    } catch (_) {
      if (mounted) _error('계정을 만들지 못했어요. 잠시 후 다시 해주세요');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _back() {
    // 계정을 만든 뒤에는 되돌아갈 곳이 없다. 흐름에서 나간다.
    if (_step == 0 || _step == 2) {
      Navigator.of(context).maybePop(_result);
      return;
    }
    setState(() => _step = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _ProxyStepHeader(
            step: _step + 1,
            total: 3,
            title: switch (_step) {
              0 => '어르신 정보 적기',
              1 => '확인번호 넣기',
              _ => '다 됐어요',
            },
            onBack: _back,
          ),
          Expanded(
            child: switch (_step) {
              0 => _elderInfoStep(),
              1 => _codeStep(),
              _ => _doneStep(),
            },
          ),
        ],
      ),
    );
  }

  // ── 1 / 3 ─────────────────────────────────────────────────────
  Widget _elderInfoStep() {
    return _StepBody(
      actionsKey: _actionsKey,
      content: [
        const _NoticeCard(
          title: '자녀분 전화기에서 적습니다',
          body: '어르신은 나중에 숫자 6자리만 불러주시면 됩니다.',
        ),
        const SizedBox(height: 14),
        SeniorCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SeniorField(
                label: '어르신 성함',
                controller: _name,
                hint: '예: 김복자',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              SeniorField(
                label: '어르신 전화번호',
                controller: _phone,
                hint: '010-0000-0000',
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneNumberFormatter()],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              Text('나와의 관계', style: AppText.label(size: 18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final relation in _relations) ...[
                    if (relation != _relations.first) const SizedBox(width: 10),
                    Expanded(
                      child: _RelationChoice(
                        label: relation,
                        selected: _relation == relation,
                        onTap: () => setState(() => _relation = relation),
                      ),
                    ),
                  ],
                ],
              ),
              if (_isOtherRelation) ...[
                const SizedBox(height: 12),
                SeniorField(
                  controller: _otherRelation,
                  hint: '어떻게 부르시나요? 예: 장모님',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ],
      actions: [
        SeniorButton(
          label: _sending ? '보내는 중...' : '어르신 전화기로 확인번호 보내기',
          minHeight: 74,
          fontSize: 23,
          onPressed: _sending ? null : _sendCode,
        ),
      ],
    );
  }

  // ── 2 / 3 ─────────────────────────────────────────────────────
  Widget _codeStep() {
    return _StepBody(
      actionsKey: _actionsKey,
      content: [
        SeniorCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '어르신 전화기에 숫자 6자리를 보냈어요',
                style: AppText.cardTitle(size: 22),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < _codeSteps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${i + 1}. ${_codeSteps[i]}',
                    style: AppText.body(size: 19),
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
              Text('확인번호', style: AppText.label(size: 18)),
              const SizedBox(height: 8),
              _CodeField(controller: _code, onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              Text(
                '3분 안에 적어야 해요. 못 받으셨으면 다시 보낼 수 있어요.',
                style: AppText.caption(size: 17.5),
              ),
              // 문자 창구가 붙기 전까지만 보이는 줄.
              // ProxySignupRepository.showsCodeOnDevice 주석 참고.
              if (ProxySignupRepository.showsCodeOnDevice &&
                  _verification != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBgSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '문자 보내기는 아직 연결 중이에요.\n'
                    '확인번호: ${_verification!.code}',
                    style: AppText.label(size: 18, color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      actions: [
        SeniorButton(
          label: _creating ? '계정을 만드는 중...' : '확인하고 계정 만들기',
          minHeight: 74,
          fontSize: 23,
          onPressed: _creating ? null : _createAccount,
        ),
        const SizedBox(height: 12),
        SeniorButton(
          label: '확인번호 다시 보내기',
          kind: SeniorButtonKind.secondary,
          minHeight: 64,
          fontSize: 21,
          onPressed: _sending || _creating
              ? null
              : () => _sendCode(again: true),
        ),
      ],
    );
  }

  // ── 3 / 3 ─────────────────────────────────────────────────────
  Widget _doneStep() {
    final result = _result!;
    final guardianName = ref.watch(currentUserNameProvider);
    final guardianLabel = guardianName.isEmpty ? '보호자' : '$guardianName 님';
    final elderLabel = result.relation.isEmpty ? result.name : result.relation;

    return _StepBody(
      actionsKey: _actionsKey,
      content: [
        SeniorCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.pointTint,
                  shape: BoxShape.circle,
                ),
                child: const ExcludeSemantics(
                  child: Icon(
                    TablerIcons.check,
                    size: 38,
                    color: AppColors.point,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$elderLabel 계정이\n만들어졌어요',
                style: AppText.screenTitle(size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                '어르신 전화기에는 알콩약콩이 바로 열립니다. '
                '비밀번호는 어르신이 나중에 바꿀 수 있어요.',
                style: AppText.body(size: 19),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.pointTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  result.guardianLinked
                      ? '자동으로 $guardianLabel이 보호자로 등록되었습니다. '
                            '이제 $guardianLabel이 어르신의 복약을 함께 볼 수 있습니다.'
                      : '보호자 연결만 아직 안 됐어요. '
                            '돌보는 분 목록에서 어르신 번호로 다시 연결해 주세요.',
                  style: AppText.body(
                    size: 19,
                    color: AppColors.pointInk,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _NoticeCard(
          title: '이제 약만 넣으면 끝나요',
          body: '처방전을 자녀분 전화기로 찍으면, 어르신 전화기에는 알림만 갑니다.',
        ),
      ],
      actions: [
        SeniorButton(
          label: '처방전 대신 찍어드리기',
          icon: TablerIcons.camera,
          minHeight: 74,
          fontSize: 23,
          onPressed: () {
            final onCapture = widget.onCapturePrescription;
            if (onCapture == null) {
              Navigator.of(context).pop(result);
              return;
            }
            onCapture(result);
          },
        ),
        const SizedBox(height: 12),
        SeniorButton(
          label: '나중에 할게요',
          kind: SeniorButtonKind.secondary,
          minHeight: 64,
          fontSize: 21,
          onPressed: () => Navigator.of(context).pop(result),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  화면 조각
// ════════════════════════════════════════════════════════════════

/// "가족이 대신 가입 · 1 / 3" + 화면 제목.
class _ProxyStepHeader extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final VoidCallback onBack;

  const _ProxyStepHeader({
    required this.step,
    required this.total,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SeniorHeader(
      child: Row(
        children: [
          SeniorBackButton(onTap: onBack),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '가족이 대신 회원가입 · $step / $total',
                  style: AppText.label(size: 17),
                ),
                Text(title, style: AppText.screenTitle(size: 28)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 스크롤되는 본문 + 바닥에 붙는 버튼.
class _StepBody extends StatelessWidget {
  final List<Widget> content;
  final List<Widget> actions;

  /// 스낵바를 얼마나 올려야 버튼을 안 가리는지 재는 자리.
  final Key actionsKey;

  const _StepBody({
    required this.content,
    required this.actions,
    required this.actionsKey,
  });

  @override
  Widget build(BuildContext context) {
    // 작은 화면에서 글자를 크게 키우시면 버튼까지 자리가 모자란다.
    // 그럴 때는 버튼을 잘라 내는 대신 함께 스크롤되게 둔다.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: content,
                  ),
                ),
                const Spacer(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Column(
                      key: actionsKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: actions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 제목 한 줄 + 설명 한 줄짜리 흰 카드.
class _NoticeCard extends StatelessWidget {
  final String title;
  final String body;

  const _NoticeCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.cardTitle(size: 22)),
          const SizedBox(height: 6),
          Text(body, style: AppText.body(size: 19)),
        ],
      ),
    );
  }
}

/// 어머니 / 아버지 / 그 밖.
class _RelationChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RelationChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointTint : AppColors.sunken,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.point : AppColors.border,
                width: 2,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 20,
                color: selected ? AppColors.point : AppColors.textBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 숫자 6자리를 넓게 벌려 적는 칸.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _CodeField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.point, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppText.bigTime(size: 34).copyWith(letterSpacing: 10),
          decoration: InputDecoration(
            border: InputBorder.none,
            counterText: '',
            isDense: true,
            hintText: '000000',
            hintStyle: AppText.bigTime(
              size: 34,
              color: AppColors.chevron,
            ).copyWith(letterSpacing: 10),
          ),
        ),
      ),
    );
  }
}
