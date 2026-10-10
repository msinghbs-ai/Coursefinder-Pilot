-- CF-247 (Decision 211, 2 Oct 2026): scholarship eligibility criteria and award scope from the provider page; old
-- course-link candidates retired.
-- Platform Admin (2 Oct 00:01, "What is happening with scholarship for courses available to international students"),
-- answers: "Read criteria" first; "Retire them" for the old candidates.
-- Measured before: 1,233 active scholarships, 124 published; structured criteria for 9 scholarships (145 more hold only
-- a narrative); award duration known for 3. 37,200 course-link candidates waiting since 3-5 Sep 2026 (35,505 from the
-- retired fill service; 17,008 of them already linked by later rules).
--
-- 1. Old candidates: status 'superseded' (kept, not deleted). The fill service no longer reopens a superseded candidate.
-- 2. security.scholarship_criteria_apply_v1: the reader's criteria (student type, study stage, full-time, ATAR/GPA/WAM
--    minimum, gender, nationality, applying without an application) become scholarship.criteria rows marked
--    value_json.by = 'scholarship_sweep'. A changed page supersedes the earlier sweep rows; criteria from any other
--    source (people, AI, feeds) are never touched. Award duration is filled only where the record has none.
-- 3. The sweep apply calls it on every read; svc_scholarship_reextract_next/_record add the two new facts to pages
--    already stored (no fetch) without changing their other facts or course links.
-- Publication rules are unchanged here.

-- 1. old candidates
alter table scholarship.course_mapping_candidates drop constraint course_mapping_candidates_status_check;
alter table scholarship.course_mapping_candidates add constraint course_mapping_candidates_status_check
  check (status = any (array['needs_review','accepted','rejected','superseded']));

update scholarship.course_mapping_candidates set status = 'superseded', updated_at = now()
 where status = 'needs_review' and created_at < timestamptz '2026-09-06 00:00:00+10';

do $f$
declare s text; d text; v text;
  o text := $o$on conflict(scholarship_id,course_id) do update set updated_at=now(),status='needs_review';$o$;
  n text := $n$on conflict(scholarship_id,course_id) do update set updated_at=now(),status=case when scholarship.course_mapping_candidates.status='superseded' then 'superseded' else 'needs_review' end;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'scholarship_course_fill_service';
  v := md5(s);
  if v is distinct from '227e2ee15a868acc5555b55bfc41ad7d' then raise exception 'scholarship_course_fill_service changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'conflict clause not found once'; end if;
  execute replace(d, o, n);
end $f$;

-- 2. criteria and award scope
create or replace function security.scholarship_criteria_apply_v1(p_scholarship_id uuid) returns text[]
language plpgsql security definer set search_path = '' as $fn$
declare pg record; s record; v_src uuid; v_new jsonb; v_old jsonb; v_changes text[] := '{}'; v_dur text; n int;
begin
  select * into pg from pipeline.scholarship_pages where scholarship_id = p_scholarship_id;
  select * into s from scholarship.scholarships where id = p_scholarship_id;
  if s.id is null or pg.read_status is distinct from 'read' or pg.facts is null or not (pg.facts ? 'criteria') then return v_changes; end if;
  v_src := security.coverage_sweep_source(s.provider_id);

  -- the reader's criteria, in a fixed order, compared with the sweep's active rows
  select coalesce(jsonb_agg(x order by x->>'type', x->>'value_text', x->>'value_codes'), '[]') into v_new
    from (select jsonb_build_object('type', c->>'type', 'operator', c->>'operator', 'value_text', c->>'value_text',
                 'value_number', (c->>'value_number')::numeric, 'value_codes', c->'value_codes', 'scale', (c->>'scale')::numeric) x
            from jsonb_array_elements(case when jsonb_typeof(pg.facts->'criteria') = 'array' then pg.facts->'criteria' else '[]' end) c
           where c->>'type' in ('student_type','study_stage','study_load','academic_minimum','gender','nationality','application_method')) q;
  select coalesce(jsonb_agg(x order by x->>'type', x->>'value_text', x->>'value_codes'), '[]') into v_old
    from (select jsonb_build_object('type', cr.criterion_type, 'operator', cr.operator, 'value_text', cr.value_text,
                 'value_number', cr.value_number, 'value_codes', to_jsonb(cr.value_codes), 'scale', (cr.value_json->>'scale')::numeric) x
            from scholarship.criteria cr
           where cr.scholarship_id = s.id and cr.status = 'active' and cr.value_json->>'by' = 'scholarship_sweep') q;
  if v_new is distinct from v_old then
    update scholarship.criteria set status = 'superseded'
     where scholarship_id = s.id and status = 'active' and value_json->>'by' = 'scholarship_sweep';
    insert into scholarship.criteria(scholarship_id, criterion_type, operator, value_text, value_number, value_codes, value_json,
                                     human_text, is_mandatory, machine_evaluable, status, source_id, evidence_id, confidence)
    select s.id, c->>'type', c->>'operator', c->>'value_text', (c->>'value_number')::numeric,
           case when jsonb_typeof(c->'value_codes') = 'array' then array(select jsonb_array_elements_text(c->'value_codes')) end,
           jsonb_strip_nulls(jsonb_build_object('by', 'scholarship_sweep', 'extractor', coalesce(pg.facts->>'criteria_extractor', pg.facts->>'extractor'), 'scale', (c->>'scale')::numeric)),
           left(c->>'text', 300), true, c->>'type' <> 'application_method', 'active', v_src, pg.evidence_id, 0.7
      from jsonb_array_elements(case when jsonb_typeof(pg.facts->'criteria') = 'array' then pg.facts->'criteria' else '[]' end) c
     where c->>'type' in ('student_type','study_stage','study_load','academic_minimum','gender','nationality','application_method');
    get diagnostics n = row_count;
    insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
    values (s.id, 'criteria', v_old, v_new, pg.evidence_id);
    v_changes := v_changes || 'criteria'::text;
  end if;

  -- award duration, only where the record has none (values entered by hand or by other sources stay)
  v_dur := pg.facts->'award_scope'->>'duration';
  if s.award_duration_basis is null and v_dur in ('one_off','first_year','annual','annual_program_duration','program_duration','per_semester') then
    begin
      update scholarship.scholarships set award_duration_basis = v_dur, updated_at = now() where id = s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
      values (s.id, 'award_duration_basis', null, pg.facts->'award_scope', pg.evidence_id);
      v_changes := v_changes || 'award_duration'::text;
    exception when others then null; -- a value locked by hand is left as it is
    end;
  end if;
  return v_changes;
