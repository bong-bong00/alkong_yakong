import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../dashboard/presentation/screens/patient_data.dart';
import '../../../guardian/application/guardians_provider.dart';
import '../../../guardian/data/guardian_repository.dart';
import '../../../guardian/data/proxy_signup_repository.dart';
import '../../../guardian/domain/proxy_signup.dart';
import '../../../dashboard/presentation/screens/guardian_home_screen.dart';
import '../../../guardian/data/alert_repository.dart';
import '../../../guardian/presentation/screens/proxy_patient_picker_screen.dart';
import '../../../guardian/presentation/screens/proxy_signup_screen.dart';
import '../../../medicines/domain/user_medicine_models.dart';
import '../../../medicines/presentation/screens/family_added_medicines_screen.dart';
import '../../../prescription/domain/proxy_target.dart';
import '../../../dur_analysis/presentation/screens/dur_analysis_screen.dart';
import '../../../prescription/presentation/screens/add_medicine_screen.dart';
import '../../../prescription/presentation/screens/manual_medicine_screen.dart';
import '../../../prescription/presentation/screens/prescription_screen.dart';
import '../../../profile/application/current_user_controller.dart';
import '../../../profile/domain/user_profile.dart';

/// 개발용 — 서버 없이 화면만 눈으로 보는 목록.
///
/// **여기 있는 값은 전부 지어낸 것이다.** 앱의 다른 어떤 화면도 이 파일을
/// 쓰지 않는다. 서버를 못 읽었을 때 진짜 화면이 가짜 값을 보여주는 일은
/// 없어야 하기 때문에, 가짜 값은 이 한 파일에 가둬 두고 개발 빌드에서만
/// 들어오는 길을 낸다.
class ScreenPreviewScreen extends StatelessWidget {
  const ScreenPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <({String title, String note, Widget Function() build})>[
      (
        title: '처방전 넣기 (방법 고르기)',
        note: '어떻게 넣을까요? — 사진 찍기 · 앨범 · 손으로 적기 · 가족에게 부탁하기',
        build: () => AddMedicineScreen(onPick: (_) {}),
      ),
      (
        title: '처방전 찍기 (내 약)',
        note: '이렇게 찍어 주세요 세 단계. 사진 찍기·앨범 고르기는 진짜로 동작합니다.',
        build: () => const PrescriptionScreen(),
      ),
      (
        title: '약 함께먹기 주의',
        note: '부딪히는 두 약과 무슨 일이 생기는지. 서버 응답 대신 지어낸 값입니다.',
        build: () => DurAnalysisScreen(initialResult: _sampleDurResult()),
      ),
      (
        title: '가족이 대신 회원가입 (1/3 → 3/3)',
        note: '확인번호까지 기기 안에서 돌아갑니다. 계정 만들기도 지어낸 값으로 끝납니다.',
        build: () => ProxySignupScreen(
          repository: _SampleProxySignupRepository(),
          onCapturePrescription: (result) {},
        ),
      ),
      (
        title: '보호자 화면 (현황 · 알림 · 돌보는 분)',
        note: '탭 세 개를 모두 걸어볼 수 있습니다. 돌보는 분 세 분이 들어 있습니다.',
        build: () => const GuardianHomeScreen(),
      ),
      (
        title: '보호자 알림',
        note: '못 드심 · 복약 완료 · 새 처방전 · 심박수 네 가지가 들어 있습니다.',
        build: () => Scaffold(
          backgroundColor: AppColors.bg,
          body: GuardianAlertsTab(
            patient: _sampleOverview.patients.first,
            repository: _SampleAlertRepository(),
            onOpenStatus: () {},
          ),
        ),
      ),
      (
        title: '어느 분 처방전인가요?',
        note: '돌보는 분 세 분이 미리 들어 있습니다.',
        build: () => Builder(
          builder: (context) => ProxyPatientPickerScreen(
            onPick: (patient) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PrescriptionScreen(
                  proxyTarget: ProxyTarget(
                    patientId: patient.patientId,
                    title: patient.title,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      (
        title: '처방전 찍기 (대신 등록)',
        note: '맨 위에 파란 "어머니 · 김복자 대신 등록" 띠가 붙습니다.',
        build: () => const PrescriptionScreen(proxyTarget: _sampleTarget),
      ),
      (
        title: '이렇게 읽었어요 (대신 등록)',
        note: '띠 + 같은 약 카드. 바닥 버튼만 "어르신께 보내기"입니다.',
        build: () => PrescriptionScreen(
          proxyTarget: _sampleTarget,
          initialOcrResult: _sampleOcrResult(unreadName: '리나릴정'),
        ),
      ),
      (
        title: '이렇게 읽었어요 (내 약)',
        note: '주성분과 쉬운 설명이 있는 일반 카드입니다. 못 읽은 이름 시트도 함께 뜹니다.',
        build: () => PrescriptionScreen(
          initialOcrResult: _sampleOcrResult(unreadName: '리나릴정'),
        ),
      ),
      (
        title: '손으로 적기',
        note: '약 이름을 찾으면 칩으로 고릅니다. 찾기는 서버가 있어야 합니다.',
        build: () => const ManualMedicineScreen(),
      ),
      (
        title: '약이 들어왔어요 (어르신 화면)',
        note: '딸이 약 세 가지를 넣어준 직후 어르신에게 뜨는 화면입니다.',
        build: () => FamilyAddedMedicinesScreen(
          guardianName: '김지안',
          guardianRelation: '딸',
          medicines: _sampleMedicines,
          onOpenMedicines: () {},
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorTitleHeader(title: '화면 미리보기'),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              itemCount: entries.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == entries.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '개발용 화면입니다. 여기 보이는 이름·전화번호·약은 모두 지어낸 값이고, '
                      '서버에 아무것도 남기지 않습니다.',
                      style: AppText.caption(size: 17),
                    ),
                  );
                }
                final entry = entries[index];
                return SeniorCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _previewScope(entry.build()),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.title,
                              style: AppText.cardTitle(size: 21),
                            ),
                            const SizedBox(height: 4),
                            Text(entry.note, style: AppText.caption(size: 17)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const SeniorChevron(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 서버에서 오는 값만 지어낸 것으로 바꿔 끼운다. 화면 자체는 진짜 화면이다.
  static Widget _previewScope(Widget child) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(_SampleCurrentUser.new),
        careOverviewProvider.overrideWith((ref) async => _sampleOverview),
        guardiansProvider.overrideWith((ref) async => _sampleGuardians),
      ],
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  지어낸 값들
// ════════════════════════════════════════════════════════════════

const _sampleTarget = ProxyTarget(
  patientId: 'preview-patient',
  title: '어머니 · 김복자',
);

final _sampleGuardianProfile = UserProfile(
  id: 'preview-guardian',
  name: '김지안',
  role: 'guardian',
  phone: '010-1234-5678',
  gender: 'F',
);

const _sampleOverview = CareOverview(
  patients: [
    CarePatient(
      linkId: 'preview-link-1',
      patientId: 'preview-patient',
      name: '김복자',
      relation: '어머니',
      takenCount: 1,
      totalCount: 2,
      nextDoseLabel: '저녁 약',
    ),
    CarePatient(
      linkId: 'preview-link-2',
      patientId: 'preview-patient-2',
      name: '김성호',
      relation: '아버지',
      takenCount: 3,
      totalCount: 3,
    ),
    CarePatient(
      linkId: 'preview-link-3',
      patientId: 'preview-patient-3',
      name: '박영자',
      relation: '장모님',
      takenCount: 0,
      totalCount: 1,
      nextDoseLabel: '아침 약',
    ),
  ],
);

const _sampleGuardians = [
  GuardianContact(
    id: 'preview-link-1',
    name: '김지안',
    relation: '딸',
    phone: '010-1234-5678',
  ),
];

const _sampleMedicines = [
  UserMedicine(
    medicineCode: 'preview-1',
    displayName: '메트포르민 500mg',
    officialProductName: '메트포르민염산염정500mg',
    ingredientName: '메트포르민염산염',
    amount: '1정',
    administrationTimes: ['08:00', '20:00'],
  ),
  UserMedicine(
    medicineCode: 'preview-2',
    displayName: '암로디핀 5mg',
    officialProductName: '암로디핀베실산염정5mg',
    ingredientName: '암로디핀베실산염',
    amount: '1정',
    administrationTimes: ['20:00'],
  ),
  UserMedicine(
    medicineCode: 'preview-3',
    displayName: '아스피린 100mg',
    officialProductName: '아스피린장용정100mg',
    ingredientName: '아스피린',
    amount: '1정',
    administrationTimes: ['08:00'],
  ),
];

/// 함께먹기 확인을 마친 직후의 서버 응답 모양.
Map<String, dynamic> _sampleDurResult() => {
  'assessment_status': 'RISK_FOUND',
  'analysis_complete': true,
  'has_risk': true,
  'matches': [
    {
      'type': '병용금기',
      'medicine_names_a': ['아스피린'],
      'medicine_names_b': ['와파린'],
      'easy_line_a': '피를 묽게',
      'easy_line_b': '피를 묽게',
      'why_easy': '피가 너무 묽어질 수 있어요. 넘어지거나 베였을 때 피가 잘 멈추지 않습니다.',
      'source_label': '식약처 DUR 병용금기 참조',
    },
  ],
};

/// 처방전을 다 읽고 난 직후의 서버 응답 모양.
Map<String, dynamic> _sampleOcrResult({String? unreadName}) => {
  'hospital_name': '햇살내과의원',
  'pharmacy_name': '푸른약국',
  'prescribed_date': '2026-09-12',
  'items': [
    {
      'medicine_code': 'preview-1',
      'drug_name': '메트포르민 500mg',
      'ingredient_name': '메트포르민염산염',
      'dose_amount': '1',
      'dose_unit': '정',
      'frequency_per_day': 2,
      'duration_days': 30,
      'administration_times': ['08:00', '20:00'],
      'match_status': 'MATCHED',
      'easy_explanation': '핏속 당을 내려 주는 약이에요',
      'ocr_field_confidences': {'drug_name': 96},
    },
    {
      'medicine_code': 'preview-2',
      'drug_name': '암로디핀 5mg',
      'ingredient_name': '암로디핀베실산염',
      'dose_amount': '1',
      'dose_unit': '정',
      'frequency_per_day': 1,
      'duration_days': 30,
      'administration_times': ['20:00'],
      'match_status': 'MATCHED',
      'easy_explanation': '혈압을 내려 주는 약이에요',
      'ocr_field_confidences': {'drug_name': 94},
    },
    {
      'medicine_code': 'preview-3',
      'drug_name': '아스피린 100mg',
      'ingredient_name': '아스피린',
      'dose_amount': '1',
      'dose_unit': '정',
      'frequency_per_day': 1,
      'duration_days': 30,
      'administration_times': ['08:00'],
      'match_status': 'REVIEW_REQUIRED',
      // 프로토타입의 "글씨가 흐려서 확실하지 않아요" 카드.
      'uncertain': true,
      'easy_explanation': '피를 묽게 해 주는 약이에요',
      'ocr_field_confidences': {'drug_name': 61},
    },
  ],
  'unrecognized_names': <String>[?unreadName],
};

/// 지어낸 알림 네 줄.
class _SampleAlertRepository extends AlertRepository {
  @override
  Future<List<AlertItem>?> fetch(String userId) async => const [
    AlertItem(
      type: 'miss',
      title: '약을 안 드셨어요',
      desc: '어머니가 저녁 약을 드시지 않았어요',
      time: '어제 저녁',
    ),
    AlertItem(
      type: 'done',
      title: '복약 완료',
      desc: '어머니가 점심 약을 드셨어요',
      time: '오늘 12:10',
    ),
    AlertItem(
      type: 'prescription',
      title: '새 처방전',
      desc: '약 3가지가 새로 등록됐어요',
      time: '어제',
    ),
    AlertItem(
      type: 'past',
      title: '심박수',
      desc: '일주일 동안 모두 정상이었어요',
      time: '3일 전',
    ),
  ];
}

/// 서버에 아무것도 보내지 않고 계정이 만들어진 척한다.
class _SampleProxySignupRepository extends ProxySignupRepository {
  @override
  Future<ProxySignupResult> createAccount({
    required ProxyElderDraft draft,
    required ProxyVerification verification,
    UserProfile? guardian,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ProxySignupResult(
      patientId: 'preview-patient',
      name: draft.name,
      phone: draft.phone,
      relation: draft.relation,
      initialPassword: verification.code,
      guardianLinked: true,
    );
  }
}

class _SampleCurrentUser extends CurrentUserController {
  @override
  Future<UserProfile?> build() async => _sampleGuardianProfile;
}
