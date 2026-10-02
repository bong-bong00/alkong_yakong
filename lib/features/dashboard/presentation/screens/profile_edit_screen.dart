import 'package:flutter/material.dart';
import '../../../../core/widgets/senior_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_feedback.dart';
import '../../../../core/widgets/senior_wheel.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../profile/application/current_user_controller.dart';
import '../../../profile/domain/user_profile.dart';
import 'patient_data.dart';
import 'patient_link_screen.dart';

/// 내 정보 상세·수정 화면.
/// isGuardian = true 면 건강정보(키·몸무게·혈액형·임신·흡연·음주·알레르기·질환·
/// 과거력·가족력)를 모두 숨긴다. 보호자는 모니터링 전용이라 본인 건강정보가 없다.
///
/// 칸은 서버에 저장된 값으로 채우고, 저장하면 서버가 돌려준 값이
/// 내 정보·오늘 화면에 그대로 반영된다.
/// 위치: lib/features/dashboard/presentation/screens/profile_edit_screen.dart
class ProfileEditScreen extends ConsumerStatefulWidget {
  final bool isGuardian;
  const ProfileEditScreen({super.key, this.isGuardian = false});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();

  DateTime? _birth;
  String? _gender;
  String? _blood;
  String? _pregnancy;
  String? _smoking;
  String? _drinking;
  final Set<String> _allergens = {};
  final Set<String> _diseases = {};
  final Set<String> _pastIllnesses = {};
  final Set<String> _familyIllnesses = {};
  bool? _pastYes;
  bool? _familyYes;

  /// 칸을 채운 원래 값. null이면 아직 서버에서 못 읽었다.
  UserProfile? _original;
  bool _saving = false;

  bool get _isGuardian => widget.isGuardian;

