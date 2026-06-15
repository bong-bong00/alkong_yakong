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
  int? _submittingScheduleId;
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

  Future<void> _markTaken(Map<String, dynamic> medication) async {
    final userId = _userIdController.text.trim();
    final scheduleId = _intValue(
      medication['schedule_id'] ?? medication['id'],
    );
    if (userId.isEmpty || scheduleId == null) {
      setState(() => _errorMessage = '사용자 또는 복약 일정 정보가 없습니다.');
      return;
    }

    setState(() {
      _submittingScheduleId = scheduleId;
      _errorMessage = null;
    });
    try {
      await _apiClient.post(
        '/api/v1/medication-logs',
        body: {'user_id': userId, 'schedule_id': scheduleId},
      );
      await _refreshDashboard();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _apiError(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = '복약 완료 처리 중 오류가 발생했습니다: $error');
    } finally {
      if (mounted) setState(() => _submittingScheduleId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final medication = _asMap(_dashboard?['medication_summary']);
    final todayMedications = _dashboard?['today_medications'];
    final summarySchedules = medication?['schedules'];
    final schedules = todayMedications is List
        ? todayMedications
        : summarySchedules is List
            ? summarySchedules
            : const <dynamic>[];
    final risk = _asMap(_dashboard?['latest_risk']);
    final prescription = _asMap(_dashboard?['latest_prescription']);
    final event = _asMap(_dashboard?['latest_abnormal_event']);
    final prescriptionMedicines = _stringList(
      prescription?['medicine_names'],
    );

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
                      child: _MedicationCard(
                        time: _text(
                          item['time'] ?? item['scheduled_time'],
                        ),
                        drugName: _text(
                          item['drug_name'] ?? item['product_name'],
                        ),
                        ingredient: _text(item['ingredient']),
                        status: _text(item['status'], fallback: 'PENDING'),
                        isSubmitting:
                            _submittingScheduleId ==
                            _intValue(item['schedule_id'] ?? item['id']),
                        onTaken: () => _markTaken(item),
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                _DashboardCard(
                  title: 'DUR 위험도',
                  value: risk == null
                      ? '데이터 없음'
                      : '${_text(risk['risk_level'])} · '
                            '${_text(risk['total_matches'], fallback: '0')}건\n'
                            '대표 유형: ${_text(risk['representative_type'])}',
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
                      : '${_text(prescription['display_name'], fallback: 'OCR 처방전')}\n'
                            'ID: ${_text(prescription['id'])}\n'
                            '등록일: ${_text(prescription['registered_at'] ?? prescription['created_at'])}\n'
                            'OCR 상태: ${_text(prescription['ocr_status'])}\n'
                            '약: ${prescriptionMedicines.isEmpty ? '데이터 없음' : prescriptionMedicines.take(3).join(', ')}',
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

class _MedicationCard extends StatelessWidget {
  final String time;
  final String drugName;
  final String ingredient;
  final String status;
  final bool isSubmitting;
  final VoidCallback onTaken;

  const _MedicationCard({
    required this.time,
    required this.drugName,
    required this.ingredient,
    required this.status,
    required this.isSubmitting,
    required this.onTaken,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toUpperCase();
    final isTaken = normalizedStatus == 'TAKEN';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$time · $drugName',
                  style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _MedicationStatus(status: normalizedStatus),
            ],
          ),
          const SizedBox(height: 7),
          Text(ingredient, style: const TextStyle(color: kTextSub)),
          if (!isTaken) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: isSubmitting ? null : onTaken,
                child: Text(isSubmitting ? '처리 중...' : '복약 완료'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedicationStatus extends StatelessWidget {
  final String status;

  const _MedicationStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'TAKEN' => kPrimary,
      'MISSED' => Colors.red,
      _ => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String _text(dynamic value, {String fallback = '데이터 없음'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

int? _intValue(dynamic value) {
  return value is int ? value : int.tryParse(value?.toString() ?? '');
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
