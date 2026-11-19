-- CF-247 s797 (Platform Admin 20 Nov 2026 05:42 AEDT, chat S1-Build; decisions B7 and B2 of the 19 Nov AU/NZ/CA gap assessment, approved).
-- B7 (REQ-52): an active AU course on the CRICOS register that is open to international students and holds no study load is recorded as
--   full_time. ESOS requires a student-visa holder to study full time, so the registration itself is the basis. Recorded with
--   study_load_source 'register' and NO evidence id: that pair marks a rule value (the register loader always records its evidence id).
--   A rule value never outranks a reading: the stored-page writer, the boost study-load lane, a person's Layer 4 decision and the register
--   loader may each replace it (seven md5-guarded edits below). A manual lock is never touched. No value already held is changed.
-- B2 (D-4, REQ-75): the primary campus. First the register head office (the existing security.campus_primary_apply_v1, AU CRICOS, unchanged);
--   where the register is silent, the active campus with the most active courses (primary_basis 'highest_course_count', a value the table
--   already allows). A provider whose top campuses tie is left for a person. A provider with a primary, or with a locked campus, is skipped.
-- Parity before writing (read live 20 Nov 2026 05:45 AEDT): history 2,198 rows, head 20261120010000; 50 post-cut-off versions = 50 files.
-- G3: data only; no consumer function, table or column changes. No spend (no reading, no AI, no Firecrawl).
-- Replaces: nothing.
-- Retires: nothing.

create or replace function security.course_study_load_register_rule_rows_v1()
returns table (id uuid) language sql stable security definer set search_path to '' as $f$
  select c.id from catalogue.courses c
    join catalogue.providers p on p.id = c.provider_id
    join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
   where c.lifecycle_status = 'active' and c.study_load is null
     and c.open_to_international is true
     and c.course_code ~ '^[0-9]{6}[0-9A-Z]$'                                   -- fixed: the CRICOS course code format
     and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos')
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id
                      and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
$f$;
revoke all on function security.course_study_load_register_rule_rows_v1() from public, anon, authenticated;
comment on function security.course_study_load_register_rule_rows_v1() is 'CF-247 s797 B7: the courses the register rule may fill (active AU CRICOS courses open to international students, no study load, no lock).';

create or replace function security.course_study_load_register_rule_v1(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_n int := 0; v_eligible int;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  select count(*) into v_eligible from catalogue.courses c where c.id in (select x.id from security.course_study_load_register_rule_rows_v1() x);
  if p_apply and v_eligible > 0 then
    update catalogue.courses c set study_load = 'full_time', study_load_source = 'register', study_load_evidence_id = null, updated_at = now()
     where c.id in (select x.id from security.course_study_load_register_rule_rows_v1() x) and c.study_load is null;
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'course_study_load_register_rule', 'catalogue.courses.study_load',
            jsonb_build_object('rule', 'B7: CRICOS international course, ESOS full time', 'set', v_n, 'eligible', v_eligible,
                               'source', 'register', 'evidence', 'none (marks a rule value)', 'approved', 'Platform Admin 20 Nov 2026 05:42 AEDT'), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'eligible', v_eligible, 'set', v_n);
end $f$;
revoke all on function security.course_study_load_register_rule_v1(boolean) from public, anon, authenticated;
comment on function security.course_study_load_register_rule_v1(boolean) is 'CF-247 s797 B7: records full_time (source register, no evidence id) for active AU CRICOS courses open to international students that hold no study load; skips manual locks; never changes a held value.';

