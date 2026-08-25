import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/session/mvp_session.dart';

enum OcrState { initial, preview, loading, result }

class PrescriptionScreen extends StatefulWidget {
  const PrescriptionScreen({super.key});

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  OcrState _state = OcrState.initial;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  final ApiClient _apiClient = ApiClient();
  
  Map<String, dynamic>? _resultData;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _state = OcrState.preview;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog("접근 권한이 거부되었거나 오류가 발생했습니다.\n설정에서 권한을 허용해주세요.");
    }
  }

  Future<void> _analyzePrescription() async {
    setState(() {
      _state = OcrState.loading;
    });

    try {
      String? base64Image;
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        base64Image = base64Encode(bytes);
      }

      final response = await _apiClient.post(
        '/api/v1/prescriptions/ocr',
        body: {
          'user_id': MvpSession.userId.isNotEmpty ? MvpSession.userId : 'test_user',
          'image_data': base64Image,
          'source_type': 'OCR',
        },
      );

      if (!mounted) return;
      
      setState(() {
        _resultData = Map<String, dynamic>.from(response as Map);
        _state = OcrState.result;
      });
      
      // Update session just in case
      final items = _resultData?['items'];
      if (items is List && items.isNotEmpty && items.first is Map) {
        MvpSession.medicineCode = (items.first as Map)['medicine_code']?.toString() ?? '';
      }
      
    } catch (error) {
      if (!mounted) return;
      _showErrorDialog("처방전을 인식할 수 없습니다. 다시 촬영해주세요.");
      setState(() {
        _state = OcrState.initial;
        _image = null;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('오류', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  void _registerSchedule() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('복약 스케줄이 자동으로 추가되었습니다!'),
        backgroundColor: kPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('처방전 등록', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_state == OcrState.initial || _state == OcrState.preview) ...[
                Expanded(
                  child: _buildImagePlaceholder(),
                ),
                const SizedBox(height: 16),
                if (_state == OcrState.preview)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _state = OcrState.initial;
                      _image = null;
                    }),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
                    label: const Text('다시 선택하기', style: TextStyle(color: Colors.grey)),
                  ),
                const SizedBox(height: 16),
                if (_state == OcrState.initial) ...[
                  _buildPrimaryButton(
                    icon: Icons.camera_alt_rounded,
                    label: '카메라로 직접 촬영',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                  const SizedBox(height: 12),
                  _buildSecondaryButton(
                    icon: Icons.photo_library_rounded,
                    label: '갤러리에서 불러오기',
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ],
                if (_state == OcrState.preview)
                  _buildPrimaryButton(
                    icon: Icons.auto_awesome_rounded,
                    label: '분석하기',
                    onTap: _analyzePrescription,
                  ),
              ] else if (_state == OcrState.loading) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: kPrimary),
                        const SizedBox(height: 24),
                        Text(
                          '처방전을 분석 중입니다...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_state == OcrState.result) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_rounded, color: Color(0xFFE24B4A), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI가 분석한 결과입니다. 실제 처방전과 일치하는지 반드시 확인해주세요.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC2185B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if ((_resultData?['ocr_text'] ?? '').toString().isNotEmpty) ...[
                  Text(
                    '읽은 원문',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resultData!['ocr_text'].toString(),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: ListView.separated(
                    itemCount: (_resultData?['items'] as List?)?.length ?? 0,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = (_resultData?['items'] as List)[index] as Map;
                      final name = item['drug_name']?.toString() ?? '';
                      final freq = item['frequency_per_day'] ?? 1;
                      final days = item['duration_days'] ?? 7;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: kPrimaryLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('💊', style: TextStyle(fontSize: 20)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: kText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '1알씩 / 하루 $freq번 / $days일',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: Colors.grey, size: 20),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('수정 기능은 추후 제공됩니다.')),
                                    );
                                  },
                                ),
                              ],
                            ),
                            if (item['easy_explanation'] != null && item['easy_explanation'].toString().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: kPrimaryLight.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('💡', style: TextStyle(fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item['easy_explanation'].toString(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: kPrimary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildPrimaryButton(
                  icon: Icons.calendar_month_rounded,
                  label: '이대로 스케줄 등록하기',
                  onTap: _registerSchedule,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kPrimary.withValues(alpha: 0.3),
          width: 2,
          style: _state == OcrState.initial ? BorderStyle.none : BorderStyle.solid,
        ),
      ),
      child: _state == OcrState.preview && _image != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(_image!, fit: BoxFit.cover),
            )
          : Stack(
              children: [
                if (_state == OcrState.initial)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DashedBorderPainter(color: Colors.grey[400]!),
                    ),
                  ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '처방전 사진 업로드',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPrimaryButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: kPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildSecondaryButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: kPrimary),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: kPrimary),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 8.0;
    const dashSpace = 6.0;
    
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20));
    final path = Path()..addRRect(rrect);
    
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
