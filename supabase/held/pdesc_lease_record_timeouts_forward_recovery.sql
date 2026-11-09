-- HELD (not a migration): forward recovery for 20261109233000 (provider-description lease and record time-outs). Run only if the Platform Admin decides to go back to the
-- text of the two functions before that migration. It restores them byte for byte (public.svc_provider_description_next body md5 54c8856ec36465059d41d71a5a5d462b, public.svc_provider_description_record
-- body md5 f7c3debc11b67d6de7b2c6d47c8c9b9c), guarded by the md5 of what is live now. After it the lease takes 3.4 to 4.5 s warm again and the 8 second time-outs return.
-- The index evidence_artifacts_source_url_idx is left in place (it is harmless); to drop it too, paste the one commented line at the end (a drop is for the Platform Admin to run).
do $g$
declare v_n text; v_r text;
begin
  select md5(p.prosrc) into v_n from pg_proc p where p.oid = to_regprocedure('public.svc_provider_description_next(integer)');
  select md5(p.prosrc) into v_r from pg_proc p where p.oid = to_regprocedure('public.svc_provider_description_record(jsonb)');
  if v_n is null or v_r is null then raise exception 'the provider-description lease or record function is missing'; end if;
  if v_n not in ('54c8856ec36465059d41d71a5a5d462b', '7583808609dc2dea1d3fc251607405a1') then raise exception 'live public.svc_provider_description_next differs from both texts this recovery knows (body md5 %)', v_n; end if;
  if v_r not in ('f7c3debc11b67d6de7b2c6d47c8c9b9c', '9b2137954bc05501e55e93c8ef9cf448') then raise exception 'live public.svc_provider_description_record differs from both texts this recovery knows (body md5 %)', v_r; end if;
