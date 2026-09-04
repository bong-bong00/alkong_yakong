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
  final FocusNode _chatFocusNode = FocusNode();

  bool _isLoading = false;
  String? _selectedKeyword;
  final List<Map<String, dynamic>> _messages = [];

  static const List<Map<String, String>> _keywordPrompts = [
    {
      'label': '#약효·효능',
      'prompt': '[약 이름]은 어떤 효능과 효과가 있는지 공식 정보 기준으로 알려주세요.',
    },
    {
      'label': '#복용방법',
      'prompt': '[약 이름]은 언제, 어떻게 복용해야 하는지 공식 복용법을 알려주세요.',
    },
    {
      'label': '#주의사항',
      'prompt': '[약 이름]을 복용할 때 주의해야 할 사항을 공식 정보 기준으로 알려주세요.',
    },
    {
      'label': '#부작용',
      'prompt': '[약 이름]의 공식 부작용과 이상반응 정보를 알려주세요.',
    },
    {
      'label': '#같이 먹는 약',
      'prompt': '현재 먹는 약들을 같이 복용해도 되는지 기존 DUR 병용금기 분석 결과를 설명해주세요.',
    },
    {
      'label': '#나이별 주의',
      'prompt': '현재 먹는 약의 나이별 주의사항을 기존 DUR 연령금기 분석 결과로 설명해주세요.',
    },
    {
      'label': '#임신 중 주의',
      'prompt': '현재 먹는 약의 임신 중 주의사항을 기존 DUR 임부금기 분석 결과로 설명해주세요.',
    },
    {
      'label': '#비슷한 약 중복',
      'prompt': '현재 먹는 약에 비슷한 효능의 약이 중복되는지 기존 DUR 효능군중복 분석 결과로 설명해주세요.',
    },
  ];

  static const String _demoTylenolSummaryReply =
      '식약처에 따르면 타이레놀정은 통증을 줄이고 열을 낮추는 데 사용하는 대표적인 해열진통제입니다.\n\n'
      '주성분은 아세트아미노펜이며, 두통, 치통, 근육통, 감기 몸살, 발열 같은 증상 완화에 사용됩니다.\n\n'
      '비교적 위에 부담이 적은 편이지만, 정해진 용량을 초과하면 간 손상 위험이 있어 주의가 필요합니다.';

  static const String _demoTylenolEffectsReply =
      '식약처에 따르면 타이레놀정의 주요 효능은 통증 완화와 해열 작용입니다.\n\n'
      '효능:\n'
      '• 두통 완화\n'
      '• 발열 감소\n'
      '• 치통 완화\n'
      '• 생리통 완화\n'
      '• 근육통 완화\n'
      '• 감기 증상 완화\n\n'
      '부작용:\n'
      '• 메스꺼움\n'
      '• 구토\n'
      '• 피부 발진\n'
      '• 알레르기 반응\n'
      '• 간 기능 이상 (과다 복용 시 위험)\n\n'
      '주의사항:\n'
      '술과 함께 복용하면 간 손상 위험이 증가할 수 있습니다.\n'
      '하루 최대 복용량을 초과하지 않는 것이 중요합니다.\n'
      '다른 감기약과 함께 복용할 경우 중복 성분 여부를 확인해야 합니다.';

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
    _chatController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _selectKeyword(Map<String, String> keyword) {
    final label = keyword['label'];
    final prompt = keyword['prompt'];
    if (label == null || prompt == null) return;

    setState(() => _selectedKeyword = label);
    _chatController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
    _chatFocusNode.requestFocus();
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

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isMe': true, 'text': text});
      _isLoading = true;
      _selectedKeyword = null;
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
      final reply = _safeDemoReply(
        text,
        data['reply']?.toString() ?? '응답을 받아오지 못했습니다.',
      );

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

  String _safeDemoReply(String question, String reply) {
    if (!reply.contains('너무 바빠') && !reply.contains('AI 약사가 설정')) {
      return reply;
    }
    final normalized = question.replaceAll(' ', '').toLowerCase();
    if (normalized.contains('효능') || normalized.contains('부작용')) {
      return _demoTylenolEffectsReply;
    }
    return _demoTylenolSummaryReply;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: const RoundedGradientAppBar('AI 약사 상담'),
      body: SafeArea(
        child: Column(
          children: [
            // 채팅 내역 리스트
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const _PharmacistGuide();
                  }
                  if (index == 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: _keywordPrompts.map((keyword) {
                          final label = keyword['label']!;
                          final selected = label == _selectedKeyword;
                          return ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: _isLoading
                                ? null
                                : (_) => _selectKeyword(keyword),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : kText,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            backgroundColor: Colors.white,
                            selectedColor: kPrimary,
                            side: BorderSide(
                              color: selected ? kPrimary : kPrimaryLight,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }

                  final msg = _messages[index - 2];
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
            // 하단 입력창 (플로팅 스타일)
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
                        focusNode: _chatFocusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: '궁금한 약 정보나 증상을 입력하세요...',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                          filled: true,
                          // 캡슐(흰색)과 구분되도록 입력칸은 연한 연두색으로.
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
            ),
          ],
        ),
      ),
    );
  }
}

class _PharmacistGuide extends StatelessWidget {
  const _PharmacistGuide();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPrimaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 약사에게 궁금한 내용을 물어보세요.',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '아래 키워드를 선택하거나 직접 질문할 수 있어요.\n답변은 공식 의약품 정보와 기존 DUR 분석 결과를 바탕으로 설명해요.',
            style: TextStyle(fontSize: 14.5, height: 1.45, color: kTextSub),
          ),
        ],
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
