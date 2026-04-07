import 'package:flutter/material.dart';
// [참조] 상태 관리를 위한 리버팟 라이브러리
import 'package:flutter_riverpod/flutter_riverpod.dart';
// [참조] 경로에 맞춰 분리된 홈 화면 가져오기
import 'features/dashboard/presentation/screens/home_screen.dart';

// ════════════════════════════════════════════════════
//  [앱시작] ProviderScope로 감싸 리버팟 사용 가능하게 설정
// ════════════════════════════════════════════════════
void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // [앱-제목]
      title: '알콩약콩',
      // [앱-디버그배너] 우측 상단 디버그 띠 숨김
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // [앱-메인컬러] 0xFF1D9E75 (민트초록) 기반으로 테마 생성
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D9E75),
        ),
        useMaterial3: true,
      ),
      // [앱-첫화면] 에러 원인 해결: MainScreen -> HomeScreen으로 수정
      home: const HomeScreen(),
    );
  }
}