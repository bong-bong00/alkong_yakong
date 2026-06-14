import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/session/mvp_session.dart';

class DrugExplainScreen extends StatefulWidget {
  const DrugExplainScreen({super.key});

  @override
  State<DrugExplainScreen> createState() => _DrugExplainScreenState();
}

class _DrugExplainScreenState extends State<DrugExplainScreen> {
  final _apiClient = ApiClient();
  late final TextEditingController _medicineCodeController;

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _medicine;
  Map<String, dynamic>? _explanation;

  @override
  void initState() {
    super.initState();
    _medicineCodeController = TextEditingController(
      text: MvpSession.medicineCode,
    );
  }

  @override
  void dispose() {
    _medicineCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadExplanation() async {
    var medicineCode = _medicineCodeController.text.trim();
    if (medicineCode.isEmpty && MvpSession.medicineCode.isNotEmpty) {
      medicineCode = MvpSession.medicineCode;
      _medicineCodeController.text = medicineCode;
    }
    if (medicineCode.isEmpty) {
      setState(() => _errorMessage = 'medicine_code를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _medicine = null;
      _explanation = null;
    });

    try {
      final response = await _apiClient.get(
        '/api/v1/drug-explain/${Uri.encodeComponent(medicineCode)}',
      );
      final data = Map<String, dynamic>.from(response as Map);
      if (!mounted) return;
      setState(() {
        _medicine = _asMap(data['medicine']);
        _explanation = _asMap(data['explanation']);
      });
      MvpSession.medicineCode = medicineCode;
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
    final medicineCode = _text(
      _medicine?['medicine_code'],
      fallback: _medicineCodeController.text,
    );

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('AI 약물 설명'), backgroundColor: kPrimary),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FeatureBanner(
                icon: Icons.psychology_alt_outlined,
                text: '처방전 등록 결과의 medicine_code로 백엔드 Mock 설명을 조회합니다.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _medicineCodeController,
                decoration: const InputDecoration(
                  labelText: 'medicine_code',
                  hintText: '예: MOCK-XXXXXXXXXX',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _loadExplanation,
                  icon: _isLoading
                      ? const _ButtonProgress()
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isLoading ? '조회 중...' : 'AI 설명 조회'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                _MessageCard(
                  title: '조회 실패',
                  message: _errorMessage!,
                  color: Colors.red,
                ),
              ],
              if (_explanation != null) ...[
                const SizedBox(height: 18),
                _ExplanationCard(
                  medicineCode: medicineCode,
                  productName: _text(_medicine?['product_name']),
                  ingredient: _text(_medicine?['ingredient']),
                  summary: _text(_explanation?['summary']),
                  howToTake: _text(_explanation?['how_to_take']),
                  cautions: _text(
                    _explanation?['cautions'] ?? _explanation?['warnings'],
                  ),
                  modelName: _text(_explanation?['model_name']),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  final String medicineCode;
  final String productName;
  final String ingredient;
  final String summary;
  final String howToTake;
  final String cautions;
  final String modelName;

  const _ExplanationCard({
    required this.medicineCode,
    required this.productName,
    required this.ingredient,
    required this.summary,
    required this.howToTake,
    required this.cautions,
    required this.modelName,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            productName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$medicineCode · 성분 $ingredient',
            style: const TextStyle(color: kTextSub),
          ),
          const Divider(height: 28),
          _LabelValue(label: '쉬운 설명', value: summary),
          _LabelValue(label: '복용 방법', value: howToTake),
          _LabelValue(label: '주의사항', value: cautions),
          _LabelValue(label: '생성 방식', value: modelName),
        ],
      ),
    );
  }
}

class _FeatureBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EEF8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: kTextSub)),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(height: 1.5, color: kText)),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String title;
  final String message;
  final Color color;

  const _MessageCard({
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: kText)),
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
