import 'package:flutter/material.dart';
import '../../../../core/widgets/senior_header.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/senior_feedback.dart';
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
    _smoking = user.smoking;
    _drinking = user.drinking;
    _allergens
      ..clear()
      ..addAll(user.allergies);
    _diseases
      ..clear()
      ..addAll(user.diseases);
    _pastYes = user.pastHistory;
    _familyYes = user.familyHistory;
  }

  static String _numberText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  /// 아바타는 이모지 대신 이름 첫 글자를 쓴다.
  /// 이모지는 기기마다 모양이 달라지고 의미 학습이 되지 않는다.
  String _avatarInitial() {
    final name = _name.text.trim();
    return name.isEmpty ? '님' : name.substring(0, 1);
  }

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
                color: Color(0xFFE24B4A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 한글 년/월/일 휠 선택기
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
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kPrimary,
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

  // 칩 + 검색 추가 시트
  Future<void> _openPicker(
    String title,
    Set<String> selected,
    List<String> options,
  ) async {
    final searchCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = searchCtrl.text.trim();
            final filtered = options
                .where((o) => q.isEmpty || o.contains(q))
                .toList();
            final canAddCustom =
                q.isNotEmpty && !options.contains(q) && !selected.contains(q);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: kText,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: const Text(
                                '완료',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: kPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: searchCtrl,
                          onChanged: (_) => setSheet(() {}),
                          decoration: InputDecoration(
                            hintText: '검색하거나 직접 입력',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: kBackground,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                            ),
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
                                title: Text("'$q' 직접 추가"),
                                onTap: () {
                                  setState(() => selected.add(q));
                                  searchCtrl.clear();
                                  setSheet(() {});
                                },
                              ),
                            // 저장돼 있던 값이 보기에 없으면 그것도 목록에 보인다.
                            for (final o in {...filtered, ...selected.where(
                              (s) => q.isEmpty || s.contains(q),
                            )})
                              CheckboxListTile(
                                value: selected.contains(o),
                                activeColor: kPrimary,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(o),
                                onChanged: (_) {
                                  setState(() {
                                    if (selected.contains(o)) {
                                      selected.remove(o);
                                    } else {
                                      selected.add(o);
                                    }
                                  });
                                  setSheet(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
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
            const SeniorBackHeader(title: '내 정보'),
            Expanded(child: _original == null ? _buildLoading() : _buildForm(accent)),
          ],
        )
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 나이·성별 아바타 ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _isGuardian ? kGuardianLight : kPrimaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _avatarInitial(),
                      style: const TextStyle(fontSize: 44),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _name.text.isEmpty ? '이름' : _name.text,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                if (_isGuardian) ...[
                  const SizedBox(height: 4),
                  Text(
                    '보호자',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kGuardian,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          _section('이름'),
          _field(_name, hint: '이름', accent: accent),
          const SizedBox(height: 18),

          _section('휴대폰번호'),
          _field(
            _phone,
            hint: '010-0000-0000',
            keyboard: TextInputType.phone,
            formatter: PhoneNumberFormatter(),
            accent: accent,
          ),
          const SizedBox(height: 18),

          _section('생년월일'),
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
          const SizedBox(height: 18),

          _section('성별'),
          Row(
            children: [
              Expanded(
                child: _pill(
                  '남성',
                  _gender == 'M',
                  () => setState(() => _gender = 'M'),
                  accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pill(
                  '여성',
                  _gender == 'F',
                  () => setState(() => _gender = 'F'),
                  accent,
                ),
              ),
            ],
          ),

          // ══════════════════════════════════════════════
          //  연결된 환자 관리 — 보호자만
          // ══════════════════════════════════════════════
          if (_isGuardian) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                _section('연결된 환자'),
                const Spacer(),
                Text(
                  '${ref.watch(careOverviewProvider).valueOrNull?.patients.length ?? 0}명',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kGuardian,
                  ),
                ),
              ],
            ),
            for (final p
                in ref.watch(careOverviewProvider).valueOrNull?.patients ??
                    const <CarePatient>[]) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kGuardianLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          p.name.isEmpty ? '님' : p.name.substring(0, 1),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: kText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.age == null ? '나이 정보 없음' : '${p.age}세',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: kTextSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _confirmUnlink(p),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE24B4A),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                      ),
                      child: const Text(
                        '연결 해제',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kGuardian,
                side: BorderSide(color: kGuardian.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PatientLinkScreen()),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                '환자 연결하기',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],

          // ══════════════════════════════════════════════
          //  건강정보 — 환자만 (보호자는 전부 숨김)
          // ══════════════════════════════════════════════
          if (!_isGuardian) ...[
            const SizedBox(height: 18),
            _section('키 / 몸무게'),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _height,
                    hint: '키',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    suffixText: 'cm',
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _weight,
                    hint: '몸무게',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    suffixText: 'kg',
                    accent: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _section('혈액형'),
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
              accent,
            ),
            const SizedBox(height: 8),

            if (_gender == 'F') ...[
              _section('임신 상태'),
              _grid(
                const ['계획 없음', '임신 준비중', '임신 중', '수유 중'],
                _pregnancy,
                (v) => setState(() => _pregnancy = v),
                accent,
              ),
              const SizedBox(height: 8),
            ],

            _section('흡연'),
            _vlist(
              const ['아니요', '예', '과거에 폈지만 끊었어요'],
              _smoking,
              (v) => setState(() => _smoking = v),
              accent,
            ),
            const SizedBox(height: 18),

            _section('음주'),
            _grid(
              const ['거의 안 마심', '주 1~2일', '주 3~4일', '주 5~7일'],
              _drinking,
              (v) => setState(() => _drinking = v),
              accent,
            ),
            const SizedBox(height: 8),

            _section('약물 알레르기'),
            _chipEditor(
              _allergens,
              '알레르기 추가',
              () => _openPicker('약물 알레르기', _allergens, _allergyOptions),
            ),
            const SizedBox(height: 20),

            _section('현재 질환 / 만성질환'),
            _chipEditor(
              _diseases,
              '질환 추가',
              () => _openPicker('현재 질환', _diseases, _diseaseOptions),
            ),
            const SizedBox(height: 20),

            _section('과거력'),
            _yesNo(_pastYes, (v) => setState(() => _pastYes = v), accent),
            const SizedBox(height: 18),

            _section('가족력'),
            _yesNo(_familyYes, (v) => setState(() => _familyYes = v), accent),
          ],

          const SizedBox(height: 28),

          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? '저장하는 중...' : '저장하기',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 공통 위젯 ─────────────────────────────────────────────
  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 2),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: kText,
      ),
    ),
  );

  Widget _field(
    TextEditingController c, {
    String? hint,
    TextInputType? keyboard,
    TextInputFormatter? formatter,
    String? suffixText,
    int lines = 1,
    Color accent = kPrimary,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      inputFormatters: formatter == null ? null : [formatter],
      maxLines: lines,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
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
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.grey[300]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? accent : kText,
          ),
        ),
      ),
    );
  }

  // 선택된 항목 = 삭제 가능한 칩, + 추가 버튼
  Widget _chipEditor(Set<String> items, String addLabel, VoidCallback onAdd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final it in items)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
                    decoration: BoxDecoration(
                      color: kPrimaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          it,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: kPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => items.remove(it)),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            addLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _grid(
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect,
    Color accent,
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
                    accent,
                  ),
                ),
                const SizedBox(width: 12),
                if (i + 1 < options.length)
                  Expanded(
                    child: _pill(
                      options[i + 1],
                      selected == options[i + 1],
                      () => onSelect(options[i + 1]),
                      accent,
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
    Color accent,
  ) {
    return Column(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: _pill(o, selected == o, () => onSelect(o), accent),
            ),
          ),
      ],
    );
  }

  Widget _yesNo(bool? value, ValueChanged<bool> onSelect, Color accent) {
    return Row(
      children: [
        Expanded(
          child: _pill('아니요', value == false, () => onSelect(false), accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _pill('예', value == true, () => onSelect(true), accent),
        ),
      ],
    );
  }
}
