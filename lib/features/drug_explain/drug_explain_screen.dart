import 'dart:async';

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
  Timer? _suggestTimer;
  int _suggestSeq = 0;
  String? _selectedMedicine;
  static const _bareFaqs = {
    '지금 먹을 약',
    '이 약 설명',
    '같이 먹으면',
    '안 먹었을 때',
  };

  @override
  void initState() {
    super.initState();
    // 초기 안내 메시지 추가
    _messages.add({
      'isMe': false,
      'text': '안녕하세요! 어떤 약에 대해 알고 싶으신가요?\n증상이나 약 이름을 편하게 물어보세요.',
    });
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
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

  void _onQueryChanged(String query) {
    _suggestTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _suggestSeq++;
      setState(() => _suggestions = []);
      return;
    }
    _suggestTimer = Timer(const Duration(milliseconds: 280), () {
      _loadSuggestions(trimmed);
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final seq = ++_suggestSeq;
    try {
      final encodedQuery = Uri.encodeQueryComponent(query);
      final encodedUser = Uri.encodeQueryComponent(MvpSession.userId);
      final response = await _apiClient.get(
        '/api/v1/drug-explain/suggestions?q=$encodedQuery&user_id=$encodedUser',
      );
      if (!mounted || seq != _suggestSeq || response is! Map) return;
      final items = response['items'];
      if (items is! List) return;
      setState(() {
        _suggestions = items
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
      });
    } catch (_) {
      if (mounted && seq == _suggestSeq) {
        setState(() => _suggestions = []);
      }
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
      setState(() => _suggestions = []);
      _loadSuggestions(label);
      return;
    }
    final question = (_selectedMedicine != null && _bareFaqs.contains(label))
        ? '$_selectedMedicine $label'
        : label;
    _chatController
      ..text = question
      ..selection = TextSelection.collapsed(offset: question.length);
    setState(() => _suggestions = []);
    if (type == 'faq') {
      _sendMessage();
    }
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
      final response = await _apiClient.post(
        '/api/v1/drug-explain/chat',
        body: {'user_id': MvpSession.userId, 'message': text},
      );

      final data = Map<String, dynamic>.from(response as Map);
      // 일치율·근거 충족률 등 내부 trace는 채팅에 노출하지 않는다.
      final reply = data['reply']?.toString() ?? '응답을 받아오지 못했습니다.';

      if (!mounted) return;
      setState(() {
        _messages.add({'isMe': false, 'text': reply});
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isMe': false,
          'text': _chatErrorText(error),
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isMe': false,
          'text': '서버에 연결하지 못했어요. 잠시 후 다시 시도해주세요.',
        });
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
            // 아산형: 입력창 바로 위에 연관어 목록, 그 아래 입력창.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_suggestions.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                            child: Text(
                              '관련 검색어를 고르면 바로 답을 볼 수 있어요',
                              style: TextStyle(
                                fontSize: 13,
                                color: kTextSub,
                              ),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 168),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: _suggestions.length,
                              separatorBuilder: (context, index) => const Divider(
                                height: 1,
                                indent: 14,
                                endIndent: 14,
                              ),
                              itemBuilder: (context, index) {
                                final item = _suggestions[index];
                                final label = item['label']?.toString() ?? '';
                                final type = item['type']?.toString();
                                final isMedicine = type == 'medicine' ||
                                    type == 'today_medicine';
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isMedicine
                                        ? Icons.medication_outlined
                                        : Icons.help_outline,
                                    size: 20,
                                    color: kPrimary,
                                  ),
                                  title: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: kText,
                                    ),
                                  ),
                                  onTap: _isLoading
                                      ? null
                                      : () => _selectSuggestion(item),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                            onChanged: _onQueryChanged,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: '약 이름을 조금만 입력해 보세요...',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: kPrimaryLight,
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
                ],
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
                child: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: kPrimary),
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

String _chatErrorText(ApiException error) {
  switch (error.statusCode) {
    case 404:
    case 422:
      return '공식 자료에서 그 약을 찾지 못했어요.\n약 이름을 목록에서 골라 주세요.';
    case 502:
    case 504:
      return '약 정보를 가져오는 데 시간이 걸렸어요.\n잠시 후 다시 시도해주세요.';
    case 503:
      return '지금은 약 검색을 쓸 수 없어요.';
    default:
      return '답변을 만들지 못했어요.\n${_apiError(error)}';
  }
}
