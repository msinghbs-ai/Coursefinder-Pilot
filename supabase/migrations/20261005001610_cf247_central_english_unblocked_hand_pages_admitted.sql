-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 20:37, Athabasca: "has all central links for requirements and course
-- link is correct, still not admitting or filling values").
-- Found:
-- 1. Central English rules stopped being written for EVERY university at 10:23 Melbourne time on 5 Oct. The hourly job
--    stops at the first approved rule with no stored evidence (24 approved rules written out by hand from a central
--    page had the evidence on the page record, not on the rule), so no rule after it was applied (61 failed runs).
--    Now: a rule takes the evidence of its central page when it has none of its own (same address), and one rule
--    that cannot be applied no longer stops the others (the reason is kept with the rule).
-- 2. A course page bound by hand (identity 'manual') never had its readings admitted: the identity lists in Coverage
--    admission countries did not include 'manual' (482 pages at 26 universities, e.g. 15 Athabasca pages). A page a
--    person bound to the course is that course's page, so 'manual' joins the official_url, intakes and english lists.
-- 3. A course taught only online has no campus: its location now reads "Online" (from the delivery), not "Missing".
-- Snippet patches are md5-guarded and found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.provider_english_apply_v1(uuid)'::regprocedure) is distinct from 'b1d29a3dffbb41d62260b6b170acc578' then
    raise exception 'provider_english_apply_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.provider_english_apply_v1(uuid)'::regprocedure);
  v_pairs := array[
    array[$s$  if x.status <> 'approved' then raise exception 'proposal is not approved'{sc} end if{sc}
$s$, $s$  if x.status <> 'approved' then raise exception 'proposal is not approved'{sc} end if{sc}
  if x.evidence_id is null then
    select fs.evidence_id into x.evidence_id from pipeline.provider_fact_sources fs where fs.id = x.fact_source_id and fs.url = x.url and fs.evidence_id is not null{sc}
  end if{sc}
$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59));
    v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
  if (select md5(prosrc) from pg_proc where oid = 'security.provider_english_apply_all_v1()'::regprocedure) is distinct from '194b5a9a7e732a8e40f6912651e54e15' then
    raise exception 'provider_english_apply_all_v1 changed, not replacing'; end if;
end $p$;

create or replace function security.provider_english_apply_all_v1() returns jsonb
language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare r record; v jsonb; v_total int := 0; v_n int := 0; v_failed int := 0;
begin
  for r in select id from pipeline.provider_policy_proposals where kind = 'english_policy' and status = 'approved' order by decided_at loop
    begin
      v := security.provider_english_apply_v1(r.id); v_total := v_total + coalesce((v->>'written')::int, 0); v_n := v_n + 1;
    exception when others then
      v_failed := v_failed + 1;
      update pipeline.provider_policy_proposals set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('last_error', left(sqlerrm, 200), 'last_failed_at', now()), updated_at = now() where id = r.id;
    end;
  end loop;
  return jsonb_build_object('proposals', v_n, 'written', v_total, 'not_applied', v_failed);
end $f$;

update pipeline.coverage_admission_countries a set identities = (select jsonb_object_agg(e.key, case when e.key in ('official_url', 'intakes', 'english') and not (e.value ? 'manual') then e.value || '["manual"]'::jsonb else e.value end) from jsonb_each(a.identities) e) where a.active;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.university_course_location_v1(uuid)'::regprocedure) is distinct from 'a63be1d2cdcda07288a0abb977c10261' then
    raise exception 'university_course_location_v1 changed, not replacing'; end if;
end $p$;

create or replace function security.university_course_location_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
           'value', coalesce((select string_agg(distinct cp.name, ', ' order by cp.name) from catalogue.course_campuses cc join catalogue.campuses cp on cp.id = cc.campus_id where cc.course_id = p_course_id),
                             case when co.delivery_mode = 'online' then 'Online' end),
           'read', coalesce(pg.candidates->'adapter_extra'->>'campus', pg.candidates->'adapter_extra'->>'location'),
           'source', case when exists (select 1 from catalogue.course_campuses cc where cc.course_id = p_course_id) then 'catalogue'
                          when co.delivery_mode = 'online' then 'catalogue'
                          when coalesce(pg.candidates->'adapter_extra'->>'campus', pg.candidates->'adapter_extra'->>'location') is not null then 'adapter'
                          else 'missing' end)
  from (select 1) one left join catalogue.courses co on co.id = p_course_id left join pipeline.coverage_course_pages pg on pg.course_id = p_course_id
$f$;
