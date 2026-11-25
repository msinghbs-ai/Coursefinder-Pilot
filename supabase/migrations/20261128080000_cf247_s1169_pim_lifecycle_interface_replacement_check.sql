-- CF-247 s1169 (S1-RM-Design; Global Autonomous PIM step 4 common interface and the interface 4 second safeguard; Platform Admin 25 Nov 2026 23:12 AEDT:
-- "Step 4 - common AER and Scholarship lifecycle interfaces, preserving existing ownership and S1-Build's ongoing model work.").
--   1. security.pim_lifecycle_v1(): one read of where each domain stands on the shared lifecycle, by country, with the lane that owns the next action. It reads the lanes' own tables and
--      changes nothing in them, so ownership is unchanged (Master Plan 6.3: 4a S2-AER, S1-AER-Claude, S3-AER-ChatGPT; 4b S1-Scholarship-Claude, S3-Scholarship-ChatGPT).
--        academic entry, per active course: not_applicable (closed to international students), admitted (active rows), in_review (a pending Layer 4 read), read_queued (a stored page
--        waiting for the deterministic reader), read_no_admissible_rows, page_stored, page_bound_not_stored, no_page.
--        scholarships, per published provider: the scholarship lane's own rollup pipeline.scholarship_provider_coverage (disposition), as it stands.
--   2. The second safeguard of interface 4 (Master Plan 6.2: "a check two cycles later ... flags for review"): every guarded Layer 4 supersession in the long Data Delivery window
--      (data_delivery.net_long_hours) is tested again with security.supersede_successor_v1; one whose successor has since gone is flagged (count and a sample), never reversed automatically.
--   3. Both are counted in the background with the PIM snapshot (pim.lifecycle): the Data Delivery read stays a snapshot read.
-- G1: no job (the existing data-delivery count). G2: the window is the existing setting. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: the s1167 snapshot expression in security.data_delivery_refresh_v1 (one key added, anchor guarded). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the guard reads and one measured run

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regprocedure('security.supersede_successor_v1(text,uuid)') is null or to_regprocedure('security.pim_excluded_gaps_v1()') is null then
    raise exception 'guard: s1167 and s1168 are not live';
  end if;
end $g$;
create temp table s1169_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1169_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.pim_lifecycle_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare v_long int := security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int; v_aer jsonb; v_sch jsonb; v_chk jsonb;
begin
  with c as (
    select co.id, k.iso_alpha2 cc, co.open_to_international oi
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
     where co.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)),
  st as (
    select c.cc, case
      when c.oi is false then 'not_applicable'
      when exists (select 1 from catalogue.course_entry_requirements q where q.course_id = c.id and q.status = 'active') then 'admitted'
      when exists (select 1 from pipeline.layer4_review_items i where i.entity_id = c.id and i.field_code = 'course_entry_first_read' and i.status = 'pending') then 'in_review'
      when exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = c.id and a.outcome is null) then 'read_queued'
      when exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = c.id) then 'read_no_admissible_rows'
      when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.status = 'bound' and g.evidence_id is not null) then 'page_stored'
      when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.status = 'bound') then 'page_bound_not_stored'
      else 'no_page' end stage
      from c),
  agg as (select cc, stage, count(*) n from st group by cc, stage)
  select jsonb_build_object(
    'stages', coalesce((select jsonb_agg(jsonb_build_object('country', cc, 'stage', stage, 'courses', n) order by cc, stage) from agg), '[]'::jsonb),
    'next_owner', jsonb_build_object(
      'no_page', 'course pages (S1-Build)', 'page_bound_not_stored', 'course pages (S1-Build)', 'page_stored', 'AER readers (S1-AER-Claude AU; S3-AER-ChatGPT NZ, CA)',
      'read_queued', 'AER deterministic reader (S2-AER)', 'read_no_admissible_rows', 'AER readers (S2-AER shared admission)', 'in_review', 'Layer 4 (Platform Admin)',
      'admitted', 'refresh (PIM step 5)', 'not_applicable', 'none'))
    into v_aer;
  select jsonb_build_object(
    'providers', coalesce((select jsonb_agg(jsonb_build_object('country', country, 'disposition', disposition, 'providers', n, 'scholarships_published', sp, 'reviews_pending', rp) order by country, disposition)
                             from (select s.country, coalesce(s.disposition, 'unclassified') disposition, count(*) n, sum(coalesce(s.scholarships_published, 0)) sp, sum(coalesce(s.ai_reviews_pending, 0)) rp
                                     from pipeline.scholarship_provider_coverage s
                                    where coalesce(s.provider_publication, 'published') = 'published'
                                    group by 1, 2) x), '[]'::jsonb),
    'as_at', (select max(s.refreshed_at) from pipeline.scholarship_provider_coverage s),
    'owner', 'scholarship lanes (S1-Scholarship-Claude AU; S3-Scholarship-ChatGPT NZ)')
    into v_sch;
  with s as (
    select x.item_id id from pipeline.layer4_supersessions x
      join pipeline.supersede_guard_scope g on g.target = 'layer4' and g.code = x.field_code and g.active
     where x.at > now() - make_interval(hours => v_long) and x.reversed_at is null),
  t as (select s.id, security.supersede_successor_v1('layer4', s.id) r from s)
  select jsonb_build_object('window_hours', v_long, 'checked', count(*), 'flagged', count(*) filter (where (r->>'ok')::boolean is not true),
                            'sample', coalesce((jsonb_agg(id) filter (where (r->>'ok')::boolean is not true)) -> 0, 'null'::jsonb),
                            'meaning', 'Guarded supersessions in the window tested again: flagged ones lost their successor since and need a person; nothing is reversed automatically.')
    into v_chk from t;
  return jsonb_build_object('academic_entry', v_aer, 'scholarships', v_sch, 'replacement_check', v_chk);
end $f$;
comment on function security.pim_lifecycle_v1() is 'PIM step 4 (s1169): academic entry and scholarship lifecycle stages by country with the owning lane, and the interface 4 second safeguard; counted into the Data Delivery snapshot.';
revoke all on function security.pim_lifecycle_v1() from public, anon, authenticated;
grant execute on function security.pim_lifecycle_v1() to service_role;

do $r$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := E'jsonb_build_object(''excluded'', security.pim_excluded_gaps_v1())';
        b constant text := E'jsonb_build_object(''excluded'', security.pim_excluded_gaps_v1(), ''lifecycle'', security.pim_lifecycle_v1())';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the s1167 snapshot anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); l jsonb; t0 timestamptz := clock_timestamp(); v_n bigint; v_active bigint;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1169_locks) then raise exception 'guard: a manual lock was removed'; end if;  -- people may add locks while this runs; none is ever removed
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron jobs above the ceiling of 140'; end if;  -- fixed: the protected ceiling; this change schedules nothing, and other lanes may switch jobs while it runs
  l := security.pim_lifecycle_v1();
  select coalesce(sum((e->>'courses')::bigint), 0) into v_n from jsonb_array_elements(l->'academic_entry'->'stages') e;
  select count(*) into v_active from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
   where co.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  if v_n <> v_active then raise exception 'guard: lifecycle stages cover % courses, % active', v_n, v_active; end if;
  if l->'replacement_check'->'checked' is null then raise exception 'guard: no replacement check'; end if;
  if position('pim_lifecycle_v1' in pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) = 0 then raise exception 'guard: the snapshot does not count the lifecycle'; end if;
  raise notice 'lifecycle read % ms; replacement check %', (extract(epoch from clock_timestamp() - t0) * 1000)::int, l->'replacement_check';  -- fixed: milliseconds
end $c$;
