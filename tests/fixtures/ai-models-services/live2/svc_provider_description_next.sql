CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric; v_od boolean; v_over boolean := false; v_pv text := security.provider_description_prompt_active_v1()->>'version'; /* 20261112010000: on demand, over a lane limit, the active prompt version */ v_fc_res int; v_fc_left int; v_ws text[]; v_stored jsonb; v_reoffer uuid[]; v_tries numeric := security.pipeline_num_v1('pdesc.tries', 3); v_acq boolean := security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1; -- the two settings the pick tests on every due read, read once
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
  if not security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end) then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if; /* 20261112010000 */
  -- the pilot's hard ceilings: total AI spend of this lane in the shared ledger, and total Firecrawl reads of this reader
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r
   where r.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int); -- 20261110250000: an allowance a window, not a lifetime count
  -- 20261112010000: a read an operator asked for (checks.on_demand) is not held by the lane limits; while one is due, this call takes on-demand reads only
  v_od := security.pdesc_on_demand_due_v1();
  if v_od then v_over := true; end if;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  if v_mach then
    -- automatic mode: no more reads in progress than the AI spend still available covers, at the dearer of the set cost and the observed cost of a read
    v_afford := floor((security.pipeline_num_v1('pdesc.ai_usd_max', 1) - v_spent - coalesce((select sum(x.reserved_usd) from pipeline.provider_description_reads x where x.state = 'reading'), 0))
                      / greatest(security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003), coalesce((select sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0) from pipeline.provider_description_reads x), 0)))
                - (select count(*) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now());
    if v_afford < 1 and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
    if v_od then v_afford := null; end if;
  end if;
  -- QA N4: Firecrawl reads held by worker calls still in flight are not available again; with automatic admission on, this call is granted at most pdesc.firecrawl_per_call of what the ceiling still allows after them
  v_fc_res := coalesce((select sum(coalesce((x.checks->>'firecrawl_reserved')::int, 0)) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now()), 0);
  v_fc_left := case when v_mach then least(greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used - v_fc_res), security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int)
                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;
  if v_od then v_fc_left := security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int; end if; -- 20261112010000: on demand, the per-call share only (spent as purpose provider_description_on_demand)
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
  -- identity hold (10 Nov 2026): due queued reads are tested for the provider identity, the ones tested longest ago first (each tested read is marked checks.identity_checked_at, so the same oldest reads are not tested on every call). The stored About copy is read from v_stored (found once, above).
  -- Only wrong_host (a provider with no website gives this too) and provider_host_conflict hold the read, with the identity rule and reason and the mark checks.identity_hold: the selection offers such a read again as soon as the provider passes (website or host corrected).
  -- Any other outcome (provider_inactive, a lifecycle hold, an open identity finding) leaves the read queued as before. wrong_host is taken by the register-fact tier; provider_host_conflict waits for a person. Not for a Run Now cohort (the job guard holds those).
  if v_mach and nullif(current_setting('cf.pdesc_cohort',true),'') is null and security.pipeline_num_v1('batch.provider_description', 3) >= 1 then
    update pipeline.provider_description_reads r set state=case when h.hold then 'held' else r.state end, rule=case when h.hold then h.idr else r.rule end, reason=case when h.hold then left(h.why,400) else r.reason end, -- fixed: the stored reason shows its first 400 characters
           leased_until=case when h.hold then null else r.leased_until end, updated_at=case when h.hold then now() else r.updated_at end,
           checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('identity_checked_at',now())||case when h.hold then jsonb_build_object('identity_hold',true) else '{}'::jsonb end
      from (select o.id, i.v->>'rule' idr, i.v->>'reason' why, (not coalesce((i.v->>'ok')::boolean,false) and i.v->>'rule' in ('wrong_host','provider_host_conflict')) hold
              from (select x.id, x.provider_id, pp.website from pipeline.provider_description_reads x join catalogue.providers pp on pp.id=x.provider_id and pp.lifecycle_status='active' and pp.publication_status='published'
                     where x.state='queued' and x.next_try_at<=now() order by (x.checks->>'identity_checked_at') nulls first, x.next_try_at, x.id limit security.pipeline_num_v1('batch.provider_description', 3)::int) o
              cross join lateral (select security.provider_description_identity_v1(o.provider_id, coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>o.provider_id::text)::uuid), o.website)) v offset 0) i) h
     where r.id=h.id and r.state='queued';
  end if;
  -- identity re-offer (9 Nov 2026): a provider whose latest finished read was held on an identity rule (pdesc.identity_reeval_rules) by another reader than the one running now (security.pdesc_reader_behaviour_v1) is not held or skipped on recovery knowledge:
  -- that knowledge recorded the earlier reader's failure. Found once here from the latest finished read of each provider. A failure of any other kind, or of the current reader, keeps its memory.
  v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id) o.provider_id, o.state, o.rule, o.checks from pipeline.provider_description_reads o
                        where o.state not in ('queued', 'reading') order by o.provider_id, o.created_at desc) l
                      where l.state = 'held' and coalesce(security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules'), '[]'::jsonb) ? l.rule
                        and coalesce(l.checks->'identity'->>'reader_behavior_version', '') is distinct from coalesce(security.pdesc_reader_behaviour_v1(), ''));
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
  where r.id in (select x.id from pipeline.provider_description_reads x join pipeline.evidence_artifacts a on a.id=(v_stored->>x.provider_id::text)::uuid
    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not security.pdesc_on_demand_live_v1(x.checks) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',x.provider_id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(v_pv,x.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)
    order by x.next_try_at,x.id limit security.pipeline_num_v1('batch.provider_description',3)::int);
  with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id),
  pick as (select l.id from (
             -- lazy pick (9 Nov 2026, lease and record time-outs): the cheap tests and the order are worked out for every due read (inner query), then the dear per-provider tests
             -- (scope, recovery memory, identity, hidden) run only on the reads taken in that order until the limit is reached. The same reads in the same order as before; the whole queue is no longer tested on every call.
             select c.id from (
               select r.id, r.provider_id, r.prompt_version, r.checks from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < v_tries
                   and (not v_over or security.pdesc_on_demand_live_v1(r.checks))
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))) or (v_mach and security.provider_description_basic_profile_v1(r.provider_id) is not null))
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when v_acq then true else (v_stored->>r.provider_id::text) is not null end
                 order by security.pdesc_on_demand_live_v1(r.checks) desc, case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 offset 0) c -- offset 0 is an optimisation fence: the dear tests below are not moved under the sort, so they stop with the limit
              where security.provider_description_scope_v1(c.provider_id)
                and (c.provider_id = any(v_reoffer) or security.pdesc_on_demand_live_v1(c.checks) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',c.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(v_pv,c.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=c.provider_id)) o
           -- the row lock, as before: skip a read another call holds; the due test is repeated on the locked row, as the lock of the old single query re-tested it
           cross join lateral (select q.id from pipeline.provider_description_reads q where q.id = o.id
                                  and ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'reading' and q.leased_until < now()))
                                  and q.tries < v_tries
                                for update skip locked) l
           limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, prompt_version = coalesce(v_pv, r.prompt_version), checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('description_at_lease',(select p.description from catalogue.providers p where p.id=r.provider_id),'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id),'firecrawl_reserved',case when v_mach and r.id=(select pk.id from pick pk order by pk.id limit 1) then v_fc_left else 0 end),
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'on_demand', security.pdesc_on_demand_live_v1(u.checks), 'provider', coalesce(p.display_name, p.canonical_name),
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
  return jsonb_build_object('model', v_model, 'prompt', security.provider_description_prompt_active_v1(),
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
end $function$
