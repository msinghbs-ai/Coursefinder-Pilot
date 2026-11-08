#!/usr/bin/env python3
# Guards: IQ-00313: the correction file (docs/paste/PASTE-20261108-iq00313-deakin-intake-withdrawal.sql) is tested as written. Only its two data blocks
# (CONSTANTS and TARGETS: the production ids and the rejected value) are replaced by the fixture's own contaminated intakes; every guard, the withdrawal,
# the rejection, the reconciliation, the verification and the audit run as they are in the file.
import re, subprocess, sys
paste, db = sys.argv[1], sys.argv[2]
names = (sys.argv[3] if len(sys.argv) > 3 else 'cC,cD').split(',')
in_names = ', '.join("'" + n + "'" for n in names)
def q(sql):
    return subprocess.run(['psql', '-X', '-At', '-F', '\t', '-d', db, '-c', sql], check=True, capture_output=True, text=True).stdout.strip().splitlines()
y0 = int(q('select public.fixture_dk_y0()')[0])
prov, prop = q("select provider_id, proposal_id from public.dk_cases where name = 'calendar'")[0].split('\t')
src = q("select i.source_id from public.dk_cases k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'cC'")[0]
rows = q("select k.intake_id, k.course_id, coalesce(i.source_intake_key, ''), c.canonical_title from public.dk_cases k join catalogue.course_intakes i on i.id = k.intake_id "
         "join catalogue.courses c on c.id = k.course_id where k.name in (" + in_names + ") order by k.name")
consts = ("  create temp table iq00313_const on commit drop as select\n"
          f"    date '{y0 + 1}-11-01' as bad_date, {y0 + 1} as bad_year, 'November'::text as label, 'calendar-v3'::text as rule,\n"
          f"    '{prov}'::uuid as provider_id, '{prop}'::uuid as proposal_id,\n"
          f"    'Trimester 3: 1 Nov - 28 Jan {y0 + 1}'::text as quote, '{src}'::uuid as source_id;\n")
vals = ",\n".join("    ('%s'::uuid, '%s'::uuid, %s, '%s')" % (r.split('\t')[0], r.split('\t')[1], ("'" + r.split('\t')[2] + "'") if r.split('\t')[2] else 'null::text', r.split('\t')[3].replace("'", "''")) for r in rows)
targets = "  create temp table iq00313_targets on commit drop as select * from (values\n" + vals + "\n  ) t(intake_id, course_id, expected_key, title);\n"
s = open(paste).read()
for tag, body in (('CONSTANTS', consts), ('TARGETS', targets)):
    s, n = re.subn(r'(  -- %s-BEGIN\n).*?(  -- %s-END\n)' % (tag, tag), lambda m: m.group(1) + body + m.group(2), s, flags=re.S)
    if n != 1:
        sys.exit('marker %s not found exactly once' % tag)
print(s)
