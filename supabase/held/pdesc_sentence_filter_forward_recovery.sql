-- HELD (not a migration): forward recovery for 20261110120000 (provider-description sentence filter: a sentence that fails a sentence rule is left out and the others are kept). Run only if the Platform Admin decides to go back to the earlier all-or-nothing sentence test.
-- It puts back the text of the two functions before that migration, byte for byte (security.provider_description_validate_v1 body md5 c1d56ef145b0673d3c475fdaa677ae1d, public.svc_provider_description_record body md5 9b2137954bc05501e55e93c8ef9cf448),
-- guarded by the md5 of what is live now: it stops, and changes nothing, if either live body is neither its earlier text nor the one the migration wrote (7347f51b70a0c4a6cdd01a117080aad5 and 5dab0348f912018e517671aef376c5b6). It also takes the nine sentence rules out of pdesc.identity_reeval_rules and puts back
-- the label, help and reason that setting had (20261109185000). Reads already recorded, the Layer 4 items and the stored proposals are never touched (a proposal made with dropped sentences keeps its kept sentences; each still passed every sentence rule).
-- After it a failing sentence holds the whole answer again, and the worker (v0.60.0) still asks only for short paraphrases. The migration applies again after it.
do $g$
declare v_v text; v_r text;
begin
  select md5(p.prosrc) into v_v from pg_proc p where p.oid = to_regprocedure('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)');
  select md5(p.prosrc) into v_r from pg_proc p where p.oid = to_regprocedure('public.svc_provider_description_record(jsonb)');
  if v_v is null or v_r is null then raise exception 'the provider-description validator or recorder is missing'; end if;
  if v_v not in ('c1d56ef145b0673d3c475fdaa677ae1d', '7347f51b70a0c4a6cdd01a117080aad5') then raise exception 'live security.provider_description_validate_v1 differs from both texts this recovery knows (body md5 %)', v_v; end if;
  if v_r not in ('9b2137954bc05501e55e93c8ef9cf448', '5dab0348f912018e517671aef376c5b6') then raise exception 'live public.svc_provider_description_record differs from both texts this recovery knows (body md5 %)', v_r; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_validate_v1(p_provider uuid, p_url text, p_captured_at timestamp with time zone, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_current text; v_other record; v_checks jsonb := '{}'::jsonb; v_claim text;
begin
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('host', v_host, 'sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if v_host <> 'own' then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', 'wrong_host', 'checks', v_checks,
      'reason', case v_host when 'other_provider' then 'the page is on another provider''s website' when 'no_url' then 'no page address' else 'the page is not on the provider''s own website' end);
  end if;
  -- pilot 2 Nov 2026 16:16: only the provider's own About or Overview page is a description source
  if not (security.provider_description_page_v1(p_provider, p_url)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', security.provider_description_page_v1(p_provider, p_url)->>'rule', 'checks', v_checks,
      'reason', 'the page is not the provider''s own About or Overview page');
  end if;
  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  if v_n < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_n > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- Platform Admin 5 Nov 2026 20:03 §2: campus, scholarship and guarantee statements are checked against their official quote, never held by keyword alone
    select r into v_claim from (select security.pdesc_claim_check_v1(t, s->>'quote', w) r from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb)) w) z where r is not null limit 1;
    if v_claim is not null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', v_claim, 'checks', v_checks, 'reason', case v_claim when 'claim_negated_in_source' then 'the official quote negates a campus, scholarship or guarantee statement that the sentence makes: ' else 'a campus, scholarship or guarantee statement that its official quote does not support: ' end || left(t, 120));
    end if;
    -- Platform Admin 2 Nov 2026 23:24 ("avoid cutting essential conditions or publishing fragments as complete descriptions"): a sentence
    -- that does not end as a sentence (no closing full stop, question or exclamation mark, or an ellipsis) is a fragment; the description is
    -- held, never cut or completed
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'incomplete_sentence', 'checks', v_checks,
        'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    -- Validation 5 Nov 2026 (decision 20:03 §2): numbers are compared after normalising format (80,000 = 80 000; per cent = %), and the quote's number words count (four = 4).
    if exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(t,false),'[0-9]+(?:[.,][0-9]+)*','g') n where not exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(s->>'quote',true),'[0-9]+(?:[.,][0-9]+)*','g') q where q[1]=n[1])) then
      return jsonb_build_object('ok',false,'outcome','held','rule','unsupported_numeric_claim','reason','A number in a factual claim does not occur in its supporting quote.','checks',v_checks);
    end if;
    -- Quote provenance is retained separately; long verbatim spans fail the existing factual description path.
    if exists(select 1 from generate_series(1,greatest(0,length(regexp_replace(t,'\s+',' ','g'))-security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int+1)) n where position(lower(substring(regexp_replace(t,'\s+',' ','g') from n for security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int)) in lower(regexp_replace(s->>'quote','\s+',' ','g')))>0) then
      return jsonb_build_object('ok',false,'outcome','held','rule','verbatim_passage','reason','A long official passage was copied; a concise source-grounded paraphrase is required.','checks',v_checks);
    end if;
    if coalesce(s->>'quote','')~* '\m(former|formerly|previously|renamed|closed|merged|ceased)\M|was known as|became'
      and t~* '\m(is|are|operates|offers)\M' and t!~* '\m(former|formerly|previously|was|were|became|renamed|closed|merged|ceased|history|founded|established|origin|since)\M'
      -- Validation 5 Nov 2026 (decision 20:03 §2): evidence-aware. Held only when the quote's present-tense part does not support the sentence,
      -- i.e. the sentence's claim is the one the quote places in the past; a historic word elsewhere in the quote never holds a supported claim.
      and security.pdesc_present_support_v1(t, s->>'quote') < v_min_sup then
      return jsonb_build_object('ok',false,'outcome','held','rule','historic_claim_context','reason','Historical source context cannot establish a present institutional identity or operation.','checks',v_checks);
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range');
  end if;
  if p_captured_at is not null and p_captured_at < now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'source_outdated', 'checks', v_checks, 'reason', 'the stored page is older than the set age');
  end if;
  -- duplicate: another provider's description held, or another provider's proposal waiting
  select z.provider_id, z.sim into v_other from (
    select p.id provider_id, security.pdesc_similarity_v1(v_text, p.description) sim from catalogue.providers p
     where p.id <> p_provider and nullif(btrim(p.description), '') is not null
    union all
    select r.provider_id, security.pdesc_similarity_v1(v_text, r.proposal->>'description') from pipeline.provider_description_reads r
     where r.provider_id <> p_provider and r.state = 'proposed') z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.provider_id is not null then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'duplicate_other_provider', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.provider_id, 'similarity', v_other.sim),
      'reason', 'the same as another provider''s description (' || v_other.sim || ')');
  end if;
  select nullif(btrim(p.description), '') into v_current from catalogue.providers p where p.id = p_provider;
  if v_current is not null and security.pdesc_similarity_v1(v_text, v_current) >= v_dup then
    return jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
  end if;
  return jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
