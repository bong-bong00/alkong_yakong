import 'dart:math';

class HrvCalculator {
  // 기획서 기준: 300ms ~ 1500ms 사이의 정상 PPI만 필터링 
  List<int> filterPpi(List<int> rawPpiList) {
    return rawPpiList.where((ppi) => ppi >= 300 && ppi <= 1500).toList();
  }

  // RMSSD (Root Mean Square of Successive Differences) 계산 함수 
  double calculateRmssd(List<int> filteredPpiList) {
    if (filteredPpiList.length < 2) return 0.0;

    double sumOfSquares = 0.0;
    for (int i = 0; i < filteredPpiList.length - 1; i++) {
      int diff = filteredPpiList[i + 1] - filteredPpiList[i];
      sumOfSquares += diff * diff;
    }

    double meanSquare = sumOfSquares / (filteredPpiList.length - 1);
    return sqrt(meanSquare);
  }
}
