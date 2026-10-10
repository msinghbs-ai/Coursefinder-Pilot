-- CF-247 Decision 254 (5 Oct 2026). Platform Admin 15:36 and fixes found by the La Trobe and RMIT runs (15:22, 15:34).
-- 1. Coverage & completeness › Universities shows Location (campus) and Requirement (entry requirement) beside delivery.
--    Location is the course's campuses held in the catalogue, with the campus the adapter reads on the course page.
--    Requirement is the entry requirement the adapter reads (new pattern field entry_requirement: prerequisites, assumed
--    knowledge, admission requirement). It is shown for review only and is not admitted.
-- 2. Excluding a reading now also withdraws the value it put in the catalogue. Only values from the university's
--    coverage source are withdrawn (fee superseded, intakes withdrawn, English withdrawn, delivery cleared where the
--    adapter wrote it). Values from other sources and values entered by hand stay. Example: RMIT 118028H, where
--    "AU$40,320 (2027 total indicative)" divided by 3 years gave 13,440 before the exclusion was saved.
-- 3. Exit awards take the course page without its view fragment as their course address, marked primary, unless the
--    address was set by hand. A Platform Admin can name an award's course and years by hand (admin_exit_awards 'set'),
--    for awards printed on several courses (La Trobe Associate Degree in Science) or in credit points (RMIT).
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon:
-- where a replacement needs a statement break it is written {sc} and turned into a semicolon with chr(59).

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_pattern_fields()'::regprocedure) is distinct from '10ca5f625a2cd8b7fb3171afc68ab9a7' then
    raise exception 'uni_adapter_pattern_fields changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_pattern_fields() returns text[]
language sql immutable set search_path = '' as $f$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level', 'location', 'fee_total', 'course_years', 'exit_awards', 'entry_requirement']
$f$;

create or replace function security.university_course_location_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
           'value', (select string_agg(distinct cp.name, ', ' order by cp.name) from catalogue.course_campuses cc join catalogue.campuses cp on cp.id = cc.campus_id where cc.course_id = p_course_id),
           'read', coalesce(pg.candidates->'adapter_extra'->>'campus', pg.candidates->'adapter_extra'->>'location'),
           'source', case when exists (select 1 from catalogue.course_campuses cc where cc.course_id = p_course_id) then 'catalogue'
                          when coalesce(pg.candidates->'adapter_extra'->>'campus', pg.candidates->'adapter_extra'->>'location') is not null then 'adapter'
                          else 'missing' end)
  from (select 1) one left join pipeline.coverage_course_pages pg on pg.course_id = p_course_id
$f$;
revoke all on function security.university_course_location_v1(uuid) from public, anon, authenticated;

create or replace function security.university_course_requirement_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('read', pg.candidates->'adapter_extra'->>'entry_requirement',
                            'source', case when pg.candidates->'adapter_extra'->>'entry_requirement' is not null then 'adapter' else 'missing' end)
  from (select 1) one left join pipeline.coverage_course_pages pg on pg.course_id = p_course_id
