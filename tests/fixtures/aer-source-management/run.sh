#!/usr/bin/env bash
# Guards: F-AER.04 source management (Platform Admin decision D3, 11 Nov 2026) and G4 database-backed tests: migration 20261112113700 on the entry-matrix path as live after
# 20261112093700 (../aer-matrix-machine), with public.svc_entry_matrix_fetch_record and security.entry_matrix_enqueue_v1 as live (3f2bf00e..., b600d54e...): ownership on the
# provider's own website host, classes, reuse of a source or stored copy, Platform Admin and a reason to attach, a failed source asked again, an unchanged read never repeated,
# an upload recorded as the stored copy with one read queued and never machine-admitted, the meta read; the held forward recovery restores the check byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (ASM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ASM_DB:-g_aer_source_management}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
Q=tests/fixtures/aer-qualification-first; MM=tests/fixtures/aer-matrix-machine; F=tests/fixtures/aer-source-management
M0=supabase/migrations/20261112093700_cf247_aer_matrix_machine_admission.sql
M=${ASM_MIG:-supabase/migrations/20261112113700_cf247_aer_source_management.sql}; R=${ASM_REC:-supabase/held/aer_source_management_forward_recovery.sql}
CK='security.aer_matrix_machine_check_v1(uuid)'; CK_B=8b25b3dcb246a08561dd0ebd48f0ff37; CK_A=${ASM_AFTER:-26e7a3f959a5bc7c2c29fc9031c594c2}
q() { psql -X -d "$DB" -Atc "$1"; }
trap '[ -n "${ASM_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f $Q/stubs.sql; $P -f $MM/stubs.sql
for f in $Q/live/public.svc_entry_matrix_record.sql $Q/live/security.entry_matrix_review_apply_v1.sql $MM/live/security.aer_machine_run_v1.sql; do { echo "set check_function_bodies = off;"; cat $f; echo ";"; } | $P; done
{ echo "set check_function_bodies = off;"; cat supabase/migrations/20261112060000_cf247_aer_qualification_first.sql; } | $P -1 >/dev/null
{ echo "set check_function_bodies = off;"; cat $M0; } | $P -1 >/dev/null
QP=supabase/migrations/20261112110700_cf247_aer_matrix_machine_quote_proof.sql
[ "$(q "select md5(prosrc) from pg_proc where oid = 'security.aer_matrix_machine_validate_v1()'::regprocedure")" = c4cb5e0f02bcee4b04c5bb0702c2a8c7 ] || { echo "the validation after 20261112093700 differs from live"; exit 1; }
$P -1 -f $QP >/dev/null 2>&1 || { echo "the quote proof migration did not apply"; $P -1 -f $QP 2>&1 | tail -3; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = 'security.aer_matrix_machine_validate_v1()'::regprocedure")" = 5c9d6e287b60f1a48fb28f71f4c3dba3 ] || { echo "the validation did not reach 5c9d6e28"; exit 1; }
$P -1 -f $QP >/dev/null 2>&1 || { echo "the quote proof migration did not apply again"; exit 1; }
echo "quote proof (20261112110700): check 6eece704 -> 8b25b3dc, validation c4cb5e0f -> 5c9d6e28; applied again: no change"
$P -f $F/stubs.sql
for f in $F/live/public.svc_entry_matrix_fetch_record.sql $F/live/security.entry_matrix_enqueue_v1.sql; do { cat $f; echo ";"; } | $P; done
[ "$(q "select md5(prosrc) from pg_proc where oid = 'public.svc_entry_matrix_fetch_record(uuid,text,text,integer,text,text,text,text)'::regprocedure")" = 3f2bf00eb7acb42396f864f64d309799 ] \
  && [ "$(q "select md5(prosrc) from pg_proc where oid = 'security.entry_matrix_enqueue_v1()'::regprocedure")" = b600d54e729047a9fa1f7a272d64627d ] || { echo "the loaded fetch record or enqueue differs from live"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")" = $CK_B ] || { echo "the check after 20261112093700 differs from live $CK_B"; exit 1; }
echo "loaded: the entry-matrix path after 20261112093700 and 20261112110700, fetch record and enqueue as live, the check as live ($CK_B)"

OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")" = "$CK_A" ] || { echo "the check did not reach $CK_A: $(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")"; exit 1; }
grep -qF -- "--   $CK $CK_B -> $CK_A" $M || { echo "header does not record the check md5s"; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")" = "$CK_A" ] || { echo "applied again: changed"; exit 1; }
echo "migration: the check goes to $CK_A; applied again: no change"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a0', 'AU');
insert into catalogue.providers(id, canonical_name, website, country_id) values
 ('a0000000-0000-0000-0000-00000000000a', 'Uni A', 'https://www.unia.edu.au', '00000000-0000-0000-0000-0000000000a0'),
 ('b0000000-0000-0000-0000-00000000000b', 'Uni B', 'https://unib.edu.au', '00000000-0000-0000-0000-0000000000a0'),
 ('c0000000-0000-0000-0000-00000000000c', 'Uni C', null, '00000000-0000-0000-0000-0000000000a0');
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, found_via, attempts) values
 ('b1000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000b', 'https://unib.edu.au/entry', 'failed', 'search', 3),
 ('b2000000-0000-0000-0000-0000000000b2', 'b0000000-0000-0000-0000-00000000000b', 'https://unib.edu.au/read', 'read', 'search', 1);
do $$ declare r jsonb; e text; v_sid uuid; v_att bigint; v_sha text := repeat('ab', 32); begin
  -- the check
  r := public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.otheruni.edu.au/entry","classes":["country_table"]}');
  perform pg_temp.ok(r->>'rule' = 'not_official_host', 'an address on another host is refused (ownership)');
  r := public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://study.unia.edu.au/entry","classes":["country_table","undergraduate"]}');
  perform pg_temp.ok((r->>'ok')::boolean and r->>'reuse' is null and r->>'reader' like 'Entry matrix reader%' and (r->>'can_attach')::boolean, 'a subdomain of the provider''s own host passes; the existing reader reads it');
  r := public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/e","classes":[]}');
  perform pg_temp.ok(r->>'rule' = 'class_required', 'a class is required');
  r := public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/e","classes":["sideways"]}');
  perform pg_temp.ok(r->>'rule' = 'class_unknown', 'an unknown class is refused');
  r := public.admin_aer_source('{"action":"check","provider_id":"c0000000-0000-0000-0000-00000000000c","url":"https://unic.edu.au/e","classes":["country_table"]}');
  perform pg_temp.ok(r->>'rule' = 'provider_no_website', 'a provider without a website cannot have ownership checked');
  r := public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://unib.edu.au/entry","classes":["country_table"]}');
  perform pg_temp.ok(r->>'rule' = 'not_official_host', 'another provider''s address is refused');
  -- rank and reason
  update pipeline.fx_caller set rank = 4;
  e := pg_temp.err($q$select public.admin_aer_source('{"action":"attach","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["country_table"],"reason":"from the handbook"}')$q$);
  perform pg_temp.ok(e like 'Platform Admin required%', 'a Pipeline Operator may check but not attach');
  perform pg_temp.ok((public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["country_table"]}')->>'can_attach')::boolean = false, 'the check says who attaches');
  update pipeline.fx_caller set rank = 1;
  perform pg_temp.ok(pg_temp.err($q$select public.admin_aer_source('{"action":"check","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["country_table"]}')$q$) like 'Pipeline Operator%', 'below Pipeline Operator: no check');
  update pipeline.fx_caller set rank = 7;
  perform pg_temp.ok(pg_temp.err($q$select public.admin_aer_source('{"action":"attach","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["country_table"],"reason":""}')$q$) = 'reason required', 'a reason is required');
  -- attach a new address
  r := public.admin_aer_source('{"action":"attach","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["country_table","international_qualification"],"reason":"official admissions page"}');
  v_sid := (r->>'source_id')::uuid;
  perform pg_temp.ok((r->>'attached')::boolean and (select status = 'found' and found_via = 'manual' from pipeline.entry_matrix_sources where id = v_sid), 'a new address joins the one registry for the existing fetch (found, manual)');
  perform pg_temp.ok((select classes = array['country_table','international_qualification'] and how = 'url' and completed_at is not null from pipeline.aer_source_attachments where source_id = v_sid), 'the attachment keeps the classes');
  perform pg_temp.ok(exists (select 1 from pipeline.admin_control_events where action = 'source_attach' and detail->>'reason' = 'official admissions page'), 'logged with the reason');
  -- reuse: the same address again adds no second source
  r := public.admin_aer_source('{"action":"attach","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry","classes":["undergraduate"],"reason":"again, as undergraduate"}');
  perform pg_temp.ok(r->>'reuse' = 'source' and (r->>'source_id')::uuid = v_sid and (select count(*) from pipeline.entry_matrix_sources where provider_id = 'a0000000-0000-0000-0000-00000000000a') = 1, 'the same address is reused, never duplicated');
  -- a failed source is asked again; a read one is not read again
  r := public.admin_aer_source('{"action":"attach","provider_id":"b0000000-0000-0000-0000-00000000000b","url":"https://unib.edu.au/entry","classes":["country_table"],"reason":"page is back online"}');
  perform pg_temp.ok((select status = 'found' and attempts = 0 from pipeline.entry_matrix_sources where id = 'b1000000-0000-0000-0000-0000000000b1'), 'a failed source is asked again (found, tries reset)');
  r := public.admin_aer_source('{"action":"attach","provider_id":"b0000000-0000-0000-0000-00000000000b","url":"https://unib.edu.au/read","classes":["country_table"],"reason":"classify the read page"}');
  perform pg_temp.ok((select status = 'read' from pipeline.entry_matrix_sources where id = 'b2000000-0000-0000-0000-0000000000b2') and r->>'outcome' like 'Already a source and read%', 'a source already read is not read again');
  -- an upload: begin, then the record, then one read queued; the machine class declines it
  e := pg_temp.err(format($q$select public.admin_aer_source('{"action":"upload_begin","how":"pdf_upload","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry.pdf","classes":["country_table"],"reason":"blocked by robots","sha256":"%s","bytes":5000}')$q$, v_sha));
  perform pg_temp.ok(e is null and (public.admin_aer_source(format('{"action":"check","how":"pdf_upload","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry.pdf","classes":["country_table"],"sha256":"%s","bytes":5000}', v_sha)::jsonb)->>'rule') = 'file_too_large', 'a file over entry.pdf_max_bytes is refused');
  r := public.admin_aer_source(format('{"action":"upload_begin","how":"pdf_upload","provider_id":"a0000000-0000-0000-0000-00000000000a","url":"https://www.unia.edu.au/entry.pdf","classes":["country_table"],"reason":"blocked by robots","sha256":"%s","bytes":900}', v_sha)::jsonb);
  v_sid := (r->>'source_id')::uuid; v_att := (r->>'attachment_id')::bigint;
  perform pg_temp.ok((r->>'upload')::boolean and r->>'storage_path' = format('layer2/AU/entry-matrix/a0000000-0000-0000-0000-00000000000a/%s/%s.pdf.gz', v_sid, v_sha)
                     and (select status from pipeline.entry_matrix_sources where id = v_sid) = 'inactive', 'upload begin: a path where the fetch step stores PDFs; the source waits (not fetched meanwhile)');
  perform pg_temp.ok(pg_temp.err(format($q$select public.svc_aer_source_upload_record(%s, 'layer2/AU/entry-matrix/x/y/%s.pdf.gz', '%s')$q$, v_att, v_sha, v_sha)) like 'the stored file does not match%', 'a path that is not the checked one is refused');
  update pipeline.fx_caller set uid = null, rank = 0, role = 'authenticated';
  perform pg_temp.ok(has_function_privilege('authenticated', 'public.svc_aer_source_upload_record(bigint,text,text)', 'execute') = false, 'signed-in users cannot record an upload');
  update pipeline.fx_caller set uid = '00000000-0000-0000-0000-0000000000a1', rank = 7, role = null;
  r := public.svc_aer_source_upload_record(v_att, r->>'storage_path', v_sha);
  perform pg_temp.ok((r->>'ok')::boolean and (r->>'reads_queued')::int >= 1 and (select status = 'read' and read_via is null and content_hash = v_sha and evidence_id is not null from pipeline.entry_matrix_sources where id = v_sid),
                     'the upload is the stored copy (read, evidence registered) and its one read is queued');
  perform pg_temp.ok((select count(*) from pipeline.entry_matrix_runs where source_id = v_sid) = 1 and security.entry_matrix_enqueue_v1() = 0, 'no second read of the same copy');
  -- meta
  r := public.admin_aer_source(format('{"action":"meta","source_ids":["%s","b1000000-0000-0000-0000-0000000000b1"]}', v_sid)::jsonb);
  perform pg_temp.ok(r->v_sid::text->'attached'->>'how' = 'pdf_upload' and (r->v_sid::text->>'version')::int = 1 and r->'b1000000-0000-0000-0000-0000000000b1'->>'next_retry' like 'Next entry-matrix-read%', 'meta: how attached, version, next retry');
end $$;
-- the machine class never admits an uploaded copy: a Layer 4 item for a read of it is declined uploaded_copy
do $$ declare v_sid uuid := (select source_id from pipeline.aer_source_attachments where how = 'pdf_upload'); v_run uuid := (select id from pipeline.entry_matrix_runs where source_id = (select source_id from pipeline.aer_source_attachments where how = 'pdf_upload')); v_item uuid := gen_random_uuid(); r jsonb; begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, layer2_state, proposed_value)
  values (v_item, 'provider', 'a0000000-0000-0000-0000-00000000000a', 'entry_matrix_first_run', 'pending', jsonb_build_object('entry_matrix_run_id', v_run, 'entry_matrix_source_id', v_sid), '{}'::jsonb);
  update pipeline.entry_matrix_runs set review_item_id = v_item, state = 'done' where id = v_run;
  r := security.aer_matrix_machine_check_v1(v_item);
  perform pg_temp.ok(r->>'rule' = 'uploaded_copy', 'an uploaded copy is never admitted by the machine class (uploaded_copy): ' || coalesce(r->>'rule', 'null'));
