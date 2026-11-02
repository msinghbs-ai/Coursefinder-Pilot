-- Before the migration, on the live definitions: the cross-check's findings (the edit must find the same), and the defect of plan cancel.
\set ON_ERROR_STOP 1
insert into ref.study_levels values ('00000000-0000-0000-0000-0000000000b1', 'Bachelor'), ('00000000-0000-0000-0000-0000000000b2', 'Master');
insert into catalogue.courses(id, provider_id, canonical_title, duration_value, duration_unit, study_level_id, delivery_mode) values
  ('00000000-0000-0000-0000-0000000000a9', '00000000-0000-0000-0000-0000000000d1', 'X', 3, 'years', '00000000-0000-0000-0000-0000000000b2', 'online'),
  ('00000000-0000-0000-0000-0000000000a8', '00000000-0000-0000-0000-0000000000d1', 'Y', 4, 'years', null, null);
insert into pipeline.uni_adapter_results values ('00000000-0000-0000-0000-0000000000a9', '{"extra":{"duration":"4 years","study_level":"Bachelor","mode":"On campus"}}', now()),
  ('00000000-0000-0000-0000-0000000000a8', '{"extra":{"duration":"4 years"}}', now());
create table security.fx_before (what text, val text);
select security.field_crosscheck_v1() \g /dev/null
insert into security.fx_before select 'crosscheck', string_agg(field || '=' || page_value::text, ';' order by field) from pipeline.field_crosscheck_findings;
do $$ begin raise notice 'before: live cross-check findings %', (select val from security.fx_before); end $$;
-- the live cancel: the run is cancelled, its task is not
insert into security.fx_ranks values ('00000000-0000-0000-0000-0000000000f4', 4);
insert into pipeline.admin_jobs(id, kind, state, requested_by) values ('00000000-0000-0000-0000-0000000000f9', 'provider_fill', 'queued', '00000000-0000-0000-0000-0000000000f4');
insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, reason, steps) values ('00000000-0000-0000-0000-0000000000f8', gen_random_uuid(), 'manual', 'running', 'r',
  '[{"step":"site","status":"running","ref":{"kind":"job","id":"00000000-0000-0000-0000-0000000000f9"}}]');
select set_config('fx.uid', '00000000-0000-0000-0000-0000000000f4', false) \g /dev/null
do $$ begin
  perform public.admin_enrich_plan('cancel', '{"run_id":"00000000-0000-0000-0000-0000000000f8"}');
  if (select state from pipeline.admin_jobs where id = '00000000-0000-0000-0000-0000000000f9') <> 'queued' then raise exception 'before: expected the defect (task left running)'; end if;
  raise notice 'before (defect reproduced): the live cancel leaves the run''s task %', (select state from pipeline.admin_jobs where id = '00000000-0000-0000-0000-0000000000f9');
end $$;
-- clean the fixture rows (a throwaway database)
truncate pipeline.field_crosscheck_findings, pipeline.admin_jobs, pipeline.enrich_plan_runs, security.fx_ranks, pipeline.admin_control_events;
select set_config('fx.uid', '', false) \g /dev/null