end $fn$;
revoke all on function security.scholarship_criteria_apply_v1(uuid) from public, anon, authenticated;

-- 3a. every read applies them (before the English-course branch, which returns early)
do $a$
declare s text; d text; v text;
  o text := E'  -- v0.5.0: an English language course scholarship links only to the provider''s English language courses\n';
  n text := E'  -- Decision 211: eligibility criteria and award duration from the page\n  v_changes:=v_changes||security.scholarship_criteria_apply_v1(s.id);\n\n' || E'  -- v0.5.0: an English language course scholarship links only to the provider''s English language courses\n';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'scholarship_sweep_apply_v1';
  v := md5(s);
  if v is distinct from '30c019473f3fe3e46382e93079d8cfb5' then raise exception 'scholarship_sweep_apply_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'English-course comment not found once'; end if;
  execute replace(d, o, n);
end $a$;

-- 3b. stored pages: add the two new facts only
create or replace function public.svc_scholarship_reextract_next(p_limit int, p_version text)
returns table(scholarship_id uuid, storage_path text)
language plpgsql security definer set search_path = '' as $fn$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return query
    select sp.scholarship_id, e.storage_path
      from pipeline.scholarship_pages sp
      join scholarship.scholarships s on s.id = sp.scholarship_id and s.lifecycle_status = 'active'
      join pipeline.evidence_artifacts e on e.id = sp.evidence_id and e.storage_path is not null
     where sp.read_status = 'read' and sp.facts is not null
       and coalesce(sp.facts->>'criteria_extractor', '') is distinct from p_version
       and coalesce(sp.facts->>'extractor', '') is distinct from p_version
     order by s.publication_status = 'published' desc, sp.scholarship_id
     limit greatest(1, least(p_limit, 300));
end $fn$;
revoke all on function public.svc_scholarship_reextract_next(int, text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_reextract_next(int, text) to service_role;

create or replace function public.svc_scholarship_reextract_record(p_scholarship_id uuid, p_facts jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v text[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.scholarship_pages
     set facts = facts || jsonb_build_object('criteria', coalesce(p_facts->'criteria', '[]'), 'award_scope', p_facts->'award_scope', 'criteria_extractor', p_facts->>'criteria_extractor')
   where scholarship_id = p_scholarship_id and read_status = 'read' and facts is not null;
  v := security.scholarship_criteria_apply_v1(p_scholarship_id);
  return jsonb_build_object('changes', to_jsonb(v));
end $fn$;
revoke all on function public.svc_scholarship_reextract_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_reextract_record(uuid, jsonb) to service_role;

-- 4. the scholarship record shows the award duration (Catalogue › Scholarships detail)
do $u$
declare s text; d text; v text;
  o text := $o$'award_value_text',s.award_value_text,$o$;
  n text := $n$'award_value_text',s.award_value_text,'award_duration_basis',s.award_duration_basis,$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ui_scholarship_detail';
  v := md5(s);
  if v is distinct from '19619049f548b3af7a26429af0a13084' then raise exception 'ui_scholarship_detail changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'award value field not found once'; end if;
  execute replace(d, o, n);
end $u$;
