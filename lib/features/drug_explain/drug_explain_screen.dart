import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/session/mvp_session.dart';
import '../../core/widgets/rounded_gradient_app_bar.dart';

class DrugExplainScreen extends StatefulWidget {
  final ApiClient? apiClient;

  const DrugExplainScreen({super.key, this.apiClient});

  @override
  State<DrugExplainScreen> createState() => _DrugExplainScreenState();
}

class _DrugExplainScreenState extends State<DrugExplainScreen> {
  late final ApiClient _apiClient;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isLoadingMedicines = false;
  String? _selectedKeyword;
  String? _selectedMedicine;
  _DrugSearchCandidate? _selectedOfficialMedicine;
  String? _medicineLoadError;
  final List<String> _medicines = [];
  final List<Map<String, dynamic>> _messages = [];

  static const List<Map<String, String>> _keywordPrompts = [
    {
      'label': '#약효·효능',
      'prompt': '{medicine}의 약효와 효능을 공식 의약품 정보 기준으로 알려주세요.',
      'intent': 'efficacy',
    },
    {
      'label': '#복용방법',
      'prompt': '{medicine}의 복용방법을 공식 의약품 정보 기준으로 알려주세요.',
      'intent': 'dosage',
    },
    {
      'label': '#주의사항',
      'prompt': '{medicine} 복용 시 주의사항을 알려주세요.',
      'intent': 'precautions',
    },
    {
      'label': '#부작용',
      'prompt': '{medicine}의 공식 부작용을 알려주세요.',
      'intent': 'side_effects',
    },
    {
      'label': '#같이 먹는 약',
      'prompt': '{medicine}과 현재 먹는 약들을 같이 복용해도 되는지 기존 DUR 병용금기 분석 결과를 설명해주세요.',
      'intent': 'combination',
    },
    {
      'label': '#나이별 주의',
      'prompt': '{medicine}의 나이별 주의사항을 기존 DUR 연령금기 분석 결과로 설명해주세요.',
      'intent': 'age',
    },
    {
      'label': '#임신 중 주의',
      'prompt': '{medicine}의 임신 중 복용 주의사항을 기존 DUR 임부금기 분석 결과로 설명해주세요.',
      'intent': 'pregnancy',
    },
    {
      'label': '#비슷한 약 중복',
      'prompt':
          '{medicine}과 현재 먹는 약에 비슷한 효능의 약이 중복되는지 기존 DUR 효능군중복 분석 결과로 설명해주세요.',
      'intent': 'duplicate',
    },
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    // 초기 안내 메시지 추가
    _messages.add({
      'isMe': false,
      'text': '안녕하세요! 어떤 약에 대해 알고 싶으신가요?\n증상이나 약 이름을 편하게 물어보세요.',
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMedicines());
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  Future<void> _selectKeyword(Map<String, String> keyword) async {
    if (_isLoading) return;

    final label = keyword['label'];
    final prompt = keyword['prompt'];
    final intent = keyword['intent'];
    if (label == null || prompt == null || intent == null) return;

    final medicine = _selectedMedicine;
    if (medicine == null || medicine.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 궁금한 약을 선택해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _selectedKeyword = label);
    final completedPrompt = prompt.replaceAll('{medicine}', medicine);
    await _sendMessage(message: completedPrompt, intent: intent);
  }

  Future<void> _loadMedicines() async {
    final names = <String>[];

    void addName(dynamic value) {
      final name = value?.toString().trim() ?? '';
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }

    for (final item in MvpSession.latestOcrItems) {
      addName(
        item['medicine_name'] ?? item['drug_name'] ?? item['ocr_drug_name'],
      );
    }

    final userId = MvpSession.userId.trim();
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _medicineLoadError = names.isEmpty ? '로그인 후 내 약을 불러올 수 있어요.' : null;
      });
      return;
    }

