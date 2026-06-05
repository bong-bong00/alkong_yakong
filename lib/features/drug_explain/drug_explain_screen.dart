import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

/// 약정보 탭.
/// - 상단 DUR 위험도 배너(전체 복용 약 위험도) → 탭하면 DUR 상세
/// - 처방전 등록 진입
/// - 직접 검색(아무 약이나 검색해서 쉬운 설명 보기)
/// - 내 약 목록(펼침/접힘 카드): 쉬운 설명·복용법·주의사항·내 증상 관계·출처
class DrugExplainScreen extends StatefulWidget {
  const DrugExplainScreen({super.key});

  @override
  State<DrugExplainScreen> createState() => _DrugExplainScreenState();
}

class _DrugExplainScreenState extends State<DrugExplainScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Map<String, String>? _searchResult;

  // 더미: 내가 복용 중인 약
  final List<Map<String, String>> _myDrugs = const [
    {
      'name': '암로디핀 5mg',
      'tag': '혈압약',
      'easy': '혈관을 넓혀서 높은 혈압을 천천히 낮춰주는 약이에요.',
      'dose': '하루 1번, 아침에 1정',
      'caution': '어지러울 수 있어요. 자몽주스와 함께 먹지 마세요.',
      'relation': '고혈압 관리를 위해 처방됐어요.',
      'source': '식약처 e약은요',
    },
    {
      'name': '메트포르민 500mg',
      'tag': '당뇨약',
      'easy': '몸이 혈당을 잘 쓰도록 도와 혈당을 낮추는 약이에요.',
      'dose': '하루 2번, 식사와 함께',
      'caution': '처음엔 속이 불편할 수 있어요. 물을 충분히 드세요.',
      'relation': '당뇨병 관리를 위해 처방됐어요.',
      'source': '식약처 e약은요',
    },
    {
      'name': '아스피린 100mg',
      'tag': '혈전 예방',
      'easy': '피를 묽게 만들어 혈관이 막히는 걸 예방하는 약이에요.',
      'dose': '하루 1번, 아침에 1정',
      'caution': '위장이 약하면 속쓰림이 있을 수 있고, 멍·출혈에 주의하세요.',
      'relation': '혈전(피떡) 예방을 위해 처방됐어요.',
      'source': '식약처 e약은요',
    },
  ];

  // 더미 검색 DB (실제로는 e약은요 + RAG 파이프라인이 채움)
  final List<Map<String, String>> _searchDb = const [
    {
      'name': '타이레놀 500mg',
      'tag': '해열·진통',
      'easy': '열을 내리고 통증을 줄여주는 약이에요.',
      'dose': '필요할 때 1정, 하루 최대 8정 이내',
      'caution': '간이 안 좋으면 주의하고, 술과 함께 먹지 마세요.',
      'relation': '검색한 약이에요. (현재 복용 약 아님)',
      'source': '식약처 e약은요',
    },
    {
      'name': '오메프라졸 20mg',
      'tag': '위산 억제',
      'easy': '위산이 많이 나오는 걸 줄여 속쓰림을 가라앉혀요.',
      'dose': '하루 1번, 식전 1정',
      'caution': '오래 복용 시 의사와 상의하세요.',
      'relation': '검색한 약이에요. (현재 복용 약 아님)',
      'source': '식약처 e약은요',
    },
  ];

  void _runSearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResult = null);
      return;
    }
    final all = [..._myDrugs, ..._searchDb];
    final hit = all.firstWhere(
      (d) => d['name']!.contains(q),
      orElse: () => {
        'name': q,
        'tag': '검색 결과',
        'easy': '$q 에 대한 쉬운 설명이에요. (예시 — 실제로는 공식 DB에서 검색해 생성)',
        'dose': '제품 설명서 기준 용법을 따르세요.',
        'caution': '복용 전 의사·약사와 상의하는 게 좋아요.',
        'relation': '검색한 약이에요.',
        'source': '식약처 e약은요',
      },
    );
    setState(() => _searchResult = hit);
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          '약 정보',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [kPrimary, Color(0xFF25B88A)]),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // DUR 위험도 배너
            GestureDetector(
              onTap: () => context.push('/dur-analysis'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFB7E4CF)),
                ),
                child: Row(
                  children: [
                    const Text('🛡️', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '복약 안전도',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '현재 복용 약 3개 · 병용 위험 없음',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B8B5A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'LOW',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF4B8B5A),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 직접 검색
            const Text(
              '약 직접 검색',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => _runSearch(),
                      decoration: const InputDecoration(
                        hintText: '약 이름을 입력하세요 (예: 타이레놀)',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _runSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kPrimary, Color(0xFF25B88A)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '검색',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_searchResult != null) ...[
              const SizedBox(height: 12),
              _DrugCard(drug: _searchResult!, highlight: true),
            ],
            const SizedBox(height: 22),

            // 내 약 + 처방전 등록
            Row(
              children: [
                const Text(
                  '내 약',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.push('/prescription'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 16, color: kPrimary),
                        SizedBox(width: 4),
                        Text(
                          '처방전 등록',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._myDrugs.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DrugCard(drug: d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 약 카드 (펼침/접힘).
class _DrugCard extends StatefulWidget {
  final Map<String, String> drug;
  final bool highlight;
  const _DrugCard({required this.drug, this.highlight = false});

  @override
  State<_DrugCard> createState() => _DrugCardState();
}

class _DrugCardState extends State<_DrugCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.highlight; // 검색 결과는 펼친 채로
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drug;
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: widget.highlight
            ? Border.all(color: kPrimary.withValues(alpha: 0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kPrimaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('💊', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d['tag'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _row('🟢', '쉬운 설명', d['easy'] ?? ''),
                  _row('⏰', '복용법', d['dose'] ?? ''),
                  _row('⚠️', '주의사항', d['caution'] ?? ''),
                  _row('🔗', '내 증상과의 관계', d['relation'] ?? ''),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '출처: ${d['source'] ?? ''} · 할루시네이션 검증 완료',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 19),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
