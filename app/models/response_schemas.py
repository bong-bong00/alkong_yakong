from pydantic import BaseModel, ConfigDict


class ApiResponse(BaseModel):
    model_config = ConfigDict(extra="allow")


class DrugSearchItemResponse(ApiResponse):
    item_name: str
    manufacturer: str | None = None
    item_seq: str | None = None


class DrugSearchResponse(ApiResponse):
    query: str
    count: int
    items: list[DrugSearchItemResponse]


class ChatResponse(ApiResponse):
    reply: str


class MedicineResponse(ApiResponse):
    id: int
    medicine_code: str
    product_name: str
    ingredient: str
    manufacturer: str | None = None
    efficacy: str | None = None
    usage: str | None = None
    precautions: str | None = None
    image_url: str | None = None
    created_at: str
    updated_at: str


class DrugExplanationDetailResponse(ApiResponse):
    medicine_code: str | None = None
    drug_name: str | None = None
    ingredient: str | None = None
    easy_summary: str
    what_it_does: str
    how_to_take: str
    cautions: list[str]
    possible_side_effects: list[str]
    storage: str
    ask_doctor_when: list[str]
    generated_by: str
    source: str
    is_verified: bool
    source_based: bool
    official_raw_summary: str


class DrugExplanationResponse(DrugExplanationDetailResponse):
    medicine: MedicineResponse
    explanation: DrugExplanationDetailResponse