  static const _allergyOptions = [
    '페니실린',
    '항생제(세팔로스포린 등)',
    '소염진통제(아스피린·NSAIDs)',
    '해열진통제(타이레놀)',
    '조영제',
    '마취제',
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
  ];
  // 회원가입에서 쓰는 보기와 같다. 같은 것을 물으면서 보기가 다르면
  // 고칠 때마다 없던 병이 생기거나 사라진다.
  static const _pastOptions = ['암', '뇌졸중', '심근경색', '간·콩팥병'];
  static const _familyOptions = ['고혈압', '당뇨', '심장병', '암', '치매', '뇌졸중'];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user != null) _fill(user);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _fill(UserProfile user) {
    _original = user;
    _name.text = user.name;
    _phone.text = user.phone ?? '';
    _height.text = _numberText(user.heightCm);
    _weight.text = _numberText(user.weightKg);
    _birth = user.birthDate;
    _gender = user.gender;
    _blood = user.bloodType;
    _pregnancy = user.pregnancyStatus;
    _smoking = _normalizeSmoking(user.smoking);
    _drinking = user.drinking;
    _allergens
      ..clear()
      ..addAll(user.allergies);
    _diseases
      ..clear()
      ..addAll(user.diseases);
    _pastYes = user.pastHistory;
    _familyYes = user.familyHistory;
    _pastIllnesses
      ..clear()
      ..addAll(user.pastIllnesses);
    _familyIllnesses
      ..clear()
      ..addAll(user.familyIllnesses);
  }

  static String _numberText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  /// 아바타는 이모지 대신 이름 첫 글자를 쓴다.
  /// 이모지는 기기마다 모양이 달라지고 의미 학습이 되지 않는다.

  void _toast(String message, {bool error = false}) =>
      showSeniorSnackbar(context, message, error: error);

  Future<void> _save() async {
    final original = _original;
    if (original == null || _saving) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('이름을 입력해주세요', error: true);
      return;
    }
    final heightText = _height.text.trim();
    final weightText = _weight.text.trim();
    final height = double.tryParse(heightText);
    final weight = double.tryParse(weightText);
    if (!_isGuardian && heightText.isNotEmpty && height == null) {
      _toast('키는 숫자로만 적어주세요', error: true);
      return;
    }
    if (!_isGuardian && weightText.isNotEmpty && weight == null) {
      _toast('몸무게는 숫자로만 적어주세요', error: true);
      return;
    }

    final phone = _phone.text.trim();
    // 임신 상태는 여성일 때만 남긴다. 성별을 바꾸면 함께 지운다.
    final pregnancy = _gender == 'F' ? _pregnancy : null;
    final edited = UserProfile(
      id: original.id,
      role: original.role,
      name: name,
      phone: phone.isEmpty ? null : phone,
      birthDate: _birth,
      gender: _gender,
      isPregnant: _isGuardian ? original.isPregnant : pregnancy == '임신 중',
      pregnancyStatus: _isGuardian ? original.pregnancyStatus : pregnancy,
      heightCm: _isGuardian ? original.heightCm : height,
      weightKg: _isGuardian ? original.weightKg : weight,
      bloodType: _isGuardian ? original.bloodType : _blood,
      smoking: _isGuardian ? original.smoking : _smoking,
      drinking: _isGuardian ? original.drinking : _drinking,
      allergies: _isGuardian ? original.allergies : _allergens.toList(),
      diseases: _isGuardian ? original.diseases : _diseases.toList(),
      pastHistory: _isGuardian ? original.pastHistory : _pastYes,
      familyHistory: _isGuardian ? original.familyHistory : _familyYes,
      // "없어요"로 바꾸면 적어 두었던 병도 함께 지운다. 안 그러면
      // 없다고 해 놓고 목록만 남는다.
      pastIllnesses: _isGuardian
          ? original.pastIllnesses
          : _pastYes == true
          ? _pastIllnesses.toList()
          : const [],
      familyIllnesses: _isGuardian
          ? original.familyIllnesses
          : _familyYes == true
          ? _familyIllnesses.toList()
          : const [],
    );

    setState(() => _saving = true);
    try {
      await ref.read(currentUserProvider.notifier).save(edited);
      if (!mounted) return;
      _toast('저장했어요');
      Navigator.of(context).maybePop();
    } on ApiException catch (error) {
      if (mounted) _toast(error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unlink(CarePatient patient) async {
    try {
      await GuardianRepository().remove(patient.linkId);
    } on ApiException catch (error) {
      if (mounted) _toast(error.message, error: true);
      return;
    }
    ref.invalidate(careOverviewProvider);
    if (mounted) _toast('${patient.name}님과 연결을 해제했어요');
  }

  void _confirmUnlink(CarePatient patient) {
    final name = patient.name;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '환자 연결을 해제할까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '$name님과의 연결을 해제하면\n더 이상 복약·심박 현황을 볼 수 없어요.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _unlink(patient);
            },
            child: const Text(
              '연결 해제',
              style: TextStyle(
                color: AppColors.legacyRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 한글 년/월/일 휠 선택기
  /// 옛 버전이 저장해 둔 "안 펴요"를 지금 칸 이름으로 옮겨 읽는다.
  static String? _normalizeSmoking(String? raw) => switch (raw?.trim()) {
    null || '' => null,
    '안 펴요' => '안 폈어요',
    '펴요' => '폈어요',
    final value => value,
  };

  Future<void> _pickBirth() async {
    final picked = await showSeniorDateWheel(
      context: context,
      initialDate: _birth,
    );
    if (picked == null) return;
    setState(() => _birth = picked);
  }

  /// 칩을 고르는 창을 연다.
  ///
  /// 창은 제 몫의 상태와 입력칸을 들고 있고, 닫힐 때 고른 것을 돌려준다.
  /// 창 안에서 이 화면의 `setState`를 부르거나 이 화면이 가진 Set을 직접
  /// 고치지 않는다 — 그렇게 하면 창이 닫히는 도중에 두 화면이 서로를
  /// 다시 그리다가 프레임워크가 넘어졌다.
  Future<void> _openPicker(
    String title,
    Set<String> selected,
    List<String> options,
  ) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _PickerSheet(title: title, options: options, initial: selected),
    );
    if (!mounted || picked == null) return;
    setState(() {
      selected
        ..clear()
        ..addAll(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 서버 값이 늦게 오면 도착하는 순간 한 번만 채운다.
    // 고치던 칸을 다시 덮어쓰지 않도록 두 번째부터는 무시한다.
    ref.listen(currentUserProvider, (_, next) {
      final user = next.valueOrNull;
      if (user != null && _original == null) setState(() => _fill(user));
    });

    final accent = _isGuardian ? kGuardian : kPrimary;
    return Scaffold(
      backgroundColor: kBackground,
      // 라벨 없는 화살표 아이콘은 어르신이 버튼으로 인식하지 못한다.
      body: SafeArea(
        child: Column(
          children: [
            const SeniorBackHeader(title: '내 정보 수정'),
            Expanded(
              child: _original == null ? _buildLoading() : _buildForm(accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final failed = ref.watch(currentUserProvider).hasError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (failed) ...[
              const Text(
                '내 정보를 불러오지 못했어요',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(currentUserProvider),
                child: const Text('다시 불러오기'),
              ),
            ] else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(Color accent) {
    final birth = _birth;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 기본 정보 (프로토타입 43번) ──
          SeniorCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeniorField(label: '이름', controller: _name, hint: '이름'),
                const SizedBox(height: 18),
                SeniorField(
                  label: '휴대폰번호',
                  controller: _phone,
                  hint: '010-0000-0000',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneNumberFormatter()],
                ),
                const SizedBox(height: 18),
                Text('생년월일', style: AppText.label(size: 18)),
                const SizedBox(height: 8),
                _PickRow(
                  value: birth == null
                      ? '아직 안 고르셨어요'
                      : '${birth.year}년 ${birth.month}월 ${birth.day}일',
                  empty: birth == null,
                  icon: Icons.calendar_month_rounded,
                  onTap: _pickBirth,
                ),
                const SizedBox(height: 18),
                Text('성별', style: AppText.label(size: 18)),
                const SizedBox(height: 8),
                _PickRow(
                  value: switch (_gender) {
                    'F' => '여자',
                    'M' => '남자',
                    _ => '아직 안 고르셨어요',
                  },
                  empty: _gender != 'F' && _gender != 'M',
                  onTap: _pickGender,
                ),
              ],
            ),
          ),

          // ── 연결된 어르신 — 보호자만 ──
          if (_isGuardian) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('연결된 어르신', style: AppText.cardTitle(size: 20)),
                  const SizedBox(height: 12),
                  for (final p
                      in ref
                              .watch(careOverviewProvider)
                              .valueOrNull
                              ?.patients ??
                          const <CarePatient>[]) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.title,
                                  style: AppText.cardTitle(size: 19),
                                ),
                                Text(
                                  p.age == null ? '나이 정보 없음' : '${p.age}세',
                                  style: AppText.caption(size: 16),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SeniorTextButton(
                            label: '연결 해제',
                            expand: false,
                            fontSize: 18,
                            color: AppColors.danger,
                            onPressed: () => _confirmUnlink(p),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SeniorButton(
                    label: '어르신 연결하기',
                    kind: SeniorButtonKind.secondary,
                    minHeight: 60,
                    fontSize: 19,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PatientLinkScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── 건강 정보 — 어르신만 (프로토타입 44번) ──
          if (!_isGuardian) ...[
            const SizedBox(height: 12),
            SeniorCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('키 (cm) · 몸무게 (kg)', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SeniorField(
                          controller: _height,
                          hint: '156 cm',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SeniorField(
                          controller: _weight,
                          hint: '54 kg',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('혈액형', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _PickRow(
                    value: _blood ?? '아직 안 고르셨어요',
                    empty: _blood == null,
                    onTap: _pickBlood,
                  ),
                  const SizedBox(height: 18),
                  Text('담배', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChoiceRow(
                    options: _smokingOptions,
                    selected: _smoking,
                    onPick: (value) => setState(() => _smoking = value),
                  ),
                  const SizedBox(height: 18),
                  Text('술', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChoiceRow(
                    options: _drinkingOptions,
                    selected: _drinking,
                    onPick: (value) => setState(() => _drinking = value),
                  ),
                  const SizedBox(height: 18),
                  Text('약물 알레르기', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChipEditor(
                    items: _allergens,
                    onAdd: () =>
                        _openPicker('약물 알레르기', _allergens, _allergyOptions),
                    onRemove: (item) => setState(() => _allergens.remove(item)),
                  ),
                  const SizedBox(height: 18),
                  Text('현재 질환 / 만성질환', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChipEditor(
                    items: _diseases,
                    onAdd: () =>
                        _openPicker('현재 질환', _diseases, _diseaseOptions),
                    onRemove: (item) => setState(() => _diseases.remove(item)),
                  ),
                  const SizedBox(height: 18),
                  // 회원가입에서 물은 것을 여기서도 다 고칠 수 있어야 한다.
                  // 한쪽에서만 고쳐지면 어느 쪽이 맞는 값인지 알 수 없다.
                  Text('예전에 크게 아팠던 적이 있나요?', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChoiceRow(
                    options: const ['네, 있어요', '아니요, 없어요'],
                    selected: switch (_pastYes) {
                      true => '네, 있어요',
                      false => '아니요, 없어요',
                      null => null,
                    },
                    onPick: (value) =>
                        setState(() => _pastYes = value == '네, 있어요'),
                  ),
                  if (_pastYes == true) ...[
                    const SizedBox(height: 10),
                    _ChipEditor(
                      items: _pastIllnesses,
                      onAdd: () =>
                          _openPicker('예전에 앓은 병', _pastIllnesses, _pastOptions),
                      onRemove: (item) =>
                          setState(() => _pastIllnesses.remove(item)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text('부모님이나 형제가 앓은 병이 있나요?', style: AppText.label(size: 18)),
                  const SizedBox(height: 8),
                  _ChoiceRow(
                    options: const ['네, 있어요', '아니요, 없어요'],
                    selected: switch (_familyYes) {
                      true => '네, 있어요',
                      false => '아니요, 없어요',
                      null => null,
                    },
                    onPick: (value) =>
                        setState(() => _familyYes = value == '네, 있어요'),
                  ),
                  if (_familyYes == true) ...[
                    const SizedBox(height: 10),
                    _ChipEditor(
                      items: _familyIllnesses,
                      onAdd: () => _openPicker(
                        '가족이 앓은 병',
                        _familyIllnesses,
                        _familyOptions,
                      ),
                      onRemove: (item) =>
                          setState(() => _familyIllnesses.remove(item)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SeniorButton(
            label: _saving ? '저장하는 중…' : '이대로 저장하기',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Future<void> _pickGender() async {
    const options = ['여자', '남자'];
    final picked = await showSeniorWheel(
      context: context,
      title: '성별을 고르세요',
      options: options,
      selectedIndex: _gender == 'M' ? 1 : 0,
    );
    if (picked == null) return;
    setState(() => _gender = picked == 1 ? 'M' : 'F');
  }

  /// 혈액형은 여덟 가지뿐이다. 칸을 여덟 개 깔지 않고 굴려서 고른다.
  Future<void> _pickBlood() async {
    final at = _bloodOptions.indexOf(_blood ?? '');
    final picked = await showSeniorWheel(
      context: context,
      title: '혈액형을 고르세요',
      options: _bloodOptions,
      selectedIndex: at < 0 ? 0 : at,
    );
    if (picked == null) return;
    setState(() => _blood = _bloodOptions[picked]);
  }
}

const List<String> _bloodOptions = [
  'RH+ A',
  'RH- A',
  'RH+ B',
  'RH- B',
  'RH+ O',
  'RH- O',
  'RH+ AB',
  'RH- AB',
];

const List<String> _smokingOptions = ['안 폈어요', '폈어요', '끊었어요'];

const List<String> _drinkingOptions = ['안 마셔요', '가끔 마셔요', '자주 마셔요'];

/// 보기가 셋뿐인 물음 — 한 줄에 네모 칸으로 늘어놓는다 (명세서 62).
class _ChoiceRow extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onPick;

  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _ChoiceBox(
                label: lifestyleLabel(options[i]),
                selected: selected == options[i],
                onTap: () => onPick(options[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 하나를 고르는 네모 칸. 고른 것만 파랗게 채운다 (명세서 62).
class _ChoiceBox extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceBox({
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
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.pointFill : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected ? null : kCardShadow,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.cardTitle(
                size: 19,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 눌러서 고르는 줄 — 값은 왼쪽, "고르기"는 오른쪽 (프로토타입 43번).
class _PickRow extends StatelessWidget {
  final String value;
  final bool empty;
  final VoidCallback onTap;

  /// 오른쪽 끝 아이콘. 굴림판은 아래 꺾쇠, 날짜만 달력이다.
  final IconData icon;

  const _PickRow({
    required this.value,
    required this.onTap,
    this.empty = false,
    this.icon = Icons.expand_more_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$value · 고르기',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kCardShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: AppText.cardTitle(
                      size: 21,
                      color: empty ? AppColors.chevron : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 26, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipEditor extends StatelessWidget {
  final Set<String> items;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _ChipEditor({
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          Semantics(
            button: true,
            label: '$item 빼기',
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: () => onRemove(item),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.pointRing,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item,
                        style: AppText.cardTitle(
                          size: 18,
                          color: AppColors.pointBorder,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppColors.pointBorder,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          button: true,
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: onAdd,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.sunken,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text('더 넣기', style: AppText.cardTitle(size: 18)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 칩을 고르는 창. 검색해서 고르거나 없는 것은 직접 적어 넣는다.
///
/// 고른 것은 제 안에만 쌓아 두었다가 닫힐 때 한 번에 돌려준다. 입력칸도
/// 제 것이라 제 `dispose`에서 함께 버린다.
class _PickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final Set<String> initial;

  const _PickerSheet({
    required this.title,
    required this.options,
    required this.initial,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String option) {
    setState(() {
      if (!_selected.remove(option)) _selected.add(option);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final filtered = widget.options
        .where((option) => query.isEmpty || option.contains(query))
        .toList();
    final canAddCustom =
        query.isNotEmpty &&
        !widget.options.contains(query) &&
        !_selected.contains(query);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.title, style: AppText.cardTitle(size: 20)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(_selected),
                      child: Text(
                        '완료',
                        style: AppText.cardTitle(size: 20, color: kPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: AppText.body(size: 19),
                  decoration: InputDecoration(
                    hintText: '검색하거나 직접 추가',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: kBackground,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (canAddCustom)
                      ListTile(
                        leading: const Icon(
                          Icons.add_circle_outline,
                          color: kPrimary,
                        ),
                        title: Text("'$query' 직접 추가"),
                        onTap: () {
                          setState(() {
                            _selected.add(query);
                            _search.clear();
                          });
                        },
                      ),
                    // 저장돼 있던 값이 보기에 없으면 그것도 목록에 보인다.
                    for (final option in {
                      ...filtered,
                      ..._selected.where(
                        (item) => query.isEmpty || item.contains(query),
                      ),
                    })
                      CheckboxListTile(
                        value: _selected.contains(option),
                        activeColor: kPrimary,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(option),
                        onChanged: (_) => _toggle(option),
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
}
