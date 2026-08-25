import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../../core/constants/app_colors.dart';
import 'patient_data.dart';
import 'patient_link_screen.dart';

/// 내 정보 상세·수정 화면.
/// isGuardian = true 면 건강정보(키·몸무게·혈액형·임신·흡연·음주·알레르기·질환·
/// 과거력·가족력)를 모두 숨긴다. 보호자는 모니터링 전용이라 본인 건강정보가 없다.
/// 위치: lib/features/dashboard/presentation/screens/profile_edit_screen.dart
class ProfileEditScreen extends StatefulWidget {
  final bool isGuardian;
  const ProfileEditScreen({super.key, this.isGuardian = false});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  // TODO: 실제 로그인 세션/백엔드 값으로 초기화
  final _name = TextEditingController(text: '김복자');
  final _phone = TextEditingController(text: '010-1234-5678');
  final _height = TextEditingController(text: '158');
  final _weight = TextEditingController(text: '60');

  DateTime? _birth = DateTime(1953, 4, 10);
  String? _gender = 'F';
  String? _blood = 'RH+ A';
  String? _pregnancy = '계획 없음';
  String? _smoking = '아니요';
  String? _drinking = '거의 안 마심';
  final Set<String> _allergens = {'페니실린'};
  final Set<String> _diseases = {'고혈압', '당뇨'};
  bool? _pastYes = false;
  bool? _familyYes = true;

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
    // 보호자는 본인 정보 기본값을 보호자용으로
    if (widget.isGuardian) {
      _name.text = '김지안';
      _phone.text = '010-9876-5432';
      _birth = DateTime(1985, 7, 22);
      _gender = 'F';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// 아바타는 이모지 대신 이름 첫 글자를 쓴다.
  /// 이모지는 기기마다 모양이 달라지고 의미 학습이 되지 않는다.
  String _avatarInitial() {
    final name = _name.text.trim();
    return name.isEmpty ? '님' : name.substring(0, 1);
  }

  void _save() {
    // TODO: 백엔드 프로필 수정 API 연동.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('저장되었습니다'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).maybePop();
  }

  void _confirmUnlink(String name) {
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
              // TODO: 백엔드 환자 연결 해제 API 연동.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$name님 연결 해제 (준비 중)'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
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
                            for (final o in filtered)
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
    final accent = _isGuardian ? kGuardian : kPrimary;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        foregroundColor: kText,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '내 정보',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                      '${DemoPatients.all.length}명',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kGuardian,
                      ),
                    ),
                  ],
                ),
                for (final p in DemoPatients.all) ...[
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
                              p.initial,
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
                                '${p.name} · ${p.relation}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: kText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${p.age}세',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: kTextSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 연결 해제 (데모: 안내만)
                        TextButton(
                          onPressed: () => _confirmUnlink(p.name),
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
                    MaterialPageRoute(
                      builder: (_) => const PatientLinkScreen(),
                    ),
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
                        keyboard: TextInputType.number,
                        suffixText: 'cm',
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        _weight,
                        hint: '몸무게',
                        keyboard: TextInputType.number,
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
                _yesNo(
                  _familyYes,
                  (v) => setState(() => _familyYes = v),
                  accent,
                ),
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
                  onPressed: _save,
                  child: const Text(
                    '저장하기',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
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
    String? suffixText,
    int lines = 1,
    Color accent = kPrimary,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
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
