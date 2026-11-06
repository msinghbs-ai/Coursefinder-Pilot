#!/usr/bin/env bash
# Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026) for English requirements: production-parity fixture of the English path, and the
# baseline of today's behaviour on stored evidence (Platform Admin 6 Nov 2026 08:12: planning and independent validation only).
# Database round trip on isolated local PostgreSQL only (never a Supabase project):
#   1 the md5-verified production manifest (manifests/english-path.json) builds a fixture that checks clean against it;
#   2 production constraints refuse what production refuses (status, found_via, the proposal key, one row per course and test);
#   3 today's behaviour: svc_provider_policy_record files a faculty-table reading as no_values, and an AI reading with quoted defaults as
#     proposed (UNSW 17 Oct, then rejected by the Platform Admin as one faculty row), from the stored outcomes in stored-outcomes.json.
#   4 the migration 20261106550000 on the same fixture: the harness (labelled stand-ins), the migration, then groups-tests.sql (course groups, D1 scope, D2 approval and binding, D3 switch, D5 reparse, status).
# Databases use agent H's prefix (h_) and are dropped at the end (EN_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${EN_DB:-h_english_fixture}
FX=tests/fixtures/english-requirements TOOL=scripts/prod-parity-capture.mjs M=$FX/manifests/english-path.json
T=$(mktemp -d); P="psql -X -q -v ON_ERROR_STOP=1"
cleanup() { [ -n "${EN_KEEP:-}" ] || dropdb --if-exists "$DB" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*"; exit 1; }
# refuses <sql> <what> <constraint>: the statement fails, and on the named production constraint (not on some other error)
refuses() { local e; if e=$($P -d "$DB" -c "$1" 2>&1 >/dev/null); then fail "$2 was accepted"; fi
  grep -qF "$3" <<<"$e" || fail "$2 failed for another reason: $e"; echo "PASS refuses: $2"; }

# 1 fixture from the production manifest
node $TOOL verify $M
dropdb --if-exists "$DB"
createdb "$DB"
$P -At -d "$DB" -c "select 'ISOLATED_POSTGRES version=' || current_setting('server_version') || ' transport=' || coalesce(host(inet_server_addr()), 'unix-socket')"
# Supabase built-ins the captured definitions name (not part of the capture): the extensions schema (gen_random_uuid default) and auth.role()/auth.uid()
$P -d "$DB" -f $FX/prelude.sql >/dev/null
node $TOOL fixture $M > $T/fixture.sql
if ! $P -d "$DB" -f $T/fixture.sql > "$T/fixture.out" 2>&1; then
  cat "$T/fixture.out" >&2
  fail 'the production-manifest fixture SQL did not apply'
fi
# Output filtering happens only after successful SQL execution; it cannot turn
# a producer/SQL failure into an empty successful result.
sed -e '/^NOTICE/d' -e '/MAINTAIN/d' "$T/fixture.out"
node $TOOL check-sql $M > $T/check.sql
$P -At -d "$DB" -f $T/check.sql > $T/diff.txt
node --input-type=module - "$M" "$T/diff.txt" <<'JS'
import fs from 'node:fs'
const [manifest, differences] = process.argv.slice(2)
const allowed = (JSON.parse(fs.readFileSync(manifest, 'utf8')).local_allowed_differences || []).filter(Boolean)
const actual = fs.readFileSync(differences, 'utf8').split(/\r?\n/).filter(Boolean)
const bad = actual.filter((line) => !allowed.some((difference) => line.includes(difference)))
if (bad.length) throw Error(`the fixture differs from the production manifest:\n${bad.join('\n')}`)
console.log(`PASS fixture built from the production manifest; check lists no unexpected difference (${actual.length} explicitly allowed)`)
JS
for sig in 'public.svc_provider_policy_record(uuid,jsonb)' 'security.policy_auto_approve_v1()' 'security.central_pages_attach_v1()' 'security.english_level_apply_v1(uuid,boolean)' 'security.provider_english_plan_v1(uuid)'; do
  want=$(node -e "const m=require('./$M');const s=process.argv[1].replace(/^public\./,'');console.log(m.functions.find(f=>f.sig===s||f.sig==='public.'+s).md5)" "$sig")
  got=$($P -At -d "$DB" -c "select md5(pg_get_functiondef('$sig'::regprocedure))")
  [ "$want" = "$got" ] || fail "$sig md5 $got, production $want"
done
echo 'PASS the five functions the plan replaces carry their live production md5 in the fixture'

# 2 production constraints (rows are fixture rows: no production data)
$P -d "$DB" >/dev/null <<'SQL'
insert into catalogue.providers(id, stable_key) values ('00000000-0000-0000-0000-00000000a001', 'h-fixture-provider');
insert into pipeline.evidence_artifacts(id) values ('00000000-0000-0000-0000-00000000e001');
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, evidence_id, content_hash)
values ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000a001', 'english_policy', 'https://example.invalid/english', 't', 5, 'search', 'read',
        '00000000-0000-0000-0000-00000000e001', 'h1');
