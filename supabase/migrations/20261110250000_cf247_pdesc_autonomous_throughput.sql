-- CF-247 F-PDESC (Platform Admin direction 10 Nov 2026 22:57, 23:02 and 23:04 AEDT): provider descriptions admitted faster, Firecrawl used as
-- needed, and the platform recovers these cases by itself in future.
--
-- Finding (live, 10 Nov 2026 22:50 AEDT): since worker v0.60.0 (#985) the pinned model often answers about_page = false while it still gives
-- quote-backed sentences. security.provider_description_validate_v1 held the whole answer as not_stated on that flag alone, before any
-- sentence rule ran: 146 of 186 AI reads of worker v0.63.0 (5-10 % before v0.60.0). Replayed through the validator with the flag ignored,
-- 6 of 6 recent holds passed every sentence rule (PSC Creative College, Medicus College, SCIC, Eastern College Australia, JTI, C3 College).
-- Second finding: pdesc.firecrawl_reads_max was a LIFETIME count (20 of 20 used), so every About page a site refused to a direct read has been
-- held for good ("Firecrawl ceiling reached", 86 reads) and nothing ever offered it again. Third: pdesc.dispatch_max 1 kept the reader to one
-- worker call of 10 providers a fire (60 reads an hour) although the fire sends up to dispatch_max calls.
--
-- What this does:
--   1 security.provider_description_validate_v1: only "no sentences" is not_stated. A false about_page flag is recorded (checks.about_page_flag)
--     and the sentences are judged by every existing rule (quote on page, marketing, claims, evidence claims, fragments, numbers, verbatim,
--     historic context, support, count, length, age, duplicate). The identity proof, the own-host and About-page rules, the machine gate,
--     the manual locks and Layer 4 are unchanged. Nothing else in the function changes (md5-guarded replace of one block).
--   2 public.svc_provider_description_next: the Firecrawl allowance counts the reads of the last pdesc.firecrawl_window_hours (new setting,
--     24) instead of every read ever made, so pdesc.firecrawl_reads_max is an allowance a window that renews by itself. The shared Firecrawl
--     daily budget and credit reserve (svc_fc_spend, useFcWhy) still refuse a read the account cannot afford. Nothing else changes.
--   3 security.provider_description_self_heal_v1 (new) and job provider-description-self-heal (every 10 minutes, between the reader's fires):
--     a re-records, through the unchanged svc_provider_description_record, a held not_stated read that holds stored sentences (no AI call,
--        no Firecrawl): the read is leased as the reader leases it (description_at_lease and identity snapshot taken now), so every record
--        guard applies (evidence, identity, lock, scope, machine gate, upgrade rule). At most pdesc.self_heal_per_run a run; each read once.
--     b puts back in the queue a held read that only stopped because the Firecrawl allowance was used up, when the window allows Firecrawl
--        again. At most pdesc.self_heal_requeue_per_run a run.
--   4 Settings, Platform Admin direction 10 Nov 2026 23:02 ("use Firecrawl as much as needed", "fasten up the process"), each with its reason:
--     pdesc.firecrawl_reads_max 20 -> 300 (now a 24-hour allowance; about US$0.30 a day at the configured US$1 per 1,000 credits);
--     pdesc.firecrawl_per_call 5 -> 10; pdesc.dispatch_max 1 -> 3; pdesc.concurrency_max 12 -> 30. pdesc.ai_usd_max is NOT changed (a person decides).
-- Consumer API (G3): not touched. No description is written by applying this migration (the job does that afterwards through the existing
-- record and admission functions). Nothing is deleted.
-- Forward recovery: supabase/held/pdesc_autonomous_throughput_forward_recovery.sql (inverse replacements, md5-guarded; job unscheduled; settings back).
-- Replaces: the not_stated veto block of validate_v1; the lifetime Firecrawl count of svc_provider_description_next.
-- Retires: nothing.

do $g$
begin
  if md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) <> '35d6d53240c1da35ecc6d28f31ccd1df' then
    raise exception 'validate_v1 is not the reviewed body (%)', md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure));
  end if;
  if md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) <> 'b87f37cc18947a976c432f07f65b1fc4' then
    raise exception 'svc_provider_description_next is not the reviewed body (%)', md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure));
  end if;
  if md5(pg_get_functiondef('public.svc_provider_description_record(jsonb)'::regprocedure)) <> '9ac9af4fcf2cb5e31d9cb185179dfc6a' then
    raise exception 'svc_provider_description_record is not the reviewed body';
  end if;
end $g$;

-- 1 -------------------------------------------------------------------------------------------------------------- validate: the flag is recorded, not a veto
do $v$
declare d text := pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure);
        o text := $o$  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;$o$;
        n text := $n$  if v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  -- CF-247 F-PDESC (20261110250000): the model's about_page flag no longer vetoes sentences; it is recorded and every sentence rule below decides
  if coalesce((p_result->>'about_page')::boolean, false) is false then v_checks := v_checks || jsonb_build_object('about_page_flag', false); end if;$n$;
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'validate_v1: the not_stated block is not found exactly once'; end if;
  execute replace(d, o, n);
