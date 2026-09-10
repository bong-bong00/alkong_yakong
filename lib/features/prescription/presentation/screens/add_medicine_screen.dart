import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/senior_button.dart';
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
    this.guardianTitle = '딸 지안 님',
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
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '약 넣기'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pointTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '어떻게 넣을까요?',
                          style: AppText.cardTitle(
                            size: 22,
                            color: AppColors.point,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '하나만 고르시면 됩니다. 나머지는 나중에도 할 수 있어요.',
                          style: AppText.body(
                            size: 17.5,
                            color: AppColors.pointInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SeniorChoiceCard(
                    icon: TablerIcons.camera,
                    title: '처방전 사진 찍기',
                    description: '약 이름을 대신 읽어 드려요',
                    primary: true,
                    onPressed: () => widget.onPick(AddMedicineMethod.camera),
                  ),
                  const SizedBox(height: 12),
                  SeniorChoiceCard(
                    icon: TablerIcons.photo,
                    title: '앨범에서 고르기',
                    description: '이미 찍어 둔 사진이 있을 때',
                    onPressed: () => widget.onPick(AddMedicineMethod.gallery),
                  ),
                  const SizedBox(height: 12),
                  SeniorChoiceCard(
                    icon: TablerIcons.edit,
                    title: '손으로 적기',
                    description: '처방전이 없어도 됩니다',
                    onPressed: () => widget.onPick(AddMedicineMethod.manual),
                  ),
                  const SizedBox(height: 12),
                  if (_asked)
                    _AskedCard(
                      guardianTitle: widget.guardianTitle,
                      onGoHome: widget.onGoHome,
                    )
                  else
                    SeniorChoiceCard(
                      icon: TablerIcons.users,
                      title: '가족에게 부탁하기',
                      description: '${widget.guardianTitle}이 대신 넣어 줘요',
                      onPressed: () {
                        setState(() => _asked = true);
                        widget.onPick(AddMedicineMethod.family);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 부탁하고 나면 화면을 옮기지 않고 이 카드로 바뀐다.
/// 어르신은 아무것도 더 하지 않아도 된다.
class _AskedCard extends StatelessWidget {
  final String guardianTitle;
  final VoidCallback? onGoHome;

  const _AskedCard({required this.guardianTitle, this.onGoHome});

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
          const SizedBox(height: 14),
          SeniorButton(
            label: '오늘 화면으로 가기',
            kind: SeniorButtonKind.secondary,
            minHeight: 66,
            fontSize: 21,
            onPressed: onGoHome ?? () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
