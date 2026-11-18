-- CF-247 API v3 data admission, PR A and PR B (plan admin docs/platform/API-V3-DATA-ADMISSION-PLAN-2026-11-17.md; Platform Admin decisions
-- 16 Nov 2026 16:52; pulled forward to the night of 16 Nov by the Platform Admin at 21:03).
-- Replaces: nothing (the fields are empty; these are their first fill functions).
-- Retires: nothing.
--
-- Three deterministic fills, zero AI, no external call. Each counts only unless p_apply is true; Platform Admin or no signed-in user; each
-- applied call is audited in pipeline.admin_control_events; each writes only rows whose value changes and is safe to run again. They do not touch
-- updated_at (catalogue.courses and catalogue.campuses have no updated_at trigger), so the website and Zoho v2 change feeds see nothing new.
-- They serve the PR 3 lanes campus_is_primary, course_empty_reason and course_study_load; this migration fills nothing itself.
--
-- PR A1  security.campus_primary_apply_v1(apply) (REQ-75, D-4 confirmed 16 Nov 16:52): a provider registered on CRICOS whose registered
--        address (catalogue.providers address_line1 and postcode, canonical source: the CRICOS register on data.gov.au) matches exactly one of its
--        active campuses (same address line 1, spaces and case aside, and the same postcode) gets that campus is_primary = true with
--        primary_basis cricos_head_office. A provider that already has a primary campus (any basis, a person's included) is never changed; no
--        match or several matches leave null. Single-campus providers are not marked (decision 2). Read 16 Nov 21:20 AEDT: 356 providers.
-- PR A2  security.course_empty_reason_apply_v1(apply) (REQ-53): for an active course with no campus, the reason from stored evidence only:
--          delivery_mode online                                       -> online_only_no_campus
--          campus reading state not_on_page (page read, no campus)    -> not_published_by_provider
--          campus reading in_review, in_queue, candidate, awaiting_l3 -> pending_extraction
--          campus reading missing_l1 (no register record)             -> not_listed_on_register
--          campus reading site_known, no_website, page_found, blocked -> source_unavailable
--        any other state leaves null. A course that has a campus again has its reason cleared. Read 16 Nov 21:10 AEDT: 5,639 courses
--        (AU 31, CA 1,604, NZ 4,004).
-- PR B   security.course_study_load_stage1_v1(apply) (REQ-52 stage 1): study_load from the verbatim page quote of a filled duration, intakes or
--        delivery reading (pipeline.field_enrich_items, state filled): full-time stated -> full_time, part-time stated -> part_time, both -> both;
--        "full-time equivalent" and "part-time work/job/employment" are not statements of study load. study_load_source provider_page and
--        study_load_evidence_id the newest such reading's evidence. Delivery mode is never used (REQ-52). A value from the register or a person
--        is never changed. Read 16 Nov 21:15 AEDT: 2,521 courses (full time 1,413, part time 183, both 925). Stage 2 (an AI question) stays off.
-- No consumer API object is read or changed in shape (G3): new columns of v3 only receive values. No job (G1), no setting, nothing dropped.

create or replace function security.campus_primary_apply_v1(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare v_n int := 0; v_several int := 0; v_none int := 0; v_kept int := 0;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  create temp table if not exists _cpa (provider_id uuid, campus_id uuid, n int, has_primary boolean) on commit drop;
  truncate _cpa;
  insert into _cpa
  select p.id, (array_agg(k.id order by k.id))[1], count(k.id),
         exists (select 1 from catalogue.campuses x where x.provider_id = p.id and x.is_primary)
    from catalogue.providers p
    left join catalogue.campuses k
      on k.provider_id = p.id and k.status = 'active'
     and lower(regexp_replace(btrim(k.address_line1), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(p.address_line1), '\s+', ' ', 'g'))
     and btrim(coalesce(k.postcode, '')) = btrim(coalesce(p.postcode, ''))
   where nullif(btrim(p.address_line1), '') is not null
     and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos')
   group by p.id;
  select count(*) filter (where n = 1 and not has_primary), count(*) filter (where n > 1), count(*) filter (where n = 0), count(*) filter (where has_primary)
    into v_n, v_several, v_none, v_kept from _cpa;
  if p_apply and v_n > 0 then
    update catalogue.campuses k set is_primary = true, primary_basis = 'cricos_head_office'
      from _cpa c where c.n = 1 and not c.has_primary and k.id = c.campus_id and k.is_primary is distinct from true;
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'campus_primary_apply', 'catalogue.campuses.is_primary',
            jsonb_build_object('basis', 'cricos_head_office', 'marked', v_n, 'several', v_several, 'no_match', v_none, 'already_primary', v_kept), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'marked', v_n, 'several_matches', v_several, 'no_match', v_none, 'already_primary', v_kept);
end;
$function$;
comment on function security.campus_primary_apply_v1(boolean) is
  'CF-247 API v3 PR A (REQ-75, D-4): marks the one active campus matching a CRICOS provider''s registered address as primary (basis cricos_head_office); never changes a provider that already has a primary campus. Count-only unless p_apply; audited.';
revoke all on function security.campus_primary_apply_v1(boolean) from public, anon, authenticated;
grant execute on function security.campus_primary_apply_v1(boolean) to service_role;

create or replace function security.course_empty_reason_apply_v1(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare v_set int := 0; v_cleared int := 0; v_by jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  create temp table if not exists _cer (course_id uuid, code text) on commit drop;
  truncate _cer;
  insert into _cer
  select c.id,
         case when c.delivery_mode = 'online' then 'online_only_no_campus'
              when a.state = 'not_on_page' then 'not_published_by_provider'
              when a.state in ('in_review', 'in_queue', 'candidate', 'awaiting_l3') then 'pending_extraction'
              when a.state = 'missing_l1' then 'not_listed_on_register'
              when a.state in ('site_known', 'no_website', 'page_found', 'blocked') then 'source_unavailable'
         end
    from catalogue.courses c
    left join pipeline.course_attribute_coverage a on a.course_id = c.id and a.attribute = 'campus'
   where c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_campuses k where k.course_id = c.id);
  select jsonb_object_agg(coalesce(code, 'left_null'), n) into v_by from (select code, count(*) n from _cer group by 1) z;
  if p_apply then
    update catalogue.courses c set empty_reason_code = e.code
      from _cer e where c.id = e.course_id and e.code is not null and c.empty_reason_code is distinct from e.code;
    get diagnostics v_set = row_count;
    update catalogue.courses c set empty_reason_code = null
     where c.empty_reason_code is not null
       and (c.lifecycle_status <> 'active' or exists (select 1 from catalogue.course_campuses k where k.course_id = c.id));
    get diagnostics v_cleared = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'course_empty_reason_apply', 'catalogue.courses.empty_reason_code',
            jsonb_build_object('set', v_set, 'cleared', v_cleared, 'by_code', v_by), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'set', v_set, 'cleared', v_cleared, 'by_code', v_by);