    setState(() {
      _isLoadingMedicines = true;
      _medicineLoadError = null;
    });
    try {
      final response = await _apiClient.get(
        '/api/v1/users/${Uri.encodeComponent(userId)}/dashboard',
      );
      final dashboard = Map<String, dynamic>.from(response as Map);
      final prescription = dashboard['latest_prescription'];
      if (prescription is Map) {
        final medicineNames = prescription['medicine_names'];
        if (medicineNames is List) {
          for (final name in medicineNames) {
            addName(name);
          }
        }
      }
      final todayMedications = dashboard['today_medications'];
      if (todayMedications is List) {
        for (final medication in todayMedications) {
          if (medication is Map) {
            addName(
              medication['product_name'] ??
                  medication['drug_name'] ??
                  medication['medicine_name'],
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _selectedMedicine ??= names.length == 1 ? names.first : null;
        _medicineLoadError = names.isEmpty ? '등록된 처방/복용약이 없습니다.' : null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _medicineLoadError = names.isEmpty ? _apiError(error) : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _medicineLoadError = names.isEmpty ? '내 약을 불러오지 못했습니다.' : null;
      });
    } finally {
      if (mounted) setState(() => _isLoadingMedicines = false);
    }
  }

  Future<void> _enterOtherMedicine() async {
    final medicine = await showDialog<_DrugSearchCandidate>(
      context: context,
      builder: (_) => _OtherMedicineDialog(apiClient: _apiClient),
    );
    if (!mounted || medicine == null) return;
    setState(() {
      if (!_medicines.contains(medicine.itemName)) {
        _medicines.add(medicine.itemName);
      }
      _selectedMedicine = medicine.itemName;
      _selectedOfficialMedicine = medicine;
      _selectedKeyword = null;
    });
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

  Future<void> _sendMessage({String? message, String? intent}) async {
    if (_isLoading) return;

    final text = (message ?? _chatController.text).trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isMe': true, 'text': text});
      _isLoading = true;
      _selectedKeyword = null;
    });
    if (message == null) _chatController.clear();
    _scrollToBottom();

    try {
      // TODO: 실제 AI 챗봇 API 엔드포인트로 변경 필요
      // 현재는 기존 약물 설명 API 구조를 임시로 챗봇 응답처럼 활용하도록 구성
      final body = <String, dynamic>{
        'user_id': MvpSession.userId,
        'message': text,
      };
      if (intent != null) body['intent'] = intent;
      final selectedOfficial = _selectedOfficialMedicine;
      if (selectedOfficial?.itemSeq != null) {
        body['selected_medicine'] = {
          'medicine_code': selectedOfficial!.itemSeq,
          'product_name': selectedOfficial.itemName,
        };
      }
      final response = await _apiClient.post(
        '/api/v1/drug-explain/chat', // 가상의 챗봇 엔드포인트
        body: body,
      );

      final data = Map<String, dynamic>.from(response as Map);
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

  Widget _buildKeywordBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _keywordPrompts.map((keyword) {
            final label = keyword['label']!;
            final selected = label == _selectedKeyword;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: _isLoading ? null : (_) => _selectKeyword(keyword),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : kText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: Colors.white,
                selectedColor: kPrimary,
                side: BorderSide(color: selected ? kPrimary : kPrimaryLight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ),
    );
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
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _messages.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const _PharmacistGuide();
                  }
                  if (index == 1) {
                    return _MedicineSelector(
                      medicines: _medicines,
                      selectedMedicine: _selectedMedicine,
                      isLoading: _isLoadingMedicines,
                      errorMessage: _medicineLoadError,
                      onSelected: (medicine) {
                        setState(() {
                          if (_selectedMedicine == medicine) {
                            _selectedMedicine = null;
                            _selectedOfficialMedicine = null;
                          } else {
                            _selectedMedicine = medicine;
                            _selectedOfficialMedicine = null;
                          }
                          _selectedKeyword = null;
                        });
                      },
                      onEnterOther: _enterOtherMedicine,
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
            _buildKeywordBar(),
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

class _OtherMedicineDialog extends StatefulWidget {
  final ApiClient apiClient;

  const _OtherMedicineDialog({required this.apiClient});

  @override
  State<_OtherMedicineDialog> createState() => _OtherMedicineDialogState();
}

class _OtherMedicineDialogState extends State<_OtherMedicineDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<_DrugSearchCandidate> _candidates = const [];
  bool _isSearching = false;
  String? _errorMessage;
  int _requestSequence = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _requestSequence++;
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final sequence = ++_requestSequence;
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _candidates = const [];
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query, sequence),
    );
  }

  void _searchNow(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) return;
    _search(query, ++_requestSequence);
  }

