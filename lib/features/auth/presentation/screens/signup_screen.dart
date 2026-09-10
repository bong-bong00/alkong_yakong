import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/exclusive_choice.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_header.dart';

/// 단계형 회원가입 (위저드).
/// 위치: lib/features/auth/presentation/screens/signup_screen.dart
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _step = 0;
  /// 틀린 곳 한 군데. **버튼 바로 위**에 둔다 —
  /// 위로 스크롤해서 찾아야 하는 오류는 없는 것과 같다.
  String? _error;
  bool _isSubmitting = false;
  final ApiClient _apiClient = ApiClient();

  /// 처음에는 아무것도 고르지 않은 상태다. 기본값이 있으면
  /// 고르지 않고 지나쳐도 환자로 가입된다.
  String _role = 'patient';
  bool _rolePicked = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _obscure = true;
  DateTime? _birth;
  String? _gender;

  final _height = TextEditingController();
  final _weight = TextEditingController();
  String? _blood;

  String? _pregnancy;
  String? _smoking;
  String? _drinking;



  bool? _allergyYes;
  final Set<String> _allergens = {};
  final _allergyOther = TextEditingController();

  final _diseaseOther = TextEditingController();

  bool? _pastYes;
  bool? _familyYes;

  final Set<String> _diseases = {};


  // 보호자 연락처. 나중에 등록해도 되므로 건너뛴 사실도 기억한다.
  final _guardianName = TextEditingController();
  final _guardianPhone = TextEditingController();
  String? _guardianRelation;
  bool _guardianLater = false;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _agreeHealth = false;
  bool _agreeMarketing = false;
  bool get _allRequired => _agreeTerms && _agreePrivacy && _agreeHealth;
  bool get _allChecked => _allRequired && _agreeMarketing;

  static const _allergyOptions = [
    '페니실린',
    '아스피린',
    '소염진통제',
    '조영제',
    '기타',
    '잘 모르겠어요',
  ];
  static const _diseaseOptions = [
    '고혈압',
    '당뇨',
    '고지혈증',
    '심장병',
    '콩팥병',
    '기타',
    '없어요',
  ];

  @override
  void dispose() {
    _guardianName.dispose();
    _guardianPhone.dispose();
    _name.dispose();
    _phone.dispose();
    _pw.dispose();
    _pw2.dispose();
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
    final now = DateTime.now();
    int y = _birth?.year ?? (now.year - 60);
    int m = _birth?.month ?? 1;
    int d = _birth?.day ?? 1;
    final years = [for (int yy = 1920; yy <= now.year; yy++) yy];

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('생년월일', style: AppText.cardTitle(size: 21)),
                  GestureDetector(
                    onTap: () {
                      final maxDay = DateUtils.getDaysInMonth(y, m);
                      if (d > maxDay) d = maxDay;
                      setState(() => _birth = DateTime(y, m, d));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '확인',
                        style: AppText.cardTitle(
                          size: 20,
                          color: AppColors.point,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 210,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _wheel(
                        years,
                        years.indexOf(y),
                        (i) => y = years[i],
                        '년',
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _wheel(
                        List.generate(12, (k) => k + 1),
                        m - 1,
                        (i) => m = i + 1,
                        '월',
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _wheel(
                        List.generate(31, (k) => k + 1),
                        d - 1,
                        (i) => d = i + 1,
                        '일',
                      ),
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

  Widget _wheel(
    List<int> items,
    int initialIndex,
    ValueChanged<int> onChanged,
    String suffix,
  ) {
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(
        initialItem: initialIndex < 0 ? 0 : initialIndex,
      ),
      itemExtent: 38,
      onSelectedItemChanged: onChanged,
      children: [
        for (final it in items)
          Center(
            child: Text(
              '$it$suffix',
              style: const TextStyle(fontSize: 18, color: kText),
            ),
          ),
      ],
    );
  }

  void _next(List<_StepDef> steps) {
    final err = steps[_step].validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_step >= steps.length - 1) {
      _submit();
    } else {
      setState(() {
        _error = null;
        _step++;
      });
    }
  }

  void _prev() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _error = null;
        _step--;
      });
    }
  }

  String? _optionalTrimmed(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _birthDateForApi() {
    final birth = _birth;
    if (birth == null) return null;
    final month = birth.month.toString().padLeft(2, '0');
    final day = birth.day.toString().padLeft(2, '0');
    return '${birth.year}-$month-$day';
  }

  Future<void> _submit() async {
    // TODO: 백엔드 회원가입 API 연동.
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    try {
      final birthDate = _birthDateForApi();
      final phone = _optionalTrimmed(_phone.text);
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'role': _role,
      };
      if (birthDate != null) body['birth_date'] = birthDate;
      if (_gender != null) body['gender'] = _gender;
      if (phone != null) body['phone'] = phone;

      final response = await _apiClient
          .post('/api/v1/users', body: body)
          .timeout(const Duration(seconds: 10));
      final userId = response is Map<String, dynamic>
          ? response['id']?.toString()
          : null;
      if (userId == null || userId.isEmpty) {
        throw const ApiException('회원가입 응답에 사용자 ID가 없습니다.');
      }

      MvpSession.userId = userId;
      if (!mounted) return;
      await _showSignupComplete();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/login');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('회원가입에 실패했습니다: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 가입이 끝났다는 사실만 알리고, 다음 한 걸음을 바로 내민다.
  /// 확인만 누르고 사라지는 알림창은 아무것도 이어주지 않는다.
  Future<void> _showSignupComplete() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SignupDoneScreen(name: _name.text.trim()),
      ),
    );
  }

  List<_StepDef> _buildSteps() {
    final steps = <_StepDef>[
      _StepDef(
        title: '어떤 분이신가요?',
        subtitle: '고르시면 물어보는 것이 달라집니다.',
        validate: () => _rolePicked ? null : '어떤 분인지 골라주세요',
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _roleCard('patient', '약을 드시는 분', '직접 챙기실 분'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _roleCard('guardian', '돌보는 가족', '보호자로 함께 보실 분'),
              ),
            ],
          ),
        ),
      ),
      _StepDef(
        title: '기본 정보를\n알려주세요',
        subtitle: '번호는 로그인과 약 알림에 씁니다.',
        validate: () {
          if (_name.text.trim().isEmpty) return '이름을 입력해주세요';
          if (_phone.text.trim().isEmpty) return '휴대폰 번호를 입력해주세요';
          if (_pw.text.isEmpty) return '비밀번호를 입력해주세요';
          if (_pw.text.length < 6) return '비밀번호는 6자 이상이어야 해요';
          if (_pw.text != _pw2.text) return '비밀번호가 일치하지 않아요';
          return null;
        },
        child: Column(
          children: [
            _field(_name, hint: '성함'),
            const SizedBox(height: 12),
            // 인증 버튼은 두지 않는다. 여기서 문자를 기다리게 하면
            // 가입이 끊긴다 — 번호 확인은 첫 알림이 도착하는 것으로 갈음한다.
            _field(
              _phone,
              hint: '010-0000-0000',
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _field(
              _pw,
              hint: '비밀번호 (6자 이상)',
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 12),
            _field(_pw2, hint: '비밀번호 다시 한 번', obscure: true),
          ],
        ),
      ),
    ];

    // 환자만 건강정보 단계를 받는다 (보호자는 환자 모니터링 전용이라 불필요)
    if (_role == 'patient') {
      steps.addAll([
        _StepDef(
          title: '생년월일과 성별을\n알려주세요',
          subtitle: '나이에 따라 주의할 약이 달라요.',
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
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.border,
                          width: 2,
                        ),
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
                        '남성',
                        _gender == 'M',
                        () => setState(() => _gender = 'M'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _pill(
                        '여성',
                        _gender == 'F',
                        () => setState(() => _gender = 'F'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _StepDef(
          title: '키, 몸무게, 혈액형을\n알려주세요',
          subtitle: '모르시면 비워두고 넘어가셔도 됩니다.',
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
                        hint: '키',
                        keyboard: TextInputType.number,
                        suffixText: 'cm',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _weight,
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
                const [
                  'RH+ A',
                  'RH- A',
                  'RH+ B',
                  'RH- B',
                  'RH+ O',
                  'RH- O',
                  'RH+ AB',
                  'RH- AB',
                ],
                _blood,
                (v) => setState(() => _blood = v),
              ),
            ],
          ),
        ),
      ]);

      // 임신·수유 여부는 병용금기 판정을 통째로 바꾼다. 건너뛰지 않는다.
      if (_gender == 'F') {
        steps.add(
          _StepDef(
            title: '임신 계획이\n있으신가요?',
            subtitle: '임신 상황에 따라 주의할 약이 달라요.',
            validate: () => _pregnancy == null ? '해당하는 것을 골라주세요' : null,
            child: _grid(
              const ['계획 없음', '임신 준비중', '임신 중', '수유 중'],
              _pregnancy,
              (v) => setState(() => _pregnancy = v),
            ),
          ),
        );
      }

      steps.addAll([
        _StepDef(
          title: '담배와 술을\n알려주세요',
          subtitle: '약이 몸에서 빠지는 속도가 달라집니다.',
          validate: () {
            if (_smoking == null) return '담배를 피우시는지 골라주세요';
            if (_drinking == null) return '술을 얼마나 드시는지 골라주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('담배를 피우시나요?'),
              _vlist(
                const ['아니요', '예', '과거에 폈지만 끊었어요'],
                _smoking,
                (v) => setState(() => _smoking = v),
              ),
              const SizedBox(height: 18),
              _sectionLabel('술을 일주일에 얼마나 드시나요?'),
              _grid(
                const ['거의 안 마심', '주 1~2일', '주 3~4일', '주 5~7일'],
                _drinking,
                (v) => setState(() => _drinking = v),
              ),
            ],
          ),
        ),
        _StepDef(
          title: '약물 알레르기가\n있으신가요?',
          subtitle: '위험한 약을 걸러내는 데 꼭 필요합니다.',
          validate: () {
            if (_allergyYes == null) return '있는지 없는지 골라주세요';
            if (_allergyYes == true && _allergens.isEmpty) {
              return '어떤 약인지 하나 이상 골라주세요';
            }
            if (_allergens.length > 1 && _allergens.contains('잘 모르겠어요')) {
              return '"잘 모르겠어요"는 약 이름과 함께 고를 수 없어요';
            }
            if (_allergens.contains('기타') &&
                _allergyOther.text.trim().isEmpty) {
              return '어떤 약인지 적어 주세요';
            }
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _yesNo(_allergyYes, (v) => setState(() => _allergyYes = v)),
              if (_allergyYes == true) ...[
                const SizedBox(height: 16),
                Text(
                  '해당하는 것을 모두 골라 주세요',
                  style: AppText.caption(size: 17.5),
                ),
                const SizedBox(height: 10),
                _multiChips(
                  _allergyOptions,
                  _allergens,
                  (o) => _toggle(_allergens, o),
                ),
                if (_allergens.contains('기타')) ...[
                  const SizedBox(height: 12),
                  _field(_allergyOther, hint: '어떤 약인지 적어 주세요'),
                ],
              ],
            ],
          ),
        ),
        _StepDef(
          // "있으신가요?"를 먼저 묻고 다시 고르게 하면 두 번 묻는 셈이 된다.
          // "없어요"를 칩 안에 넣어 한 번에 끝낸다.
          title: '지금 앓고 있는\n병이 있으신가요?',
          subtitle: '약을 함께 먹어도 되는지 판단할 때 씁니다.',
          validate: () {
            if (_diseases.isEmpty) {
              return '해당하는 것을 고르거나 "없어요"를 눌러주세요';
            }
            if (_diseases.length > 1 && _diseases.contains('없어요')) {
              return '지병과 "없어요"는 함께 고를 수 없어요';
            }
            if (_diseases.contains('기타') &&
                _diseaseOther.text.trim().isEmpty) {
              return '어떤 병인지 적어 주세요';
            }
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _multiChips(
                _diseaseOptions,
                _diseases,
                (o) => _toggle(_diseases, o),
              ),
              if (_diseases.contains('기타')) ...[
                const SizedBox(height: 12),
                _field(_diseaseOther, hint: '어떤 병인지 적어 주세요'),
              ],
            ],
          ),
        ),
      ]);
      steps.add(
        _StepDef(
          title: '과거에 앓았거나\n가족이 앓는 병이 있나요?',
          subtitle: '지금은 낫았어도 약을 고를 때 참고합니다.',
          validate: () {
            if (_pastYes == null) return '과거에 앓았던 병이 있는지 골라주세요';
            if (_familyYes == null) return '가족력이 있는지 골라주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('과거에 앓았던 병이 있나요?'),
              _yesNo(_pastYes, (v) => setState(() => _pastYes = v)),
              const SizedBox(height: 18),
              _sectionLabel('가족 중에 같은 병을 앓는 분이 있나요?'),
              _yesNo(_familyYes, (v) => setState(() => _familyYes = v)),
            ],
          ),
        ),
      );

      steps.add(
        _StepDef(
          title: '보호자 연락처를\n알려주세요',
          subtitle: '약을 놓치거나 심박수가 빠를 때 이 분에게 알려드립니다. '
              '나중에 등록해도 됩니다.',
          validate: () {
            if (_guardianLater) return null;
            if (_guardianName.text.trim().isEmpty &&
                _guardianRelation == null &&
                _guardianPhone.text.trim().isEmpty) {
              return '보호자를 등록하거나 "나중에 등록할게요"를 눌러주세요';
            }
            if (_guardianName.text.trim().isEmpty) {
              return '보호자 성함을 입력해주세요';
            }
            if (_guardianRelation == null) return '나와의 관계를 골라주세요';
            if (_guardianPhone.text.trim().isEmpty) {
              return '보호자 휴대폰 번호를 입력해주세요';
            }
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_guardianName, hint: '보호자 성함'),
              const SizedBox(height: 12),
              _multiChips(
                const ['딸', '아들', '배우자', '그 외'],
                {?_guardianRelation},
                (o) => setState(() {
                  _guardianRelation = _guardianRelation == o ? null : o;
                  _guardianLater = false;
                }),
              ),
              const SizedBox(height: 12),
              _field(
                _guardianPhone,
                hint: '010-0000-0000',
                keyboard: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              SeniorButton(
                label: _guardianLater ? '나중에 등록할게요 ✓' : '나중에 등록할게요',
                kind: SeniorButtonKind.secondary,
                minHeight: 62,
                fontSize: 20,
                onPressed: () => setState(() {
                  _guardianLater = !_guardianLater;
                  if (_guardianLater) {
                    _guardianName.clear();
                    _guardianPhone.clear();
                    _guardianRelation = null;
                  }
                }),
              ),
            ],
          ),
        ),
      );
    } // 환자 전용 건강정보 단계 끝

    // 동의는 환자·보호자 공통
    steps.addAll([
      _StepDef(
        title: '약관에\n동의해주세요',
        subtitle: '필수 3개에 동의하면 가입이 끝납니다.',
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
                    _agreeTerms = v;
                    _agreePrivacy = v;
                    _agreeHealth = v;
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
                          ? AppColors.pointTint
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _allChecked
                            ? AppColors.point
                            : AppColors.strongBorder,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _allChecked
                              ? TablerIcons.circle_check_filled
                              : TablerIcons.circle,
                          size: 32,
                          color: _allChecked
                              ? AppColors.point
                              : AppColors.inactive,
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
              '민감정보(건강정보) 수집·이용 동의',
              _agreeHealth,
              (v) => setState(() => _agreeHealth = v),
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
    ]);

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    if (_step > steps.length - 1) _step = steps.length - 1;
    final cur = steps[_step];
    final isLast = _step == steps.length - 1;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            SeniorHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      Text(
                        '${_step + 1} / ${steps.length}',
                        style: AppText.cardTitle(
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / steps.length,
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    SeniorErrorBox(_error!),
                    const SizedBox(height: 10),
                  ],
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
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    String? suffixText,
  }) {
    return SeniorField(
      controller: c,
      hint: hint,
      obscure: obscure,
      keyboardType: keyboard,
      suffix: suffix ??
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
              color: selected ? AppColors.pointTint : AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? AppColors.point : AppColors.strongBorder,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  role == 'guardian' ? TablerIcons.users : TablerIcons.user,
                  size: 36,
                  color: selected ? AppColors.point : AppColors.textTertiary,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppText.cardTitle(
                    size: 19,
                    color: selected ? AppColors.point : AppColors.textPrimary,
                  ),
                ),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: AppText.caption(size: 17),
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
              color: selected ? AppColors.point : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    selected ? AppColors.pointBorder : AppColors.strongBorder,
                width: 2,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 19,
                color: selected ? Colors.white : AppColors.textBody,
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

  /// 두 칸씩 늘어놓는 단일 선택.
  Widget _grid(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < options.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            // 글자가 커져도 두 칸의 키가 맞는다.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _pill(
                      options[i],
                      selected == options[i],
                      () => onSelect(options[i]),
                      minHeight: 64,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (i + 1 < options.length)
                    Expanded(
                      child: _pill(
                        options[i + 1],
                        selected == options[i + 1],
                        () => onSelect(options[i + 1]),
                        minHeight: 64,
                      ),
                    )
                  else
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 한 줄에 하나씩 놓는 단일 선택. 보기가 길어 두 칸에 안 들어갈 때 쓴다.
  Widget _vlist(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _pill(o, selected == o, () => onSelect(o), minHeight: 64),
          ),
      ],
    );
  }

  Widget _multiChips(
    List<String> options,
    Set<String> selected,
    void Function(String) onTap,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          Semantics(
            button: true,
            selected: selected.contains(o),
            label: '$o ${selected.contains(o) ? '고름' : '고르지 않음'}',
            child: GestureDetector(
              onTap: () => onTap(o),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected.contains(o)
                        ? AppColors.point
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected.contains(o)
                          ? AppColors.pointBorder
                          : AppColors.strongBorder,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    o,
                    style: AppText.cardTitle(
                      size: 18,
                      color: selected.contains(o)
                          ? Colors.white
                          : AppColors.textBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _yesNo(bool? value, ValueChanged<bool> onSelect) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _pill('없어요', value == false, () => onSelect(false)),
          ),
          const SizedBox(width: 10),
          Expanded(child: _pill('있어요', value == true, () => onSelect(true))),
        ],
      ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
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
                  Expanded(
                    child: Text(label, style: AppText.label(size: 18)),
                  ),
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
  final String title;
  final String? subtitle;
  final Widget child;
  final String? Function() validate;

  _StepDef({
    required this.title,
    this.subtitle,
    required this.child,
    String? Function()? validate,
  }) : validate = (validate ?? (() => null));
}


/// 회원가입 완료.
///
/// 가입이 끝난 자리에서 약 등록으로 바로 이어준다.
/// 로그인 화면으로 되돌려 보내면 방금 만든 계정으로 다시 들어와야 한다.
class SignupDoneScreen extends StatelessWidget {
  final String name;

  const SignupDoneScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
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
                      '$name 님, 반갑습니다.\n이제 드시는 약만 넣으면 됩니다.',
                      textAlign: TextAlign.center,
                      style: AppText.body(
                        size: 19,
                        color: AppColors.textSecondary,
                      ),
                    ),
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