$f$;
revoke all on function security.university_course_requirement_v1(uuid) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_university_courses_read(uuid,jsonb)'::regprocedure) is distinct from 'b40cd7b5684a0dbea7bf1889c1bb48d9' then
    raise exception 'admin_university_courses_read changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_university_courses_read(uuid,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$'delivery', security.university_course_delivery_v1(y.course_id))$s$,
          $s$'delivery', security.university_course_delivery_v1(y.course_id), 'location', security.university_course_location_v1(y.course_id), 'requirement', security.university_course_requirement_v1(y.course_id))$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_control(text,jsonb)'::regprocedure) is distinct from '2d3d707f06bf5b62721e28884e8e4811' then
    raise exception 'admin_uni_adapter_control changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_control(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$if v_on and v_field = 'fee' then$s$,
          $s$-- 5 Oct 15:40: an exclusion also withdraws what the excluded reading put in the catalogue (coverage source only)
    update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = any (v_courses) and v_on and v_field = 'fee' and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id = security.coverage_sweep_source(v_pid) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = course_id and k.field in ('tuition', 'fee', 'fees')){sc}
    update catalogue.course_intakes set status = 'withdrawn' where course_id = any (v_courses) and v_on and v_field = 'intakes' and status = 'active' and source_id = security.coverage_sweep_source(v_pid) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = course_id and k.field in ('intakes', 'intake')){sc}
    update catalogue.course_english_requirements set status = 'withdrawn' where course_id = any (v_courses) and v_on and v_field = 'english' and status = 'active' and source_id = security.coverage_sweep_source(v_pid) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = course_id and k.field in ('english', 'english_requirements')){sc}
    update catalogue.courses c set delivery_mode = null, updated_at = now() where c.id = any (v_courses) and v_on and v_field = 'delivery' and exists (select 1 from pipeline.adapter_overwrite_changes x where x.course_id = c.id and x.field = 'delivery' and x.after = to_jsonb(c.delivery_mode)) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('delivery_mode', 'delivery')){sc}
    if v_on then perform search.refresh_course_enrichment_scoped_v1(v_courses, true){sc} end if{sc}
    if v_on and v_field = 'fee' then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.exit_awards_apply_v1(uuid)'::regprocedure) is distinct from '2e46d0e839e6502f9569c299f71e6c90' then
    raise exception 'exit_awards_apply_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.exit_awards_apply_v1(uuid)'::regprocedure);
  v_pairs := array[
    array[$s$v_payload := jsonb_build_object('course_url', r.page_url)$s$,
          $s$v_payload := jsonb_build_object('course_url', regexp_replace(r.page_url, '#.*$', ''))$s$],
    array[$s$perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload)$s$,
          $s$perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload){sc}
      if not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('course_url', 'official_url')) then
        update catalogue.courses set course_url = regexp_replace(r.page_url, '#.*$', ''), updated_at = now() where id = r.child_course_id and course_url is distinct from regexp_replace(r.page_url, '#.*$', ''){sc}
        update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now() where course_id = r.child_course_id and link_type = 'official_course' and url = r.page_url and r.page_url <> regexp_replace(r.page_url, '#.*$', ''){sc}
        update catalogue.course_links set is_primary = (url = regexp_replace(r.page_url, '#.*$', '')), updated_at = now() where course_id = r.child_course_id and link_type = 'official_course' and status = 'active'{sc}
      end if$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_exit_awards(text,jsonb)'::regprocedure) is distinct from 'b24897beeaafbe218b48e8cad3d38c87' then
    raise exception 'admin_exit_awards changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_exit_awards(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$elsif p_action in ('off', 'on') then$s$,
          $s$elsif p_action = 'set' then
    if not exists (select 1 from catalogue.courses c where c.id = (p_args->>'child_course_id')::uuid and c.provider_id = v_pid)
       or not exists (select 1 from catalogue.courses c where c.id = (p_args->>'parent_course_id')::uuid and c.provider_id = v_pid) then
      raise exception 'both courses must belong to this university'{sc}
    end if{sc}
    if coalesce((p_args->>'years')::numeric, 0) not between 0.5 and 8 then raise exception 'years must be from 0.5 to 8'{sc} end if{sc}
    insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, set_by, reason)
      select (p_args->>'child_course_id')::uuid, pg.course_id, v_pid, (p_args->>'years')::numeric, coalesce(nullif(btrim(p_args->>'page_url'), ''), pg.url), pg.evidence_id, left(p_args->>'printed', 300), 'hand', v_reason
      from pipeline.coverage_course_pages pg where pg.course_id = (p_args->>'parent_course_id')::uuid
    on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, set_by = 'hand', reason = excluded.reason, active = true, set_at = now() where pipeline.course_exit_awards.child_course_id = excluded.child_course_id{sc}
    v_res := jsonb_build_object('ok', true){sc}
  elsif p_action in ('off', 'on') then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;