end;
$function$;
comment on function security.course_empty_reason_apply_v1(boolean) is
  'CF-247 API v3 PR A (REQ-53): the reason an active course has no campus, from stored evidence only (delivery mode online; the campus reading state); clears the reason when a campus exists. Count-only unless p_apply; audited.';
revoke all on function security.course_empty_reason_apply_v1(boolean) from public, anon, authenticated;
grant execute on function security.course_empty_reason_apply_v1(boolean) to service_role;

create or replace function security.course_study_load_stage1_v1(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare v_set int := 0; v_by jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  create temp table if not exists _csl (course_id uuid, load text, evidence_id uuid) on commit drop;
  truncate _csl;
  insert into _csl
  select r.course_id,
         case when r.ft and r.pt then 'both' when r.ft then 'full_time' else 'part_time' end,
         r.evidence_id
    from (select f.course_id,
                 bool_or(lower(f.quote) ~ '\mfull[- ]?time\M' and lower(f.quote) !~ '\mfull[- ]?time[- ]equivalent') ft,
                 bool_or(lower(f.quote) ~ '\mpart[- ]?time\M' and lower(f.quote) !~ '\mpart[- ]?time (work|job|jobs|employment)\M') pt,
                 (array_agg(f.evidence_id order by f.updated_at desc nulls last, f.id desc)
                    filter (where (lower(f.quote) ~ '\mfull[- ]?time\M' or lower(f.quote) ~ '\mpart[- ]?time\M') and f.evidence_id is not null))[1] evidence_id
            from pipeline.field_enrich_items f
            join catalogue.courses c on c.id = f.course_id and c.lifecycle_status = 'active'
           where f.state = 'filled' and f.field in ('duration', 'intakes', 'delivery') and f.quote is not null
           group by f.course_id) r
   where r.ft or r.pt;
  select jsonb_object_agg(load, n) into v_by from (select load, count(*) n from _csl group by 1) z;
  if p_apply then
    update catalogue.courses c set study_load = s.load, study_load_source = 'provider_page', study_load_evidence_id = s.evidence_id
      from _csl s
     where c.id = s.course_id
       and coalesce(c.study_load_source, 'provider_page') = 'provider_page'
       and (c.study_load, c.study_load_source, c.study_load_evidence_id) is distinct from (s.load, 'provider_page', s.evidence_id);
    get diagnostics v_set = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'course_study_load_stage1', 'catalogue.courses.study_load',
            jsonb_build_object('set', v_set, 'by_load', v_by, 'source', 'provider_page'), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'set', v_set, 'by_load', v_by);
end;
$function$;
comment on function security.course_study_load_stage1_v1(boolean) is
  'CF-247 API v3 PR B (REQ-52 stage 1): study load from the verbatim page quote of a filled duration, intakes or delivery reading (full-time, part-time or both); never from delivery mode; never changes a register or manual value. Count-only unless p_apply; audited.';
revoke all on function security.course_study_load_stage1_v1(boolean) from public, anon, authenticated;
grant execute on function security.course_study_load_stage1_v1(boolean) to service_role;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in)
values
  ('function', 'security.campus_primary_apply_v1', 'consumer', 'api_v3', 'PR A: primary campus by CRICOS registered address (REQ-75, D-4), on demand', 'active', '{}', '20261116180000'),
  ('function', 'security.course_empty_reason_apply_v1', 'consumer', 'api_v3', 'PR A: reason an active course has no campus, from stored evidence (REQ-53), on demand', 'active', '{}', '20261116180000'),
  ('function', 'security.course_study_load_stage1_v1', 'consumer', 'api_v3', 'PR B: study load from stated page evidence (REQ-52 stage 1), on demand', 'active', '{}', '20261116180000')
on conflict (kind, name) do nothing;

do $post$
begin
  if (security.campus_primary_apply_v1(false)->>'applied')::boolean or (security.course_empty_reason_apply_v1(false)->>'applied')::boolean
     or (security.course_study_load_stage1_v1(false)->>'applied')::boolean then
    raise exception 'post-check: a count call applied';
  end if;
end $post$;