end $g$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric; v_fc_res int; v_fc_left int; v_ws text[]; v_stored jsonb; v_reoffer uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('idle', true, 'reason', 'off', 'items', '[]'::jsonb); end if;
  -- Validation 5 Nov 2026: a worker leases only through public.svc_provider_description_lease_v1 or _cohort_next, which declare the
  -- reservation protocol. A worker from before this release (it calls this function directly and never reserves) gets no item, so it cannot
  -- make an unreserved paid AI call against this database.
  if coalesce(auth.role(), '') = 'service_role' and coalesce(current_setting('cf.pdesc_worker_protocol', true), '') <> 'provider-description-reserve-v1' then
    return jsonb_build_object('idle', true, 'reason', 'worker_protocol_required', 'items', '[]'::jsonb);
  end if;
  -- fixed: serialize reservation of review slots across all reader callers; no waiting behind another worker.
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;
  v_cap := case when v_mach then security.pipeline_num_v1('pdesc.concurrency_max', 12) else security.pipeline_num_v1('pdesc.pending_max', 10) end;
  select (case when v_mach then 0 else (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending') end)
       + (select count(*) from pipeline.provider_description_reads r where r.state='reading' and r.leased_until>=now()) into v_pending;
  if v_pending >= v_cap then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
  select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;
  if nullif(btrim(v_model), '') is null then return jsonb_build_object('idle', true, 'reason', 'no_model', 'items', '[]'::jsonb); end if;
  -- the shared AI rule (credit floor, daily ceiling, lane guard; v2.15.404): nothing new is claimed while AI use is refused
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if;
  -- the pilot's hard ceilings: total AI spend of this lane in the shared ledger, and total Firecrawl reads of this reader
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  if v_mach then
    -- automatic mode: no more reads in progress than the AI spend still available covers, at the dearer of the set cost and the observed cost of a read
    v_afford := floor((security.pipeline_num_v1('pdesc.ai_usd_max', 1) - v_spent - coalesce((select sum(x.reserved_usd) from pipeline.provider_description_reads x where x.state = 'reading'), 0))
                      / greatest(security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003), coalesce((select sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0) from pipeline.provider_description_reads x), 0)))
                - (select count(*) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now());
    if v_afford < 1 then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  end if;
  -- QA N4: Firecrawl reads held by worker calls still in flight are not available again; with automatic admission on, this call is granted at most pdesc.firecrawl_per_call of what the ceiling still allows after them
  v_fc_res := coalesce((select sum(coalesce((x.checks->>'firecrawl_reserved')::int, 0)) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now()), 0);
  v_fc_left := case when v_mach then least(greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used - v_fc_res), security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int)
                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;
  if v_mach then
    -- QA N6/N7/N11: a provider the automatic rule must not describe now (locked, earlier rejection, withdrawn, cleared by hand, open finding, unusable name, already described) is held here, before any AI call
    update pipeline.provider_description_reads r set state='held',rule='machine_declined_'||(b.blk->>'rule'),reason=left(b.blk->>'reason',400),leased_until=null,updated_at=now() -- fixed: the stored reason shows its first 400 characters
      from (select x.id,security.provider_description_machine_blocked_v1(x.provider_id) blk from pipeline.provider_description_reads x where (x.state='queued' and x.next_try_at<=now()) or (x.state='reading' and x.leased_until<now())) b
     where r.id=b.id and b.blk is not null;
  end if;
  -- one pass (9 Nov 2026, lease statement time-out): the stored About copy of each provider with open work is found ONCE here and read from v_stored below; it was found up to three times per queued row.
  -- Only a provider with a copy at an About address can have one (security.pdesc_about_like_patterns_v1 is the first step of security.provider_description_stored_v1), so the others are not asked.
  v_ws := security.pdesc_about_like_patterns_v1();
  select coalesce(jsonb_object_agg(z.pid, to_jsonb(z.sid)), '{}'::jsonb) into v_stored from (
    select x.provider_id::text pid, security.provider_description_stored_v1(x.provider_id) sid
      from (select distinct o.provider_id from pipeline.provider_description_reads o where (o.state='queued' or (o.state='reading' and o.leased_until<now()))
               and exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id=s.id where s.provider_id=o.provider_id and lower(a.source_url) like any (v_ws))
             offset 0) x) z -- offset 0 is an optimisation fence: without it the planner moves the not-null test below the DISTINCT and asks stored_v1 for every open read
   where z.sid is not null;
  -- identity re-offer (9 Nov 2026): a provider whose latest finished read was held on an identity rule (pdesc.identity_reeval_rules) by another reader than the one running now (security.pdesc_reader_behaviour_v1) is not held or skipped on recovery knowledge:
  -- that knowledge recorded the earlier reader's failure. Found once here from the latest finished read of each provider. A failure of any other kind, or of the current reader, keeps its memory.
  v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id) o.provider_id, o.state, o.rule, o.checks from pipeline.provider_description_reads o
                        where o.state not in ('queued', 'reading') order by o.provider_id, o.created_at desc) l
                      where l.state = 'held' and coalesce(security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules'), '[]'::jsonb) ? l.rule
                        and coalesce(l.checks->'identity'->>'reader_behavior_version', '') is distinct from coalesce(security.pdesc_reader_behaviour_v1(), ''));
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
  where r.id in (select x.id from pipeline.provider_description_reads x join pipeline.evidence_artifacts a on a.id=(v_stored->>x.provider_id::text)::uuid
    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',x.provider_id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(x.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)
    order by x.next_try_at,x.id limit security.pipeline_num_v1('batch.provider_description',3)::int);
  with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id),
  pick as (select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   and (r.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>r.provider_id::text)::uuid),v_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and exists(select 1 from catalogue.providers p where p.id=r.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                   and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=r.provider_id)
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))
                 for update skip locked),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('description_at_lease',(select p.description from catalogue.providers p where p.id=r.provider_id),'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id),'firecrawl_reserved',case when v_mach and r.id=(select pk.id from pick pk order by pk.id limit 1) then v_fc_left else 0 end),
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
           'website', p.website, 'country', k.iso_alpha2, 'identity_names',jsonb_build_array(p.canonical_name,p.display_name), 'provider_type',(select t.code from ref.provider_types t where t.id=p.provider_type_id), 'hosts', to_jsonb(security.provider_hosts_v1(u.provider_id)),
           'stored', (select jsonb_build_object('evidence_id', a.id, 'storage_path', a.storage_path, 'url', a.source_url, 'captured_at', coalesce(a.captured_at, a.created_at),'content_hash',coalesce(a.content_hash,a.id::text))
                        from pipeline.evidence_artifacts a where a.id = st.stored_id),
           -- About pages the central page finder suggested (page type about_page, central.ts), on the provider's own hosts, best first
           -- IQ-00055: the page rule once per suggestion (a lateral), for the filter and the order
           'candidates', (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select y.url, y.score, g.pg from (
                              select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                                from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                               where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                                 and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                              cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g
                             where (g.pg->>'ok')::boolean) z))), '[]'::jsonb)
    into v
    -- IQ-00055: the stored copy once per claimed row
    from upd u cross join lateral (select case when nullif(current_setting('cf.pdesc_cohort',true),'') is not null then (select m.evidence_id from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=u.id) else (v_stored->>u.provider_id::text)::uuid end stored_id offset 0) st
         join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return jsonb_build_object('model', v_model,
    'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'firecrawl_left', v_fc_left,
    'page_chars', security.pipeline_num_v1('pdesc.page_chars', 16000)::int,'verbatim_span_max_chars',security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int,
    'min_quote_chars', security.pipeline_num_v1('pdesc.min_quote_chars', 20)::int,
    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb),
    -- pilot 2 Nov 2026 16:16: the page rule's lists, for the home page's links (security.provider_description_page_v1 decides the same way)
    'page_rule', jsonb_build_object('about_prefixes', coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb),
                                    'refused_path_words', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb),
                                    'refused_host_labels', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb),
                                    'about_max_segments', security.pipeline_num_v1('pdesc.about_max_segments', 2)::int),
    -- pilot 2 Nov 2026 16:16 (CDU held at 916 characters): the model is told the limits the validation applies
    'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2)::int, 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5)::int,
                                 'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150)::int, 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int),
    'items', v);
