#!/usr/bin/env python3
# CF-247 RM1B (approval A-4, Platform Admin 17 Nov 2026 07:35): Postal Area to Significant Urban Area shares from the ASGS Edition 3 (2021)
# Mesh Block allocation files. For each Postal Area (POA_2021_AUST: Mesh Block -> POA, with Mesh Block area) the area of its Mesh Blocks is
# summed per SUA (MB_2021_AUST: Mesh Block -> SA2; SUA_2021_AUST: SA2 -> SUA). Columns are found by name, never by position.
# Usage: abs_postcode_sua_shares.py <MB_2021_AUST.xlsx> <POA_2021_AUST.xlsx> <SUA_2021_AUST.xlsx> <out.json>
import json, re, sys
from collections import defaultdict
from openpyxl import load_workbook


def rows(path, wanted):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]
    it = ws.iter_rows(values_only=True)
    head = [str(c or '').strip().upper() for c in next(it)]
    idx = []
    for w in wanted:
        if w not in head:
            raise SystemExit(f'{path}: column {w} not found in {head}')
        idx.append(head.index(w))
    n = 0
    for r in it:
        n += 1
        yield tuple(r[i] for i in idx)
    print(f'{path}: {n} rows', file=sys.stderr)


def code(v):
    s = str(v if v is not None else '').strip()
    return s[:-2] if s.endswith('.0') else s


mb_file, poa_file, sua_file, out = sys.argv[1:5]
sa2_sua = {}
for sa2, sua, name in rows(sua_file, ['SA2_CODE_2021', 'SUA_CODE_2021', 'SUA_NAME_2021']):
    sa2_sua[code(sa2)] = (code(sua), str(name or '').strip())
mb_sa2 = {code(mb): code(sa2) for mb, sa2 in rows(mb_file, ['MB_CODE_2021', 'SA2_CODE_2021'])}

overlap = defaultdict(float)
mbs = defaultdict(int)
total = defaultdict(float)
names = {}
missing = 0
for mb, poa, area in rows(poa_file, ['MB_CODE_2021', 'POA_CODE_2021', 'AREA_ALBERS_SQKM']):
    poa = code(poa)
    if not re.fullmatch(r'\d{4}', poa):
        continue  # non-postal codes (no usual address, offshore, shipping)
    a = float(area or 0)
    sua = sa2_sua.get(mb_sa2.get(code(mb), ''))
    if not sua:
        missing += 1
        continue
    total[poa] += a
    overlap[(poa, sua[0])] += a
    mbs[(poa, sua[0])] += 1
    names[sua[0]] = sua[1]

result = [
    {'postcode': p, 'sua_code': s, 'sua_name': names[s], 'overlap_sqkm': round(v, 6), 'postcode_sqkm': round(total[p], 6), 'mesh_blocks': mbs[(p, s)]}
    for (p, s), v in sorted(overlap.items()) if total[p] > 0
]
json.dump({'rows': result, 'stats': {'postcodes': len(total), 'rows': len(result), 'mesh_blocks_without_sua': missing}}, open(out, 'w'))
print(json.dumps({'postcodes': len(total), 'rows': len(result), 'mesh_blocks_without_sua': missing}), file=sys.stderr)
