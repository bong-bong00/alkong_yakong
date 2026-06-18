import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// 보호자 ↔ 환자 연동 화면.
/// 보호자가 환자의 휴대폰번호(또는 연동 코드)로 연결을 요청한다.
/// 위치: lib/features/dashboard/presentation/screens/patient_link_screen.dart
class PatientLinkScreen extends StatefulWidget {
  const PatientLinkScreen({super.key});

  @override
  State<PatientLinkScreen> createState() => _PatientLinkScreenState();
}

class _PatientLinkScreenState extends State<PatientLinkScreen> {
  final _phone = TextEditingController();
  String? _relation; // 자녀 | 배우자 | 부모 | 형제자매 | 기타
  bool _requested = false;

  static const _relations = ['자녀', '배우자', '부모', '형제자매', '기타'];

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
  );

  void _sendRequest() {
    if (_phone.text.trim().isEmpty) {
      _toast('환자의 휴대폰번호를 입력해주세요');
      return;
    }
    if (_relation == null) {
      _toast('환자와의 관계를 선택해주세요');
      return;
    }
    // TODO: 백엔드 연동 요청 API. 환자에게 승인 알림을 보낸다.
    setState(() => _requested = true);
  }

  @override
  Widget build(BuildContext context) {
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
          '환자 연결',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: _requested ? _doneView() : _formView()),
    );
  }

  // ── 입력 화면 ──
  Widget _formView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kGuardianLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Center(
                child: Icon(Icons.link_rounded, color: kGuardian, size: 36),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '돌봐드릴 환자를 연결해주세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '환자의 휴대폰번호로 연결을 요청하면,\n환자가 수락한 뒤 복약 현황을 볼 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),

          _label('환자 휴대폰번호'),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '010-0000-0000',
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: kGuardian, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _label('환자와의 관계'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _relations)
                GestureDetector(
                  onTap: () => setState(() => _relation = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: _relation == r
                          ? kGuardian.withValues(alpha: 0.10)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _relation == r ? kGuardian : Colors.grey[300]!,
                        width: _relation == r ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      r,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _relation == r ? kGuardian : kText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),

          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kGuardian,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _sendRequest,
              child: const Text(
                '연결 요청 보내기',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '연동 코드로 연결하기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 요청 완료 화면 ──
  Widget _doneView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kGuardianLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.send_rounded, color: kGuardian, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '연결 요청을 보냈어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_phone.text} 님에게 요청을 보냈어요.\n환자가 수락하면 복약 현황을 볼 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kGuardian,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text(
                '확인',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
    ),
  );
}