SQL
refuses "update pipeline.provider_fact_sources set found_via = 'reparse'" 'provider_fact_sources.found_via outside search/manual' provider_fact_sources_found_via_check
refuses "insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, style, proposal, status) values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001', 'english_policy', 'p', 'h1', 'u', 's', '{}', 'group_rules')" \
  'a new proposal status such as group_rules: group rules must travel as status proposed' provider_policy_proposals_status_check
$P -d "$DB" -c "insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, style, proposal, status) values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001', 'english_policy', 'p', 'h1', 'u', 's', '{}', 'no_values')" >/dev/null
refuses "insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, style, proposal, status) values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001', 'english_policy', 'p', 'h1', 'u', 's', '{}', 'proposed')" \
  'a second proposal for the same document, parser and content: a re-read needs a new parser version' provider_policy_proposals_key
# the row triggers (manual_fact_guard and the evidence syncs) read tables outside this scope: replica mode skips triggers, never constraints
$P -d "$DB" >/dev/null <<'SQL'
set session_replication_role = replica;
insert into catalogue.courses(id, stable_key) values ('00000000-0000-0000-0000-00000000c001', 'h-fixture-course');
insert into catalogue.course_english_requirements(id, course_id, english_test_id, status)
select gen_random_uuid(), '00000000-0000-0000-0000-00000000c001', id, 'withdrawn' from ref.english_tests where code = 'IELTS';
SQL
refuses "set session_replication_role = replica; insert into catalogue.course_english_requirements(id, course_id, english_test_id, status) select gen_random_uuid(), '00000000-0000-0000-0000-00000000c001', id, 'active' from ref.english_tests where code = 'IELTS'" \
  'a second IELTS row for a course whose IELTS row is withdrawn: a group rule must reuse the row' course_english_requirements_course_id_english_test_id_key

# 3 today's behaviour on stored evidence
node $FX/baseline.mjs record-inputs > $T/inputs.json
node -e "
const i=require('$T/inputs.json'); const q=(s)=>\"'\"+String(s).replaceAll(\"'\",\"''\")+\"'\";
let sql='';
i.forEach((x,k)=>{ const fs='00000000-0000-0000-0000-0000000f1'+String(k).padStart(3,'0');
  sql+=\"insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, content_hash) values ('\"+fs+\"', '00000000-0000-0000-0000-00000000a001', 'english_policy', \"+q(x.url+'#'+k)+\", 't', 5, 'search', 'read', \"+q(x.content_hash)+\");\n\";
  sql+='select '+q(x.case)+\" || '|' || (public.svc_provider_policy_record('\"+fs+\"', \"+q(JSON.stringify(x.parsed))+\"::jsonb)->>'status');\n\"; });
require('fs').writeFileSync('$T/record.sql', sql)"
$P -At -d "$DB" -f $T/record.sql | grep '|' > $T/record.txt
node $FX/baseline.mjs check-recorded $T/record.txt
# 4 the migration on top: the harness (labelled stand-ins), the migration itself, then the group scenarios (each prints PASS or raises)
$P -q -v ON_ERROR_STOP=1 -d "$DB" -f $FX/groups-harness.sql >/dev/null 2>&1 || fail 'groups-harness.sql did not apply'
$P -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/migrations/20261106550000_cf247_english_requirements_complete.sql >/dev/null 2>$T/mig.err || { cat $T/mig.err; fail 'the migration did not apply on the production-shaped fixture'; }
echo 'PASS the migration applies on the production-shaped fixture (every live md5 guard held)'
$P -X -v ON_ERROR_STOP=1 -d "$DB" -f $FX/groups-tests.sql > $T/groups.out 2>&1 || { cat "$T/groups.out" >&2; fail 'a group scenario failed'; }
$P -X -v ON_ERROR_STOP=1 -d "$DB" -f $FX/exceptions-tests.sql > $T/exceptions.out 2>&1 || { cat "$T/exceptions.out" >&2; fail 'an exception scenario failed'; }
# Require every existing assertion to have executed. An empty/truncated log, an
# omitted scenario file or successful psql with no assertions is not a pass.
node --input-type=module - "$FX" "$T" <<'JS'
import fs from 'node:fs'
const [fixture, output] = process.argv.slice(2)
for (const [file, log] of [['groups-tests.sql', 'groups.out'], ['exceptions-tests.sql', 'exceptions.out']]) {
  const sql = fs.readFileSync(`${fixture}/${file}`, 'utf8')
  const text = fs.readFileSync(`${output}/${log}`, 'utf8')
  const expected = (sql.match(/\b(?:select|perform)\s+pg_temp\.ok\s*\(/gi) || []).length
  const passed = (text.match(/\bNOTICE:\s+PASS\b/g) || []).length
  if (!expected || passed !== expected) throw Error(`${file}: ${passed} scenario assertions passed, expected ${expected}`)
  for (const line of text.split('\n').filter((line) => /\bNOTICE:\s+PASS\b/.test(line))) console.log(line)
  console.log(`PASS scenario-count ${file}: ${passed}/${expected}`)
}
JS
echo 'english-requirements fixture round trip: passed'