end $v$;

-- 2 -------------------------------------------------------------------------------------------------------------- the Firecrawl allowance renews each window
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason, control_class) values
 ('pipeline', 'pdesc.firecrawl_window_hours', 'Provider descriptions: Firecrawl allowance window',
  'The Firecrawl allowance (Provider descriptions: Firecrawl reads) counts the reads of this many past hours, so it renews by itself. The shared Firecrawl daily budget and credit reserve still apply.',
  'number', '24'::jsonb, 1, 720, 'hours', 1031, 'Provider descriptions', 'public.svc_provider_description_next; security.provider_description_self_heal_v1',
  'CF-247 F-PDESC (Platform Admin 10 Nov 2026 23:02): the allowance was a lifetime count and stopped Firecrawl for good after 20 reads', 'human'),
 ('pipeline', 'pdesc.self_heal_per_run', 'Provider descriptions: held answers re-checked a run',
  'Each run of job provider-description-self-heal re-records at most this many reads held as not_stated that still hold their stored sentences, through the normal record and admission checks. No AI call, no Firecrawl.',
  'number', '5'::jsonb, 0, 50, 'reads', 1032, 'Provider descriptions', 'security.provider_description_self_heal_v1',
  'CF-247 F-PDESC (Platform Admin 10 Nov 2026 23:04): recover by itself', 'automatic'),
 ('pipeline', 'pdesc.self_heal_requeue_per_run', 'Provider descriptions: Firecrawl-stopped reads put back a run',
  'Each run of job provider-description-self-heal puts back in the queue at most this many reads that stopped only because the Firecrawl allowance was used up, when the window allows Firecrawl again.',
  'number', '20'::jsonb, 0, 200, 'reads', 1033, 'Provider descriptions', 'security.provider_description_self_heal_v1',
  'CF-247 F-PDESC (Platform Admin 10 Nov 2026 23:04): recover by itself', 'automatic')
on conflict (toolset_key, key) do nothing;

do $f$
declare d text := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
        o text := $o$  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r;$o$;
        n text := $n$  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r
   where r.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int); -- 20261110250000: an allowance a window, not a lifetime count$n$;
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'next: the Firecrawl count is not found exactly once'; end if;
  execute replace(d, o, n);
end $f$;

update pipeline.platform_toolset_settings set help = 'Firecrawl page reads the description reader may make in the allowance window (Provider descriptions: Firecrawl allowance window), for home and About pages a site refused to a direct read. 0: none. Each read also passes the shared Firecrawl budget.'
 where toolset_key = 'pipeline' and key = 'pdesc.firecrawl_reads_max';

-- 3 -------------------------------------------------------------------------------------------------------------- self-heal
create or replace function security.provider_description_self_heal_v1() returns jsonb
language plpgsql security definer set search_path to '' as $fn$
-- CF-247 F-PDESC (20261110250000): the provider-description reader recovers by itself. Writes only through svc_provider_description_record
-- (a) and the read row's own queue fields (b).
declare r record; v_n int := 0; v_q int := 0; v_out jsonb; v_tally jsonb := '{}'::jsonb; v_fc_used int; v_fc_ok boolean;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description self heal')) then return jsonb_build_object('skipped', 'in_flight'); end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- (a) answers held only for the model's flag: the stored sentences are recorded again (the read is leased now, exactly as the reader leases it)
  for r in select x.id from pipeline.provider_description_reads x
            where x.state = 'held' and x.rule = 'not_stated' and x.evidence_id is not null
              and jsonb_array_length(coalesce(x.proposal->'sentences', '[]'::jsonb)) > 0
              and not coalesce(x.checks ? 'self_heal', false)
            order by x.updated_at desc
            limit greatest(0, security.pipeline_num_v1('pdesc.self_heal_per_run', 5)::int) loop
    update pipeline.provider_description_reads x set state = 'reading', leased_until = now() + interval '5 minutes', -- fixed: one record call
           checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('description_at_lease', (select p.description from catalogue.providers p where p.id = x.provider_id),
                     'identity_snapshot', security.provider_description_identity_snapshot_v1(x.provider_id),
                     'self_heal', jsonb_build_object('at', now(), 'from_rule', 'not_stated', 'release', '20261110250000'))
     where x.id = r.id;
    v_out := public.svc_provider_description_record(jsonb_build_array((select jsonb_build_object('item_id', x.id,
               'answer', jsonb_build_object('about_page', false, 'sentences', x.proposal->'sentences'),
               'model', x.model, 'prompt_version', x.prompt_version, 'worker', x.worker) from pipeline.provider_description_reads x where x.id = r.id)));
    v_tally := v_tally || coalesce((select jsonb_object_agg(k, coalesce((v_tally->>k)::int, 0) + coalesce((v_out->>k)::int, 0)) from jsonb_object_keys(coalesce(v_out, '{}'::jsonb)) k), '{}'::jsonb);
    v_n := v_n + 1;
  end loop;
  -- (b) reads that stopped only because the Firecrawl allowance was used up go back in the queue once the window allows Firecrawl again
  select coalesce(sum(x.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads x
   where x.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int);
  v_fc_ok := security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and v_fc_used < security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0);
  if v_fc_ok then
    with q as (select x.id from pipeline.provider_description_reads x
                where x.state = 'held' and x.reason ilike '%Firecrawl ceiling reached%'
                order by x.updated_at
                limit greatest(0, security.pipeline_num_v1('pdesc.self_heal_requeue_per_run', 20)::int))
    update pipeline.provider_description_reads x set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = null,
           reason = 'put back: the Firecrawl allowance renewed (provider-description-self-heal)', updated_at = now()
      from q where x.id = q.id;
    get diagnostics v_q = row_count;
  end if;
  return jsonb_build_object('rechecked', v_n, 'outcomes', v_tally, 'requeued_firecrawl', v_q, 'firecrawl_used_window', v_fc_used, 'firecrawl_open', v_fc_ok);
