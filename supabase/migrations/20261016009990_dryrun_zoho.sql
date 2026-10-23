-- CF-247 (23 Oct 2026). Platform Admin 22:57 "How do increase the capacity, can you dry run and test maximum capacity to be
-- configured by UI?" and 23:13 "Go". The course-page read lane (job coverage-read, every 30 seconds) read at most 60 pages a call
-- whatever Settings › Pipeline settings › Read course pages said (the worker capped it at 60), fetching 8 pages at the same time
-- (fixed in the worker). Measured 23 Oct 22:31 to 23:02: about 100 pages a minute; the setting at 120 changed nothing.
-- 1 reading.pages_at_once (1 to 32, 8 today): pages one read call fetches at the same time; the worker (v0.44.0) reads it.
-- 2 public.svc_worker_settings_v1 also returns the reading.* keys to the worker (md5-guarded edit).
-- 3 Already done live by the Platform Admin's "Go" (logged here for the record, not repeated): pages.render_countries gained CA;
--   job coverage-read-2 switched on (a second read call every 30 seconds).
-- Replaces: nothing (public.svc_worker_settings_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'reading.pages_at_once', 'Read course pages: pages fetched at once',
        'How many course pages one read call (job coverage-read, every 30 seconds) fetches from the universities at the same time. Each call reads up to Read course pages and stops after 110 seconds. Raise it in steps and watch fetch failures and blocked pages on the hourly report: universities answer slowly or refuse when hit too hard.',
        'number', '8'::jsonb, '1', '32', 'pages', 103, 'Job sizes', 'job coverage-read, coverage-read-2; worker coverage-sweep read',
        'Platform Admin 23 Oct 2026 23:13 "Go": read lane capacity configurable (it was 8, fixed in the worker)')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit_once('public.svc_worker_settings_v1()', '2b5b30d2c25bf540f76419a33c48be34', array[
  array[$o$or (s.toolset_key = 'pipeline' and s.key like 'enrich.%')$o$,
        $n$or (s.toolset_key = 'pipeline' and (s.key like 'enrich.%' or s.key like 'reading.%'))$n$]
]);

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.reading.pages_at_once',
        jsonb_build_object('before', '8 (fixed in the worker)', 'after', 8, 'range', '1 to 32', 'reason', 'Platform Admin 23 Oct 2026 23:13 "Go" (migration 20261023027000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('setting', 'pipeline.reading.pages_at_once', 'Layer 2', 'Pages one course-page read call fetches at the same time (worker coverage-sweep read)', 'active', '{}', '20261023027000')
on conflict (kind, name) do nothing;

do $t$ declare r jsonb; s record; begin
  select value, min_value, max_value, unit, section into s from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='reading.pages_at_once';
  set role service_role; r := public.svc_worker_settings_v1(); reset role;
  raise exception 'DRYRUN OK %', jsonb_build_object('setting', to_jsonb(s), 'worker_sees', r->'reading.pages_at_once', 'enrich_still', r ? 'enrich.ai_pages_at_once'); end $t$;
