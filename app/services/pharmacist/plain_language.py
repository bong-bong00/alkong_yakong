"""Explain terminology without replacing clinical conditions or prescribing advice.

Definitions: https://www.nhlbi.nih.gov/health/long-qt-syndrome
https://medlineplus.gov/fluidandelectrolytebalance.html
https://www.ncbi.nlm.nih.gov/books/NBK459388/
"""
import re

# Keep the original term, severity, negation, numbers and exceptions intact.
_GLOSSARY = (
    (r"QT\s*간격\s*연장|QT\s*연장", "심장이 다음 박동을 준비하는 전기 신호의 시간이 길어지는 상태"),
    (r"QT\s*간격", "심장이 다음 박동을 준비하는 전기 신호의 시간"),
    (r"저칼륨혈증", "혈액 속 칼륨이 부족한 상태"),
    (r"저마그네슘혈증", "혈액 속 마그네슘이 부족한 상태"),
    (r"Torsades?\s+de\s+pointes", "심장이 매우 빠르고 불규칙하게 뛰는 부정맥의 한 종류"),
)


def explain_health_terms(text: str) -> str:
    """Add a short explanation once, including in deterministic fallback replies."""
    explained_qt = False
    for pattern, explanation in _GLOSSARY:
        if pattern == r"QT\s*간격" and explained_qt:
            continue
        match = re.search(pattern, text, re.I)
        if match is None:
            continue
        following = text[match.end():].lstrip()
        # Do not duplicate an existing Korean explanation immediately after a term.
        parenthetical = re.match(r"[（(]([^()（）]{2,100})[）)]", following)
        if parenthetical and re.search(r"혈액|박동|전기 신호|부정맥|상태", parenthetical[1]):
            if pattern.startswith("QT"):
                explained_qt = True
            continue
        text = text[:match.end()] + f"({explanation})" + text[match.end():]
        if pattern.startswith("QT"):
            explained_qt = True
    return text
