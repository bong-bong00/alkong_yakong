"""Narrow, reviewed general questions; never a product-specific prescription.

Source checked 2026-10-16: https://nedrug.mfds.go.kr/cntnts/127
Only exact general questions are eligible. Specific medicines, symptoms and
storage temperatures must use their own verified product information.
"""
import re

SOURCE = "식약처 의약품안전나라 · 약물복용 안전수칙"
SOURCE_URL = "https://nedrug.mfds.go.kr/cntnts/127"

_ANSWERS = (
    (("약 보관할 때 주의할 점은요?", "약을 보관할 때 일반적으로 확인할 주의사항을 알려주세요.", "약 보관법은요?"),
     "약은 포장이나 설명서의 저장방법과 약사가 알려준 보관법을 따라 보관하세요. "
     "어린이가 만질 수 없는 곳에 두고, 다른 용기에 옮겨 담지 않는 것이 좋아요. "
     "보관 조건은 약마다 다르므로 모든 약을 같은 온도나 냉장고에 보관하지 말고 해당 약의 안내를 확인하세요."),
    (("약 설명서에서 무엇을 확인하나요?", "약 설명서에서 확인해야 하는 항목을 쉽게 알려주세요."),
     "설명서에서 성분, 사용 목적(효능·효과), 사용하는 방법과 양(용법·용량), "
     "사용상의 주의사항, 저장방법을 확인하세요. 특히 사용하면 안 되는 경우, "
     "함께 쓰지 말아야 하는 약, 이상 증상이 생겼을 때의 안내를 살펴보세요. "
     "실제 사용은 처방과 의사·약사의 안내를 따르세요."),
    (("약을 먹을 때 물로 먹어야 하나요?", "약은 꼭 물로 먹어야 하나요?"),
     "일반적인 알약·캡슐은 별도 지시가 없다면 물과 함께 복용해요. "
     "하지만 혀 밑에서 녹이는 약이나 입에서 녹는 약처럼 사용법이 다른 제형도 있어요. "
     "모든 약을 물로 삼키는 것은 아니므로 해당 약의 설명서와 의사·약사 안내를 확인하세요."),
)


def general_guidance(message):
    normalize = lambda s: re.sub(r"[\s.!?？]", "", s)
    question = normalize(message)
    for variants, reply in _ANSWERS:
        if question in {normalize(v) for v in variants}:
            return reply
    return None