end $$;
-- the quote proof (20261112110700): a row whose quote does not carry its published minimum keeps the item with a person
do $$ declare v_item uuid := gen_random_uuid(); v_run uuid := gen_random_uuid(); v_src uuid := gen_random_uuid(); v_ev uuid; r jsonb; begin
  perform pg_temp.ok(security.aer_quote_has_value_v1('IB Diploma: 24 points', null, 24) and not security.aer_quote_has_value_v1('IB Diploma: 124 points', null, 24)
    and security.aer_quote_has_value_v1('Austria | Maturity | 70 | 3.3', '70', 70) and not security.aer_quote_has_value_v1('Please see the table below to determine the minimum', '70', 70)
    and security.aer_quote_has_value_v1('A Levels AAB', 'AAB', null) and not security.aer_quote_has_value_v1('A Levels AABB', 'AAB', null), 'the minimum is matched as a whole token');
  insert into pipeline.evidence_artifacts(id, storage_path) values (gen_random_uuid(), 'x') returning id into v_ev;
  insert into pipeline.entry_matrix_sources(id, provider_id, url, status, read_via, evidence_id, content_hash) values (v_src, 'a0000000-0000-0000-0000-00000000000a', 'https://www.unia.edu.au/at', 'read', 'direct', v_ev, 'hq');
  insert into pipeline.entry_matrix_runs(id, source_id, provider_id, content_hash, review_item_id, state) values (v_run, v_src, 'a0000000-0000-0000-0000-00000000000a', 'hq', v_item, 'done');
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (v_item, 'provider', 'a0000000-0000-0000-0000-00000000000a', 'entry_matrix_first_run', 'pending');
  insert into catalogue.provider_entry_matrix(provider_id, country_code, qualification_name, run_id, status, confidence, quote, study_level_id, min_grade)
  values ('a0000000-0000-0000-0000-00000000000a', 'AT', 'Maturity certificate', v_run, 'proposed', 0.99, 'Please see the table below to determine the minimum indicative score', '11111111-1111-1111-1111-111111111111', '70');
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.matrix_machine_audit_pct';
  r := security.aer_matrix_machine_check_v1(v_item);
  perform pg_temp.ok(r->>'rule' = 'row_minimum_not_in_quote', 'a quote without its minimum keeps the item with a person (row_minimum_not_in_quote): ' || coalesce(r->>'rule', 'null'));
  update catalogue.provider_entry_matrix set quote = 'Austria | Maturity certificate | 70 | 3.3' where run_id = v_run;
  r := security.aer_matrix_machine_check_v1(v_item);
  perform pg_temp.ok(r->>'rule' = 'aer-matrix-machine-v1', 'the same row quoting its minimum passes: ' || coalesce(r->>'rule', 'null'));