create or replace function security.campus_primary_rule_v1(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_reg jsonb; v_n int := 0; v_tie int; v_tie_ids jsonb; v_single int; v_by jsonb; v_rows jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_reg := security.campus_primary_apply_v1(p_apply);   -- the register head office first (unchanged)
  with prov as (
    select p.id, k.iso_alpha2 cc from catalogue.providers p join ref.countries k on k.id = p.country_id and k.iso_alpha2 in ('AU', 'NZ', 'CA')
     where p.lifecycle_status = 'active'
       and not exists (select 1 from catalogue.campuses x where x.provider_id = p.id and x.is_primary)
       and not exists (select 1 from pipeline.manual_locks l join catalogue.campuses x on x.id = l.entity_id
                        where l.entity = 'campus' and l.field in ('is_primary', 'primary_basis') and x.provider_id = p.id)),
  cnt as (
    select k.provider_id, k.id campus_id, prov.cc,
           (select count(distinct cc.course_id) from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id and c.lifecycle_status = 'active'
             where cc.campus_id = k.id)::int n
      from catalogue.campuses k join prov on prov.id = k.provider_id where k.status = 'active'),
  ranked as (
    select provider_id, campus_id, cc, n, rank() over (partition by provider_id order by n desc) rk,
           count(*) over (partition by provider_id, n) top, count(*) over (partition by provider_id) campuses from cnt)
  select coalesce(jsonb_agg(to_jsonb(ranked)), '[]'::jsonb) into v_rows from ranked;
  select count(distinct x.provider_id) filter (where x.rk = 1 and x.top > 1), count(distinct x.provider_id) filter (where x.campuses = 1),
         coalesce(jsonb_agg(distinct x.provider_id) filter (where x.rk = 1 and x.top > 1), '[]'::jsonb)
    into v_tie, v_single, v_tie_ids
    from jsonb_to_recordset(v_rows) x(provider_id uuid, campus_id uuid, cc text, n int, rk int, top int, campuses int);
  if p_apply then
    update catalogue.campuses k set is_primary = true, primary_basis = 'highest_course_count', updated_at = now()
      from jsonb_to_recordset(v_rows) r(provider_id uuid, campus_id uuid, cc text, n int, rk int, top int, campuses int)
     where r.campus_id = k.id and r.rk = 1 and r.top = 1 and k.is_primary is distinct from true
       and not exists (select 1 from catalogue.campuses x where x.provider_id = r.provider_id and x.is_primary);
    get diagnostics v_n = row_count;
    select coalesce(jsonb_object_agg(cc, n), '{}'::jsonb) into v_by from (
      select r.cc, count(*) n from jsonb_to_recordset(v_rows) r(provider_id uuid, campus_id uuid, cc text, n int, rk int, top int, campuses int)
        join catalogue.campuses k on k.id = r.campus_id where r.rk = 1 and r.top = 1 and k.primary_basis = 'highest_course_count' group by 1) z;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'campus_primary_rule', 'catalogue.campuses.is_primary',
            jsonb_build_object('rule', 'B2: register head office, then the campus with the most active courses', 'register', v_reg,
                               'most_courses_marked', v_n, 'by_country', v_by, 'sole_campus_providers', v_single,
                               'ties_left_for_review', v_tie, 'tie_providers', v_tie_ids, 'approved', 'Platform Admin 20 Nov 2026 05:42 AEDT'), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'register', v_reg, 'most_courses_marked', v_n, 'by_country', v_by, 'ties_left_for_review', v_tie, 'sole_campus_providers', v_single);
end $f$;
revoke all on function security.campus_primary_rule_v1(boolean) from public, anon, authenticated;
comment on function security.campus_primary_rule_v1(boolean) is 'CF-247 s797 B2: primary campus by the register head office, then by the most active courses; ties and locked providers are left for a person.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- a rule value (source register, no evidence id) never outranks a reading: each writer that fills an empty study load may replace it
select pg_temp.cf_edit_def('security.course_study_load_stage1_v1(boolean)'::regprocedure, '866bac4e020c8110a690afd5112e72f2',
  array[$o$and coalesce(c.study_load_source, 'provider_page') = 'provider_page'$o$],
  array[$n$and (coalesce(c.study_load_source, 'provider_page') = 'provider_page' or (c.study_load_source = 'register' and c.study_load_evidence_id is null))  -- s797: a page replaces a B7 rule value$n$]);
select pg_temp.cf_edit_def('security.boost_study_load_review_feed_v1()'::regprocedure, '1b533e4dd4591a7910f7c6edc7b6fd08',
  array[$o$c.id = r.course_id and c.study_load is not null)$o$, $o$     where c.study_load is null$o$],
  array[$n$c.id = r.course_id and c.study_load is not null and not (c.study_load_source = 'register' and c.study_load_evidence_id is null))$n$,
        $n$     where (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null))  -- s797: a B7 rule value is still open to a reading$n$]);
