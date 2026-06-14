import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _apiClient = ApiClient();
  late final TextEditingController _userIdController;

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _dashboard;

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

  Future<void> _refreshDashboard() async {
    var userId = _userIdController.text.trim();
    if (userId.isEmpty && MvpSession.userId.isNotEmpty) {
      userId = MvpSession.userId;
      _userIdController.text = userId;
    }
    if (userId.isEmpty) {
      setState(() => _errorMessage = '사용자 ID를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(userId)}/dashboard',
      );
      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(response as Map);
      });
      MvpSession.userId = userId;
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _apiError(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '응답 처리 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final medication = _asMap(_dashboard?['medication_summary']);
    final schedules = medication?['schedules'] is List
        ? medication!['schedules'] as List
        : const <dynamic>[];
    final risk = _asMap(_dashboard?['latest_risk']);
    final prescription = _asMap(_dashboard?['latest_prescription']);
    final event = _asMap(_dashboard?['latest_abnormal_event']);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('복약 기록'), backgroundColor: kPrimary),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _userIdController,
                decoration: const InputDecoration(
                  labelText: '사용자 ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _refreshDashboard,
                icon: _isLoading
                    ? const _ButtonProgress()
                    : const Icon(Icons.refresh),
                label: Text(_isLoading ? '불러오는 중...' : '대시보드 새로고침'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _DashboardCard(
                  title: '조회 실패',
                  value: _errorMessage!,
                  icon: Icons.error_outline,
                  color: Colors.red,
                ),
              ],
              if (_dashboard == null && _errorMessage == null) ...[
                const SizedBox(height: 16),
                const _DashboardCard(
                  title: '대시보드',
                  value: '사용자 ID를 입력하고 새로고침을 눌러주세요.',
                  icon: Icons.dashboard_outlined,
                  color: kPrimary,
                ),
              ],
              if (_dashboard != null) ...[
                const SizedBox(height: 18),
                Text(
                  '${_text(_dashboard?['date'])} 요약',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 12),
                _DashboardCard(
                  title: '오늘 복약',
                  value:
                      '${_text(medication?['completed'], fallback: '0')} / '
                      '${_text(medication?['total'], fallback: '0')} 완료',
                  icon: Icons.medication_outlined,
                  color: kPrimary,
                ),
                const SizedBox(height: 10),
                if (schedules.isEmpty)
                  const _SmallDataCard(title: '복약 일정', value: '데이터 없음')
                else
                  ...schedules.map((schedule) {
                    final item = _asMap(schedule) ?? const <String, dynamic>{};
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SmallDataCard(
                        title:
                            '${_text(item['scheduled_time'])} · ${_text(item['product_name'])}',
                        value:
                            '${_text(item['ingredient'])} / ${_text(item['status'])}',
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                _DashboardCard(
                  title: 'DUR 위험도',
                  value: risk == null
                      ? '데이터 없음'
                      : '${_text(risk['risk_level'])}\n${_text(risk['description'])}',
                  icon: Icons.health_and_safety_outlined,
                  color: _riskColor(
                    _text(risk?['risk_level'], fallback: 'LOW'),
                  ),
                ),
                const SizedBox(height: 10),
                _DashboardCard(
                  title: '최근 처방전',
                  value: prescription == null
                      ? '데이터 없음'
                      : '처방일: ${_text(prescription['prescribed_date'])}\n'
                            '병원: ${_text(prescription['hospital_name'])}\n'
                            '상태: ${_text(prescription['status'])}',
                  icon: Icons.description_outlined,
                  color: const Color(0xFF4A78C2),
                ),
                const SizedBox(height: 10),
                _DashboardCard(
                  title: '최근 생체신호 이벤트',
                  value: event == null
                      ? '데이터 없음'
                      : '${_text(event['event_type'])} · ${_text(event['bpm'])} BPM\n'
                            '${_text(event['occurred_at'])}',
                  icon: Icons.monitor_heart_outlined,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 10),
                _DashboardCard(
                  title: '보호자 알림',
                  value:
                      '${_text(_dashboard?['notification_count'], fallback: '0')}건',
                  icon: Icons.notifications_outlined,
                  color: Colors.orange,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(color: kTextSub, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallDataCard extends StatelessWidget {
  final String title;
  final String value;

  const _SmallDataCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: kText)),
          ),
          Text(value, style: const TextStyle(fontSize: 12, color: kTextSub)),
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

Map<String, dynamic>? _asMap(dynamic value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
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
