import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../mode/app_mode.dart';
import '../theme/app_typography.dart';
import 'senior_card.dart';

/// 헤더 오른쪽의 모드 배지.
///
/// 오늘 · 기록 · 내 정보 세 탭 헤더에 모두 있다. 누르면 모드가 바뀐다.
/// 배지가 **지금 어느 화면인지**를 말하고, 누르면 반대쪽으로 간다.
class ModeBadge extends ConsumerWidget {
  const ModeBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final easy = ref.watch(appModeProvider).isEasy;
    return Semantics(
      button: true,
      label: easy ? '쉬운 화면. 누르면 일반 화면으로 바뀝니다' : '일반 화면. 누르면 쉬운 화면으로 바뀝니다',
      child: GestureDetector(
        onTap: () => ref.read(appModeProvider.notifier).toggle(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: kCardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                size: 22,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 7),
              // 글자 배율을 크게 키운 기기에서는 라벨이 줄어든다.
              // 배지가 헤더를 밀어내면 날짜와 이름이 잘린다.
              Flexible(
                child: Text(
                  easy ? '일반 화면으로' : '쉬운 화면으로',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(size: 17),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
