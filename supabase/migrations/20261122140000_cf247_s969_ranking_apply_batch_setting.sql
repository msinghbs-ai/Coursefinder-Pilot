-- CF-247 s969 (session S1-API-Frontend-Delivery, third fix to s966, 22 Nov 2026 12:40 AEDT; IR-005 / RM1J).
-- THE 2027 is live (the s967 re-run published 3,146 rows at 00:49 UTC). The s968 re-run read the same edition again: every row was then an
-- update, and a batch of 200 rows passed the service role's 8 s statement limit. A batch that commits before a later one fails also set the
-- edition's access back to licensed_upload. This change:
--   1. Pipeline setting reading.ranking_apply_batch_rows (50 rows a call): ranking-layer1-etl v1.8.2 reads it through svc_worker_settings_v1
--      (reading.* keys) instead of its fixed 200.
--   2. svc_ranking_ingest_apply keeps an edition's access 'public' on a re-read (an uploaded file still sets licensed_upload).
--   3. The waiting s968 THE re-run (no worker holds it) is replaced by a fresh one after the edge function deploy, to prove the re-read.
-- Live on deploy. $0. G1: no job. G2: the batch size is a setting. G3 checked before and after; locks and cron unchanged.
-- Parity: live head 20261122130000 read 22 Nov 2026 12:35 AEDT; this file is numbered strictly above it.
-- Replaces: the fixed apply batch of 200 rows in ranking-layer1-etl; the s968 THE re-run. Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s969_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s969_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'reading.ranking_apply_batch_rows', 'Ranking rows applied a call',
        'THE and QS public ranking readers: rows sent to the database in one apply call. Each call must finish inside the 8 s statement limit, also when an edition is read again (every row an update).',
        'number', '50'::jsonb, 10, 500, 'rows a call', 900, 'Job sizes', 'ranking-layer1-etl (THE and QS Layer 1 readers)', 'CF-247 s969: was a fixed 200 in the worker')
on conflict do nothing;

-- regex edits of the live definition, guarded by its md5 before; each edit must apply exactly once
create or replace function pg_temp.edit_re(p_sig text, p_before text, p_after text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_new text;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g')) <> 1 then
      raise exception '%: edit % must apply exactly once (found %)', p_sig, i, (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g'));
    end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', '2cca41270f90cca1fc9e2b9286f984b4', null, array[
  array[$o$access_status='licensed_upload',status=case$o$, $n$access_status=case when editions.access_status='public' then 'public' else 'licensed_upload' end,status=case$n$]]);

update pipeline.layer1_run_queue set status = 'cancelled', current_stage = 'cancelled', completed_at = now(), heartbeat_at = now(), updated_at = now(),
       error_text = 'Replaced by the s969 re-run (the apply batch size is now a setting)'
 where idempotency_key = 's968-rerun:eb8cb79d-dc73-41a2-ad28-e46c08eba860' and status in ('queued', 'running') and (lease_until is null or lease_until < now());

insert into pipeline.layer1_run_queue (source_id, country_code, mode, status, idempotency_key, requested_by, expected_count, resume_cursor, processed_count,
  source_hash, warning_acknowledged, current_stage, heartbeat_at, result)
select s.id, 'GLOBAL', 'apply', 'queued', 's969-reread:' || s.id::text, 'c0ffee00-0000-4000-8000-000000000150', null, 0, 0, null, false, 'queued',
       now() + interval '7 minutes',  -- fixed: fire guard, so the run starts after the edge function deploy that follows this migration
       jsonb_build_object('start_cursor', 0, 'requested_reason', 's969: THE 2027 read again with the apply batch size from the setting (ranking-layer1-etl v1.8.2)')
  from pipeline.sources s
 where s.id = 'eb8cb79d-dc73-41a2-ad28-e46c08eba860'
   and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = s.id and q.status in ('queued', 'running'))
on conflict (idempotency_key) do nothing;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reading.ranking_apply_batch_rows') then raise exception 'post-check: the setting is missing'; end if;
  if not (public.svc_worker_settings_v1() ? 'reading.ranking_apply_batch_rows') then raise exception 'post-check: the worker settings do not return the batch size'; end if;
  if position('when editions.access_status=''public'' then ''public''' in pg_get_functiondef('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: a re-read would drop public access'; end if;
  if (select count(*) from cron.job where active) <> (select n from s969_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s969_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
