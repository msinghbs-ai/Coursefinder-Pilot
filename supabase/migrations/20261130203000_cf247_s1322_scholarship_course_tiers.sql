-- CF-247 s1322 (S1-Build; SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved scoped development exception 2: "Implement the VU
-- course-specific scholarship calculation correction using exact evidence-backed course-to-tier mapping. Do not rely on fuzzy title matching
-- or record-level maximum percentages").
-- Measured live 27 Nov 2026 (rolled-back read-backs): VU Sydney & Brisbane 2027 International Scholarship (c377de6f) holds award_percentage 30
-- with award_value_is_maximum (the page's "up to"), so all 14 mapped courses calculate as award_not_structured. The scholarship's official
-- 2027 table (evidence db338b04, recorded as scholarship.award_tiers) gives the exact rate per course: official_rate_2 "Graduate Diploma in
-- Early Childhood Education (EGEC)" 30%, official_rate_1 "All other eligible courses" 20%. scholarship.award_tiers has no course link.
-- What changes:
--   1. scholarship.course_tier_assignments (new, beside): one row per course mapping, naming the tier that applies, how (tier_names_course: the
--      tier's own label is the course's exact registered title, with an optional trailing "(CODE)"; tier_all_other: the table's single
--      catch-all tier for every other mapped course of the same table) and the tier's evidence. A tier that names no mapped course or more than
--      one, a table with more than one catch-all tier, or a tier without evidence or a percentage assigns nothing.
--   2. scholarship.assign_course_tiers_v1(scholarship, apply): writes the assignments for one scholarship and recalculates its mapped courses.
--      This change applies it to c377de6f only (the approved scope).
--   3. scholarship.refresh_course_financial_calculation (md5 guarded, whitespace-tolerant anchored edits): when a mapping has a tier
--      assignment, the tier's exact percentage is the award percentage and the record-level "up to" no longer stops the calculation; the tier
--      is named in the calculation's metadata. Every other mapping calculates exactly as before.
-- Consumer impact: the 14 courses are unpublished at course level; nothing the website or Zoho reads changes shape (75/48 checked).
-- G1: no job. G2: no operational value (the tier rates are data). Locks, Layer 4 decisions and cron checked. $0. Nothing dropped or deleted.
-- Replaces: scholarship.refresh_course_financial_calculation (md5 c12328425158de6865cdd664c298e52f; the award percentage of a tier-assigned course).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

create temp table s1322_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

create table if not exists scholarship.course_tier_assignments (
  id uuid primary key default gen_random_uuid(),
  mapping_id uuid not null unique references scholarship.course_mappings(id),
  scholarship_id uuid not null,
  course_id uuid not null,
  tier_id uuid not null references scholarship.award_tiers(id),
  basis text not null check (basis in ('tier_names_course', 'tier_all_other')),
  evidence_id uuid not null,
  assigned_at timestamptz not null default now(),
  change_ref text not null
);
comment on table scholarship.course_tier_assignments is 'CF-247 s1322: the scholarship tier that applies to a mapped course, assigned exactly from the scholarship''s own evidence-backed tier table (the tier label is the course''s registered title, or the table''s single "all other eligible courses" tier). Read by scholarship.refresh_course_financial_calculation; written only by scholarship.assign_course_tiers_v1.';
alter table scholarship.course_tier_assignments enable row level security;
revoke all on table scholarship.course_tier_assignments from public, anon, authenticated;

create or replace function scholarship.assign_course_tiers_v1(p_scholarship uuid, p_apply boolean) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  t record; m record; v_named jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; v_all uuid; v_all_n int; v_n int; v_done int := 0; v_calc jsonb := '[]'::jsonb;
  v_name text; v_course uuid; v_mapping uuid; v_taken uuid[] := '{}';
  norm text;
begin
  if current_user not in ('service_role', 'postgres') then raise exception 'service_role required' using errcode = '42501'; end if;
  select count(*) into v_all_n from scholarship.award_tiers x where x.scholarship_id = p_scholarship and x.label ~* '^\s*all other (eligible )?courses\s*$';
  for t in select * from scholarship.award_tiers x where x.scholarship_id = p_scholarship order by x.display_order, x.tier_code loop
    if t.evidence_id is null or t.percentage is null then v_skip := v_skip || jsonb_build_object('tier', t.tier_code, 'why', 'no evidence or no percentage'); continue; end if;
    if t.label ~* '^\s*all other (eligible )?courses\s*$' then
      if v_all_n = 1 then v_all := t.id; else v_skip := v_skip || jsonb_build_object('tier', t.tier_code, 'why', 'more than one catch-all tier'); end if;
      continue;
    end if;
    -- the label is the course's exact registered title, with an optional trailing "(CODE)"; letter case and spacing only are ignored
    v_name := lower(regexp_replace(btrim(regexp_replace(t.label, '\s*\([A-Za-z0-9]{2,12}\)\s*$', '')), '\s+', ' ', 'g'));
    select count(*), min(mm.id::text)::uuid, min(mm.course_id::text)::uuid into v_n, v_mapping, v_course
      from scholarship.course_mappings mm join catalogue.courses c on c.id = mm.course_id
     where mm.scholarship_id = p_scholarship and mm.mapping_state = 'mapped' and lower(regexp_replace(btrim(c.canonical_title), '\s+', ' ', 'g')) = v_name;
    if v_n <> 1 then v_skip := v_skip || jsonb_build_object('tier', t.tier_code, 'why', format('the label names %s mapped course(s)', v_n)); continue; end if;
    v_named := v_named || jsonb_build_object('tier_id', t.id, 'tier', t.tier_code, 'mapping_id', v_mapping, 'course_id', v_course, 'evidence_id', t.evidence_id, 'pct', t.percentage);
    v_taken := v_taken || v_mapping;
  end loop;
  if p_apply then
    for m in select * from jsonb_array_elements(v_named) e(x) loop
      insert into scholarship.course_tier_assignments (mapping_id, scholarship_id, course_id, tier_id, basis, evidence_id, change_ref)
      values ((m.x->>'mapping_id')::uuid, p_scholarship, (m.x->>'course_id')::uuid, (m.x->>'tier_id')::uuid, 'tier_names_course', (m.x->>'evidence_id')::uuid, 's1322')
      on conflict (mapping_id) do nothing;
      get diagnostics v_n = row_count; v_done := v_done + v_n;
    end loop;
    if v_all is not null then
      insert into scholarship.course_tier_assignments (mapping_id, scholarship_id, course_id, tier_id, basis, evidence_id, change_ref)
      select mm.id, p_scholarship, mm.course_id, v_all, 'tier_all_other', (select x.evidence_id from scholarship.award_tiers x where x.id = v_all), 's1322'
        from scholarship.course_mappings mm where mm.scholarship_id = p_scholarship and mm.mapping_state = 'mapped' and not (mm.id = any (v_taken))
      on conflict (mapping_id) do nothing;
      get diagnostics v_n = row_count; v_done := v_done + v_n;
    end if;
    for m in select a.mapping_id from scholarship.course_tier_assignments a where a.scholarship_id = p_scholarship loop
      v_calc := v_calc || (select jsonb_build_object('mapping_id', r.mapping_id, 'status', r.calculation_status, 'pct', r.award_percentage, 'saving', r.scholarship_saving_amount)
                             from scholarship.refresh_course_financial_calculation(m.mapping_id) r);
    end loop;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scholarship', 'course_tiers_assigned', 'scholarship.course_tier_assignments',
            jsonb_build_object('scholarship_id', p_scholarship, 'assigned', v_done, 'skipped', v_skip, 'change', 's1322'), security.system_actor_id());
  end if;
  return jsonb_build_object('named', v_named, 'all_other_tier', v_all, 'skipped', v_skip, 'assigned', v_done, 'calculations', v_calc);
end $f$;
comment on function scholarship.assign_course_tiers_v1(uuid, boolean) is 'CF-247 s1322: assigns each mapped course of one scholarship its tier from the scholarship''s own evidence-backed tier table, exactly (a tier label that is the course''s registered title, or the single catch-all tier for the rest) and recalculates them; a preview with p_apply false writes nothing.';
revoke all on function scholarship.assign_course_tiers_v1(uuid, boolean) from public, anon, authenticated;

do $e$
declare d text; n int;
begin
  d := pg_get_functiondef('scholarship.refresh_course_financial_calculation(uuid)'::regprocedure);
  if position('s1322' in d) > 0 then raise notice 's1322: already applied'; return; end if;
  if md5(d) <> 'c12328425158de6865cdd664c298e52f' then raise exception 'guard: scholarship.refresh_course_financial_calculation differs from the definition this change edits (live md5 %)', md5(d); end if;
  -- 1. every use of the record-level percentage becomes the effective percentage
  n := regexp_count(d, 'v_s\.award_percentage'); if n < 4 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'v_s.award_percentage', n; end if;
  d := regexp_replace(d, 'v_s\.award_percentage', 'v_pct', 'g');
  -- 2. the declarations
  n := regexp_count(d, 'v_est\s+numeric\(14,2\);'); if n <> 1 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'v_est', n; end if;
  d := regexp_replace(d, 'v_est\s+numeric\(14,2\);', 'v_est numeric(14,2); v_pct numeric; v_tier scholarship.award_tiers%rowtype;  -- s1322');
  -- 3. the tier of a tier-assigned course, after the scholarship is read
  n := regexp_count(d, 'select\s+\*\s+into\s+v_s\s+from\s+scholarship\.scholarships\s+where\s+id\s*=\s*v_map\.scholarship_id;'); if n <> 1 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'select v_s', n; end if;
  d := regexp_replace(d, '(select\s+\*\s+into\s+v_s\s+from\s+scholarship\.scholarships\s+where\s+id\s*=\s*v_map\.scholarship_id;)',
         E'\\1\n  -- s1322 (27 Nov 2026): a course assigned a tier of the scholarship''s own table takes that tier''s exact percentage\n  select t.* into v_tier from scholarship.course_tier_assignments a join scholarship.award_tiers t on t.id = a.tier_id where a.mapping_id = v_map.id and t.percentage is not null;\n  v_pct := coalesce(v_tier.percentage, v_s.award_percentage);');
  -- 4. the structure checks: a tier-assigned course is structured by its tier, so the record-level "up to" does not stop it
  n := regexp_count(d, 'if\s+v_s\.award_value_type\s+is\s+distinct\s+from\s+''percentage''\s+or\s+v_pct\s+is\s+null\s+then'); if n <> 1 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'award_value_type', n; end if;
  d := regexp_replace(d, 'if\s+v_s\.award_value_type\s+is\s+distinct\s+from\s+''percentage''\s+or\s+v_pct\s+is\s+null\s+then',
         'if v_pct is null or (v_tier.id is null and v_s.award_value_type is distinct from ''percentage'') then');
  n := regexp_count(d, 'elsif\s+v_s\.award_value_is_maximum\s+then'); if n <> 1 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'award_value_is_maximum', n; end if;
  d := regexp_replace(d, 'elsif\s+v_s\.award_value_is_maximum\s+then', 'elsif v_tier.id is null and v_s.award_value_is_maximum then');
  -- 5. the tier in the calculation's metadata
  n := regexp_count(d, '''decision''\s*,\s*''Decision 212''\)'); if n <> 1 then raise exception 'guard: scholarship.refresh_course_financial_calculation anchor % found % times', 'metadata', n; end if;
  d := regexp_replace(d, '''decision''\s*,\s*''Decision 212''\)', '''decision'',''Decision 212'',''tier_code'',v_tier.tier_code,''tier_id'',v_tier.id,''tier_rule'',case when v_tier.id is null then null else ''s1322 course tier'' end)');
  execute d;