end $fn$;
comment on function security.provider_description_self_heal_v1() is 'CF-247 F-PDESC (20261110250000): job provider-description-self-heal. Re-records held not_stated reads that hold stored sentences through svc_provider_description_record (no AI, no Firecrawl) and requeues reads stopped by the Firecrawl allowance once it renews.';
revoke all on function security.provider_description_self_heal_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('provider-description-self-heal', 'Layer 2 reading', 64, 'Provider descriptions: recover held answers and Firecrawl-stopped reads',
  'Every 10 minutes, between the reader''s fires: records again, through the normal checks, answers held only because the model said the page does not describe the institution while giving quote-backed sentences (Pipeline settings > Provider descriptions > held answers re-checked a run; no AI, no Firecrawl), and puts back in the queue reads that stopped only because the Firecrawl allowance was used up, once it renews.',
  5, false, null)
on conflict (jobname) do nothing;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'provider-description-self-heal', 'Layer 2', 'Provider descriptions', 'F-PDESC: recovers held answers and Firecrawl-stopped reads by itself', 'active', '{}', '20261110250000'),
 ('function', 'security.provider_description_self_heal_v1', 'Layer 2', 'Provider descriptions', 'F-PDESC: the writer behind job provider-description-self-heal', 'active', '{}', '20261110250000')
on conflict do nothing;

do $sched$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('provider-description-self-heal', '1,11,21,31,41,51 * * * *', 'select security.provider_description_self_heal_v1()');
  end if;
end $sched$;

-- 4 -------------------------------------------------------------------------------------------------------------- settings (Platform Admin direction, with reasons)
update pipeline.platform_toolset_settings set value = '300'::jsonb, updated_at = now(),
       reason = 'Platform Admin direction 10 Nov 2026 23:02 AEDT: use Firecrawl as much as needed; now a 24-hour allowance (20261110250000)'
 where toolset_key = 'pipeline' and key = 'pdesc.firecrawl_reads_max';
update pipeline.platform_toolset_settings set value = '10'::jsonb, updated_at = now(),
       reason = 'Platform Admin direction 10 Nov 2026 23:02 AEDT: Firecrawl as needed for each worker call (20261110250000)'
 where toolset_key = 'pipeline' and key = 'pdesc.firecrawl_per_call';
update pipeline.platform_toolset_settings set value = '3'::jsonb, updated_at = now(),
       reason = 'Platform Admin direction 10 Nov 2026 23:02 AEDT: fasten up; up to three worker calls a fire (the function default) (20261110250000)'
 where toolset_key = 'pipeline' and key = 'pdesc.dispatch_max';
update pipeline.platform_toolset_settings set value = '30'::jsonb, updated_at = now(),
       reason = 'Platform Admin direction 10 Nov 2026 23:02 AEDT: fasten up; room for three calls of 10 reads (20261110250000)'
 where toolset_key = 'pipeline' and key = 'pdesc.concurrency_max';

-- 5 -------------------------------------------------------------------------------------------------------------- post-check
do $post$
begin
  if position('about_page_flag' in pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: validate_v1 not changed'; end if;
  if position('pdesc.firecrawl_window_hours' in pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) = 0 then raise exception 'post-check: next not changed'; end if;
  if to_regnamespace('cron') is not null and not exists (select 1 from cron.job where jobname = 'provider-description-self-heal' and active) then raise exception 'post-check: job not scheduled'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.ai_usd_max') is distinct from '0.75'::jsonb then raise exception 'post-check: ai_usd_max must not change here'; end if;
end $post$;
