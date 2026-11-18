-- CF-247 (22 Oct 2026). Platform Admin 22:32 (website review): "Some universities are showing Diploma and Certificate courses that they
-- do not offer. For example, the University of Auckland". Choice 22:40: "Fixes only, no note".
-- Found: the register reader gives each qualification its level as a code (graduate_certificate, graduate_diploma), but
-- public.svc_layer1_apply_register_records matched words with a space ('%graduate certificate%'), so every New Zealand postgraduate and
-- graduate certificate became Certificate (437) and every postgraduate and graduate diploma became Diploma (767). Auckland's
-- "Postgraduate Diploma in Arts (Level 8)" showed as a Diploma.
-- 1 The apply reads the code with underscores as spaces, so the next NZQA run keeps the right level (md5-guarded edit).
-- 2 The 1,204 New Zealand courses take the level the reader gave them (the register title's qualification type), logged in
--   pipeline.admin_control_events; manual locks are kept. The website search copy is asked to refresh.
-- Replaces: public.svc_layer1_apply_register_records (md5-guarded edit)
-- Retires: nothing
do $edit$
declare v_def text := pg_get_functiondef('public.svc_layer1_apply_register_records'::regproc);
        v_old text := $o$v_level_name:=lower(coalesce(r->>'course_level',''));$o$;
begin
  if position($p$replace(lower(coalesce(r->>'course_level','')),'_',' ')$p$ in v_def) > 0 then return; end if;
  if md5(v_def) <> 'd8e3ed699880f44ff3257d9941f11d1b' then raise exception 'live public.svc_layer1_apply_register_records differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'level name line must occur once'; end if;
  execute replace(v_def, v_old, $n$v_level_name:=replace(lower(coalesce(r->>'course_level','')),'_',' ');  -- CF-247 22 Oct 2026: the reader gives codes (graduate_certificate)$n$);
end $edit$;

do $fix$
declare v_n int;
begin
  with t as (
    select c.id, sl.code old_code, case when c.canonical_title ~* 'graduate diploma' then 'graduate_diploma' else 'graduate_certificate' end new_code
      from catalogue.courses c join ref.study_levels sl on sl.id = c.study_level_id
     where security.coverage_country(c.provider_id) = 'NZ' and sl.code in ('certificate', 'diploma')
       and c.canonical_title ~* '^(post-?graduate|graduate) (certificate|diploma)'
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'study_level_id')),
  u as (update catalogue.courses c set study_level_id = (select x.id from ref.study_levels x where x.code = t.new_code), updated_at = now()
          from t where c.id = t.id returning t.id, t.old_code, t.new_code)
  select count(*) into v_n from u;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('course_levels', 'register_level_fix', 'NZ', jsonb_build_object('courses', v_n, 'reason', 'Register level codes (graduate_certificate, graduate_diploma) were read as Certificate and Diploma by svc_layer1_apply_register_records; Platform Admin 22 Oct 2026 website review'));
  if v_n > 0 then insert into search.refresh_requests(requested_by) values ('NZ graduate and postgraduate levels corrected: ' || v_n || ' courses'); end if;
end $fix$;
