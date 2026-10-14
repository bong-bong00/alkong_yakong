import pytest
from app.services.ocr.parser import parse_prescription_text, _tables_from_field_coordinates


def field(text, x, y, confidence=0.99):
    return {'text': text, 'confidence': confidence,
        'boundingPoly': {'vertices': [{'x': x-20, 'y': y-20}, {'x': x+20, 'y': y-20},
                                      {'x': x+20, 'y': y+20}, {'x': x-20, 'y': y+20}]}}


def prescription_fields():
    fields = [field('투약량', 300, 0), field('투여횟수', 400, 0), field('일수', 500, 0)]
    for i, name in enumerate(['프리마란정', '아디팜정', '휴온스시메티딘정200밀리그램', '프레벨액0.25%'], 1):
        y = i * 120
        fields += [field(name, 80, y), field('1.00' if i == 4 else '0.50', 300, y+15),
                   field('1' if i == 4 else '3', 400, y+12), field('1' if i == 4 else '7', 500, y+5)]
    return fields


def test_header_only_table_and_scrambled_ocr_order_preserve_all_four_dosing_rows():
    fields = prescription_fields()
    # The final days field occurs before the drug name in OCR traversal order.
    raw = '약품명 1회 투약량 1일 투여횟수 투약 일수\n7\n프리마란정\n0.50\n3\n7\n아디팜정\n0.50\n3\n휴온스시메티딘정200밀리그램\n0.50\n3\n7\n1\n프레벨액0.25%\n1.00\n1'
    table = {'cells': [{'rowIndex': 0, 'columnIndex': 0, 'text': '약품명'},
                       {'rowIndex': 0, 'columnIndex': 1, 'text': '복용법 1회 투약량 1일 투여횟수 투약일수'}]}
    result = parse_prescription_text(raw, tables=[table], fields=fields)
    items = result['items']
    assert len(items) == 4
    assert result['parser_engine'] == 'heuristic+clova-coordinates'
    assert [(float(i['dosage']), i['frequency_per_day'], i['duration_days']) for i in items] == [
        (0.5, 3, 7), (0.5, 3, 7), (0.5, 3, 7), (1.0, 1, 1)]
    assert result['dosing_diagnostics']['missing_counts']['duration_days'] == 0


def test_ambiguous_cells_are_not_guessed():
    fields = prescription_fields()[:7]
    fields.append(field('9', 503, 125))
    tables = _tables_from_field_coordinates(fields)
    assert all(cell['rowIndex'] == 0 for cell in tables[0]['cells'])


@pytest.mark.parametrize('confidence', [0.1, float('nan'), 2])
def test_unreliable_numeric_field_cannot_supply_a_complete_row(confidence):
    fields = prescription_fields()[:7]
    fields[-1]['confidence'] = confidence
    tables = _tables_from_field_coordinates(fields)
    assert all(cell['rowIndex'] == 0 for cell in tables[0]['cells'])


def test_geometry_does_not_invent_headers_or_copy_a_different_drug_row():
    fields = prescription_fields()[3:7]
    assert _tables_from_field_coordinates(fields) == []
    fields = prescription_fields()[:7]
    fields[-1] = field('7', 500, 250)
    assert all(cell['rowIndex'] == 0 for cell in _tables_from_field_coordinates(fields)[0]['cells'])


def test_invalid_bounds_fail_safely():
    fields = prescription_fields()[:7] + [{'text': '7', 'boundingPoly': []}]
    assert _tables_from_field_coordinates(fields)
