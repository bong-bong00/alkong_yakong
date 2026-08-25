import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/session/mvp_session.dart';
import '../../core/widgets/rounded_gradient_app_bar.dart';

class DrugExplainScreen extends StatefulWidget {
  const DrugExplainScreen({super.key});

  @override
  State<DrugExplainScreen> createState() => _DrugExplainScreenState();
}

class _DrugExplainScreenState extends State<DrugExplainScreen> {
  final _apiClient = ApiClient();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  final List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _suggestions = [];
  String? _selectedMedicine;
  static const _quickQuestions = [
    '지금 먹을 약',
    '이 약 설명',
    '같이 먹으면',
    '안 먹었을 때',
  ];

  @override
  void initState() {
    super.initState();
    // 초기 안내 메시지 추가
    _messages.add({
      'isMe': false,
      'text': '안녕하세요! 어떤 약에 대해 알고 싶으신가요?\n증상이나 약 이름을 편하게 물어보세요. 🤖',
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final encodedQuery = Uri.encodeQueryComponent(query.trim());
      final encodedUser = Uri.encodeQueryComponent(MvpSession.userId);
      final response = await _apiClient.get(
        '/api/v1/drug-explain/suggestions?q=$encodedQuery&user_id=$encodedUser',
      );
      if (!mounted || response is! Map) return;
      final items = response['items'];
      if (items is! List) return;
      setState(() {
        _suggestions = items.whereType<Map>().map(Map<String, dynamic>.from).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    }
  }

  void _selectSuggestion(Map<String, dynamic> item) {
    final label = item['label']?.toString() ?? '';
    final type = item['type']?.toString();
    if (label.isEmpty) return;
    if (type == 'medicine' || type == 'today_medicine') {
      _selectedMedicine = label;
      _chatController
        ..text = label
        ..selection = TextSelection.collapsed(offset: label.length);
    } else {
      final question = _selectedMedicine == null
          ? label
          : '$_selectedMedicine $label';
      _chatController
        ..text = question
        ..selection = TextSelection.collapsed(offset: question.length);
    }
    setState(() => _suggestions = []);
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isMe': true, 'text': text});
      _isLoading = true;
    });
    _chatController.clear();
    _scrollToBottom();

    try {
      // TODO: 실제 AI 챗봇 API 엔드포인트로 변경 필요
      // 현재는 기존 약물 설명 API 구조를 임시로 챗봇 응답처럼 활용하도록 구성
      final response = await _apiClient.post(
        '/api/v1/drug-explain/chat', // 가상의 챗봇 엔드포인트
        body: {'user_id': MvpSession.userId, 'message': text},
      );

      final data = Map<String, dynamic>.from(response as Map);
      var reply = data['reply']?.toString() ?? '응답을 받아오지 못했습니다.';
      final trace = data['trace'];
      if (trace is Map) {
        final corrected = trace['corrected']?.toString();
        final source = trace['source']?.toString();
        final nameScore = trace['name_match_score'];
        final evidenceScore = trace['evidence_score'];
        final metadata = [
          if (corrected != null && corrected.isNotEmpty) '찾은 약: $corrected',
          if (source != null && source.isNotEmpty) '출처: $source',
          if (nameScore != null) '약 이름 일치율: $nameScore%',
          if (evidenceScore != null) '공식자료 근거 충족률: $evidenceScore%',
        ];
        if (metadata.isNotEmpty) {
          reply = '${metadata.join('\n')}\n\n$reply';
        }
      }

      if (!mounted) return;
      setState(() {
        _messages.add({'isMe': false, 'text': reply});
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isMe': false,
          'text': '죄송합니다. 오류가 발생했어요.\n${_apiError(error)}',
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({'isMe': false, 'text': '통신 중 문제가 발생했습니다.\n다시 시도해주세요.'});
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: const RoundedGradientAppBar('AI 약사 상담'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickQuestions
                      .map(
                        (question) => ActionChip(
                          label: Text(question),
                          onPressed: _isLoading
                              ? null
                              : () {
                                  _chatController.text = question;
                                  _sendMessage();
                                },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            if (_selectedMedicine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.medication_outlined, size: 18),
                    label: Text('선택한 약: $_selectedMedicine'),
                    onDeleted: () => setState(() => _selectedMedicine = null),
                  ),
                ),
              ),
            // 채팅 내역 리스트
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isMe = msg['isMe'] as bool;
                  return _ChatBubble(isMe: isMe, text: msg['text'] as String);
                },
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'AI가 답변을 작성하고 있습니다...',
                  style: TextStyle(fontSize: 12, color: kTextSub),
                ),
              ),
            if (_suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions
                        .map(
                          (item) => ActionChip(
                            label: Text(item['label']?.toString() ?? ''),
                            onPressed: () => _selectSuggestion(item),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            // 하단 입력창 (플로팅 스타일로 변경)
            Padding(
              // 하단바와 겹치지 않도록 좌, 우, 아래에 여백을 주어 띄웁니다.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  // 전체 컨테이너를 캡슐 모양으로 완전히 둥글게 처리합니다.
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        textInputAction: TextInputAction.send,
                        onChanged: _loadSuggestions,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: '궁금한 약 정보나 증상을 입력하세요...',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: kBackground,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _isLoading ? null : _sendMessage,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _isLoading ? Colors.grey : kPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;

  const _ChatBubble({required this.isMe, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: kPrimaryLight,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? kPrimary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: isMe ? Colors.white : kText,
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 44),
        ],
      ),
    );
  }
}

String _apiError(ApiException error) {
  return error.statusCode == null
      ? error.message
      : '${error.message} (HTTP ${error.statusCode})';
}
