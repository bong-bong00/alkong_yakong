import 'dart:async';

import 'package:flutter/material.dart';
import '../../../medication/application/medication_controller.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/family_request_sheet.dart';
import '../../../../core/widgets/senior_card.dart';
import '../../../../core/widgets/senior_header.dart';

/// 어떤 방법으로 약을 넣을지.
enum AddMedicineMethod { camera, gallery, manual, family }

/// 07 · 약 넣기 · 방법 고르기.
///
/// **어두운 카메라 화면 위에 선택지를 얹지 않는다.**
/// 밝은 화면에서 고르는 일만 먼저 끝내고, 카메라는 찍기만 한다.
class AddMedicineScreen extends StatefulWidget {
  final void Function(AddMedicineMethod method) onPick;
  final String guardianTitle;

  /// 부탁을 마친 뒤 오늘 화면으로 돌아가는 길.
  final VoidCallback? onGoHome;

  /// 이미 부탁을 마치고 들어왔는지. 첫 사용 화면에서 넘어올 때 true다.
  final bool familyAsked;

  const AddMedicineScreen({
    super.key,
    required this.onPick,
    this.guardianTitle = '',
    this.onGoHome,
    this.familyAsked = false,
  });

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  /// 가족에게 부탁했는지. 화면을 옮기지 않고 자리에서 카드로 바뀐다.
  late bool _asked = widget.familyAsked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '처방전 넣기'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '어떻게 ',
                            style: AppText.screenTitle(
                              size: 26,
                            ).copyWith(fontWeight: FontWeight.w500),
                          ),
                          TextSpan(
                            text: '넣을까요?',
                            style: AppText.screenTitle(size: 26),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 가장 쉬운 길 하나만 파란 면으로 크게 둔다.
                  _PrimaryWay(
                    icon: TablerIcons.camera,
                    label: '사진 찍기',
                    sub: '가장 쉽고 빨라요',
                    onTap: () => widget.onPick(AddMedicineMethod.camera),
                  ),
                  const SizedBox(height: 16),
                  // 나머지 길은 가로를 다 쓰는 긴 칸으로 쌓는다.
                  _SmallWay(
                    icon: TablerIcons.photo,
                    label: '앨범에서 고르기',
                    onTap: () => widget.onPick(AddMedicineMethod.gallery),
                  ),
                  const SizedBox(height: 12),
                  _SmallWay(
                    icon: TablerIcons.pencil,
                    label: '손으로 적기',
                    onTap: () => widget.onPick(AddMedicineMethod.manual),
                  ),
                  if (!_asked) ...[
                    const SizedBox(height: 12),
                    _SmallWay(
                      icon: TablerIcons.users,
                      label: '가족에게 부탁하기',
                      onTap: () {
                        setState(() => _asked = true);
                        unawaited(
                          showFamilyRequestSheet(
                            context,
                            guardianTitle: resolveGuardianTitle(
                              context,
                              widget.guardianTitle,
                            ),
                          ),
                        );
                        widget.onPick(AddMedicineMethod.family);
                      },
                    ),
                  ],
                  if (_asked) ...[
                    const SizedBox(height: 12),
                    _AskedCard(
                      guardianTitle: resolveGuardianTitle(
                        context,
                        widget.guardianTitle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 가장 쉬운 길 하나. 이 화면에서 파란 면은 여기뿐이다.
class _PrimaryWay extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _PrimaryWay({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $sub',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 128),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.pointFill,
              borderRadius: BorderRadius.circular(26),
              boxShadow: kAccentShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.pointPressed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 34, color: Colors.white),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppText.cardTitle(size: 24, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: AppText.body(
                          size: 18,
                          color: AppColors.pointRing,
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
}

/// 나머지 길. 작은 칸 셋이 나란히 선다.
class _SmallWay extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallWay({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: kCardShadow,
            ),
            child: Row(
              children: [
                Icon(icon, size: 28, color: AppColors.textPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: AppText.cardTitle(size: 21)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 부탁하고 나면 화면을 옮기지 않고 이 카드로 바뀐다.
/// 어르신은 아무것도 더 하지 않아도 된다.
class _AskedCard extends StatelessWidget {
  final String guardianTitle;

  const _AskedCard({required this.guardianTitle});

  @override
  Widget build(BuildContext context) {
    return SeniorCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pointTint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const ExcludeSemantics(
                  child: Icon(
                    TablerIcons.check,
                    size: 28,
                    color: AppColors.point,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$guardianTitle에게 부탁했어요',
                      style: AppText.cardTitle(size: 21),
                    ),
                    Text(
                      '$guardianTitle이 처방전을 넣으면 '
                      '이 화면에 약이 나타납니다',
                      style: AppText.caption(size: 17.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
