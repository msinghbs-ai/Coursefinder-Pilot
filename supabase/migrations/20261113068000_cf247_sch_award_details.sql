-- CF-247 F-SCH redesign, developer field contract step 1 (Platform Admin 12 Nov 2026 20:19, "proceed with 2 then decided best option and continue":
-- the scholarship API fields for sponsor, award type, benefits, application route and round, and R24). This step is internal: it stores the verified
-- facts those fields need, beside the consumer tables, so that the API change (a separate, approval-gated release) reads held data. Nothing the
-- website or Zoho reads changes here (G3): the new table is not read by any consumer function, and scholarship.coverage is not read by the consumer API.
--   scholarship.award_details  one row per scholarship: award type, sponsor, programme and award code (from a version 3 extraction whose passage
--                              proved them), whether applications are rolling, and the extraction and evidence behind them.
--   scholarship.coverage       one row per verified benefit (tuition, stipend, living allowance, accommodation, travel, health cover, other) with its
--                              amount, currency, percentage and passage, beside the existing award-duration rows.
-- security.scholarship_detail_extend_v1 writes both (empty fields only; a verified value never overwrites a held one); the detail fill calls it
-- (md5-guarded edit), and the 1,377 scholarships already read with sch-extract-v3 are filled from their latest successful extraction.
-- Replaces: nothing. Retires: nothing.

create table if not exists scholarship.award_details (
  scholarship_id uuid primary key references scholarship.scholarships(id) on delete cascade,
  award_type text,
  sponsor text,
  programme text,
  award_code text,
  application_rolling boolean,
  extraction_id bigint,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint award_details_type_check check (award_type is null or award_type = any (array['scholarship','bursary','tuition_waiver','fee_discount','research_funding','grant','stipend','other']))
);
comment on table scholarship.award_details is 'F-SCH redesign (12 Nov 2026): verified award type, sponsor, programme, award code and rolling applications per scholarship, from a version 3 extraction (sch-extract-v3) whose passages proved them; filled only where empty. Read by the approval-gated scholarship API fields, not yet by any consumer function.';
alter table scholarship.award_details enable row level security;

