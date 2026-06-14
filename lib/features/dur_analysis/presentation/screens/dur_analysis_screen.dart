import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';

class DurAnalysisScreen extends StatefulWidget {
  const DurAnalysisScreen({super.key});

  @override
  State<DurAnalysisScreen> createState() => _DurAnalysisScreenState();
}

class _DurAnalysisScreenState extends State<DurAnalysisScreen> {
  final _apiClient = ApiClient();
  late final TextEditingController _userIdController;

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _analysis;
  Map<String, dynamic>? _latest;

  @override
  void initState() {
    super.initState();
    _userIdController = TextEditingController(text: MvpSession.userId);
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      setState(() => _errorMessage = '사용자 ID를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _analysis = null;
      _latest = null;
    });

    try {
      final analysisResponse = await _apiClient.post(
        '/api/v1/dur/analyze',
        body: {'user_id': userId, 'medicine_codes': <String>[]},
      );
      final latestResponse = await _apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(userId)}/dur/latest',
      );
      if (!mounted) return;
      setState(() {
        _analysis = Map<String, dynamic>.from(analysisResponse as Map);
        _latest = Map<String, dynamic>.from(latestResponse as Map);
      });
      MvpSession.userId = userId;
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.statusCode == 400
            ? '분석할 복용 약이 없습니다. 먼저 처방전 Mock OCR을 등록해주세요.'
            : _apiError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '응답 처리 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _analysis?['matches'] is List
        ? _analysis!['matches'] as List
        : const <dynamic>[];
    final riskLevel = _text(_analysis?['risk_level'] ?? _latest?['risk_level']);
    final analyzedAt = _text(_latest?['created_at']);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 안전도'), backgroundColor: kPrimary),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: '사용자 ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _analyze,
                  icon: _isLoading
                      ? const _ButtonProgress()
                      : const Icon(Icons.health_and_safety_outlined),
                  label: Text(_isLoading ? '분석 중...' : 'DUR 분석 실행'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                _StatusCard(
                  title: '분석 실패',
                  value: _errorMessage!,
                  color: Colors.red,
                ),
              ],
              if (_analysis != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatusCard(
                        title: '위험도',
                        value: riskLevel,
                        color: _riskColor(riskLevel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatusCard(
                        title: '분석 시각',
                        value: analyzedAt,
                        color: kPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '충돌 ${matches.length}건',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 10),
                if (matches.isEmpty)
                  const _StatusCard(
                    title: '분석 결과',
                    value: '현재 DUR 기준에서 발견된 성분 충돌이 없습니다.',
                    color: kPrimary,
                  )
                else
                  ...matches.map((item) {
                    final match = item is Map
                        ? Map<String, dynamic>.from(item)
                        : <String, dynamic>{};
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StatusCard(
                        title:
                            '${_text(match['ingredient_a'])} + ${_text(match['ingredient_b'])}',
                        value: _text(match['description']),
                        color: Colors.orange,
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('원본 응답 보기'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(_analysis),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatusCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(height: 1.4, color: kText)),
        ],
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

String _text(dynamic value, {String fallback = '데이터 없음'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _apiError(ApiException error) {
  return error.statusCode == null
      ? error.message
      : '${error.message} (HTTP ${error.statusCode})';
}

Color _riskColor(String riskLevel) {
  return switch (riskLevel.toUpperCase()) {
    'CRITICAL' || 'HIGH' => Colors.red,
    'WARNING' || 'CAUTION' => Colors.orange,
    _ => kPrimary,
  };
}