  Future<void> _search(String query, int sequence) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.get(
        '/api/v1/drugs/search?q=${Uri.encodeQueryComponent(query)}',
      );
      if (!mounted ||
          sequence != _requestSequence ||
          _controller.text.trim() != query) {
        return;
      }
      final data = Map<String, dynamic>.from(response as Map);
      final rawItems = data['items'];
      final candidates = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => _DrugSearchCandidate.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where((item) => item.itemName.isNotEmpty)
                .toList()
          : <_DrugSearchCandidate>[];
      setState(() => _candidates = candidates);
    } on ApiException catch (error) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() {
        _candidates = const [];
        _errorMessage = error.statusCode == null
            ? '네트워크 연결을 확인한 후 다시 시도해주세요.'
            : '의약품 정보를 불러오지 못했습니다. 다시 시도해주세요.';
      });
    } catch (_) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() {
        _candidates = const [];
        _errorMessage = '의약품 정보를 불러오지 못했습니다. 다시 시도해주세요.';
      });
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _select(_DrugSearchCandidate candidate) {
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final maxContentHeight = (availableHeight - 200)
        .clamp(120.0, 368.0)
        .toDouble();

    return AlertDialog(
      title: const Text('다른 약 검색하기'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentHeight),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('otherMedicineSearchField'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '약 이름을 입력하세요',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: _onQueryChanged,
                onSubmitted: _searchNow,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: _buildSearchContent(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ],
    );
  }

  Widget _buildSearchContent() {
    if (_controller.text.trim().length < 2) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('약 이름을 2글자 이상 입력해주세요.'),
      );
    }
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (_errorMessage != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(_errorMessage!, key: const Key('drugSearchError')),
      );
    }
    if (_candidates.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('검색된 공식 의약품이 없습니다.'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _candidates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final candidate = _candidates[index];
        return ListTile(
          key: ValueKey(
            'drugCandidate:${candidate.itemSeq ?? candidate.itemName}',
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            candidate.itemName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: candidate.manufacturer == null
              ? null
              : Text(candidate.manufacturer!),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _select(candidate),
        );
      },
    );
  }
}

class _DrugSearchCandidate {
  final String itemName;
  final String? manufacturer;
  final String? itemSeq;

  const _DrugSearchCandidate({
    required this.itemName,
    this.manufacturer,
    this.itemSeq,
  });

  factory _DrugSearchCandidate.fromJson(Map<String, dynamic> json) {
    String? optionalText(dynamic value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return _DrugSearchCandidate(
      itemName: json['item_name']?.toString().trim() ?? '',
      manufacturer: optionalText(json['manufacturer']),
      itemSeq: optionalText(json['item_seq']),
    );
  }
}

class _MedicineSelector extends StatelessWidget {
  final List<String> medicines;
  final String? selectedMedicine;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<String> onSelected;
  final VoidCallback onEnterOther;

  const _MedicineSelector({
    required this.medicines,
    required this.selectedMedicine,
    required this.isLoading,
    required this.errorMessage,
    required this.onSelected,
    required this.onEnterOther,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '어떤 약이 궁금하세요?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '내 처방/복용약',
            style: TextStyle(fontSize: 14, color: kTextSub),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const LinearProgressIndicator(minHeight: 3)
          else if (medicines.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: medicines.map((medicine) {
                final selected = medicine == selectedMedicine;
                return ChoiceChip(
                  label: Text(medicine),
                  selected: selected,
                  onSelected: (_) => onSelected(medicine),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : kText,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: kPrimary,
                  backgroundColor: kPrimaryLight,
                  side: BorderSide(color: selected ? kPrimary : kBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                );
              }).toList(),
            )
          else
            Text(
              errorMessage ?? '등록된 처방/복용약이 없습니다.',
              style: const TextStyle(fontSize: 14, color: kTextSub),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onEnterOther,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text('다른 약 검색하기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
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
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: kPrimary,
                ),
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