end $body$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
declare x jsonb; r pipeline.provider_description_reads%rowtype; v_ev uuid; v_url text; v_cap timestamptz; v_via text; v_hash text;
        v_chk jsonb; v_item uuid; v_tally jsonb := '{}'::jsonb; v_out text; v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text; v_m jsonb; v_src uuid; v_idc jsonb;
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
        -- the sweep source is found once (9 Nov 2026, record time-out): security.coverage_sweep_source is volatile, so as a test on every row it could not be an index condition and the lookup read the whole (source, hash) index (22 ms on average, 142 ms at worst, against 0.2 ms with the id in hand)
        v_src := security.coverage_sweep_source(r.provider_id);
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = v_src and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(v_src, v_url, x->'fetch'->>'storage_path', v_hash,
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
    v_idc := security.provider_description_identity_v1(r.provider_id,r.source_url); -- once: the same answer was asked for up to three times
    if not (v_idc->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',v_idc->>'rule','reason',v_idc->>'reason','checks',v_chk->'checks');
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

update pipeline.platform_toolset_settings s
   set value = coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(s.value) with ordinality t(e, o)
                          where e #>> '{}' not in ('verbatim_passage', 'quote_not_on_page', 'unsupported_sentence', 'unsupported_claim', 'unsupported_numeric_claim', 'unsupported_marketing', 'claim_negated_in_source', 'incomplete_sentence', 'historic_claim_context')), '[]'::jsonb),
       label = 'Provider descriptions: identity holds read again when the reader changes',
       help = 'Hold rules (provider_name_conflict, provider_name_not_proved, provider_subunit_source) that come from the reader''s identity proof of an official page. When the reader that made such a hold is not the current reader (its behaviour version differs), the provider is offered to the current reader once more, using the stored official page. A hold the current reader still refuses stays held. Empty: identity holds are never offered again before the recheck period.',
       reason = 'CF-247 F-PDESC sentence filter recovery: back to the identity rules only (Platform Admin decision)',
       updated_at = now()
 where s.toolset_key = 'pipeline' and s.key = 'pdesc.identity_reeval_rules';
