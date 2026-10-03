import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';
import '../../../../core/widgets/medicine_conflict_card.dart';
import '../../../../core/widgets/senior_button.dart';
import '../../../../core/widgets/senior_header.dart';
import '../../../prescription/domain/registration_result.dart';

/// Registration warnings use the saved response; displaying it does not rerun
/// or persist a different DUR analysis.
class DurAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic>? initialResult;
  final VoidCallback? onOpenScheduleDays;
  const DurAnalysisScreen({
    super.key,
    this.initialResult,
    this.onOpenScheduleDays,
  });
  @override
  State<DurAnalysisScreen> createState() => _DurAnalysisScreenState();
}

class _DurAnalysisScreenState extends State<DurAnalysisScreen> {
  Map<String, dynamic>? _result;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final response = await ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl)
          .get(
            '/api/v1/users/${Uri.encodeComponent(MvpSession.userId)}/dur/latest',
          );
      if (response is! Map) throw const FormatException('Missing DUR result');
      if (mounted) {
        setState(() => _result = Map<String, dynamic>.from(response));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _continue() {
    if (widget.onOpenScheduleDays != null) {
      widget.onOpenScheduleDays!();
    } else if (widget.initialResult?['open_schedule_days'] == true) {
      context.pushReplacement(
        '/schedule-days',
        extra: MvpSession.latestPrescriptionId,
      );
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = pairConflictMatches(_result);
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          const SeniorBackHeader(title: '약 함께먹기 주의'),
          Expanded(
            child: _failed
                ? Center(
                    child: SeniorButton(label: '다시 불러오기', onPressed: _load),
                  )
                : _result == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final match in matches) ...[
                        MedicineConflictCard(match: match),
                        const SizedBox(height: 12),
                      ],
                      if (!registrationDurComplete(_result!))
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text('확인된 주의 항목을 표시했어요. 일부 검사는 아직 완료되지 않았어요.'),
                        ),
                      if (matches.isEmpty)
                        const Text('현재 확인된 약끼리의 충돌 항목은 없어요.'),
                      const SizedBox(height: 16),
                      SeniorButton(label: '확인했어요', onPressed: _continue),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
