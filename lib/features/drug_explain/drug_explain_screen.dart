import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/polar_pharmacist_ui/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/session/mvp_session.dart';
import '../../core/polar_pharmacist_ui/theme/app_typography.dart';
import '../../core/polar_pharmacist_ui/widgets/senior_button.dart';
import '../../core/polar_pharmacist_ui/widgets/senior_card.dart';
import '../../core/polar_pharmacist_ui/widgets/senior_feedback.dart';
import '../../core/polar_pharmacist_ui/widgets/senior_header.dart';
import '../../core/polar_pharmacist_ui/widgets/senior_sheet.dart';
import '../medicines/domain/display_policy.dart';
import 'conversation_store.dart';
import 'answer_cache.dart';

class DrugExplainScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ApiClient? medicationApiClient;

  /// 약 자세히에서 "이 약 물어보기"로 들어오면 그 약을 고른 채로 연다.
  final String? initialMedicine;

  const DrugExplainScreen({
    super.key,
    this.apiClient,
    this.medicationApiClient,
    this.initialMedicine,
  });

  @override
  State<DrugExplainScreen> createState() => _DrugExplainScreenState();
}

class _DrugExplainScreenState extends State<DrugExplainScreen>
    with WidgetsBindingObserver {
  late final ApiClient _apiClient;
  late final ApiClient _medicationApiClient;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isLoadingMedicines = false;
  // 고르는 약은 **하나까지**다. 여러 약은 질문에 적으면 된다.
  final List<String> _selectedMedicines = [];
  String? _pendingGeneralQuestion;
  final Map<String, _DrugSearchCandidate> _officialMedicinesByName = {};
  final Set<String> _confirmedOfficialProductNames = {};
  final Map<String, _DrugSearchCandidate> _temporaryMedicinesByCode = {};
  final Set<String> _registeredMedicineCodes = {};
  String? _medicineLoadError;
  final List<String> _medicines = [];
  final List<Map<String, dynamic>> _messages = [];
  int _conversationStart = 0;
  final _conversationStore = PharmacistConversationStore();
  late final String _conversationUserId = MvpSession.userId;
  String? _conversationId;
  final _answerCache = PharmacistAnswerCache();
  String? _healthFingerprint;
  String? _medicineFingerprint;
  DateTime? _contextVerifiedAt;

  Future<void> _refreshCacheContext() async {
    _healthFingerprint = null;
    _contextVerifiedAt = null;
    try {
      final result = await _apiClient.get(
        '/api/v1/drug-explain/cache-context?user_id=${Uri.encodeComponent(_conversationUserId)}',
      );
      if (result is Map &&
          result['verified'] == true &&
          result['fingerprint'] is String) {
        _healthFingerprint = result['fingerprint'] as String;
        _contextVerifiedAt = DateTime.now();
      }
    } catch (_) {
      // Unknown health state permits historical viewing, never automatic reuse.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _medicineFingerprint = null;
      unawaited(_loadMedicines());
      unawaited(_refreshCacheContext());
    }
  }

  Future<void> _saveConversation() async {
    final messages = _messages
        .skip(_conversationStart)
        .where((message) => message['createdAt'] != null)
        .toList();
    if (!messages.any((message) => message['isMe'] == true)) return;
    _conversationId ??= DateTime.now().microsecondsSinceEpoch.toString();
    final title = _selectedMedicines.isEmpty
        ? '내 약 전체'
        : _selectedMedicines.join(', ');
    await _conversationStore.save(_conversationUserId, {
      'id': _conversationId,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': messages,
      'pendingQuestion': _pendingGeneralQuestion,
      'selected': _selectedMedicines
          .map(
            (name) => {
              'name': name,
              'product_name': _officialMedicinesByName[name]?.itemName ?? name,
              'medicine_code': _officialMedicinesByName[name]?.itemSeq,
            },
          )
          .toList(),
      'temporary': _temporaryMedicinesByCode.values
          .map(
            (medicine) => {
              'item_name': medicine.itemName,
              'item_seq': medicine.itemSeq,
            },
          )
          .toList(),
    });
  }

  Future<void> _openPreviousConversations() async {
    if (_isLoading || _isLoadingMedicines) return;
    try {
      final records = await _conversationStore.load(_conversationUserId);
      if (!mounted) return;
      final conversation = await Navigator.of(context)
          .push<Map<String, dynamic>>(
            MaterialPageRoute(
              builder: (_) => _PreviousConversationsScreen(records: records),
            ),
          );
      if (!mounted || conversation == null) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            (conversation['messages'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
        _conversationStart = 0;
        _conversationId = conversation['id'] as String;
        _selectedMedicines.clear();
        // Keep current registered medicines. Old search selections are not registered.
        for (final candidate in _temporaryMedicinesByCode.values) {
          if (!_registeredMedicineCodes.contains(candidate.itemSeq)) {
            _medicines.remove(candidate.itemName);
            _officialMedicinesByName.remove(candidate.itemName);
          }
        }
        _temporaryMedicinesByCode.clear();
        for (final item in conversation['temporary'] as List? ?? []) {
          final candidate = _DrugSearchCandidate.fromJson(
            Map<String, dynamic>.from(item as Map),
          );
          if (candidate.itemSeq != null) {
            _temporaryMedicinesByCode[candidate.itemSeq!] = candidate;
          }
          _officialMedicinesByName[candidate.itemName] = candidate;
          if (!_medicines.contains(candidate.itemName)) {
            _medicines.add(candidate.itemName);
          }
        }
        for (final item in conversation['selected'] as List? ?? []) {
          final name = item['name'] as String;
          _selectedMedicines.add(name);
          _officialMedicinesByName[name] = _DrugSearchCandidate(
            itemName: item['product_name'] as String,
            itemSeq: item['medicine_code'] as String?,
          );
          if (!_medicines.contains(name)) _medicines.add(name);
        }
        _pendingGeneralQuestion = conversation['pendingQuestion'] as String?;
        _chatController.clear();
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        showSeniorSnackbar(
          context,
          '이전 대화를 불러오지 못했어요. 다시 시도해 주세요.',
          error: true,
        );
      }
    }
  }

  String? get _selectedMedicine =>
      _selectedMedicines.isEmpty ? null : _selectedMedicines.first;

  /// 고른 약이 없으면 알콩이는 **내 약 전부**를 놓고 답한다.
  /// 그래서 "아침 약이랑 우유" 같은 질문이 그대로 통한다.
  bool get _asksAboutAllMedicines => _selectedMedicines.isEmpty;

  /// 화면에 적는 이름. 용량(mg)은 떼고 약 이름만 보여 준다.
  String _shortName(String name) => nameWithoutStrength(name);

  _DrugSearchCandidate? get _selectedOfficialMedicine {
    final medicine = _selectedMedicine;
    return medicine == null ? null : _officialMedicinesByName[medicine];
  }

  /// 약을 고르지 않았을 때. 알콩이가 내 약 전부를 알고 있으니
  /// 약 이름 없이 "아침 약"처럼 물어도 된다.
  static const List<Map<String, String>> _generalSuggestions = [
    {
      'label': '아침 약이랑 우유 같이 먹어도 돼요?',
      'prompt': '제가 아침에 먹는 약이랑 우유를 같이 먹어도 되는지 알려주세요.',
      'intent': 'combination',
    },
    {
      'label': '혈압약이랑 관절약 같이 먹어도 돼요?',
      'prompt': '제가 먹는 혈압약이랑 관절약을 같이 먹어도 되는지 알려주세요.',
      'intent': 'combination',
    },
    {
      'label': '졸리지 않는 감기약이 있어요?',
      'prompt': '제가 먹는 약과 같이 먹어도 되는, 졸리지 않는 감기약이 있는지 알려주세요.',
      'intent': 'overview',
    },
  ];

  /// 약 하나를 골랐을 때. {medicine} 자리에 고른 약 이름이 들어간다.
  static const List<Map<String, String>> _medicineSuggestions = [
    {
      'label': '꼭 식사 후에 복용해야 하나요?',
      'prompt': '{medicine}은 꼭 식사 후에 복용해야 하나요?',
      'intent': 'dosage',
    },
    {
      'label': '속이 울렁거리는데 괜찮나요?',
      'prompt': '{medicine}을 먹고 속이 울렁거리는데 괜찮은가요?',
      'intent': 'side_effects',
    },
    {
      'label': '같이 먹으면 안 되는 음식은요?',
      'prompt': '{medicine}과 같이 먹으면 안 되는 음식이 있나요?',
      'intent': 'combination',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiClient = widget.apiClient ?? ApiClient();
    _medicationApiClient =
        widget.medicationApiClient ??
        ApiClient(baseUrl: ApiConfig.localFeatureBaseUrl);
    final initial = widget.initialMedicine?.trim() ?? '';
    if (initial.isNotEmpty) _selectedMedicines.add(initial);
    // 첫 인사는 이름과 고른 약에 따라 달라진다. 글은 그릴 때 만든다.
    _messages.add({'isMe': false, 'greeting': true, 'text': _greeting('')});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadMedicines());
      unawaited(_refreshCacheContext());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (_chatFocusNode.hasFocus) _scrollToBottom();
  }

  /// 머리말 인사. 약을 고르면 그 약 이야기로 좁혀 말한다.
  String _greeting(String userName) {
    final medicine = _selectedMedicine;
    if (medicine != null) {
      return '${_shortName(medicine)}에 대해 궁금한 걸 물어보세요.';
    }
    final given = _givenName(userName);
    final hello = given.isEmpty ? '안녕하세요.' : '$given 님, 안녕하세요.';
    return '$hello 드시는 모든 약들에 대해 알고 있어요. 약이든 건강이든 편하게 물어보세요.';
  }

  /// "김복자" → "복자". 성은 떼고 부른다 — 성만으로는 누구인지 모른다.
  String _givenName(String userName) {
    final name = userName.trim();
    if (name.length < 3 || name.contains(' ')) return name;
    return name.substring(1);
  }

  Future<void> _loadMedicines() async {
    _medicineFingerprint = null;
    final names = <String>[];
    final officialMedicines = <String, _DrugSearchCandidate>{};
    final ambiguousNames = <String>{};
    final namesByCode = <String, String>{};
    final officialNamesByCode = <String, String>{};
    final namesByNormalizedName = <String, String>{};

    String firstText(Iterable<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    void addName(dynamic value) {
      final name = value?.toString().trim() ?? '';
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }

    void addMedicine(dynamic nameValue, dynamic codeValue, {String? label}) {
      final officialName = nameValue?.toString().trim() ?? '';
      final name = (label ?? officialName).trim();
      final code = codeValue?.toString().trim() ?? '';
      if (code.isNotEmpty) {
        if (officialName.isNotEmpty) officialNamesByCode[code] = officialName;
        final oldName = namesByCode[code];
        if (oldName != null && oldName != name) {
          names.remove(oldName);
          officialMedicines.remove(oldName);
        }
        namesByCode[code] = name;
      } else if (name.isNotEmpty) {
        final normalizedName = name
            .replaceAll(RegExp(r'\s+'), '')
            .toLowerCase();
        if (namesByNormalizedName.containsKey(normalizedName)) return;
        namesByNormalizedName[normalizedName] = name;
      }
      addName(name);
      if (name.isEmpty ||
          officialName.isEmpty ||
          code.isEmpty ||
          ambiguousNames.contains(name)) {
        return;
      }
      final existing = officialMedicines[name];
      if (existing != null && existing.itemSeq != code) {
        officialMedicines.remove(name);
        ambiguousNames.add(name);
        return;
      }
      officialMedicines[name] = _DrugSearchCandidate(
        itemName: officialName,
        itemSeq: code,
      );
    }

    for (final item in MvpSession.latestOcrItems) {
      final officialName = firstText([
        item['official_product_name'],
        item['product_name'],
      ]);
      final label = firstText([
        item['medicine_name'],
        item['drug_name'],
        item['ocr_drug_name'],
        officialName,
      ]);
      addMedicine(
        officialName,
        officialName.isEmpty
            ? null
            : item['medicine_code'] ?? item['item_seq'] ?? item['itemSeq'],
        label: label,
      );
    }

    final userId = MvpSession.userId.trim();
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _officialMedicinesByName
          ..clear()
          ..addAll(officialMedicines);
        _confirmedOfficialProductNames
          ..clear()
          ..addAll(officialNamesByCode.values);
        _medicineLoadError = names.isEmpty ? '로그인 후 내 약을 불러올 수 있어요.' : null;
      });
      return;
    }

    setState(() {
      _isLoadingMedicines = true;
      _medicineLoadError = null;
    });
    try {
      final response = await _medicationApiClient.get(
        '/api/v1/users/${Uri.encodeComponent(userId)}/medicines',
      );
      final payload = Map<String, dynamic>.from(response as Map);
      final medicines = payload['medicines'];
      if (medicines is! List) {
        throw const FormatException('medicines must be a list');
      }
      final rows = medicines.map(PharmacistAnswerCache.canonical).toList()
        ..sort();
      _medicineFingerprint = PharmacistAnswerCache.canonical(rows);
      // 성공한 약 데이터 Render 조회가 OCR 임시 목록을 대체하도록 한다.
      names.clear();
      officialMedicines.clear();
      ambiguousNames.clear();
      namesByCode.clear();
      officialNamesByCode.clear();
      namesByNormalizedName.clear();
      for (final medicine in medicines) {
        if (medicine is Map &&
            (medicine['status']?.toString() ?? 'active') == 'active') {
          final officialName = firstText([
            medicine['official_product_name'],
            medicine['product_name'],
            medicine['display_name'],
          ]);
          final ingredient = firstText([
            medicine['ingredient_name'],
            medicine['ingredient'],
          ]);
          addMedicine(
            officialName,
            medicine['medicine_code'],
            label: compactProductName(officialName, ingredient: ingredient),
          );
        }
      }
      final registeredCodes = namesByCode.keys.toSet();
      for (final medicine in _temporaryMedicinesByCode.values) {
        addMedicine(medicine.itemName, medicine.itemSeq);
      }
      if (!mounted) return;
      setState(() {
        _registeredMedicineCodes
          ..clear()
          ..addAll(registeredCodes);
        _medicines
          ..clear()
          ..addAll(names);
        _officialMedicinesByName
          ..clear()
          ..addAll(officialMedicines);
        _confirmedOfficialProductNames
          ..clear()
          ..addAll(officialNamesByCode.values);
        _medicineLoadError = names.isEmpty ? '등록된 처방/복용약이 없습니다.' : null;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _officialMedicinesByName
          ..clear()
          ..addAll(officialMedicines);
        _confirmedOfficialProductNames
          ..clear()
          ..addAll(officialNamesByCode.values);
        _medicineLoadError = _medicineLoadFailureMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(names);
        _officialMedicinesByName
          ..clear()
          ..addAll(officialMedicines);
        _confirmedOfficialProductNames
          ..clear()
          ..addAll(officialNamesByCode.values);
        _medicineLoadError = '내 약을 불러오지 못했습니다.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingMedicines = false);
    }
  }

  /// 물어볼 약을 하나 고른다. 고르지 않아도 되는 지름길이다.
  Future<void> _pickMedicines() async {
    if (_isLoading) return;
    final pick = await SeniorSheet.show<_MedicinePick>(
      context: context,
      builder: (_) => _MedicinePickSheet(
        apiClient: _apiClient,
        medicines: _medicines,
        shortName: _shortName,
        selected: _selectedMedicine,
      ),
    );
    if (!mounted || pick == null) return;
    final found = pick.candidate;
    if (found != null) {
      _selectMedicine(found.itemName, candidate: found);
      return;
    }
    final name = pick.name;
    if (name != null) _selectMedicine(name);
  }

  /// 고른 약 하나만 남긴다. 대화도 거기서 새로 시작한다.
  void _selectMedicine(String name, {_DrugSearchCandidate? candidate}) {
    setState(() {
      if (candidate != null) {
        if (!_medicines.contains(candidate.itemName)) {
          _medicines.add(candidate.itemName);
        }
        final code = candidate.itemSeq?.trim();
        if (code != null && code.isNotEmpty) {
          _temporaryMedicinesByCode[code] = candidate;
        }
        _officialMedicinesByName[candidate.itemName] = candidate;
      }
      _selectedMedicines
        ..clear()
        ..add(name);
      _conversationStart = _messages.length;
      _conversationId = null;
      _pendingGeneralQuestion = null;
    });
  }

  /// 고른 약을 뺀다. 다시 내 약 전부를 놓고 묻는 자리로 돌아온다.
  void _clearMedicine() {
    if (_isLoading) return;
    setState(() {
      _selectedMedicines.clear();
      _conversationStart = _messages.length;
      _conversationId = null;
      _pendingGeneralQuestion = null;
    });
  }

  Future<void> _askSuggestion(Map<String, String> suggestion) async {
    if (_isLoading) return;
    final medicine = _selectedMedicine;
    final official = medicine == null
        ? ''
        : (_officialMedicinesByName[medicine]?.itemName ?? medicine);
    await _sendMessage(
      message: suggestion['prompt']!.replaceAll('{medicine}', official),
      displayMessage: suggestion['label'],
      intent: suggestion['intent'],
    );
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

  Future<void> _sendMessage({
    String? message,
    String? displayMessage,
    String? intent,
    bool forceRefresh = false,
  }) async {
    if (_isLoading) return;

    final text = (message ?? _chatController.text).trim();
    if (text.isEmpty) return;
    final pendingQuestion = _pendingGeneralQuestion;
    // 약을 고르지 않고 직접 적은 질문. 서버가 약을 되물으면 다음 줄에서
    // 적은 약 이름을 그 질문에 붙여 다시 보낸다.
    final isGeneralFreeInput = message == null && _selectedMedicines.isEmpty;
    final isFollowup = RegExp(
      r'^(그럼|그러면|그 약|이 약|그건)|번째\s*약|요약|짧게|간단히',
    ).hasMatch(text);
    final requestText =
        isGeneralFreeInput &&
            pendingQuestion != null &&
            _looksLikeMedicineIdentity(text)
        ? '$text에 대해 다음 질문에 답해 주세요: $pendingQuestion'
        : text;

    final previousMessages = _messages
        .skip(_conversationStart)
        .where(
          (entry) =>
              entry['isMe'] == true || entry['conversationMedicines'] != null,
        )
        .toList();
    final recentHistory = previousMessages
        .skip(previousMessages.length > 6 ? previousMessages.length - 6 : 0)
        .map((entry) {
          final content = (entry['contextText'] ?? entry['text']).toString();
          return {
            'role': entry['isMe'] == true ? 'user' : 'assistant',
            'content': content.length > 4000
                ? content.substring(0, 4000)
                : content,
            if (entry['intent'] != null) 'intent': entry['intent'],
            if (entry['scope'] != null) 'scope': entry['scope'],
            'medicines': entry['conversationMedicines'] ?? const [],
          };
        })
        .toList(growable: false);
    final questionIndex = _messages.length;
    setState(() {
      _messages.add({
        'isMe': true,
        'createdAt': DateTime.now().toIso8601String(),
        'text': displayMessage ?? text,
        'contextText': requestText,
        'intent': intent,
        'scope': _asksAboutAllMedicines ? 'all' : 'selection',
      });
      _isLoading = true;
    });
    if (message == null) _chatController.clear();
    _scrollToBottom();

    Map<String, dynamic>? historicalAnswer;
    try {
      if (forceRefresh ||
          (_contextVerifiedAt != null &&
              DateTime.now().difference(_contextVerifiedAt!) >=
                  const Duration(minutes: 5))) {
        await Future.wait([_loadMedicines(), _refreshCacheContext()]);
      }
      final officialProductNames = _selectedMedicines.isNotEmpty
          ? _selectedMedicines
                .map((name) => _officialMedicinesByName[name]?.itemName)
                .whereType<String>()
                .toList(growable: false)
          : <String>{
              ..._confirmedOfficialProductNames,
              ..._temporaryMedicinesByCode.values.map(
                (medicine) => medicine.itemName,
              ),
            }.toList(growable: false);
      // TODO: 실제 AI 챗봇 API 엔드포인트로 변경 필요
      // 현재는 기존 약물 설명 API 구조를 임시로 챗봇 응답처럼 활용하도록 구성
      final body = <String, dynamic>{
        'user_id': MvpSession.userId,
        'message': requestText,
        'recent_history': recentHistory,
      };
      if (intent != null) body['intent'] = intent;
      final selectedOfficial = _selectedOfficialMedicine;
      if (selectedOfficial?.itemSeq != null) {
        body['selected_medicine'] = {
          'medicine_code': selectedOfficial!.itemSeq,
          'product_name': selectedOfficial.itemName,
        };
      }
      // 고른 약이 없으면 알콩이가 내 약 전부를 본다. 이름으로 찾아 둔 약도
      // 그 안에 든다.
      final temporaryMedicines = _temporaryMedicinesByCode.values;
      if (_asksAboutAllMedicines && temporaryMedicines.isNotEmpty) {
        body['temporary_medicines'] = temporaryMedicines
            .map(
              (medicine) => {
                'medicine_code': medicine.itemSeq,
                'product_name': medicine.itemName,
              },
            )
            .toList(growable: false);
      }
      final requestKey = PharmacistAnswerCache.canonical({
        ...body,
        'scope': _asksAboutAllMedicines ? 'all' : 'selection',
        'recent_history':
            message == null || isFollowup || pendingQuestion != null
            ? recentHistory
            : [],
      });
      historicalAnswer = await _answerCache.find(
        _conversationUserId,
        requestKey,
      );
      final contextFresh =
          _contextVerifiedAt != null &&
          DateTime.now().difference(_contextVerifiedAt!) <
              const Duration(minutes: 5);
      final cacheContext =
          _healthFingerprint != null &&
              _medicineFingerprint != null &&
              contextFresh
          ? PharmacistAnswerCache.canonical([
              _healthFingerprint,
              _medicineFingerprint,
            ])
          : null;
      final saved = !forceRefresh && cacheContext != null
          ? await _answerCache.find(
              _conversationUserId,
              requestKey,
              context: cacheContext,
              maxAge: const Duration(minutes: 15),
            )
          : null;
      final response =
          saved?['response'] ??
          await _apiClient.post('/api/v1/drug-explain/chat', body: body);
      final data = Map<String, dynamic>.from(response as Map);
      if (saved == null) {
        try {
          await _answerCache.save(
            _conversationUserId,
            requestKey,
            cacheContext ?? 'unverified',
            data,
          );
        } catch (_) {
          /* Storage failure must not discard a received answer. */
        }
      }
      final reply = data['reply']?.toString() ?? '응답을 받아오지 못했습니다.';
      final asksForMedicine = reply.contains('물어볼 약을 선택하거나 제품명·성분명을 알려주세요');
      final generalCoffeeQuestion = _isGeneralCoffeeMedicineQuestion(text);

      if (!mounted) return;
      setState(() {
        _messages[questionIndex]['contextText'] =
            data['resolved_message'] ?? requestText;
        _messages[questionIndex]['intent'] = data['resolved_intent'] ?? intent;
        if (data['resolved_scope'] != null) {
          _messages[questionIndex]['scope'] = data['resolved_scope'];
        }
        if (isGeneralFreeInput) {
          _pendingGeneralQuestion = asksForMedicine
              ? (pendingQuestion ?? text)
              : generalCoffeeQuestion
              ? text
              : null;
        }
        _messages.add({
          'isMe': false,
          'createdAt': DateTime.now().toIso8601String(),
          'text': _plainAiReply(reply),
          if (saved != null)
            'cacheNotice':
                '저장된 답변 · ${_conversationDate(saved['savedAt'].toString())}',
          if (saved != null) 'refreshQuestion': text,
          if (saved != null) 'refreshIntent': intent,
          'sources':
              (data['sources'] as List?)?.whereType<String>().toList(
                growable: false,
              ) ??
              const <String>[],
          'conversationMedicines': data['conversation_medicines'] ?? const [],
          'officialProductNames': officialProductNames,
          'isHealthReply':
              (data['resolved_intent'] ?? intent) == 'health_precautions',
          'healthHighlightTerms':
              (data['resolved_intent'] ?? intent) == 'health_precautions'
              ? (data['health_highlight_terms'] as List?)
                        ?.whereType<String>()
                        .toList(growable: false) ??
                    const <String>[]
              : const <String>[],
        });
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        final unavailable =
            error.statusCode == null ||
            error.statusCode == 408 ||
            (error.statusCode ?? 0) >= 500;
        final old = unavailable ? historicalAnswer : null;
        final response = old?['response'] as Map?;
        _messages.add({
          'isMe': false,
          'text': response?['reply'] == null
              ? _chatFailureMessage
              : _plainAiReply(response!['reply'].toString()),
          if (old != null)
            'cacheNotice':
                '연결을 확인하지 못해 이전 답변을 보여드려요.\n${_conversationDate(old['savedAt'].toString())} 저장 · 현재 약·건강정보는 다시 확인하지 않았어요.',
          if (response != null) 'sources': response['sources'] ?? [],
          'createdAt': DateTime.now().toIso8601String(),
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isMe': false,
          'text': '통신 중 문제가 발생했습니다.\n다시 시도해주세요.',
          'createdAt': DateTime.now().toIso8601String(),
        });
      });
    } finally {
      try {
        await _saveConversation();
      } catch (_) {
        if (mounted) {
          showSeniorSnackbar(context, '답변은 받았지만 대화를 저장하지 못했어요.', error: true);
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  bool _looksLikeMedicineIdentity(String text) {
    return RegExp(
      r'[0-9A-Za-z가-힣]{2,}(?:정|캡슐|연질|시럽|주사|액|패치|크림|산)(?=과|와|은|는|이|가|을|를|에|의|도|만|,|\s|$)',
    ).hasMatch(text.trim());
  }

  bool _isGeneralCoffeeMedicineQuestion(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final mentionsCoffee =
        normalized.contains('커피') || normalized.contains('카페인');
    final mentionsMedicine =
        normalized.contains('약') ||
        normalized.contains('복용') ||
        normalized.contains('먹');
    return mentionsCoffee &&
        mentionsMedicine &&
        !_looksLikeMedicineIdentity(text);
  }

  @override
  Widget build(BuildContext context) {
    final historyButton = _HistoryButton(
      onTap: _isLoading || _isLoadingMedicines
          ? null
          : _openPreviousConversations,
    );
    final medicine = _selectedMedicine;
    final shortName = medicine == null ? null : _shortName(medicine);
    // 지금 대화에서 아직 아무것도 안 물어봤을 때만 질문 보기를 보여 준다.
    // 약을 새로 고르면 거기서 대화가 다시 시작되므로 보기도 다시 나온다.
    final showSuggestions = _messages.length - _conversationStart <= 1;
    final suggestions = medicine == null
        ? _generalSuggestions
        : _medicineSuggestions;
    final greeting = _greeting(MvpSession.userName);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 머리와 약 고르는 칸은 흰 바탕 한 덩어리다. 경계선은 그 아래에
            // 한 번만 긋는다.
            SeniorHeader(
              borderColor: AppColors.surface,
              child: Row(
                children: [
                  const SeniorBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'AI 약사 상담',
                            style: AppText.screenTitle(size: 28),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  historyButton,
                ],
              ),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: _SubjectCard(
                key: const ValueKey('ai-subject-card'),
                medicineName: shortName,
                onTap: _isLoading ? null : _pickMedicines,
                onClear: _isLoading ? null : _clearMedicine,
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  for (final message in _messages) ...[
                    if (message['cacheNotice'] != null)
                      Text(
                        message['cacheNotice'].toString(),
                        style: AppText.caption(size: 14),
                      ),
                    _ChatBubble(
                      text: message['greeting'] == true
                          ? greeting
                          : message['text'] as String,
                      isMe: message['isMe'] as bool,
                      // 화면 제목이 이미 누구와 이야기하는지 말한다.
                      speaker: null,
                      sources:
                          (message['sources'] as List?)
                              ?.whereType<String>()
                              .toList(growable: false) ??
                          const [],
                      isHealthReply: message['isHealthReply'] == true,
                      healthHighlightTerms:
                          (message['healthHighlightTerms'] as List?)
                              ?.whereType<String>()
                              .toList(growable: false) ??
                          const [],
                      officialProductNames:
                          (message['officialProductNames'] as List?)
                              ?.whereType<String>()
                              .toList(growable: false) ??
                          const [],
                    ),
                    if (message['refreshQuestion'] != null)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => _sendMessage(
                                message: message['refreshQuestion'].toString(),
                                intent: message['refreshIntent'] as String?,
                                forceRefresh: true,
                              ),
                        child: const Text('최신 정보 확인'),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (_isLoadingMedicines) ...[
                    Text('내 약을 불러오는 중이에요…', style: AppText.caption(size: 18)),
                    const SizedBox(height: 12),
                  ] else if (_medicineLoadError != null) ...[
                    Text(
                      _medicineLoadError!,
                      style: AppText.caption(size: 16.5),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showSuggestions) ...[
                    const SizedBox(height: 4),
                    Text(
                      medicine == null ? '이렇게 물어보셔도 돼요' : '이 약에 대해 많이 묻는 것',
                      style: AppText.caption(size: 18.5),
                    ),
                    const SizedBox(height: 10),
                    for (final suggestion in suggestions) ...[
                      SeniorCard(
                        key: ValueKey('suggestion-${suggestion['label']}'),
                        onTap: _isLoading
                            ? null
                            : () => _askSuggestion(suggestion),
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: Text(
                          suggestion['label']!,
                          style: AppText.cardTitle(size: 20),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (_isLoading) ...[
                    const SizedBox(height: 4),
                    Text('답변을 작성하고 있어요', style: AppText.caption(size: 18)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      key: const ValueKey('pharmacist-chat-input'),
                      constraints: const BoxConstraints(minHeight: 60),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.strongLine,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _chatController,
                        focusNode: _chatFocusNode,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: AppText.body(size: 20),
                        decoration: InputDecoration(
                          hintText: shortName == null
                              ? '여기에 물어보세요'
                              : '$shortName에 대해 물어보세요',
                          hintStyle: AppText.body(
                            size: 20,
                            color: AppColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: '질문 보내기',
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => _sendMessage(),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _isLoading
                              ? AppColors.inactive
                              : AppColors.point,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const ExcludeSemantics(
                          child: Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
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

/// 머리 아래 칸. 약을 고르기 전에는 "약 고르기", 고른 뒤에는 그 약과
/// 빼는 단추를 보여 준다. 고르지 않아도 묻는 데는 아무 지장이 없다.
class _SubjectCard extends StatelessWidget {
  final String? medicineName;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _SubjectCard({super.key, this.medicineName, this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    final name = medicineName;
    final picked = name != null;
    return Semantics(
      button: true,
      label: picked ? '물어볼 약 $name' : '물어볼 약 고르기',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: picked ? AppColors.pointTint : AppColors.bg,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            picked ? 12 : 16,
            picked ? 12 : 18,
            picked ? 12 : 16,
          ),
          child: Row(
            children: [
              Icon(
                TablerIcons.pill,
                size: 28,
                color: picked ? AppColors.point : AppColors.textPrimary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: picked
                    ? Text(
                        name,
                        style: AppText.cardTitle(size: 22),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('약 고르기', style: AppText.cardTitle(size: 22)),
                          const SizedBox(height: 2),
                          Text(
                            '약 하나만 물어볼 때',
                            style: AppText.caption(size: 16.5),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 10),
              if (picked)
                Semantics(
                  button: true,
                  label: '고른 약 빼기',
                  child: GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(TablerIcons.x, size: 20),
                          const SizedBox(width: 4),
                          Text('삭제', style: AppText.label(size: 19)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const SeniorChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 창에서 고른 결과. 내 약에서 고르면 [name], 이름으로 찾으면 [candidate].
class _MedicinePick {
  final String? name;
  final _DrugSearchCandidate? candidate;

  const _MedicinePick({this.name, this.candidate});
}

/// 약 하나를 고르는 창.
///
/// 누르면 확인 단추 없이 바로 닫힌다. 여러 개를 고르는 길은 없앴다 —
/// 여러 약이 궁금하면 질문에 적으면 되고, 그 편이 훨씬 쉽다.
class _MedicinePickSheet extends StatefulWidget {
  final ApiClient apiClient;
  final List<String> medicines;
  final String Function(String name) shortName;

  /// 지금 고른 약. 그 줄에만 체크가 찬다.
  final String? selected;

  const _MedicinePickSheet({
    required this.apiClient,
    required this.medicines,
    required this.shortName,
    this.selected,
  });

  @override
  State<_MedicinePickSheet> createState() => _MedicinePickSheetState();
}

class _MedicinePickSheetState extends State<_MedicinePickSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<_DrugSearchCandidate> _candidates = const [];
  bool _isSearching = false;
  String? _errorMessage;
  String? _inFlightQuery;
  String? _lastCompletedQuery;
  int _requestSequence = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _requestSequence++;
    _controller.dispose();
    super.dispose();
  }

  void _searchNow(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) return;
    if (query == _inFlightQuery || query == _lastCompletedQuery) return;
    _search(query, ++_requestSequence);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final sequence = ++_requestSequence;
    final query = value.trim();
    setState(() {});
    if (query.length < 2) {
      setState(() {
        _candidates = const [];
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }
    if (query == _inFlightQuery || query == _lastCompletedQuery) return;
    _debounce = Timer(
      const Duration(milliseconds: 550),
      () => _search(query, sequence),
    );
  }

  Future<void> _search(String query, int sequence) async {
    if (query == _inFlightQuery) return;
    _inFlightQuery = query;
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
      setState(() {
        _candidates = candidates;
        _lastCompletedQuery = query;
      });
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
      if (_inFlightQuery == query) _inFlightQuery = null;
      if (mounted && sequence == _requestSequence) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = _controller.text.trim().length >= 2;
    return SeniorSheet(
      title: '어떤 약이 궁금하세요?',
      bodyGap: 18,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!searching) ...[
            Text('내 약', style: AppText.caption(size: 17.5)),
            const SizedBox(height: 10),
            if (widget.medicines.isEmpty)
              Text(
                '등록된 약이 없어요. 아래에서 약 이름으로 찾아보세요.',
                style: AppText.body(size: 18, color: AppColors.textBody),
              )
            else
              // 칸을 늘어놓지 않고 줄로 세운다. 오른쪽 스위치를 켜면 그 약을
              // 고른 것이다 — 약이 늘어도 줄만 길어질 뿐 모양이 흐트러지지
              // 않는다.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < widget.medicines.length; i++) ...[
                    if (i > 0) const SeniorDivider(),
                    _MedicineToggleRow(
                      label: widget.shortName(widget.medicines[i]),
                      picked: widget.selected == widget.medicines[i],
                      onPick: () => Navigator.of(
                        context,
                      ).pop(_MedicinePick(name: widget.medicines[i])),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 20),
          ],
          Text('다른 약은 이름으로 찾기', style: AppText.caption(size: 17.5)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.strongLine, width: 2),
            ),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                const Icon(TablerIcons.search, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('otherMedicineSearchField'),
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: _searchNow,
                    style: AppText.body(size: 20),
                    decoration: InputDecoration(
                      hintText: '약 이름 적기 (예: 타이레놀)',
                      hintStyle: AppText.body(
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (searching) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _buildSearchContent(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
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
        // 시트 안에서는 ListTile이 제 배경을 못 칠한다. 줄을 직접 그린다.
        return GestureDetector(
          key: ValueKey(
            'drugCandidate:${candidate.itemSeq ?? candidate.itemName}',
          ),
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              Navigator.of(context).pop(_MedicinePick(candidate: candidate)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.itemName,
                        style: AppText.cardTitle(size: 19),
                      ),
                      if (candidate.manufacturer != null)
                        Text(
                          candidate.manufacturer!,
                          style: AppText.caption(size: 16),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const SeniorChevron(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 내 약 한 칸. 누르면 바로 닫힌다.
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

String _conversationDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

class _PreviousConversationsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  const _PreviousConversationsScreen({required this.records});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: Column(
        children: [
          const SeniorBackHeader(title: '이전 대화'),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      '아직 저장된 대화가 없어요.',
                      style: AppText.caption(size: 18),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final messages = record['messages'] as List;
                      final first = messages.firstWhere(
                        (item) => item['isMe'] == true,
                      );
                      return SeniorCard(
                        onTap: () async {
                          final resume = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  _PreviousConversationScreen(record: record),
                            ),
                          );
                          if (resume == true && context.mounted) {
                            Navigator.of(context).pop(record);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record['title'] as String,
                              style: AppText.cardTitle(size: 21),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _conversationDate(record['updatedAt']),
                              style: AppText.caption(size: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              first['text'] as String,
                              style: AppText.label(size: 18),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _PreviousConversationScreen extends StatelessWidget {
  final Map<String, dynamic> record;
  const _PreviousConversationScreen({required this.record});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: Column(
        children: [
          const SeniorBackHeader(title: '이전 대화'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  record['title'] as String,
                  style: AppText.cardTitle(size: 21),
                ),
                const SizedBox(height: 16),
                for (final message in record['messages'] as List) ...[
                  if (message['cacheNotice'] != null)
                    Text(
                      message['cacheNotice'].toString(),
                      style: AppText.caption(size: 14),
                    ),
                  Text(
                    _conversationDate(
                      message['createdAt'] ?? record['updatedAt'],
                    ),
                    style: AppText.caption(size: 14),
                  ),
                  const SizedBox(height: 6),
                  _ChatBubble(
                    text: message['text'] as String,
                    isMe: message['isMe'] == true,
                    sources: (message['sources'] as List? ?? [])
                        .whereType<String>()
                        .toList(),
                    isHealthReply: message['isHealthReply'] == true,
                    healthHighlightTerms:
                        (message['healthHighlightTerms'] as List? ?? [])
                            .whereType<String>()
                            .toList(),
                    officialProductNames:
                        (message['officialProductNames'] as List? ?? [])
                            .whereType<String>()
                            .toList(),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SeniorButton(
              label: '이어서 대화하기',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;

  /// 누가 한 말인지. 알콩이 답장에만 적는다.
  final String? speaker;
  final List<String> officialProductNames;
  final bool isHealthReply;
  final List<String> healthHighlightTerms;
  final List<String> sources;

  const _ChatBubble({
    required this.isMe,
    required this.text,
    this.speaker,
    this.officialProductNames = const [],
    this.isHealthReply = false,
    this.healthHighlightTerms = const [],
    this.sources = const [],
  });

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
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaker != null) ...[
                    Text(
                      speaker!,
                      style: AppText.cardTitle(
                        size: 18,
                        color: AppColors.point,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text.rich(
                    TextSpan(
                      children: _officialProductNameSpans(
                        text,
                        isMe
                            ? const []
                            : isHealthReply
                            ? healthHighlightTerms
                            : officialProductNames,
                        AppText.body(
                          size: 20,
                          color: isMe ? Colors.white : AppColors.textPrimary,
                        ),
                        emphasisColor: isHealthReply
                            ? AppColors.danger
                            : AppColors.detailEmphasis,
                        healthWarningsOnly: isHealthReply,
                      ),
                    ),
                  ),
                  if (!isMe && sources.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '출처: ${sources.join(' · ')}',
                      style: AppText.caption(size: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 44),
        ],
      ),
    );
  }
}

List<TextSpan> _officialProductNameSpans(
  String text,
  List<String> officialProductNames,
  TextStyle baseStyle, {
  Color emphasisColor = AppColors.detailEmphasis,
  bool healthWarningsOnly = false,
}) {
  final names =
      officialProductNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort((left, right) => right.length.compareTo(left.length));
  if (names.isEmpty) return [TextSpan(text: text, style: baseStyle)];

  final matches = <({int start, int end})>[];
  var cursor = 0;
  while (cursor < text.length) {
    ({int start, int end})? next;
    for (final name in names) {
      var start = text.indexOf(name, cursor);
      while (start >= 0 &&
          (!_hasOfficialProductNameBoundary(text, start, name) ||
              (healthWarningsOnly && !_isHealthWarningSentence(text, start)))) {
        start = text.indexOf(name, start + 1);
      }
      if (start < 0) continue;
      final candidate = (start: start, end: start + name.length);
      if (next == null ||
          candidate.start < next.start ||
          (candidate.start == next.start && candidate.end > next.end)) {
        next = candidate;
      }
    }
    if (next == null) break;
    matches.add(next);
    cursor = next.end;
  }
  if (matches.isEmpty) return [TextSpan(text: text, style: baseStyle)];

  final spans = <TextSpan>[];
  cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: baseStyle.copyWith(
          color: emphasisColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

bool _isHealthWarningSentence(String text, int start) {
  final delimiters = RegExp(r'[.!?。\n]');
  var sentenceStart = 0;
  var sentenceEnd = text.length;
  for (final match in delimiters.allMatches(text)) {
    if (match.start < start) {
      sentenceStart = match.end;
    } else {
      sentenceEnd = match.start;
      break;
    }
  }
  return !RegExp(
    r'확인(?:하지|되지|할 수).*(?:못|않)|정보.*(?:없어|없음)|안내.*찾지 못|가족력|가족의',
  ).hasMatch(text.substring(sentenceStart, sentenceEnd));
}

bool _hasOfficialProductNameBoundary(String text, int start, String name) {
  final word = RegExp(r'[A-Za-z0-9가-힣_]');
  if (start > 0 && word.hasMatch(text[start - 1])) return false;
  final end = start + name.length;
  if (end >= text.length || !word.hasMatch(text[end])) return true;

  const particles = [
    '에게',
    '께서',
    '처럼',
    '보다',
    '에서',
    '으로',
    '은',
    '는',
    '이',
    '가',
    '을',
    '를',
    '과',
    '와',
    '의',
    '에',
    '로',
    '도',
    '만',
  ];
  for (final particle in particles) {
    if (!text.startsWith(particle, end)) continue;
    final afterParticle = end + particle.length;
    if (afterParticle >= text.length || !word.hasMatch(text[afterParticle])) {
      return true;
    }
  }
  return false;
}

const _medicineLoadFailureMessage = '지금은 등록한 약을 불러오지 못했어요.\n잠시 후 다시 시도해 주세요.';

const _chatFailureMessage =
    '지금은 답변을 불러오지 못했어요.\n'
    '잠시 후 다시 시도해 주세요.\n'
    '약의 사용 방법을 임의로 바꾸지는 마세요.';

String _plainAiReply(String value) {
  var text = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(
    RegExp(r'^[ \t]*```(?:[A-Za-z][A-Za-z0-9_-]*)?[ \t]*$', multiLine: true),
    '',
  );
  text = text.replaceAll(
    RegExp(r'^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$', multiLine: true),
    '',
  );
  text = text.replaceAll(
    RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}>+[ \t]?', multiLine: true), '');
  text = text.replaceAll(
    RegExp(r'^[ \t]{0,3}\d+[.)][ \t]+', multiLine: true),
    '• ',
  );
  text = text.replaceAll(
    RegExp(r'^[ \t]{0,3}[-*+][ \t]+', multiLine: true),
    '• ',
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*([^*\n]+)\*\*'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'__([^\n]+?)__'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<![A-Za-z0-9가-힣_*])\*([^*\s\n](?:[^*\n]*?[^*\s\n])?)\*(?!\*)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'(?<![A-Za-z0-9가-힣_])_([^_\s\n](?:[^_\n]*?[^_\s\n])?)_(?!_)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]\n]+)\]\([^\s)]+(?:\s+"[^"]*")?\)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll('`', '');
  text = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]{3,}'), ' ').trimRight())
      .join('\n');
  text = _withoutClosingDisclaimer(text);
  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 답장 끝에 늘 붙는 면책 한 줄을 뗀다.
///
/// 매번 같은 말이 붙으면 어르신은 그 줄을 읽지 않고 넘기게 되고, 정작
/// 읽어야 할 주의사항까지 같이 묻힌다. 약을 바꾸거나 끊는 일을 혼자
/// 정하지 말라는 말은 약 자세히와 이용 안내에 그대로 남아 있다.
String _withoutClosingDisclaimer(String text) {
  final lines = text.split('\n');
  while (lines.isNotEmpty) {
    final last = lines.last.replaceFirst(RegExp(r'^[•\-\s]+'), '').trim();
    if (last.isEmpty) {
      lines.removeLast();
      continue;
    }
    final isDisclaimer =
        last.length <= 80 &&
        RegExp(r'(약사|의사|전문가)').hasMatch(last) &&
        RegExp(r'(상의|상담|문의)하').hasMatch(last);
    if (!isDisclaimer) break;
    lines.removeLast();
  }
  return lines.join('\n');
}

/// 머리 오른쪽의 "이전 대화" 칸.
///
/// 작은 글자 단추로 두었더니 지난 이야기를 다시 볼 수 있다는 것을 모르고
/// 같은 것을 또 물으셨다. 글자만 두지 않고 칸으로 세워 눈에 띄게 한다.
class _HistoryButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _HistoryButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = enabled ? AppColors.textPrimary : AppColors.inactiveLabel;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '이전 대화 보기',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(TablerIcons.history, size: 22, color: ink),
                const SizedBox(width: 6),
                Text('이전 대화', style: AppText.cardTitle(size: 18, color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 내 약 한 줄. 오른쪽 스위치를 켜면 그 약으로 고른다.
class _MedicineToggleRow extends StatelessWidget {
  final String label;

  /// 지금 고른 약이면 체크가 찬다.
  final bool picked;
  final VoidCallback onPick;

  const _MedicineToggleRow({
    required this.label,
    required this.onPick,
    this.picked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label 고르기',
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('medicine-selection-$label'),
          onTap: onPick,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppText.cardTitle(
                      size: 19,
                      color: picked ? AppColors.point : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: picked ? AppColors.point : Colors.transparent,
                    shape: BoxShape.circle,
                    border: picked
                        ? null
                        : Border.all(color: AppColors.strongLine, width: 2),
                  ),
                  child: picked
                      ? const Icon(
                          TablerIcons.check,
                          size: 18,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