end $body$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
declare x jsonb; r pipeline.provider_description_reads%rowtype; v_ev uuid; v_url text; v_cap timestamptz; v_via text; v_hash text;
        v_chk jsonb; v_item uuid; v_tally jsonb := '{}'::jsonb; v_out text; v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text; v_m jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity')); -- fixed: serialize final Layer 4 capacity check with leases.
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into r from pipeline.provider_description_reads where id = (x->>'item_id')::uuid for update;
    if r.id is null or r.state <> 'reading' then v_tally := v_tally || jsonb_build_object('stale', coalesce((v_tally->>'stale')::int, 0) + 1); continue; end if;
    update pipeline.provider_description_reads set ai_calls=ai_calls+case when coalesce((x->>'ai_call_started')::boolean,false) then 1 else 0 end, checks=coalesce(checks,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known')), reserved_usd=case when coalesce((x->>'cost_known')::boolean,false) or coalesce((x->>'cost')::numeric,0)>0 then 0 else reserved_usd end, cost_usd = cost_usd + greatest(coalesce((x->>'cost')::numeric, 0), 0),
           firecrawl_reads = firecrawl_reads + greatest(coalesce((x->>'fc_reads')::int, 0), 0),
           model = coalesce(nullif(x->>'model', ''), model), prompt_version = coalesce(nullif(x->>'prompt_version', ''), prompt_version),
           worker = coalesce(left(nullif(x->>'worker', ''), 60), worker), updated_at = now()
     where id = r.id;
    v_ev := null; v_url := null; v_cap := null; v_via := null; v_hash := null;
    -- the page: a stored copy, or a page the worker read and stored now (registered as evidence under the provider's coverage-sweep source)
    if (x->>'stored_evidence_id') is not null then
      select a.id, a.source_url, coalesce(a.captured_at, a.created_at), coalesce(a.content_hash, a.id::text) into v_ev, v_url, v_cap, v_hash
        from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
       where a.id = (x->>'stored_evidence_id')::uuid and s.provider_id = r.provider_id;
      v_via := case when v_ev is not null then 'stored' end;
    elsif x->'fetch'->>'status' = 'read' and x->'fetch'->>'storage_path' is not null and x->'fetch'->>'sha256' ~ '^[0-9a-f]{64}$' then
      v_url := x->'fetch'->>'url'; v_hash := x->'fetch'->>'sha256'; v_via := x->'fetch'->>'via'; v_cap := now();
      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = security.coverage_sweep_source(r.provider_id) and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(security.coverage_sweep_source(r.provider_id), v_url, x->'fetch'->>'storage_path', v_hash,
                    coalesce(x->'fetch'->>'mime', 'text/html'),
                    jsonb_build_object('layer', 2, 'kind', 'provider_about_page', 'worker', 'coverage-sweep', 'provider_description_read_id', r.id, 'read_via', v_via));
        end if;
      end if;
    end if;
    update pipeline.provider_description_reads set evidence_id = coalesce(v_ev, evidence_id), source_url = coalesce(v_url, x->'fetch'->>'url', source_url),
           read_via = coalesce(v_via, read_via), content_hash = coalesce(v_hash, content_hash), source_captured_at = coalesce(v_cap, source_captured_at)
     where id = r.id;
    v_err := nullif(x->>'error', '');
    if v_err is not null or coalesce((x->>'retry')::boolean, false) then
      -- a failed read is tried again after pdesc.retry_minutes, at most pdesc.tries times; then the dead letter list
      update pipeline.provider_description_reads set state = case when tries >= v_max then 'dead_letter' else 'queued' end,
             next_try_at = now() + make_interval(mins => security.pipeline_num_v1('pdesc.retry_minutes', 360)::int), leased_until = null,
             rule = case when tries >= v_max then 'dead_letter' else 'retry' end, reason = left(coalesce(v_err, x->>'reason', 'retry'), 400), updated_at = now()
       where id = r.id returning state into v_out;
      v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1); continue;
    end if;
    if x->'answer' is null and x->>'rule' in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and coalesce((select reserved_usd from pipeline.provider_description_reads where id=r.id),0)=0 then
      update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,rule=x->>'rule',reason=left(coalesce(x->>'reason','Waiting for existing AI spending or pricing policy to allow the next read.'),400),updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked_policy',coalesce((v_tally->>'parked_policy')::int,0)+1); continue;
    end if;
    if x->'answer' is null then
      -- no page to read: no About page on the provider's own hosts, robots.txt, another provider's host
      update pipeline.provider_description_reads set state = 'held', leased_until = null, rule = coalesce(nullif(x->>'rule', ''), 'no_about_page'),
             reason = left(coalesce(x->>'reason', 'no About page found on the provider''s own website'), 400), updated_at = now()
       where id = r.id;
      v_tally := v_tally || jsonb_build_object('held', coalesce((v_tally->>'held')::int, 0) + 1); continue;
    end if;
    select * into r from pipeline.provider_description_reads where id = r.id;
    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer');
    if v_chk->>'outcome' = 'propose' and r.evidence_id is null then
      v_chk := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'no_evidence', 'reason', 'the page copy is not stored as evidence', 'checks', v_chk->'checks');
    end if;
    if (select p.description from catalogue.providers p where p.id=r.provider_id) is distinct from r.checks->>'description_at_lease' then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','description_changed_after_lease','reason','The description was edited while this read was in progress; retain the human value.','checks',v_chk->'checks');
    end if;
    if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','identity_changed_after_lease','reason','Provider names, type, country or website changed after source identity was checked.','checks',v_chk->'checks');
    end if;
    if not security.provider_description_scope_v1(r.provider_id) or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all')) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','provider_eligibility_changed','reason','Provider eligibility or manual lock changed after the read was leased.','checks',v_chk->'checks');
    end if;
    if exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and (m.evidence_id is distinct from r.evidence_id or m.snapshot->>'source_hash' is distinct from r.content_hash) and m.evidence_id is not null) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','cohort_evidence_changed','reason','The recorded evidence differs from the immutable cohort source. Preview the changed evidence again.','checks',v_chk->'checks');
    end if;
    if x->'quality_hold' is not null then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',coalesce(x->'quality_hold'->>'rule','worker_quality_hold'),'reason',x->'quality_hold'->>'reason','checks',v_chk->'checks');
    end if;
    if not (security.provider_description_identity_v1(r.provider_id,r.source_url)->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'rule','reason',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'reason','checks',v_chk->'checks');
    end if;
    if v_chk->>'outcome' in ('propose','verified') and not coalesce((x->'identity_check'->>'ok')::boolean,(r.checks->'identity'->>'ok')::boolean,false) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','source_identity_proof_missing','reason','The worker did not provide current source-identity proof; retain this evidence and retry only through the current approved reader.','checks',v_chk->'checks');
    end if;
    v_chk:=v_chk||jsonb_build_object('checks',coalesce(v_chk->'checks','{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known','description_at_lease',r.checks->'description_at_lease','identity_snapshot',r.checks->'identity_snapshot')));
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
      -- machine rule pdesc-machine-v1. A description the TEXT rule refuses waits for a person in Layer 4 while there is room (pdesc.machine_pending_max); any other refusal (a lock, an earlier
      -- rejection, a withdrawal, an open finding ...) or no room: HELD with the whole proposal and the exact reason. Nothing is dropped.
      v_m:=security.provider_description_machine_gate_v1(r.provider_id,v_chk->>'text',jsonb_build_object('tier',r.read_via,'sentences',x->'answer'->'sentences'));
      if not (v_m->>'ok')::boolean and (v_m->>'rule' not like 'machine_text%' or (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.machine_pending_max',200)) then
        update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='machine_declined_'||(v_m->>'rule'),
          reason=left(v_m->>'reason'||case when v_m->>'rule' like 'machine_text%' then ' Held with the full proposal: the places for a person to decide in Layer 4 are taken (pdesc.machine_pending_max).' else '' end,400),last_verified_at=now(),updated_at=now() where id=r.id; -- fixed: the stored reason shows its first 400 characters
        v_tally:=v_tally||jsonb_build_object('machine_declined',coalesce((v_tally->>'machine_declined')::int,0)+1); continue;
      end if;
    end if;
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
      -- Keep the complete validated proposal; scheduler resumes this exact evidence without another AI call.
      update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='review_full',reason='Layer 4 provider-description capacity is full; resume automatically when a slot is free',updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked',coalesce((v_tally->>'parked')::int,0)+1); continue;
    end if;
    if v_chk->>'outcome' = 'propose' then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, 'provider_description', r.evidence_id,
              jsonb_build_object('description', (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = r.provider_id)),
              jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences', 'source_url', r.source_url, 'evidence_id', r.evidence_id,
                                 'captured_at', r.source_captured_at, 'read_id', r.id),
              jsonb_build_object('read_via', r.read_via, 'content_hash', r.content_hash, 'source_url', r.source_url),
              jsonb_build_object('model', r.model, 'prompt_version', r.prompt_version, 'worker', r.worker, 'cost_usd', r.cost_usd, 'checks', v_chk->'checks', 'rule', v_chk->>'rule'),
              'pending', 'Provider description read from the official page: every sentence quotes the page. A person approves or rejects it; nothing is published before.',
              'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28)')
      returning id into v_item;
      update pipeline.provider_description_reads set state = 'proposed', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = null, review_item_id = v_item, last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'proposed';
      if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
        -- admitted here under the machine rule, or left waiting for a person with the reason on the item; a failure never undoes the proposal
        begin
          v_m:=security.provider_description_machine_admit_v1(v_item);
          if (v_m->>'ok')::boolean then v_out:='admitted'; end if;
        exception when others then null;
        end;
      end if;
    elsif v_chk->>'outcome' = 'verified' then
      update pipeline.provider_description_reads set state = 'verified', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = v_chk->>'reason', last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'verified';
    else
      update pipeline.provider_description_reads set state = 'held', leased_until = null, proposal = jsonb_build_object('sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = left(v_chk->>'reason', 400), updated_at = now()
       where id = r.id;
      v_out := 'held';
    end if;
    v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1);
  end loop;
  return v_tally;
end $body$;

-- optional, Platform Admin only:
-- drop index if exists pipeline.evidence_artifacts_source_url_idx;
