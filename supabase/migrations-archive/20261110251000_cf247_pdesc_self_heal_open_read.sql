-- CF-247 F-PDESC follow-up to 20261110250000 (found by the first live run, 10 Nov 2026 23:2x AEDT): a provider may hold only one open read
-- (index provider_description_reads_open_uq: queued, reading, proposed). The first run of security.provider_description_self_heal_v1 tried to
-- put back a Firecrawl-stopped read of a provider that already had a newer open read; the unique index refused it and the whole run rolled
-- back (nothing was changed). Now:
--   (a) and (b) skip a provider that has an open read, (b) puts back at most one read of a provider, and every item of (a) and (b) runs in
--   its own sub-transaction, so one refused row is counted (outcomes.skipped_error) and never stops the run.
-- Nothing else changes. No setting, job or consumer object (G1, G2, G3). Forward recovery: re-apply the body of 20261110250000 section 3.
-- Replaces: the body of security.provider_description_self_heal_v1 (20261110250000).
-- Retires: nothing.

do $g$
begin
  if to_regprocedure('security.provider_description_self_heal_v1()') is null then raise exception 'apply 20261110250000 first'; end if;
  if md5(pg_get_functiondef('security.provider_description_self_heal_v1()'::regprocedure)) <> '92f92ccd9203521919e9de345c1ab2af' then
    raise exception 'self_heal_v1 is not the 20261110250000 body (%)', md5(pg_get_functiondef('security.provider_description_self_heal_v1()'::regprocedure));
  end if;
end $g$;

create or replace function security.provider_description_self_heal_v1() returns jsonb
language plpgsql security definer set search_path to '' as $fn$
-- CF-247 F-PDESC (20261110250000, 20261110251000): the provider-description reader recovers by itself. Writes only through
-- svc_provider_description_record (a) and the read row's own queue fields (b). One open read a provider (provider_description_reads_open_uq).
declare r record; v_n int := 0; v_q int := 0; v_err int := 0; v_out jsonb; v_tally jsonb := '{}'::jsonb; v_fc_used int; v_fc_ok boolean;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description self heal')) then return jsonb_build_object('skipped', 'in_flight'); end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- (a) answers held only for the model's flag: the stored sentences are recorded again (the read is leased now, exactly as the reader leases it)
  for r in select x.id, x.provider_id from pipeline.provider_description_reads x
            where x.state = 'held' and x.rule = 'not_stated' and x.evidence_id is not null
              and jsonb_array_length(coalesce(x.proposal->'sentences', '[]'::jsonb)) > 0
              and not coalesce(x.checks ? 'self_heal', false)
            order by x.updated_at desc
            limit greatest(0, security.pipeline_num_v1('pdesc.self_heal_per_run', 5)::int) loop
    begin
      if exists (select 1 from pipeline.provider_description_reads o where o.provider_id = r.provider_id and o.state in ('queued', 'reading', 'proposed')) then
        update pipeline.provider_description_reads x set checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('self_heal', jsonb_build_object('at', now(), 'skipped', 'open_read', 'release', '20261110251000'))
         where x.id = r.id;
        v_tally := v_tally || jsonb_build_object('skipped_open_read', coalesce((v_tally->>'skipped_open_read')::int, 0) + 1);
        continue;
      end if;
      update pipeline.provider_description_reads x set state = 'reading', leased_until = now() + interval '5 minutes', -- fixed: one record call
             checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('description_at_lease', (select p.description from catalogue.providers p where p.id = x.provider_id),
                       'identity_snapshot', security.provider_description_identity_snapshot_v1(x.provider_id),
                       'self_heal', jsonb_build_object('at', now(), 'from_rule', 'not_stated', 'release', '20261110251000'))
       where x.id = r.id;
      v_out := public.svc_provider_description_record(jsonb_build_array((select jsonb_build_object('item_id', x.id,
                 'answer', jsonb_build_object('about_page', false, 'sentences', x.proposal->'sentences'),
                 'model', x.model, 'prompt_version', x.prompt_version, 'worker', x.worker) from pipeline.provider_description_reads x where x.id = r.id)));
      v_tally := v_tally || coalesce((select jsonb_object_agg(k, coalesce((v_tally->>k)::int, 0) + coalesce((v_out->>k)::int, 0)) from jsonb_object_keys(coalesce(v_out, '{}'::jsonb)) k), '{}'::jsonb);
      v_n := v_n + 1;
    exception when others then
      v_err := v_err + 1;  -- the sub-transaction is rolled back; the read stays as it was and is offered again next run
    end;
  end loop;
  -- (b) reads that stopped only because the Firecrawl allowance was used up go back in the queue once the window allows Firecrawl again
  select coalesce(sum(x.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads x
   where x.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int);
  v_fc_ok := security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and v_fc_used < security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0);
  if v_fc_ok then
    for r in select distinct on (x.provider_id) x.id, x.provider_id, x.updated_at from pipeline.provider_description_reads x
              where x.state = 'held' and x.reason ilike '%Firecrawl ceiling reached%'
                and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = x.provider_id and o.state in ('queued', 'reading', 'proposed'))
              order by x.provider_id, x.updated_at desc loop
      exit when v_q >= greatest(0, security.pipeline_num_v1('pdesc.self_heal_requeue_per_run', 20)::int);
      begin
        update pipeline.provider_description_reads x set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = null,
               reason = 'put back: the Firecrawl allowance renewed (provider-description-self-heal)', updated_at = now()
         where x.id = r.id and x.state = 'held';
        v_q := v_q + 1;
      exception when others then
        v_err := v_err + 1;
      end;
    end loop;
  end if;
  return jsonb_build_object('rechecked', v_n, 'outcomes', v_tally, 'requeued_firecrawl', v_q, 'skipped_error', v_err, 'firecrawl_used_window', v_fc_used, 'firecrawl_open', v_fc_ok);
end $fn$;
comment on function security.provider_description_self_heal_v1() is 'CF-247 F-PDESC (20261110250000, 20261110251000): job provider-description-self-heal. Re-records held not_stated reads that hold stored sentences through svc_provider_description_record (no AI, no Firecrawl) and requeues reads stopped by the Firecrawl allowance once it renews; one open read a provider; each item isolated.';
revoke all on function security.provider_description_self_heal_v1() from public, anon, authenticated;