create or replace function security.scholarship_detail_extend_v1(p_extraction bigint, p_scholarship uuid)
returns text[] language plpgsql security definer set search_path to '' as $function$
declare e pipeline.scholarship_ai_extractions%rowtype; d jsonb; c jsonb; v_done text[] := '{}'; v_src uuid; n int; v_pid uuid;
begin
  select * into e from pipeline.scholarship_ai_extractions where id = p_extraction;
  if e.id is null or e.error is not null or coalesce(e.prompt_version, 0) < 3 or jsonb_typeof(e.answer->'detail') <> 'object' or jsonb_typeof(e.checks->'detail') <> 'object' then return v_done; end if;
  select provider_id into v_pid from scholarship.scholarships where id = p_scholarship and lifecycle_status = 'active';
  if v_pid is null or v_pid is distinct from e.provider_id or not coalesce((e.checks->>'name')::boolean, false) or e.verdict is distinct from 'scholarship' then return v_done; end if;
  d := e.answer->'detail'; c := e.checks->'detail'; v_src := security.coverage_sweep_source(v_pid);
  insert into scholarship.award_details(scholarship_id, extraction_id, evidence_id) values (p_scholarship, e.id, e.evidence_id) on conflict (scholarship_id) do nothing;
  if coalesce((c->>'award_type')::boolean, false) and d->>'award_type' in ('scholarship','bursary','tuition_waiver','fee_discount','research_funding','grant','stipend','other') then
    update scholarship.award_details set award_type = d->>'award_type', extraction_id = e.id, evidence_id = coalesce(e.evidence_id, evidence_id), updated_at = now() where scholarship_id = p_scholarship and award_type is null;
    get diagnostics n = row_count; if n > 0 then v_done := v_done || 'award_type'::text; end if;
  end if;
  if coalesce((c->>'identity')::boolean, false) then
    update scholarship.award_details set sponsor = coalesce(sponsor, left(nullif(btrim(d->>'sponsor'), ''), 200)), programme = coalesce(programme, left(nullif(btrim(d->>'programme'), ''), 200)),
           award_code = coalesce(award_code, left(nullif(btrim(d->>'award_code'), ''), 60)), updated_at = now()
     where scholarship_id = p_scholarship and (sponsor is null or programme is null or award_code is null);
    get diagnostics n = row_count; if n > 0 then v_done := v_done || 'identity'::text; end if;
  end if;
  if jsonb_typeof(c->'application'->'rolling') = 'boolean' then
    update scholarship.award_details set application_rolling = (c->'application'->>'rolling')::boolean, updated_at = now() where scholarship_id = p_scholarship and application_rolling is null;
    get diagnostics n = row_count; if n > 0 then v_done := v_done || 'rolling'::text; end if;
  end if;
  -- verified benefits, once per scholarship from this reader
  if jsonb_array_length(coalesce(c->'benefits', '[]')) > 0
     and not exists (select 1 from scholarship.coverage cv where cv.scholarship_id = p_scholarship and cv.notes like 'sch-extract-v3:%') then
    insert into scholarship.coverage(scholarship_id, coverage_type, percentage, amount, currency_code, notes, source_id, evidence_id)
    select p_scholarship,
           case b->>'kind' when 'tuition_percentage' then 'tuition_fees' when 'tuition_amount' then 'tuition_fees' when 'full_tuition' then 'tuition_fees'
                           when 'living_allowance' then 'living_expenses' when 'health_cover' then 'overseas_student_health_cover' when 'travel' then 'travel'
                           when 'accommodation' then 'accommodation' when 'stipend' then 'stipend' when 'fixed_amount' then 'fixed_amount' when 'in_kind' then 'in_kind' else 'other' end,
           case when b->>'kind' = 'full_tuition' then 100 when jsonb_typeof(b->'percentage') = 'number' then (b->>'percentage')::numeric end,
           case when jsonb_typeof(b->'amount') = 'number' and (b->>'amount')::numeric >= 50 then (b->>'amount')::numeric end,  -- fixed: under 50 is a page placeholder (20261113066000)
           (select r.code from ref.currencies r where r.code = b->>'currency'),
           left('sch-extract-v3:' || e.id || (case when coalesce((b->>'maximum')::boolean, false) then ' (maximum)' else '' end) || ' ' || coalesce(b->>'quote', ''), 600),
           v_src, e.evidence_id
      from jsonb_array_elements(c->'benefits') b;
    get diagnostics n = row_count; if n > 0 then v_done := v_done || 'benefits'::text; end if;
  end if;
  return v_done;
end $function$;
comment on function security.scholarship_detail_extend_v1(bigint, uuid) is 'F-SCH redesign (12 Nov 2026): writes verified award type, sponsor, programme, award code, rolling applications (scholarship.award_details) and benefits (scholarship.coverage) from a version 3 extraction; empty fields only.';

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_detail_apply_v1(bigint)', '36efaa75305b1724fb3daa2afaecd28e', array[
  array[$o$  if cardinality(v_done) > 0 then
    insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
    values (s.id, 'detail_fill', null,$o$,
        $n$  v_done := v_done || security.scholarship_detail_extend_v1(e.id, s.id);  -- 20261113068000: award type, sponsor, rolling, benefits
  if cardinality(v_done) > 0 then
    insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
    values (s.id, 'detail_fill', null,$n$]
], array[1]);

-- the scholarships already read with version 3: filled from their latest successful extraction
do $b$
declare x record; v_n int := 0; v_f int := 0; r text[];
begin
  for x in select distinct on (e.scholarship_id) e.id, e.scholarship_id from pipeline.scholarship_ai_extractions e
            where e.prompt_version >= 3 and e.error is null and e.scholarship_id is not null order by e.scholarship_id, e.id desc loop
    r := security.scholarship_detail_extend_v1(x.id, x.scholarship_id);
    v_n := v_n + 1; if cardinality(r) > 0 then v_f := v_f + 1; end if;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'sch_award_details_backfill', 'Scholarship award details and benefits filled from existing version 3 extractions',
          jsonb_build_object('read', v_n, 'filled', v_f, 'migration', '20261113068000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  raise notice 'award details: % scholarships read, % filled', v_n, v_f;
end $b$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'scholarship.award_details', 'Layer 2', 'Scholarships', 'Verified award type, sponsor, programme, award code and rolling applications per scholarship', 'active', '{}', '20261113068000'),
 ('function', 'security.scholarship_detail_extend_v1', 'Layer 2', 'Scholarships', 'Writes award details and benefits from a verified version 3 extraction', 'active', '{}', '20261113068000')
on conflict do nothing;