select pg_temp.cf_edit_def('security.layer4_boost_study_load_inbox_decide_v1(text,text,text,text)'::regprocedure, '58344e5618e9ac2ae8a88e852a9b65cf',
  array[$o$where id = r.course_id and study_load is null;$o$],
  array[$n$where id = r.course_id and (study_load is null or (study_load_source = 'register' and study_load_evidence_id is null));  -- s797: a person replaces a B7 rule value$n$]);
select pg_temp.cf_edit_def('security.boost_extract_claim_v1(integer)'::regprocedure, 'a80ff8e9ce2989abe8f786b0748c9357',
  array[$o$c.lifecycle_status = 'active' and c.study_load is null$o$],
  array[$n$c.lifecycle_status = 'active' and (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null))  -- s797$n$]);
select pg_temp.cf_edit_def('security.boost_promote_v1(text,boolean,timestamp with time zone)'::regprocedure, 'fa4e3a8671577e2674e652fc5012f497',
  array[$o$where c.id = p.entity_id and c.study_load is null;$o$],
  array[$n$where c.id = p.entity_id and (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null));  -- s797$n$]);
select pg_temp.cf_edit_def('public.svc_page_text_next_v1(integer)'::regprocedure, '04f3286ab30c4d7cd49ed8e401ed83cb',
  array[$o$and (c.study_load is null or nullif(btrim(c.description), '') is null)$o$],
  array[$n$and (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null) or nullif(btrim(c.description), '') is null)  -- s797$n$]);
select pg_temp.cf_edit_def('public.svc_layer1_apply_baseline_records_v1(text,text,uuid,uuid,text,jsonb)'::regprocedure, '784027d2f339d7aebc00b2629be2d197',
  array[$o$where id = v_course and study_load is null;$o$],
  array[$n$where id = v_course and (study_load is null or (study_load_source = 'register' and study_load_evidence_id is null));  -- s797: a register value replaces a B7 rule value$n$]);

-- apply both rules
do $$
declare b7 jsonb; b2 jsonb; v_before_held int; v_after_held int; v_locked int; v_multi int;
begin
  if (select count(*) from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
       where c.lifecycle_status = 'active' and c.study_load is null and c.open_to_international and c.course_code ~ '^[0-9]{6}[0-9A-Z]$'
         and not exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos')) > 0 then
    raise notice 's797: some CRICOS-format AU courses belong to a provider without a CRICOS registration; they are left out';
  end if;
  select count(*) into v_before_held from catalogue.courses where study_load is not null;
  b7 := security.course_study_load_register_rule_v1(true);
  select count(*) into v_after_held from catalogue.courses where study_load is not null;
  if v_after_held - v_before_held <> (b7->>'set')::int then raise exception 'post-check: held loads moved by % but the rule set %', v_after_held - v_before_held, b7->>'set'; end if;
  if (b7->>'set')::int < 10000 or (b7->>'set')::int > 17100 then raise exception 'post-check: B7 set % courses, outside the expected 10,000 to 17,100', b7->>'set'; end if;
  if exists (select 1 from catalogue.courses c join pipeline.manual_locks l on l.entity = 'course' and l.entity_id = c.id and l.field like 'study_load%'
              where c.study_load_source = 'register' and c.study_load_evidence_id is null) then raise exception 'post-check: a locked course was changed'; end if;
  if (select count(*) from catalogue.courses where study_load_source = 'provider_page') < 12000 then raise exception 'post-check: page readings were lost'; end if;
  b2 := security.campus_primary_rule_v1(true);
  select count(*) into v_multi from (select provider_id from catalogue.campuses where is_primary group by 1 having count(*) > 1) z;
  if v_multi > 0 then raise exception 'post-check: % providers now have more than one primary campus', v_multi; end if;
  perform security.course_study_load_stage1_v1(false);   -- the edited writers still run (dry)
  perform set_config('cf.diag', 'B7 ' || b7::text || ' | B2 ' || b2::text
    || ' | AU active with no load now ' || (select count(*) from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU' where c.lifecycle_status = 'active' and c.study_load is null)
    || ' | primary campuses ' || (select string_agg(cc || ' ' || n, ', ') from (select k.iso_alpha2 cc, count(*) n from catalogue.campuses ca join ref.countries k on k.id = ca.country_id where ca.is_primary and k.iso_alpha2 in ('AU','NZ','CA') group by 1 order by 1) z), true);
end $$;
