import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/session/mvp_session.dart';

class PrescriptionScreen extends StatefulWidget {
  const PrescriptionScreen({super.key});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiClient = ApiClient();
  late final TextEditingController _userIdController;
  late final TextEditingController _ocrTextController;
  late final TextEditingController _mockItemsController;

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _userIdController = TextEditingController(text: MvpSession.userId);
    _ocrTextController = TextEditingController(text: '아스피린 100mg\n메트포르민 500mg');
    _mockItemsController = TextEditingController(
      text: '아스피린 100mg|aspirin\n메트포르민 500mg|metformin',
    );
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _ocrTextController.dispose();
    _mockItemsController.dispose();
    super.dispose();
  }

  Future<void> _submitMockOcr() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final mockItems = _parseMockItems(_mockItemsController.text);
    if (mockItems.isEmpty) {
      setState(() {
        _errorMessage = 'Mock 약 항목을 한 개 이상 입력해주세요.';
        _result = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final response = await _apiClient.post(
        '/api/v1/prescriptions/ocr',
        body: {
          'user_id': _userIdController.text.trim(),
          'ocr_text': _ocrTextController.text.trim(),
          'source_type': 'OCR',
          'mock_items': mockItems,
        },
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _result = Map<String, dynamic>.from(response as Map);
      });
      MvpSession.userId = _userIdController.text.trim();
      final items = _result?['items'];
      if (items is List && items.isNotEmpty && items.first is Map) {
        MvpSession.medicineCode =
            (items.first as Map)['medicine_code']?.toString() ?? '';
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.statusCode == null
            ? error.message
            : '${error.message} (HTTP ${error.statusCode})';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '응답 처리 중 오류가 발생했습니다: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _parseMockItems(String input) {
    return input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final parts = line.split('|');
          final drugName = parts.first.trim();
          final ingredient = parts.length > 1 ? parts[1].trim() : drugName;
          return {
            'drug_name': drugName,
            'ingredient': ingredient.isEmpty ? drugName : ingredient,
            'frequency_per_day': 1,
            'times_per_take': 1,
            'duration_days': 7,
            'administration_times': ['08:00'],
          };
        })
        .where((item) => (item['drug_name'] as String).isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('처방전 등록'), backgroundColor: kPrimary),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBanner(baseUrl: ApiConfig.baseUrl),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: '사용자 ID',
                    hintText: 'FastAPI에서 생성한 사용자 UUID',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '사용자 ID를 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ocrTextController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Mock OCR 원문',
                    hintText: 'OCR로 인식했다고 가정할 처방전 문구',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'OCR 원문을 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _mockItemsController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Mock 약 항목',
                    hintText: '약 이름|성분을 한 줄에 하나씩 입력',
                    helperText: '예: 아스피린 100mg|aspirin',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Mock 약 항목을 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _submitMockOcr,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(_isLoading ? '등록 중...' : 'Mock OCR 처방전 등록'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ResultPanel(
                    title: '요청 실패',
                    color: Colors.red,
                    content: _errorMessage!,
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  _ResultPanel(
                    title: '처방전 등록 성공',
                    color: kPrimary,
                    content: const JsonEncoder.withIndent(
                      '  ',
                    ).convert(_result),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String baseUrl;

  const _InfoBanner({required this.baseUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mock OCR 연동 테스트',
            style: TextStyle(fontWeight: FontWeight.w700, color: kText),
          ),
          const SizedBox(height: 6),
          Text(
            'API: $baseUrl\n실제 카메라와 OCR 대신 입력한 약 목록을 서버에 등록합니다.',
            style: const TextStyle(fontSize: 12, color: kTextSub, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final String title;
  final Color color;
  final String content;

  const _ResultPanel({
    required this.title,
    required this.color,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 10),
          SelectableText(
            content,
            style: const TextStyle(fontSize: 12, height: 1.5, color: kText),
          ),
        ],
      ),
    );
  }
}
