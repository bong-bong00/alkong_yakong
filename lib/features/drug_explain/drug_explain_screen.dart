import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DrugExplainScreen extends StatelessWidget {
  const DrugExplainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('AI 약물 설명'),
        backgroundColor: kPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE3EEF8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB8CCE0)),
              ),
              child: Row(
                children: [
                  const Text('🤖', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '식약처 공식 데이터를 기반으로 내 증상에 맞춘 쉬운 설명을 제공해요',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '내 약 목록',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 12),
            const _DrugCard(
              name: '암로디핀 5mg',
              category: '혈압약',
              simpleExplain: '혈관을 넓혀서 혈압을 낮추는 약이에요.',
              howToTake: '1일 1회, 아침에 드세요.',
              warnings: ['자몽주스와 함께 드시지 마세요.', '어지러울 수 있으니 갑자기 일어나지 마세요.'],
              myCondition: '고혈압에 직접 효과가 있는 약이에요.',
            ),
            const SizedBox(height: 12),
            const _DrugCard(
              name: '메트포르민 500mg',
              category: '당뇨약',
              simpleExplain: '혈당을 낮추는 약이에요. 간에서 포도당이 만들어지는 것을 줄여줘요.',
              howToTake: '1일 2회, 아침·저녁 식사와 함께 드세요.',
              warnings: ['술을 많이 드시면 안 돼요.', '설사가 날 수 있어요.'],
              myCondition: '당뇨병 관리에 핵심적인 약이에요.',
            ),
            const SizedBox(height: 12),
            const _DrugCard(
              name: '아스피린 100mg',
              category: '혈전 예방',
              simpleExplain: '피가 굳는 것을 막아서 혈관이 막히지 않게 해주는 약이에요.',
              howToTake: '1일 1회, 아침 식후에 드세요.',
              warnings: ['위장에 부담이 될 수 있어요.', '출혈이 잘 멈추지 않을 수 있어요.'],
              myCondition: '혈전 예방을 위해 복용하는 약이에요.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DrugCard extends StatefulWidget {
  final String name;
  final String category;
  final String simpleExplain;
  final String howToTake;
  final List<String> warnings;
  final String myCondition;

  const _DrugCard({
    required this.name,
    required this.category,
    required this.simpleExplain,
    required this.howToTake,
    required this.warnings,
    required this.myCondition,
  });

  @override
  State<_DrugCard> createState() => _DrugCardState();
}

class _DrugCardState extends State<_DrugCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: _expanded ? Border.all(color: kPrimary, width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        widget.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                      ),
                      Text(
                        widget.category,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kTextSub,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.simpleExplain,
              style: const TextStyle(fontSize: 14, color: kText, height: 1.5),
            ),
            if (_expanded) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              _Section(emoji: '⏰', title: '복용법', content: widget.howToTake),
              const SizedBox(height: 12),
              _Section(
                emoji: '⚠️',
                title: '주의사항',
                content: widget.warnings.map((w) => '• $w').join('\n'),
              ),
              const SizedBox(height: 12),
              _Section(
                emoji: '🩺',
                title: '내 증상과의 관계',
                content: widget.myCondition,
              ),
              const SizedBox(height: 10),
              Text(
                '출처: 식약처 의약품개요정보(e약은요)',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String emoji;
  final String title;
  final String content;
  const _Section({
    required this.emoji,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              title,
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
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}