end $e$;

-- the approved scope: VU Sydney & Brisbane 2027 International Scholarship
do $a$
declare v jsonb;
begin
  if exists (select 1 from scholarship.scholarships where id = 'c377de6f-87c2-5e7e-a130-e68a6c323884') then
    v := scholarship.assign_course_tiers_v1('c377de6f-87c2-5e7e-a130-e68a6c323884', true);
    raise notice 's1322 VU: %', left(v::text, 1500);
    if (v->>'assigned')::int <> 14 then raise exception 'post-check: VU expected 14 tier assignments, got %', v->>'assigned'; end if;
    if exists (select 1 from scholarship.course_financial_calculations f join scholarship.course_tier_assignments a on a.mapping_id = f.mapping_id
                where a.scholarship_id = 'c377de6f-87c2-5e7e-a130-e68a6c323884' and f.calculation_status = 'award_not_structured') then
      raise exception 'post-check: a tier-assigned VU course still calculates as award_not_structured';
    end if;
  end if;
end $a$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s1322_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided_before then raise exception 'post-check: a Layer 4 item was decided'; end if;
  if position('s1322' in pg_get_functiondef('scholarship.refresh_course_financial_calculation(uuid)'::regprocedure)) = 0 then raise exception 'post-check: the calculation edit is missing'; end if;
end $post$;
