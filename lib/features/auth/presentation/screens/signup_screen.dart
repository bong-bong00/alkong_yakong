import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/exclusive_choice.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/user_role.dart';
import '../../../../core/session/auth_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../profile/application/session_actions.dart';
import '../../../profile/domain/user_profile.dart';

/// 병력 선택값과 기존 불리언 계약을 함께 보낸다.
Map<String, dynamic> buildIllnessHistoryPayload({
  required Iterable<String> pastIllnesses,
  required Iterable<String> familyIllnesses,
  bool? pastHistory,
  bool? familyHistory,
}) {
  List<String> selected(Iterable<String> values) => [
    for (final value in values)
      if (value.trim().isNotEmpty && value.trim() != '없어요') value.trim(),
  ];

  final past = selected(pastIllnesses);
  final family = selected(familyIllnesses);
  return {
    'past_illnesses': past,
    'family_illnesses': family,
    'past_history': pastHistory ?? past.isNotEmpty,
    'family_history': familyHistory ?? family.isNotEmpty,
  };
}

/// 단계형 회원가입 (위저드).
/// 위치: lib/features/auth/presentation/screens/signup_screen.dart
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  int _step = 0;

  /// 아래 버튼 영역. 오류 스낵바를 이 높이만큼 올려 버튼을 가리지 않는다.
  final _actionsKey = GlobalKey();
  bool _isSubmitting = false;
  final ApiClient _apiClient = ApiClient();

  /// 처음에는 아무것도 고르지 않은 상태다. 기본값이 있으면
  /// 고르지 않고 지나쳐도 환자로 가입된다.
  String _role = 'patient';
  bool _rolePicked = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  DateTime? _birth;
  String? _gender;

  final _height = TextEditingController();
  final _weight = TextEditingController();
  String? _blood;

  bool? _pregnant;
  String? _smoking;
  String? _drinking;

  /// 건강 질문의 답 — 'y' 있어요 · 'n' 없어요 · 'u' 잘 모르겠어요.
  /// "네"라고 하신 질문에만 자세히 고르는 화면이 한 장 더 붙는다.
  String? _allergyAnswer;
  String? _diseaseAnswer;
  String? _pastAnswer;
  String? _familyAnswer;
  String? _guardianAnswer;

  final Set<String> _allergens = {};
  final _allergyOther = TextEditingController();

  final _diseaseOther = TextEditingController();

  /// 과거에 앓았던 병과 부모·형제가 앓은 병.
  /// "없어요"는 다른 것과 함께 고를 수 없다.
  final Set<String> _pastIllnesses = {};
  final Set<String> _familyIllnesses = {};

  // "없어요"는 보기에서 뺀다 — 앞 화면에서 이미 네/아니요로 여쭤봤다.
  static const _pastOptions = ['암', '뇌졸중', '심근경색', '간·콩팥병'];

  static const _familyOptions = ['고혈압', '당뇨', '심장병', '암', '치매', '뇌졸중'];

  final Set<String> _diseases = {};

  // 보호자 연락처. 나중에 등록해도 되므로 건너뛴 사실도 기억한다.
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  String? _guardianRelation;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _agreeAge = false;
  bool _agreeMarketing = false;
  bool get _allRequired => _agreeAge && _agreeTerms && _agreePrivacy;
  bool get _allChecked => _allRequired && _agreeMarketing;

  static const _allergyOptions = [
    '페니실린 (항생제)',
    '아스피린',
    '소염진통제 (이부프로펜 등)',
    '이름을 몰라요',
  ];
  static const _diseaseOptions = ['고혈압', '당뇨', '고지혈증', '심장병', '콩팥병', '간 질환'];

  /// 화면에 적는 말과 저장하는 값이 다르다. 저장값은 "내 정보 고치기"가
  /// 쓰는 이름에 맞춘다 — 두 화면이 다른 말을 쓰면 고칠 때 값이 튄다.
  static const _smokingValues = {
    '네, 피워요': '폈어요',
    '아니요, 안 피워요': '안 폈어요',
    '예전에 끊었어요': '끊었어요',
  };

  @override
  void dispose() {
    _guardianName.dispose();
    _guardianPhone.dispose();
    _name.dispose();
    _phone.dispose();
    _pw.dispose();
    _height.dispose();
    _weight.dispose();
    _allergyOther.dispose();
    _diseaseOther.dispose();
    super.dispose();
  }

  void _toggle(Set<String> set, String o) => setState(() {
    final next = toggleChoice(set, o);
    set
      ..clear()
      ..addAll(next);
  });

  Future<void> _pickBirth() async {
    final picked = await showSeniorDateWheel(
      context: context,
      initialDate: _birth,
    );
    if (picked == null) return;
    setState(() => _birth = picked);
  }

  /// 적지 않고 지나간다. 검사를 거치지 않는 것만 [_next]와 다르다.
  void _skip(List<_StepDef> steps) {
    if (_step >= steps.length - 1) {
      _submit();
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _step++);
  }

  void _next(List<_StepDef> steps) {
    final err = steps[_step].validate();
    if (err != null) {
      _showError(err);
      return;
    }
    if (_step >= steps.length - 1) {
      _submit();
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() => _step++);
    }
  }

  /// "네 / 아니요"를 먼저 묻는 건강 질문 한 걸음.
  /// "네"라고 하시면 자세히 고르는 화면이 뒤에 한 장 붙는다.
  _StepDef _yesNoStep({
    required String title,
    required String subtitle,
    required String? answer,
    required ValueChanged<String> onAnswer,
    String yesLabel = '네, 있어요',
    String noLabel = '아니요, 없어요',
    String? unsureLabel,
  }) {
    return _StepDef(
      title: title,
      subtitle: subtitle,
      validate: () => answer == null ? '해당하는 것을 골라주세요' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _choice(
            yesLabel,
            icon: TablerIcons.check,
            selected: answer == 'y',
            onTap: () => setState(() => onAnswer('y')),
          ),
          const SizedBox(height: 12),
          _choice(
            noLabel,
            icon: TablerIcons.x,
            selected: answer == 'n',
            onTap: () => setState(() => onAnswer('n')),
          ),
          if (unsureLabel != null) ...[
            const SizedBox(height: 12),
            // 모르는 것을 "없어요"로 적어 두면 위험한 약을 못 거른다.
            // 따로 받아 두고, 자세히는 여쭤보지 않는다.
            _choice(
              unsureLabel,
              selected: answer == 'u',
              onTap: () => setState(() => onAnswer('u')),
            ),
          ],
        ],
      ),
    );
  }

  void _prev() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  /// 틀린 곳 한 군데를 스낵바로 알린다. 아래 버튼을 가리지 않도록 그 위에 띄운다.
  void _showError(String message) {
    final actionsHeight = _actionsKey.currentContext?.size?.height ?? 0;
    showSeniorSnackbar(context, message, error: true, bottom: actionsHeight);
  }

  String? _optionalTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 가입 화면에서 받은 것을 빠짐없이 서버로 보낸다.
  /// 건강 질문은 약을 드시는 분에게만 묻는다.
  Map<String, dynamic> _signupBody() {
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'role': _role,
      'phone': _optionalTrimmed(_phone.text),
      'password': _pw.text,
    };
    if (_role != 'patient') return body;
    return body..addAll({
      'birth_date': UserProfile.formatDate(_birth),
      'gender': _gender,
      'height_cm': double.tryParse(_height.text.trim()),
      'weight_kg': double.tryParse(_weight.text.trim()),
      'blood_type': _blood,
      // 네/아니요를 그대로 싣는다. 서버가 "임신 중"으로 풀어 적는다.
      'is_pregnant': _gender == 'F' ? _pregnant : null,
      'smoking': _smoking,
      'drinking': _drinking,
      // "네"라고 하신 질문의 답만 보낸다. 자세히 화면을 안 거친 질문은
      // 골라 둔 것이 남아 있어도 보내지 않는다.
      'allergies': _allergyAnswer == 'y'
          ? _picked(_allergens, _allergyOther, skip: '이름을 몰라요')
          : <String>[],
      'diseases': _diseaseAnswer == 'y'
          ? _picked(_diseases, _diseaseOther)
          : <String>[],
      ...buildIllnessHistoryPayload(
        pastIllnesses: _pastAnswer == 'y' ? _pastIllnesses : const <String>[],
        familyIllnesses: _familyAnswer == 'y'
            ? _familyIllnesses
            : const <String>[],
        pastHistory: _pastAnswer == 'y',
        familyHistory: _familyAnswer == 'y',
      ),
    });
  }

  /// "기타"는 적어 준 글자로 바꾸고, 약·병 이름이 아닌 보기는 뺀다.
  List<String> _picked(
    Set<String> chosen,
    TextEditingController other, {
    String skip = '',
  }) => [
    for (final item in chosen)
      if (item == '기타') other.text.trim() else if (item != skip) item,
  ].where((item) => item.isNotEmpty).toList();

  /// 보호자 초대는 가입 완료 화면을 막지 않는다. 결과는 완료 화면에서 알린다.
  Future<InviteResult>? _saveGuardianContact() {
    final name = _guardianName.text.trim();
    // 화면은 "알려드릴까요?"로 묻는다(이 브랜치). 초대를 보내고 결과를
    // 기다리는 방식은 main 쪽을 쓴다.
    if (_role != 'patient' || _guardianAnswer != 'y' || name.isEmpty) {
      return null;
    }
    return GuardianRepository()
        .invite(
          name: name,
          relation: _guardianRelation ?? '그 외',
          phone: _guardianPhone.text.trim(),
        )
        .then((result) {
          if (mounted) ref.invalidate(guardiansProvider);
          return result;
        });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final timer = Stopwatch()..start();

    try {
      final body = _signupBody();

      final response = await _apiClient.post('/api/v1/users', body: body);
      debugPrint('[SIGNUP_DIAG] team_create_ms=${timer.elapsedMilliseconds}');
      timer.reset();
      final userId = response is Map<String, dynamic>
          ? response['id']?.toString()
          : null;
      if (userId == null || userId.isEmpty) {
        throw const ApiException('회원가입 응답에 사용자 ID가 없습니다.');
      }

      await AuthSession.persistUserId(userId);
      // 가입한 역할대로 로그인 상태를 만든다. 보호자로 가입하면 보호자 화면이 열린다.
      await AuthSession.setLoggedIn(_role);
      debugPrint('[SIGNUP_DIAG] save_session_ms=${timer.elapsedMilliseconds}');
      if (mounted) {
        ref.read(userRoleProvider.notifier).state = _role == 'guardian'
            ? UserRole.guardian
            : UserRole.patient;
        // 방금 만든 계정으로 바뀌었으니 앞사람의 약·가족·기록은 버린다.
        resetUserScopedData(ref);
      }
      if (!mounted) return;
      final guardianInvite = _saveGuardianContact();
      // 가입 완료 화면이 다음 길(약 등록 / 나중에 하기)을 스스로 정한다.
      // 여기서 또 옮기면 방금 연 화면이 곧바로 로그인으로 덮인다.
      await _showSignupComplete(guardianInvite: guardianInvite);
    } catch (error) {
      if (!mounted) return;
      _showError('회원가입에 실패했습니다: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 가입이 끝났다는 사실만 알리고, 다음 한 걸음을 바로 내민다.
  /// 확인만 누르고 사라지는 알림창은 아무것도 이어주지 않는다.
  Future<void> _showSignupComplete({Future<InviteResult>? guardianInvite}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SignupDoneScreen(
          name: _name.text.trim(),
          guardianInvite: guardianInvite,
        ),
      ),
    );
  }

  /// 시안 1c — 건강 질문은 "네 / 아니요"를 먼저 크게 묻고, "네"라고 하신
  /// 질문에만 자세히 고르는 화면이 한 장 더 붙는다. 큰 단계는 13개이고
  /// 임신·수유를 여쭤보지 않는 남성은 12개다.
  ///
  /// 고르는 것과 넘어가는 것은 떼어 둔다 — 답을 고른 뒤 "다음"을 눌러야
  /// 넘어간다. 잘못 눌렀을 때 그 자리에서 고쳐 누를 수 있어야 한다.
  List<_StepDef> _buildSteps() {
    final steps = <_StepDef>[];
    var no = 0;
    void big(_StepDef step) => steps.add(step..stepNo = ++no);
    // 자세히 화면은 앞 단계의 번호를 그대로 쓴다. 한 가지를 여쭤보는
    // 중이므로 걸음이 늘어난 것처럼 보이면 안 된다.
    void detail(_StepDef step) => steps.add(step..stepNo = no);

    big(
      _StepDef(
        title: '어떤 분이신가요?',
        subtitle: '고르시면 여쭤보는 것이 달라져요.',
        validate: () => _rolePicked ? null : '어떤 분이신지 골라주세요',
        // 둘을 나란히 두면 칸이 좁아 설명이 두세 줄로 접힌다.
        // 위아래로 쌓아 한 줄씩 읽게 둔다.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _roleCard('patient', '약을 드시는 분', '내 약을 넣고 알림을 받아요'),
            const SizedBox(height: 12),
            _roleCard('guardian', '돌보는 가족', '부모님 복약을 함께 봐요'),
          ],
        ),
      ),
    );
    big(
      _StepDef(
        title: '기본 정보를\n알려주세요',
        subtitle: '번호는 로그인과 약 알림에 써요.',
        validate: () {
          if (_name.text.trim().isEmpty) return '이름을 입력해주세요';
          if (_phone.text.trim().isEmpty) return '휴대폰 번호를 입력해주세요';
          if (_pw.text.isEmpty) return '비밀번호를 입력해주세요';
          if (_pw.text.length < 6) return '비밀번호는 6자 이상이어야 해요';
          return null;
        },
        child: Column(
          children: [
            _field(_name, label: '이름', hint: '성함'),
            const SizedBox(height: 12),
            // 인증 버튼은 두지 않는다. 여기서 문자를 기다리게 하면
            // 가입이 끊긴다 — 번호 확인은 첫 알림이 도착하는 것으로 갈음한다.
            _field(
              _phone,
              label: '휴대폰 번호',
              hint: '010-0000-0000',
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _field(
              _pw,
              label: '비밀번호 (6자 이상)',
              hint: '비밀번호',
              obscure: _obscure,
              // 눈 모양 아이콘은 학습이 안 된다. 한글 라벨로 둔다.
              suffix: SeniorTextButton(
                label: _obscure ? '보기' : '숨기기',
                color: AppColors.point,
                expand: false,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ],
        ),
      ),
    );

    // 환자만 건강정보 단계를 받는다 (보호자는 환자 모니터링 전용이라 불필요)
    if (_role == 'patient') {
      big(
        _StepDef(
          title: '생년월일과 성별을\n알려주세요',
          subtitle: '나이에 따라 조심할 약이 달라요.',
          validate: () {
            if (_birth == null) return '생년월일을 골라주세요';
            if (_gender == null) return '성별을 골라주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: _birth == null
                    ? '생년월일 고르기'
                    : '생년월일 ${_birth!.year}년 ${_birth!.month}월 '
                          '${_birth!.day}일, 바꾸기',
                child: GestureDetector(
                  onTap: _pickBirth,
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 66),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: kCardShadow,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _birth == null
                                  ? '생년월일'
                                  : '${_birth!.year}년 ${_birth!.month}월 '
                                        '${_birth!.day}일',
                              style: AppText.label(
                                size: 22,
                                color: _birth == null
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            TablerIcons.calendar_month,
                            size: 24,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _pill(
                        '여자',
                        _gender == 'F',
                        () => setState(() => _gender = 'F'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _pill(
                        '남자',
                        _gender == 'M',
                        () => setState(() => _gender = 'M'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      big(
        _StepDef(
          title: '키와 몸무게,\n혈액형을 알려주세요',
          // 이 세 가지는 내 정보와 가족 화면에 보여 줄 뿐, 약 양을 정하지
          // 않는다. 하지 않는 일을 적어 두면 그것대로 믿게 된다.
          subtitle: '지금 안 적으셔도 넘어갑니다.',
          // "저장 후 다음"은 적은 것을 저장하겠다는 뜻이다. 하나도 안 적었으면
          // 적어 달라고 말한다. 적지 않고 지나가려면 "넘어가기"가 있다.
          validate: () =>
              _height.text.trim().isEmpty &&
                  _weight.text.trim().isEmpty &&
                  _blood == null
              ? '내용을 채워주세요. 지금 적고 싶지 않으시면 넘어가기를 눌러주세요'
              : null,
          // 넘어가면 적던 값은 비우고 지나간다.
          onSkip: () => setState(() {
            _height.clear();
            _weight.clear();
            _blood = null;
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 두 칸을 나란히 두되 각자 최소 높이를 지킨다.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _field(
                        _height,
                        label: '키',
                        hint: '키',
                        keyboard: TextInputType.number,
                        suffixText: 'cm',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _weight,
                        label: '몸무게',
                        hint: '몸무게',
                        keyboard: TextInputType.number,
                        suffixText: 'kg',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _sectionLabel('혈액형'),
              _grid(
                const ['A형', 'B형', 'O형', 'AB형', '몰라요'],
                _blood,
                (v) => setState(() => _blood = v),
              ),
            ],
          ),
        ),
      );

      // 임신·수유 여부는 병용금기 판정을 통째로 바꾼다. 건너뛰지 않는다.
      if (_gender == 'F') {
        big(
          _StepDef(
            title: '지금 임신 중이거나\n젖을 먹이고 계신가요?',
            subtitle: '이때는 피해야 하는 약이 있어요.',
            validate: () => _pregnant == null ? '해당하는 것을 골라주세요' : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _choice(
                  '네',
                  icon: TablerIcons.check,
                  selected: _pregnant == true,
                  onTap: () => setState(() => _pregnant = true),
                ),
                const SizedBox(height: 12),
                _choice(
                  '아니요',
                  icon: TablerIcons.x,
                  selected: _pregnant == false,
                  onTap: () => setState(() => _pregnant = false),
                ),
              ],
            ),
          ),
        );
      }

      big(
        _StepDef(
          title: '담배를\n피우시나요?',
          subtitle: '함께 먹으면 안 좋은 약이 있어요.',
          validate: () => _smoking == null ? '해당하는 것을 골라주세요' : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in _smokingValues.entries) ...[
                _choice(
                  entry.key,
                  selected: _smoking == entry.value,
                  onTap: () => setState(() => _smoking = entry.value),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
      big(
        _StepDef(
          title: '술은 얼마나\n드시나요?',
          subtitle: '술과 같이 먹으면 위험한 약이 있어요.',
          validate: () => _drinking == null ? '해당하는 것을 골라주세요' : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choice(
                '자주 마셔요',
                sub: '일주일에 세 번 넘게',
                selected: _drinking == '자주 마셔요',
                onTap: () => setState(() => _drinking = '자주 마셔요'),
              ),
              const SizedBox(height: 12),
              _choice(
                '가끔 마셔요',
                sub: '한 달에 두세 번',
                selected: _drinking == '가끔 마셔요',
                onTap: () => setState(() => _drinking = '가끔 마셔요'),
              ),
              const SizedBox(height: 12),
              _choice(
                '안 마셔요',
                selected: _drinking == '안 마셔요',
                onTap: () => setState(() => _drinking = '안 마셔요'),
              ),
            ],
          ),
        ),
      );

      big(
        _yesNoStep(
          title: '약을 먹고 두드러기가 나거나\n숨이 찬 적이 있나요?',
          subtitle: '약 알레르기를 여쭤보는 거예요.',
          answer: _allergyAnswer,
          onAnswer: (v) => _allergyAnswer = v,
          yesLabel: '네, 있어요',
          noLabel: '아니요, 없어요',
          unsureLabel: '잘 모르겠어요',
        ),
      );
      if (_allergyAnswer == 'y') {
        detail(
          _StepDef(
            confirm: '알레르기가 있다고 하셨어요',
            title: '어떤 약이었나요?',
            subtitle: '여러 개 골라도 돼요.',
            validate: () => _allergens.isEmpty ? '어떤 약인지 하나 이상 골라주세요' : null,
            child: _multiChips(
              _allergyOptions,
              _allergens,
              (o) => _toggle(_allergens, o),
            ),
          ),
        );
      }

      big(
        _yesNoStep(
          title: '지금 치료받고 있는\n병이 있나요?',
          subtitle: '약을 함께 먹어도 되는지 볼 때 써요.',
          answer: _diseaseAnswer,
          onAnswer: (v) => _diseaseAnswer = v,
        ),
      );
      if (_diseaseAnswer == 'y') {
        detail(
          _StepDef(
            confirm: '치료받는 병이 있다고 하셨어요',
            title: '어떤 병인가요?',
            subtitle: '여러 개 골라도 돼요.',
            validate: () => _diseases.isEmpty ? '어떤 병인지 하나 이상 골라주세요' : null,
            child: _multiChips(
              _diseaseOptions,
              _diseases,
              (o) => _toggle(_diseases, o),
            ),
          ),
        );
      }

      big(
        _yesNoStep(
          title: '예전에 크게\n아팠던 적이 있나요?',
          subtitle: '암, 뇌졸중, 심근경색 같은 병이요.',
          answer: _pastAnswer,
          onAnswer: (v) => _pastAnswer = v,
        ),
      );
      if (_pastAnswer == 'y') {
        detail(
          _StepDef(
            confirm: '크게 아팠던 적이 있다고 하셨어요',
            title: '어떤 병이었나요?',
            subtitle: '여러 개 골라도 돼요.',
            validate: () =>
                _pastIllnesses.isEmpty ? '어떤 병인지 하나 이상 골라주세요' : null,
            child: _multiChips(
              _pastOptions,
              _pastIllnesses,
              (o) => _toggle(_pastIllnesses, o),
            ),
          ),
        );
      }

      big(
        _yesNoStep(
          title: '부모님이나 형제가\n앓은 병이 있나요?',
          subtitle: '나에게도 생기기 쉬운 병을 미리 살펴요.',
          answer: _familyAnswer,
          onAnswer: (v) => _familyAnswer = v,
          unsureLabel: '잘 모르겠어요',
        ),
      );
      if (_familyAnswer == 'y') {
        detail(
          _StepDef(
            confirm: '가족이 앓은 병이 있다고 하셨어요',
            title: '어떤 병이었나요?',
            subtitle: '여러 개 골라도 돼요.',
            validate: () =>
                _familyIllnesses.isEmpty ? '어떤 병인지 하나 이상 골라주세요' : null,
            child: _multiChips(
              _familyOptions,
              _familyIllnesses,
              (o) => _toggle(_familyIllnesses, o),
            ),
          ),
        );
      }

      big(
        _StepDef(
          title: '약을 놓치시면\n가족에게 알려드릴까요?',
          subtitle: '심박수가 빠를 때도 함께 알려드려요.',
          validate: () => _guardianAnswer == null ? '해당하는 것을 골라주세요' : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choice(
                '네, 알려주세요',
                sub: '다음 화면에서 번호를 적어요',
                icon: TablerIcons.users,
                selected: _guardianAnswer == 'y',
                onTap: () => setState(() => _guardianAnswer = 'y'),
              ),
              const SizedBox(height: 12),
              _choice(
                '나중에 할게요',
                sub: '내 정보에서 언제든 넣어요',
                icon: TablerIcons.clock,
                selected: _guardianAnswer == 'n',
                onTap: () => setState(() {
                  _guardianAnswer = 'n';
                  _guardianName.clear();
                  _guardianPhone.clear();
                  _guardianRelation = null;
                }),
              ),
            ],
          ),
        ),
      );
      if (_guardianAnswer == 'y') {
        detail(
          _StepDef(
            title: '누구에게\n알려드릴까요?',
            validate: () {
              if (_guardianRelation == null) return '나와의 관계를 골라주세요';
              if (_guardianName.text.trim().isEmpty) {
                return '보호자 성함을 입력해주세요';
              }
              if (_guardianPhone.text.trim().isEmpty) {
                return '보호자 휴대폰 번호를 입력해주세요';
              }
              return null;
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel('나와의 관계'),
                _grid(
                  const ['딸', '아들', '배우자', '다른 분'],
                  _guardianRelation,
                  (v) => setState(() => _guardianRelation = v),
                ),
                const SizedBox(height: 18),
                _field(_guardianName, label: '성함', hint: '보호자 성함'),
                const SizedBox(height: 12),
                _field(
                  _guardianPhone,
                  label: '휴대폰 번호',
                  hint: '010-0000-0000',
                  keyboard: TextInputType.phone,
                ),
              ],
            ),
          ),
        );
      }
    } // 환자 전용 건강정보 단계 끝

    // 동의는 환자·보호자 공통
    big(
      _StepDef(
        title: '약관에\n동의해주세요',
        subtitle: '필수 3개에 동의하면 가입이 끝나요.',
        validate: () => _allRequired ? null : '필수 3개에 동의해주세요',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 한 번에 끝내는 길을 맨 위에 크게 둔다.
            Semantics(
              button: true,
              checked: _allChecked,
              child: GestureDetector(
                onTap: () {
                  final v = !_allChecked;
                  setState(() {
                    _agreeAge = v;
                    _agreeTerms = v;
                    _agreePrivacy = v;
                    _agreeMarketing = v;
                  });
                },
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 70),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: _allChecked
                          ? AppColors.pointFillSignup
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _allChecked ? null : kCardShadow,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _allChecked
                              ? TablerIcons.circle_check_filled
                              : TablerIcons.circle,
                          size: 32,
                          color: _allChecked
                              ? Colors.white
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '전체 동의하기',
                            style: AppText.cardTitle(size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _consent(
              '만 14세 이상입니다',
              _agreeAge,
              (v) => setState(() => _agreeAge = v),
              required: true,
            ),
            _consent(
              '서비스 이용약관 동의',
              _agreeTerms,
              (v) => setState(() => _agreeTerms = v),
              required: true,
            ),
            _consent(
              '개인정보 수집·이용 동의',
              _agreePrivacy,
              (v) => setState(() => _agreePrivacy = v),
              required: true,
            ),
            _consent(
              '마케팅 정보 수신 동의',
              _agreeMarketing,
              (v) => setState(() => _agreeMarketing = v),
              required: false,
            ),
          ],
        ),
      ),
    );

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    if (_step > steps.length - 1) _step = steps.length - 1;
    final cur = steps[_step];
    final isLast = _step == steps.length - 1;
    // 자세히 화면은 앞 단계와 같은 번호를 쓰므로 큰 단계만 센다.
    final bigTotal = steps.last.stepNo;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            SeniorHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 뒤로 버튼이 라벨을 갖게 되면서 한 줄에 셋을 넣으면
                  // 글자가 커질 때 넘친다. 걸음 표시를 아래로 내린다.
                  Row(
                    children: [
                      SeniorBackButton(onTap: _prev),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '회원가입',
                          style: AppText.screenTitle(size: 24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${cur.stepNo} / $bigTotal',
                    style: AppText.cardTitle(
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: cur.stepNo / bigTotal,
                      minHeight: 8,
                      backgroundColor: AppColors.secondaryFill,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.point,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 한 화면에 하나만 묻는다.
                    if (cur.confirm != null) ...[
                      // 방금 "네"라고 하신 것을 되짚어 준다 — 다른 질문에
                      // 답하고 있다고 헷갈리지 않게.
                      Text(
                        cur.confirm!,
                        style: AppText.cardTitle(
                          size: 19,
                          color: AppColors.point,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(cur.title, style: AppText.screenTitle(size: 27)),
                    if (cur.subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        cur.subtitle!,
                        style: AppText.body(
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    cur.child,
                  ],
                ),
              ),
            ),
            Padding(
              key: _actionsKey,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 넘어가도 되는 단계에서는 "넘어가기"를 왼쪽에 작게 두고
                  // 가는 단추를 오른쪽에 크게 둔다. 위아래로 쌓으면 둘 다
                  // 같은 무게로 보여 어느 쪽이 보통 길인지 흐려진다.
                  if (cur.skippable && !isLast)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 2,
                            child: SeniorButton(
                              label: '넘어가기',
                              kind: SeniorButtonKind.card,
                              minHeight: 74,
                              fontSize: 20,
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      cur.onSkip?.call();
                                      _skip(steps);
                                    },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: SeniorButton(
                              label: '저장 후 다음',
                              minHeight: 74,
                              fontSize: 22,
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _next(steps),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SeniorButton(
                      label: isLast && _isSubmitting
                          ? '가입 중...'
                          : isLast
                          ? '가입하기'
                          : '다음',
                      minHeight: 74,
                      fontSize: 24,
                      onPressed: _isSubmitting ? null : () => _next(steps),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 공통 위젯 ─────────────────────────────────────────────
  //
  // 단계 정의는 모두 이 일곱 개를 통과한다. 여기만 시니어 규격으로
  // 맞추면 일곱 단계가 한꺼번에 따라온다.

  Widget _field(
    TextEditingController c, {
    String? label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    String? suffixText,
  }) {
    return SeniorField(
      controller: c,
      label: label,
      hint: hint,
      obscure: obscure,
      keyboardType: keyboard,
      suffix:
          suffix ??
          (suffixText == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Text(suffixText, style: AppText.label(size: 18)),
                )),
    );
  }

  /// 0단계 역할 카드. 최소 104, 아이콘 36.
  Widget _roleCard(String role, String title, String sub) {
    final selected = _rolePicked && _role == role;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $sub',
      child: GestureDetector(
        onTap: () => setState(() {
          _role = role;
          _rolePicked = true;
        }),
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointFillSignup : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: selected ? null : kCardShadow,
            ),
            child: Row(
              children: [
                Icon(
                  role == 'guardian' ? TablerIcons.users : TablerIcons.user,
                  size: 34,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppText.cardTitle(
                          size: 25,
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: AppText.caption(
                          size: 16.5,
                          color: selected
                              ? AppColors.onPointMuted
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 큰 답 하나. 한 줄에 하나씩 쌓아 한 번에 하나씩 읽게 둔다.
  Widget _choice(
    String label, {
    String? sub,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: sub == null ? label : '$label, $sub',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointFillSignup : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: selected ? null : kCardShadow,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 34,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppText.cardTitle(
                          size: 25,
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (sub != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          style: AppText.caption(
                            size: 16.5,
                            color: selected
                                ? AppColors.onPointMuted
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(
    String label,
    bool selected,
    VoidCallback onTap, {
    double minHeight = 74,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label ${selected ? '고름' : '고르지 않음'}',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointFillSignup : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected ? null : kCardShadow,
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

  /// 단계 안의 작은 제목. 한 걸음에 두 가지를 물을 때만 쓴다.
  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppText.label(size: 18)),
  );

  /// 두 칸씩 늘어놓는 단일 선택. 글자가 길면 그 보기만 한 줄을 다 쓴다.
  Widget _grid(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return _OptionFlow(
      options: options,
      builder: (option, full) => _pill(
        option,
        selected == option,
        () => onSelect(option),
        minHeight: 64,
      ),
    );
  }

  Widget _multiChips(
    List<String> options,
    Set<String> selected,
    void Function(String) onTap,
  ) {
    return _OptionFlow(
      options: options,
      builder: (option, full) {
        final picked = selected.contains(option);
        return Semantics(
          button: true,
          selected: picked,
          label: '$option ${picked ? '고름' : '고르지 않음'}',
          child: GestureDetector(
            onTap: () => onTap(option),
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: picked ? AppColors.pointFillSignup : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: picked ? null : kCardShadow,
                ),
                child: Text(
                  option,
                  textAlign: TextAlign.center,
                  style: AppText.cardTitle(
                    size: 19,
                    color: picked ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 약관 한 줄. 필수·선택 태그를 오른쪽에 둔다.
  Widget _consent(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    required bool required,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        checked: value,
        label: '${required ? '필수' : '선택'} $label',
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    value
                        ? TablerIcons.circle_check_filled
                        : TablerIcons.circle,
                    size: 28,
                    color: value ? AppColors.point : AppColors.inactive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: AppText.label(size: 18))),
                  const SizedBox(width: 10),
                  Text(
                    required ? '필수' : '선택',
                    style: AppText.cardTitle(
                      size: 17,
                      color: required
                          ? AppColors.point
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDef {
  /// 큰 단계 번호. 자세히 화면은 앞 단계와 같은 번호를 쓴다.
  int stepNo = 0;

  /// "네"라고 하신 것을 자세히 여쭤보는 화면의 머리말.
  final String? confirm;
  final String title;
  final String? subtitle;

  final String? Function() validate;
  final Widget child;

  /// 적지 않고 지나가도 되는 단계. 아래에 "넘어가기"가 붙는다.
  final VoidCallback? onSkip;

  bool get skippable => onSkip != null;

  _StepDef({
    this.confirm,
    required this.title,
    this.subtitle,
    String? Function()? validate,
    required this.child,
    this.onSkip,
  }) : validate = validate ?? (() => null);
}

/// 회원가입 완료.
///
/// 가입이 끝난 자리에서 약 등록으로 바로 이어준다.
/// 로그인 화면으로 되돌려 보내면 방금 만든 계정으로 다시 들어와야 한다.
class SignupDoneScreen extends StatelessWidget {
  final String name;
  final Future<InviteResult>? guardianInvite;

  const SignupDoneScreen({super.key, required this.name, this.guardianInvite});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 60, 26, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.pointTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          TablerIcons.check,
                          size: 52,
                          color: AppColors.point,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '가입이 끝났어요',
                      textAlign: TextAlign.center,
                      style: AppText.screenTitle(size: 28),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$name 님, 반갑습니다.\n이제 드시는 약만 넣으면 돼요.',
                      textAlign: TextAlign.center,
                      style: AppText.body(
                        size: 19,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (guardianInvite != null) ...[
                      const SizedBox(height: 18),
                      FutureBuilder<InviteResult>(
                        future: guardianInvite,
                        builder: (context, snapshot) => Text(
                          snapshot.connectionState != ConnectionState.done
                              ? '보호자 초대를 보내는 중이에요.'
                              : snapshot.data?.isSent == true
                              ? '보호자 초대를 보냈어요.'
                              : '보호자 초대는 완료되지 않았어요. 내 정보에서 다시 시도해 주세요.',
                          textAlign: TextAlign.center,
                          style: AppText.body(
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeniorButton(
                    label: '약 등록 시작하기',
                    minHeight: 74,
                    fontSize: 24,
                    onPressed: () => context.go('/first-run'),
                  ),
                  const SizedBox(height: 10),
                  SeniorButton(
                    label: '나중에 할게요',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 62,
                    fontSize: 20,
                    onPressed: () => context.go('/'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 보기 칸을 두 칸씩 놓되, 한 줄로 안 들어가는 보기는 한 줄을 다 쓴다.
///
/// 글자를 줄이지 않고 줄바꿈을 막는 길이다. 반쪽 칸에 글자가 들어가는지
/// 실제로 재 보고 정한다.
class _OptionFlow extends StatelessWidget {
  final List<String> options;

  /// [full]이면 한 줄을 다 쓰는 칸이다.
  final Widget Function(String option, bool full) builder;

  const _OptionFlow({required this.options, required this.builder});

  /// 이 글자가 [maxWidth] 안에 한 줄로 들어가는지.
  static bool _fits(
    String text,
    TextStyle style,
    double maxWidth,
    double scale,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(scale),
    )..layout();
    return painter.width <= maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final style = AppText.cardTitle(size: 19);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 칸 안쪽 여백(12+12)과 테두리(2+2), 칸 사이 간격 10을 뺀 폭.
        final half = (constraints.maxWidth - 10) / 2 - 28;
        final rows = <Widget>[];
        var i = 0;
        while (i < options.length) {
          final current = options[i];
          final next = i + 1 < options.length ? options[i + 1] : null;
          final pairs =
              next != null &&
              _fits(current, style, half, scale) &&
              _fits(next, style, half, scale);
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: pairs
                      ? [
                          Expanded(child: builder(current, false)),
                          const SizedBox(width: 10),
                          Expanded(child: builder(next, false)),
                        ]
                      : [Expanded(child: builder(current, true))],
                ),
              ),
            ),
          );
          i += pairs ? 2 : 1;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
