-- CF-247 Decision 254 (6 Oct 2026, Platform Admin decision D2 at 10:56: "Build, opt-in per adapter"). Three reading
-- options a Platform Admin can switch on for one adapter (pipeline.uni_adapters.reading), read by worker v0.17.13:
--   numeric_dates: start dates printed as numbers ("14/09/2026", "19/01/26", "2026-09-14") are read as months
--   upper_dates: month names printed in capitals ("JAN", "SEPT", "NOVEMBER") are read as months
--   academic_year: a course of 34 to 44 weeks is one academic year, so its printed fee is the annual fee
-- Nothing changes for an adapter that does not opt in. Values already admitted are not touched by this file.
-- uni_adapter_json is replaced (md5-guarded) to carry the options to the worker and the editor. admin_uni_adapter_write
-- is snippet-patched (md5-guarded, each snippet found exactly once) to check and store them. No text value in this file
-- contains a semicolon: where a replacement needs a statement break it is written {sc} and turned into chr(59).

alter table pipeline.uni_adapters add column if not exists reading jsonb not null default '{}'::jsonb;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_json(uuid)'::regprocedure) is distinct from 'cea75cd537f56ab3e03d93c55c1bb74e' then
    raise exception 'uni_adapter_json changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_json(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('title_strip', a.title_strip, 'course_title_strip', a.course_title_strip, 'json_source', a.json_source, 'json_paths', a.json_paths,
                            'sections', a.sections, 'patterns', a.patterns, 'pick', a.pick, 'term_months', a.term_months, 'page_view', a.page_view,
                            'reading', a.reading,
                            'section_chars', a.section_chars, 'enabled', a.enabled, 'notes', a.notes, 'reason', a.reason, 'updated_at', a.updated_at)
  from pipeline.uni_adapters a where a.provider_id = p_provider
$f$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from 'dec2b629c166cd897d26990e4983c8e0' then
    raise exception 'admin_uni_adapter_write changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_write(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$then raise exception 'the JSON script id may only hold letters, digits, _ and -'$s$,
          $s$then raise exception 'the JSON script id may only hold letters, digits, _ and -'{sc} end if{sc}
    if jsonb_typeof(coalesce(v_a->'reading', '{}'::jsonb)) <> 'object'
       or exists (select 1 from jsonb_each(coalesce(v_a->'reading', '{}'::jsonb)) r where r.key not in ('numeric_dates', 'upper_dates', 'academic_year') or jsonb_typeof(r.value) <> 'boolean') then
      raise exception 'reading may only hold numeric_dates, upper_dates and academic_year, each true or false'$s$],
    array[$s$pick, term_months, page_view, section_chars, notes, reason, updated_by, updated_at)$s$,
          $s$pick, term_months, page_view, reading, section_chars, notes, reason, updated_by, updated_at)$s$],
    array[$s$coalesce(v_a->'page_view', '{}'::jsonb), greatest($s$,
          $s$coalesce(v_a->'page_view', '{}'::jsonb), coalesce(v_a->'reading', '{}'::jsonb), greatest($s$],
    array[$s$page_view = excluded.page_view,$s$,
          $s$page_view = excluded.page_view, reading = excluded.reading,$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;
