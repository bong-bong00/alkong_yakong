"""Presentation policy over verified label text, never a medical inference engine."""
import re


def food_question(message):
    text = re.sub(r'\s+', '', message)
    return bool(re.search(r'음식|식품|우유|자몽|커피|카페인|음료|음주|알코올', text)
                or re.search(r'(?<![가-힣])술(?:을|과|은|이|도|\s|\?|$)', message))


def food_only_question(message):
    """Mixed food/drug-pair questions still require the medication-pair check."""
    return food_question(message) and not re.search(r'다른\s*약|약끼리|병용|상호작용|두\s*약|세\s*약|약들', message)


def broad_stop_instruction(reply):
    return bool(re.search(
        r'(?:(?:이러한|이런|위와\s*같은|평소와\s*다른|어떤)\s*증상|이상\s*(?:증상|반응)|부작용)'
        r'[^.!?\n]{0,100}(?:중단|중지)', reply))


def label_dosage_voice(reply):
    # Preserve all numbers/conditions; frame a quoted label as a label, not a
    # personalized prescription. Do not synthesize a dose or change a number.
    reply = re.sub(r'드세요(?=[.!?\n]|$)', '복용하도록 설명서에 기재되어 있습니다', reply)
    return reply


def complete_units(text):
    """Keep decimal numbers and parenthetical qualification clauses intact."""
    text = re.sub(r'\s+', ' ', str(text or '')).strip()
    depth, start, units = 0, 0, []
    for i, ch in enumerate(text):
        if ch in '(（': depth += 1
        elif ch in ')）': depth = max(0, depth - 1)
        if not depth and ch in '.!?。' and (i + 1 == len(text) or text[i + 1].isspace()):
            units.append(text[start:i + 1].strip()); start = i + 1
    if text[start:].strip(): units.append(text[start:].strip())
    return [u for u in units if u]


def official_excerpt_reply(contexts, intents, *, food=False):
    """A bounded, explicitly partial quotation when generation is unavailable.

    Do not cut clauses to fit, infer safety from no match, or present a label
    quotation as a full interaction assessment.
    """
    fields = (('interaction', 'cautions') if food else
              ('efficacy',) if intents & {'overview', 'efficacy'} else
              ('usage',) if intents & {'dosage', 'usage'} else
              ('side_effects', 'cautions') if 'side_effects' in intents else ('cautions',))
    parts = []
    for context in contexts:
        name = str(context.get('product_name') or '').split('(')[0].strip()
        if not name: continue
        units = [u for field in fields for u in complete_units(context.get(field))
                 if not re.fullmatch(r'(?:사용상의\s*주의사항|주의사항|용법\s*용량|효능\s*효과)?\s*[\d.)\s]*', u)
                 and len(re.sub(r'[\d\W_]', '', u)) >= 4]
        if food:
            units = [u for u in units if food_question(u)]
        share = max(50, 410 // max(1, len(contexts)) - len(name))
        unit = next((u for u in units if len(u) <= share and not broad_stop_instruction(u)), None)
        detail = ('공식 안내 일부: “' + unit + '”' if unit else
                  '질문과 관련된 공식 안내의 세부 조건을 이 답변에서 확인하지 못했어요.')
        parts.append(name + ': ' + detail)
    if not parts: return None
    return '\n'.join(parts) + '\n일부 내용만 안내했어요. 안전하다는 뜻은 아니며, 정확한 적용 조건은 의사나 약사에게 확인해 주세요.'
