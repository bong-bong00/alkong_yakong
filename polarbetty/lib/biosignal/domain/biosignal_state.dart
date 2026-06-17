// lib/biosignal/domain/biosignal_state.dart
class BiosignalState {
  final int currentHr;
  final double currentRmssd;
  final bool isMoving;
  final bool isAnomalyDetected;
  final String aiReport;
  final bool isAnalyzing;

  BiosignalState({
    this.currentHr = 0,
    this.currentRmssd = 0.0,
    this.isMoving = false,
    this.isAnomalyDetected = false,
    this.aiReport = "",
    this.isAnalyzing = false,
  });

  BiosignalState copyWith({
    int? currentHr,
    double? currentRmssd,
    bool? isMoving,
    bool? isAnomalyDetected,
    String? aiReport,
    bool? isAnalyzing,
  }) {
    return BiosignalState(
      currentHr: currentHr ?? this.currentHr,
      currentRmssd: currentRmssd ?? this.currentRmssd,
      isMoving: isMoving ?? this.isMoving,
      isAnomalyDetected: isAnomalyDetected ?? this.isAnomalyDetected,
      aiReport: aiReport ?? this.aiReport,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }
}