end $$;
SQL
echo "behaviour: ownership, classes, ranks and reason, attach, reuse, failed asked again, read not repeated, upload path and record, one read, meta, never machine-admitted"

OUT=$($P -1 -At -f $R 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")" = $CK_B ] || { echo "recovery did not restore the check"; exit 1; }
[ "$(q "select count(*) from pg_tables where tablename = 'aer_source_attachments'")" = 1 ] || { echo "recovery dropped the table"; exit 1; }
echo "recovery: the check back to $CK_B, nothing dropped"
OUT=$($P -1 -At -f supabase/held/aer_matrix_machine_quote_proof_forward_recovery.sql 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$CK'::regprocedure")" = 6eece704435e4c72cdbcbccc683b194f ] && [ "$(q "select md5(prosrc) from pg_proc where oid = 'security.aer_matrix_machine_validate_v1()'::regprocedure")" = c4cb5e0f02bcee4b04c5bb0702c2a8c7 ] \
  && [ "$(q "select (value #>> '{}')::numeric <= 1 from pipeline.platform_toolset_settings where key = 'aer.matrix_machine_mode'")" = t ] || { echo "the quote proof recovery state is wrong"; exit 1; }
echo "recovery (20261112110700): check back to 6eece704, validation back to c4cb5e0f, admission in shadow"
echo "PASS aer-source-management"
