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

  Future<void> _loadExplanation({bool forceRefresh = false}) async {
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
        '/api/v1/drug-explain/${Uri.encodeComponent(medicineCode)}'
        '?force_refresh=$forceRefresh',
      );
      final data = Map<String, dynamic>.from(response as Map);
      final nestedMedicine = _asMap(data['medicine']);
      final nestedExplanation = _asMap(data['explanation']);
      if (!mounted) return;
      setState(() {
        _medicine = nestedMedicine ?? {
          'medicine_code': data['medicine_code'],
          'product_name': data['drug_name'],
          'ingredient': data['ingredient'],
        };
        _explanation = nestedExplanation ?? data;
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
                text: '처방전의 medicine_code로 e약은요 공식 정보와 AI 쉬운 설명을 조회합니다.',
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _loadExplanation(),
                      icon: _isLoading
                          ? const _ButtonProgress()
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isLoading ? '조회 중...' : 'AI 설명 조회'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: _isLoading
                        ? null
                        : () => _loadExplanation(forceRefresh: true),
                    tooltip: '공식 정보와 AI 설명 새로 생성',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
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
                  summary: _text(
                    _explanation?['easy_summary'] ??
                        _explanation?['summary'],
                  ),
                  whatItDoes: _text(_explanation?['what_it_does']),
                  howToTake: _text(_explanation?['how_to_take']),
                  cautions: _stringList(
                    _explanation?['cautions'] ?? _explanation?['warnings'],
                  ),
                  sideEffects: _stringList(
                    _explanation?['possible_side_effects'] ??
                        _explanation?['side_effects'],
                  ),
                  storage: _text(_explanation?['storage']),
                  askDoctorWhen: _stringList(
                    _explanation?['ask_doctor_when'],
                  ),
                  generatedBy: _text(
                    _explanation?['generated_by'] ??
                        _explanation?['model_name'],
                  ),
                  source: _text(_explanation?['source']),
                  isVerified: _boolValue(_explanation?['is_verified']),
                  sourceBased: _boolValue(_explanation?['source_based']),
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
  final String whatItDoes;
  final String howToTake;
  final List<String> cautions;
  final List<String> sideEffects;
  final String storage;
  final List<String> askDoctorWhen;
  final String generatedBy;
  final String source;
  final bool isVerified;
  final bool sourceBased;

  const _ExplanationCard({
    required this.medicineCode,
    required this.productName,
    required this.ingredient,
    required this.summary,
    required this.whatItDoes,
    required this.howToTake,
    required this.cautions,
    required this.sideEffects,
    required this.storage,
    required this.askDoctorWhen,
    required this.generatedBy,
    required this.source,
    required this.isVerified,
    required this.sourceBased,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CardShell(
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: _generatedByLabel(generatedBy),
                    verified: generatedBy != 'mock',
                  ),
                  _StatusChip(
                    label: sourceBased ? '공식 정보 기반' : '공식 정보 미확인',
                    verified: sourceBased,
                  ),
                  _StatusChip(
                    label: isVerified ? '검증됨' : 'AI 생성 · 확인 필요',
                    verified: isVerified,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(title: '쉬운 설명', value: summary),
        _SectionCard(title: '어떤 약인가요?', value: whatItDoes),
        _SectionCard(title: '복용 방법', value: howToTake),
        _SectionCard(title: '주의사항', items: cautions),
        _SectionCard(title: '가능한 부작용', items: sideEffects),
        _SectionCard(title: '보관 방법', value: storage),
        _SectionCard(
          title: '의사/약사 상담이 필요한 경우',
          items: askDoctorWhen,
        ),
        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabelValue(label: '정보 출처', value: source),
              _LabelValue(
                label: '생성 방식',
                value: _generatedByLabel(generatedBy),
              ),
              _LabelValue(
                label: '공식 정보 기반 여부',
                value: sourceBased ? '예' : '아니요',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? value;
  final List<String>? items;

  const _SectionCard({required this.title, this.value, this.items});

  @override
  Widget build(BuildContext context) {
    final safeItems = items ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _CardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: kPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (safeItems.isNotEmpty)
              ...safeItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('• $item'),
                ),
              )
            else
              Text(value ?? '데이터 없음'),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool verified;

  const _StatusChip({required this.label, required this.verified});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        verified ? Icons.verified_outlined : Icons.info_outline,
        size: 16,
        color: verified ? kPrimary : Colors.orange,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
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

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty
      ? const []
      : text
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
}

bool _boolValue(dynamic value) {
  return value == true || value == 1 || value?.toString().toLowerCase() == 'true';
}

String _generatedByLabel(String value) {
  return switch (value) {
    'e약은요+gemini' => '공식 정보 + AI 쉬운 설명',
    'e약은요-fallback' => '공식 정보 기반 설명',
    'local-cache' => '저장된 최신 설명',
    'mock' => '테스트용 설명',
    _ => value,
  };
}

String _apiError(ApiException error) {
  return error.statusCode == null
      ? error.message
      : '${error.message} (HTTP ${error.statusCode})';
}
