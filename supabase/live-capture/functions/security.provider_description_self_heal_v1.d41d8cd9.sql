CREATE OR REPLACE FUNCTION security.provider_description_self_heal_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 F-PDESC (20261110250000, 20261110251000, 20261112010000): the provider-description reader recovers by itself. Writes only through
-- svc_provider_description_record (a) and the read row's own queue fields (b, c). One open read a provider (provider_description_reads_open_uq).
declare r record; v_n int := 0; v_q int := 0; v_p int := 0; v_err int := 0; v_out jsonb; v_tally jsonb := '{}'::jsonb; v_fc_used int; v_fc_ok boolean;
        v_pv text := security.provider_description_prompt_active_v1()->>'version'; v_max int := greatest(0, security.pipeline_num_v1('pdesc.self_heal_requeue_per_run', 20)::int);
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
        update pipeline.provider_description_reads x set checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('self_heal', jsonb_build_object('at', now(), 'skipped', 'open_read', 'release', '20261112010000'))
         where x.id = r.id;
        v_tally := v_tally || jsonb_build_object('skipped_open_read', coalesce((v_tally->>'skipped_open_read')::int, 0) + 1);
        continue;
      end if;
      update pipeline.provider_description_reads x set state = 'reading', leased_until = now() + interval '5 minutes', -- fixed: one record call
             checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('description_at_lease', (select p.description from catalogue.providers p where p.id = x.provider_id),
                       'identity_snapshot', security.provider_description_identity_snapshot_v1(x.provider_id),
                       'self_heal', jsonb_build_object('at', now(), 'from_rule', 'not_stated', 'release', '20261112010000'))
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
      exit when v_q >= v_max;
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
  -- (c) 20261112010000: the latest read of a provider still without a description, held on an AI-answer check under an older prompt version, is read
  -- again once with the active prompt (the recovery memory counts the prompt version, so the same failure is never asked twice)
  if v_pv is not null then
    for r in select l.id from (select distinct on (x.provider_id) x.id, x.provider_id, x.state, x.rule, x.prompt_version, x.updated_at
                                 from pipeline.provider_description_reads x order by x.provider_id, x.created_at desc) l
              join catalogue.providers p on p.id = l.provider_id
             where l.state = 'held' and coalesce(l.prompt_version, '') is distinct from v_pv
               and coalesce(security.toolset_setting('pipeline', 'pdesc.prompt_reoffer_rules'), '[]'::jsonb) ? l.rule
               and (nullif(btrim(p.description), '') is null or security.provider_description_basic_profile_v1(p.id) is not null)
               and not exists (select 1 from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p.id and k.field in ('description', 'p_description', 'all'))
               and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = l.provider_id and o.state in ('queued', 'reading', 'proposed'))
             order by l.updated_at desc loop
      exit when v_p >= v_max;
      begin
        update pipeline.provider_description_reads x set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = null,
               reason = 'put back: a new provider-description prompt (' || v_pv || ')', updated_at = now()
         where x.id = r.id and x.state = 'held';
        v_p := v_p + 1;
      exception when others then
        v_err := v_err + 1;
      end;
    end loop;
  end if;
  return jsonb_build_object('rechecked', v_n, 'outcomes', v_tally, 'requeued_firecrawl', v_q, 'requeued_prompt', v_p, 'skipped_error', v_err, 'firecrawl_used_window', v_fc_used, 'firecrawl_open', v_fc_ok, 'prompt_version', v_pv);
end $function$
