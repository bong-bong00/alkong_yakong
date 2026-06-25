import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';

/// 단계형 회원가입 (위저드).
/// 위치: lib/features/auth/presentation/screens/signup_screen.dart
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _step = 0;
  String? _error; // 질문 바로 아래에 크게 표시
  bool _isSubmitting = false;
  final ApiClient _apiClient = ApiClient();

  String _role = 'patient';
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

  bool? _chronicYes;
  final Set<String> _diseases = {};
  final _diseaseOther = TextEditingController();

  bool? _pastYes;
  bool? _familyYes;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _agreeHealth = false;
  bool _agreeMarketing = false;
  bool get _allRequired => _agreeTerms && _agreePrivacy && _agreeHealth;
  bool get _allChecked => _allRequired && _agreeMarketing;

  Color get _accent => _role == 'guardian' ? kGuardian : kPrimary;

  static const _allergyOptions = [
    '페니실린',
    '항생제(세팔로스포린 등)',
    '소염진통제(아스피린·NSAIDs)',
    '해열진통제(타이레놀)',
    '조영제',
    '마취제',
    '기타',
  ];
  static const _diseaseOptions = [
    '고혈압',
    '당뇨',
    '고지혈증',
    '심장질환',
    '신장질환',
    '간질환',
    '천식·COPD',
    '갑상선질환',
    '관절염',
    '위장질환',
    '기타',
  ];

  @override
  void dispose() {
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

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
  );

  void _toggle(Set<String> set, String o) => setState(() {
    if (set.contains(o)) {
      set.remove(o);
    } else {
      set.add(o);
    }
  });

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    int y = _birth?.year ?? (now.year - 60);
    int m = _birth?.month ?? 1;
    int d = _birth?.day ?? 1;
    final years = [for (int yy = 1920; yy <= now.year; yy++) yy];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                  const Text(
                    '생년월일',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kText,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      final maxDay = DateUtils.getDaysInMonth(y, m);
                      if (d > maxDay) d = maxDay;
                      setState(() => _birth = DateTime(y, m, d));
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
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
      await _showSignupCompleteDialog();
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

  Future<void> _showSignupCompleteDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '가입이 완료되었습니다',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('로그인 화면으로 이동합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  List<_StepDef> _buildSteps() {
    final steps = <_StepDef>[
      _StepDef(
        title: '어떤 분이신가요?',
        child: Row(
          children: [
            Expanded(child: _roleCard('patient', '🧓', '환자', '직접 복약 관리')),
            const SizedBox(width: 12),
            Expanded(child: _roleCard('guardian', '👩', '보호자', '가족 복약 관리')),
          ],
        ),
      ),
      _StepDef(
        title: '기본 정보를 입력해주세요',
        validate: () {
          if (_name.text.trim().isEmpty) return '이름을 입력해주세요';
          if (_phone.text.trim().isEmpty) return '휴대폰번호를 입력해주세요';
          if (_pw.text.length < 6) return '비밀번호는 6자 이상이어야 해요';
          if (_pw.text != _pw2.text) return '비밀번호가 일치하지 않아요';
          return null;
        },
        child: Column(
          children: [
            _field(_name, hint: '이름'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _phone,
                    hint: '휴대폰번호 (로그인·알림용)',
                    keyboard: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 8),
                _smallBtn('인증', () => _toast('인증 — 백엔드 연동 예정')),
              ],
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
            _field(_pw2, hint: '비밀번호 확인', obscure: true),
          ],
        ),
      ),
    ];

    // 환자만 건강정보 단계를 받는다 (보호자는 환자 모니터링 전용이라 불필요)
    if (_role == 'patient') {
      steps.addAll([
        _StepDef(
          title: '생년월일과 성별을 알려주세요',
          validate: () {
            if (_birth == null) return '생년월일을 선택해주세요';
            if (_gender == null) return '성별을 선택해주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _pickBirth,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _birth == null
                            ? '생년월일 선택'
                            : '${_birth!.year}년 ${_birth!.month}월 ${_birth!.day}일',
                        style: TextStyle(
                          fontSize: 15,
                          color: _birth == null ? Colors.grey[500] : kText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      '남성',
                      _gender == 'M',
                      () => setState(() => _gender = 'M'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pill(
                      '여성',
                      _gender == 'F',
                      () => setState(() => _gender = 'F'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _StepDef(
          title: '키, 몸무게, 혈액형',
          subtitle: '모르면 비워두고 넘어가도 돼요 (선택)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _height,
                      hint: '키',
                      keyboard: TextInputType.number,
                      suffixText: 'cm',
                    ),
                  ),
                  const SizedBox(width: 12),
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
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '혈액형',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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

      if (_gender == 'F') {
        steps.add(
          _StepDef(
            title: '임신 계획이 있으신가요?',
            subtitle: '임신 상황에 따라 주의 약물이 달라요',
            validate: () => _pregnancy == null ? '하나를 선택해주세요' : null,
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
          title: '흡연과 음주를 알려주세요',
          validate: () {
            if (_smoking == null) return '흡연 여부를 선택해주세요';
            if (_drinking == null) return '음주 여부를 선택해주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '담배를 피우시나요?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _vlist(
                const ['아니요', '예', '과거에 폈지만 끊었어요'],
                _smoking,
                (v) => setState(() => _smoking = v),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '술을 일주일에 얼마나 마시나요?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _grid(
                const ['거의 안 마심', '주 1~2일', '주 3~4일', '주 5~7일'],
                _drinking,
                (v) => setState(() => _drinking = v),
              ),
            ],
          ),
        ),
        _StepDef(
          title: '약물 알레르기가 있으신가요?',
          subtitle: '약물 알레르기 안전을 위해 꼭 필요해요',
          validate: () {
            if (_allergyYes == null) return '하나를 선택해주세요';
            if (_allergyYes == true && _allergens.isEmpty) {
              return '해당하는 약물 알레르기를 선택해주세요';
            }
            if (_allergens.contains('기타') &&
                _allergyOther.text.trim().isEmpty) {
              return '기타 약물 알레르기를 입력해주세요';
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
                  '해당하는 것을 모두 선택해주세요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 10),
                _multiChips(
                  _allergyOptions,
                  _allergens,
                  (o) => _toggle(_allergens, o),
                ),
                if (_allergens.contains('기타')) ...[
                  const SizedBox(height: 12),
                  _field(_allergyOther, hint: '기타 약물 알레르기를 입력해주세요'),
                ],
              ],
            ],
          ),
        ),
        _StepDef(
          title: '현재 앓고 있는 질환이 있으신가요?',
          subtitle: '복약 안전도 판단에 사용돼요',
          validate: () {
            if (_chronicYes == null) return '하나를 선택해주세요';
            if (_chronicYes == true && _diseases.isEmpty) {
              return '해당하는 질환을 선택해주세요';
            }
            if (_diseases.contains('기타') && _diseaseOther.text.trim().isEmpty) {
              return '기타 질환을 입력해주세요';
            }
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _yesNo(_chronicYes, (v) => setState(() => _chronicYes = v)),
              if (_chronicYes == true) ...[
                const SizedBox(height: 16),
                Text(
                  '해당하는 것을 모두 선택해주세요',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(height: 10),
                _multiChips(
                  _diseaseOptions,
                  _diseases,
                  (o) => _toggle(_diseases, o),
                ),
                if (_diseases.contains('기타')) ...[
                  const SizedBox(height: 12),
                  _field(_diseaseOther, hint: '기타 질환을 입력해주세요'),
                ],
              ],
            ],
          ),
        ),
        _StepDef(
          title: '과거력과 가족력',
          validate: () {
            if (_pastYes == null) return '과거력을 선택해주세요';
            if (_familyYes == null) return '가족력을 선택해주세요';
            return null;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '과거에 앓았던 질환이 있나요?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _yesNo(_pastYes, (v) => setState(() => _pastYes = v)),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '가족력이 있나요?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _yesNo(_familyYes, (v) => setState(() => _familyYes = v)),
            ],
          ),
        ),
      ]);
    } // 환자 전용 건강정보 단계 끝

    // 동의는 환자·보호자 공통
    steps.addAll([
      _StepDef(
        title: '약관에 동의해주세요',
        validate: () => _allRequired ? null : '필수 약관에 동의해주세요',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                final v = !_allChecked;
                setState(() {
                  _agreeTerms = v;
                  _agreePrivacy = v;
                  _agreeHealth = v;
                  _agreeMarketing = v;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _allChecked ? Icons.check_circle : Icons.circle_outlined,
                      color: _allChecked ? _accent : Colors.grey[400],
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '전체 동의',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: kText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
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
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        foregroundColor: kText,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _prev,
        ),
        title: const Text(
          '회원가입',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / steps.length,
                      minHeight: 4,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(_accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_step + 1} / ${steps.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kText,
                        height: 1.3,
                      ),
                    ),
                    if (cur.subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        cur.subtitle!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                    const SizedBox(height: 22),
                    cur.child,
                    // ── 검증 실패 시 질문 바로 아래에 크게 표시 ──
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFE24B4A),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFE24B4A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kText,
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _prev,
                          child: const Text(
                            '이전',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : () => _next(steps),
                        child: Text(
                          isLast && _isSubmitting
                              ? '가입 중...'
                              : isLast
                              ? '가입하기'
                              : '다음',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
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
  Widget _field(
    TextEditingController c, {
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    String? suffixText,
    int lines = 1,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      maxLines: obscure ? 1 : lines,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
        suffixText: suffixText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _smallBtn(String label, VoidCallback onTap) => SizedBox(
    height: 54,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: _accent.withValues(alpha: 0.12),
        foregroundColor: _accent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );

  Widget _roleCard(String role, String emoji, String title, String sub) {
    final selected = _role == role;
    final c = role == 'guardian' ? kGuardian : kPrimary;
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? c : kText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _accent : Colors.grey[300]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? _accent : kText,
          ),
        ),
      ),
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
          GestureDetector(
            onTap: () => onTap(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected.contains(o)
                    ? _accent.withValues(alpha: 0.10)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected.contains(o) ? _accent : Colors.grey[300]!,
                  width: selected.contains(o) ? 1.5 : 1,
                ),
              ),
              child: Text(
                o,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected.contains(o) ? _accent : kText,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: _pill(
                    options[i],
                    selected == options[i],
                    () => onSelect(options[i]),
                  ),
                ),
                const SizedBox(width: 12),
                if (i + 1 < options.length)
                  Expanded(
                    child: _pill(
                      options[i + 1],
                      selected == options[i + 1],
                      () => onSelect(options[i + 1]),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _vlist(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: _pill(o, selected == o, () => onSelect(o)),
            ),
          ),
      ],
    );
  }

  Widget _yesNo(bool? value, ValueChanged<bool> onSelect) {
    return Row(
      children: [
        Expanded(child: _pill('아니요', value == false, () => onSelect(false))),
        const SizedBox(width: 12),
        Expanded(child: _pill('예', value == true, () => onSelect(true))),
      ],
    );
  }

  Widget _consent(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    required bool required,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              color: value ? _accent : Colors.grey[400],
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              required ? '[필수] ' : '[선택] ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: required ? _accent : Colors.grey[500],
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13.5, color: kText),
              ),
            ),
          ],
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
