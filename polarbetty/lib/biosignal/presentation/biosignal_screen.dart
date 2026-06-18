// lib/biosignal/presentation/biosignal_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'biosignal_notifier.dart';

class BiosignalScreen extends ConsumerWidget {
  const BiosignalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(biosignalProvider);

    // 의학적 비정상치 지속 상태 감지 시 UI 알림 에스컬레이션
    if (state.isAnomalyDetected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text(
              "⚠️ 약물 이상 반응 경고",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "안정 상태에서 고심박수 증상이 지속되었습니다.\n",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                state.isAnalyzing
                    ? const Center(child: CircularProgressIndicator())
                    : Text("임상적 분석 결과:\n${state.aiReport}"),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(biosignalProvider.notifier).stopMonitoring();
                  Navigator.of(context).pop();
                },
                child: const Text("확인"),
              ),
            ],
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text("알콩약콩 생체 신호 분석")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              elevation: 4,
              color: state.isMoving
                  ? Colors.orange.shade50
                  : Colors.green.shade50,
              child: ListTile(
                leading: const Icon(Icons.directions_run),
                title: const Text("현재 신체 활동 상태"),
                trailing: Text(
                  state.isMoving ? "운동/움직임 중" : "안정 상태 (모니터링 유효)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: state.isMoving ? Colors.orange : Colors.green,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text("실시간 심박수"),
                          Text(
                            "${state.currentHr} BPM",
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text("HRV (RMSSD)"),
                          Text(
                            "${state.currentRmssd.toStringAsFixed(1)} ms",
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => ref
                      .read(biosignalProvider.notifier)
                      .startMonitoring("SAMPLE_ID_123"),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("모니터링 시작"),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(biosignalProvider.notifier).stopMonitoring(),
                  icon: const Icon(Icons.stop),
                  label: const Text("종료"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
