-- Decision 152 (option B): Layer 1 apply functions write facts only when they change, and refresh
-- verification markers (courses.last_verified_at; registrations' evidence pointer) at most once per
-- 30-day re-check cycle. Every register run is still recorded in full at run level (snapshot evidence
-- and run log). Previously each weekly CRICOS run rewrote ~26,600 courses and ~26,600 registrations.
-- Applied as checksum-guarded, exact-once text patches of the live definitions.
do $patch$
declare d text; n int; f record;
  guard_ver constant text := ' or last_verified_at is null or last_verified_at < now() - interval ''30 days'')';
  guard_reg constant text := ' or evidence_id is null or not exists (select 1 from pipeline.evidence_artifacts ea where ea.id = catalogue.course_registrations.evidence_id and ea.captured_at >= now() - interval ''30 days''))';
begin
  for f in select * from (values
    ('svc_layer1_apply_cricos_records','7be75b0cce002317763015d4b039989c'),
    ('svc_layer1_apply_register_records','d17ad31185d649d1870a176a306e6e30'),
    ('svc_layer1_apply_scoped_course_records','abf7ea60495cefa287bcc9b13e005c1a')) v(fn, md5) loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=f.fn;
    if md5(d) <> f.md5 then raise exception '% changed since review (md5 %), aborting', f.fn, md5(d); end if;

    -- courses: facts-or-cycle guard
    if f.fn='svc_layer1_apply_scoped_course_records' then
      select count(*) into n from regexp_matches(d, 'last_verified_at\s*=\s*now\(\)\s*,\s*updated_at\s*=\s*now\(\)\s+where\s+id\s*=\s*v_course\s*;', 'g');
      if n<>1 then raise exception '% courses pattern found % times', f.fn, n; end if;
      d := regexp_replace(d, '(last_verified_at\s*=\s*now\(\)\s*,\s*updated_at\s*=\s*now\(\)\s+where\s+id\s*=\s*v_course)\s*;',
        '\1 and (canonical_title is distinct from v_cname or display_title is distinct from v_cname or course_code is distinct from v_ccode or lifecycle_status is distinct from v_lifecycle or canonical_source_id is distinct from p_course_source_id'||guard_ver||';');
    else
      select count(*) into n from regexp_matches(d, 'last_verified_at\s*=\s*now\(\)\s*,\s*updated_at\s*=\s*now\(\)\s+where\s+id\s*=\s*v_course\s*;', 'g');
      if n<>1 then raise exception '% courses pattern found % times', f.fn, n; end if;
      d := regexp_replace(d, '(last_verified_at\s*=\s*now\(\)\s*,\s*updated_at\s*=\s*now\(\)\s+where\s+id\s*=\s*v_course)\s*;',
        '\1 and (study_level_id is distinct from coalesce(v_level,study_level_id)'||
        case when f.fn='svc_layer1_apply_register_records' then ' or primary_field_id is distinct from coalesce(v_field,primary_field_id)' else '' end||
        ' or duration_value is distinct from coalesce(v_weeks,duration_value) or (v_weeks is not null and duration_unit is distinct from ''weeks'') or canonical_source_id is distinct from p_source_id'||guard_ver||';');
    end if;

    -- registrations: facts-or-cycle guard
    if f.fn='svc_layer1_apply_cricos_records' then
      select count(*) into n from regexp_matches(d, 'upper\(registration_code\)\s*=\s*v_ccode\s*;', 'g');
      if n<>1 then raise exception '% registrations pattern found % times', f.fn, n; end if;
      d := regexp_replace(d, '(evidence_id\s*=\s*p_evidence_id\s+where\s+course_id\s*=\s*v_course\s+and\s+lower\(scheme\)\s*=\s*''cricos''\s+and\s+upper\(registration_code\)\s*=\s*v_ccode)\s*;',
        '\1 and (source_id is distinct from p_source_id or status is distinct from ''active'''||guard_reg||';');
    elsif f.fn='svc_layer1_apply_register_records' then
      select count(*) into n from regexp_matches(d, 'lower\(scheme\)\s*=\s*v_scheme\s+and\s+upper\(registration_code\)\s*=\s*v_ccode\s*;', 'g');
      if n<>1 then raise exception '% registrations pattern found % times', f.fn, n; end if;
      d := regexp_replace(d, '(lower\(scheme\)\s*=\s*v_scheme\s+and\s+upper\(registration_code\)\s*=\s*v_ccode)\s*;',
        '\1 and (source_id is distinct from p_source_id or status is distinct from ''active'''||guard_reg||';');
    end if;

    if d !~ 'last_verified_at < now\(\) - interval ''30 days''' then raise exception '% course guard not applied', f.fn; end if;
    if f.fn<>'svc_layer1_apply_scoped_course_records' and d !~ 'ea\.captured_at >= now\(\) - interval ''30 days''' then raise exception '% registration guard not applied', f.fn; end if;
    execute d;
  end loop;
end $patch$;
