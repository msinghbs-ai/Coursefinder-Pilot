-- HELD (not a migration): forward recovery for 20261110140000 (settlement of abandoned provider-description AI reservations; faster duplicate test). Run only if the Platform Admin decides to go back to the earlier text.
-- It puts back the text of the two functions before that migration, byte for byte (security.provider_description_fire_v1 body md5 21662da5fc9c4e15facbaef47b63a50f, security.provider_description_validate_v1 body md5 7347f51b70a0c4a6cdd01a117080aad5),
-- guarded by the md5 of what is live now: it stops, and changes nothing, if either live body is neither its earlier text nor the one the migration wrote (e518081dfb0882f93c264813b6ce3788 and 91a7c9b7757cace6006af37df2bdc40a). It also takes the new
-- function name out of the used_by line of pdesc.queue_cap and pdesc.read_cost_floor_usd. security.provider_description_settle_abandoned_v1 is left in place (nothing calls it afterwards; it is dropped by a paste file after hygiene.retire_after_days, once nothing used it).
-- Reads already settled, ledger rows and settings values are never touched. After it the fire no longer settles abandoned reservations and the duplicate test works out the similarity for every description again. The migration applies again after it.
do $g$
declare v_f text; v_v text;
begin
  select md5(p.prosrc) into v_f from pg_proc p where p.oid = to_regprocedure('security.provider_description_fire_v1()');
  select md5(p.prosrc) into v_v from pg_proc p where p.oid = to_regprocedure('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)');
  if v_f is null or v_v is null then raise exception 'the provider-description fire or validator is missing'; end if;
  if v_f not in ('21662da5fc9c4e15facbaef47b63a50f', 'e518081dfb0882f93c264813b6ce3788') then raise exception 'live security.provider_description_fire_v1 differs from both texts this recovery knows (body md5 %)', v_f; end if;
  if v_v not in ('7347f51b70a0c4a6cdd01a117080aad5', '91a7c9b7757cace6006af37df2bdc40a') then raise exception 'live security.provider_description_validate_v1 differs from both texts this recovery knows (body md5 %)', v_v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int; v_sent int; v_i int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description fire')) then return jsonb_build_object('sent',0,'reason','reader_dispatch_in_flight'); end if; -- fixed: serialize the existing job dispatch, never wait or duplicate a nonce.
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- Publication and parked proposal progress do not require another paid read. Manual Run Now never adds work outside its fixed cohort.
  if nullif(current_setting('cf.pdesc_run_now',true),'') is null then
  perform security.provider_description_publication_check_v1();
  update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,updated_at=now()
  where state='held' and rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and reserved_usd=0;

  update pipeline.provider_description_reads r set state='held',rule='selection_changed_before_lease',reason='Provider scope, identity, manual lock or pinned source changed; inspect saved evidence before preparing another cohort',updated_at=now()
  where r.state='queued' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_cohorts c on c.id=m.cohort_id where m.read_id=r.id and c.state='started')
  and (not security.provider_description_scope_v1(r.provider_id)
    or exists(select 1 from pipeline.provider_description_cohort_members m join catalogue.providers p on p.id=m.provider_id where m.read_id=r.id and p.description is distinct from m.snapshot->>'current_description')
    or exists(select 1 from catalogue.providers p where p.id=r.provider_id and not (security.provider_description_identity_v1(r.provider_id,coalesce((select m.snapshot->>'source_url' from pipeline.provider_description_cohort_members m where m.read_id=r.id order by m.pick limit 1),p.website))->>'ok')::boolean)
    or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
    or exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and m.evidence_id is not null and not exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int) and (security.provider_description_identity_v1(r.provider_id,a.source_url)->>'ok')::boolean)));
  v_resumed:=security.provider_description_resume_v1();
  v_q := security.provider_description_enqueue_v1();
  if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then perform security.provider_description_machine_step_v1(); end if;
  else v_q:=0; v_resumed:=0; end if;
  select count(*) into v_dead from pipeline.provider_description_reads r where r.state = 'dead_letter';
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then
    return jsonb_build_object('queued', v_q, 'ai', 'ceiling', 'dead_letter', v_dead);
  end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
  select count(*) into v_due from pipeline.provider_description_reads r
   where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
     and (nullif(current_setting('cf.pdesc_run_now',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid and m.read_id=r.id));
  select max(l.created_at) into v_last from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int) + interval '30 seconds'; -- fixed: fire jitter, so a fire exactly one window after the last dispatch is not blocked by the milliseconds that dispatch started after its minute
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_last:=null; end if; -- Run Now bypasses frequency only; all other job guards remain.
  if v_due > 0 and v_open = 0 and v_last is null then
    if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_cohort:=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid;
    else
    select c.id into v_cohort from pipeline.provider_description_cohorts c
    where c.state='started' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and ((r.state='queued' and r.next_try_at<=now()) or (r.state='reading' and r.leased_until<now())))
    order by c.prepared_at,c.id limit 1;
    end if;
    -- automatic mode: as many worker calls as the due reads need, up to pdesc.dispatch_max (each lease is bounded by the concurrency and spend limits); otherwise one call, as before
    v_sent := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and v_cohort is null then least(security.pipeline_num_v1('pdesc.dispatch_max',3)::int, greatest(1, ceil(v_due::numeric / greatest(1, security.pipeline_num_v1('batch.provider_description', 3)))::int)) else 1 end;
    for v_i in 1 .. v_sent loop
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    end loop;
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', v_sent, 'dead_letter', v_dead);
  end if;
  return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 0, 'dead_letter', v_dead);
end $body$;

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
        v_drop boolean := coalesce((p_result->>'drop_failing')::boolean, false); v_keep jsonb := '[]'::jsonb; v_dropped jsonb := '[]'::jsonb; v_bad jsonb; v_first jsonb; v_idx int := 0; v_ret jsonb;
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
    v_idx := v_idx + 1; v_bad := null; v_claim := null;
    t := btrim(coalesce(s->>'text', ''));
    -- the sentence rules, in their order, for one sentence: the first that fails sets v_bad and leaves the pass (a single-pass loop)
    <<chk>>
    loop
      if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120)); exit chk;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      -- Platform Admin 5 Nov 2026 20:03 §2: campus, scholarship and guarantee statements are checked against their official quote, never held by keyword alone
      select r into v_claim from (select security.pdesc_claim_check_v1(t, s->>'quote', w) r from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb)) w) z where r is not null limit 1;
      if v_claim is not null then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', v_claim, 'checks', v_checks, 'reason', case v_claim when 'claim_negated_in_source' then 'the official quote negates a campus, scholarship or guarantee statement that the sentence makes: ' else 'a campus, scholarship or guarantee statement that its official quote does not support: ' end || left(t, 120)); exit chk;
      end if;
      -- Platform Admin 2 Nov 2026 23:24 ("avoid cutting essential conditions or publishing fragments as complete descriptions"): a sentence
      -- that does not end as a sentence (no closing full stop, question or exclamation mark, or an ellipsis) is a fragment; the description is
      -- held, never cut or completed
      if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'incomplete_sentence', 'checks', v_checks,
          'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120)); exit chk;
      end if;
      -- Validation 5 Nov 2026 (decision 20:03 §2): numbers are compared after normalising format (80,000 = 80 000; per cent = %), and the quote's number words count (four = 4).
      if exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(t,false),'[0-9]+(?:[.,][0-9]+)*','g') n where not exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(s->>'quote',true),'[0-9]+(?:[.,][0-9]+)*','g') q where q[1]=n[1])) then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','unsupported_numeric_claim','reason','A number in a factual claim does not occur in its supporting quote.','checks',v_checks); exit chk;
      end if;
      -- Quote provenance is retained separately; long verbatim spans fail the existing factual description path.
      if exists(select 1 from generate_series(1,greatest(0,length(regexp_replace(t,'\s+',' ','g'))-security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int+1)) n where position(lower(substring(regexp_replace(t,'\s+',' ','g') from n for security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int)) in lower(regexp_replace(s->>'quote','\s+',' ','g')))>0) then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','verbatim_passage','reason','A long official passage was copied; a concise source-grounded paraphrase is required.','checks',v_checks); exit chk;
      end if;
      if coalesce(s->>'quote','')~* '\m(former|formerly|previously|renamed|closed|merged|ceased)\M|was known as|became'
        and t~* '\m(is|are|operates|offers)\M' and t!~* '\m(former|formerly|previously|was|were|became|renamed|closed|merged|ceased|history|founded|established|origin|since)\M'
        -- Validation 5 Nov 2026 (decision 20:03 §2): evidence-aware. Held only when the quote's present-tense part does not support the sentence,
        -- i.e. the sentence's claim is the one the quote places in the past; a historic word elsewhere in the quote never holds a supported claim.
        and security.pdesc_present_support_v1(t, s->>'quote') < v_min_sup then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','historic_claim_context','reason','Historical source context cannot establish a present institutional identity or operation.','checks',v_checks); exit chk;
      end if;
      v_sup := security.pdesc_support_v1(t, s->>'quote');
      if v_sup < v_min_sup then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
          'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120)); exit chk;
      end if;
      exit chk;
    end loop chk;
    if v_bad is not null then
      -- without drop_failing (every caller except the record of a new read) the first failing sentence holds the whole answer, exactly as before
      if not v_drop then return v_bad; end if;
      v_dropped := v_dropped || jsonb_build_object('index', v_idx, 'rule', v_bad->>'rule', 'reason', left(coalesce(v_bad->>'reason', ''), 300), 'text', left(t, 300), 'quote', left(coalesce(s->>'quote', ''), 300), 'support', v_bad#>'{checks,support}');
      v_first := coalesce(v_first, v_bad);
    else
      v_keep := v_keep || jsonb_build_array(s);
    end if;
  end loop;
  -- sentence filter (the record of a new read only): the sentences that failed a rule are left out, the others are checked as a whole description below.
  -- Every kept sentence passed every sentence rule above; the count, the length, the age and the duplicate tests apply to what is kept. Fewer kept sentences than the set
  -- minimum hold the read with the rule of the first sentence that failed. The dropped sentences and why stay in checks.dropped.
  if v_drop and jsonb_array_length(v_dropped) > 0 then
    v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_keep) with ordinality e(x, o));
    v_checks := v_checks || jsonb_build_object('sentences', jsonb_array_length(v_keep), 'sentences_given', v_n, 'chars', length(coalesce(v_text, '')), 'dropped', v_dropped);
    if jsonb_array_length(v_keep) < security.pipeline_num_v1('pdesc.min_sentences', 2) then
      return v_first || jsonb_build_object('checks', v_checks);
    end if;
  end if;
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
    v_ret := jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
    if v_drop then v_ret := v_ret || jsonb_build_object('sentences', v_keep); end if;
    return v_ret;
  end if;
  v_ret := jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
  if v_drop then v_ret := v_ret || jsonb_build_object('sentences', v_keep); end if;
  return v_ret;
end 
$body$;

update pipeline.platform_toolset_settings
   set used_by = replace(replace(used_by, '; security.provider_description_settle_abandoned_v1 (batch bound)', ''), '; security.provider_description_settle_abandoned_v1 (cost of an abandoned reservation)', ''), updated_at = now()
 where toolset_key = 'pipeline' and key in ('pdesc.queue_cap', 'pdesc.read_cost_floor_usd') and used_by like '%provider_description_settle_abandoned_v1%';

do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.provider_description_fire_v1()'::regprocedure) <> '21662da5fc9c4e15facbaef47b63a50f' then raise exception 'the fire was not restored byte for byte'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure) <> '7347f51b70a0c4a6cdd01a117080aad5' then raise exception 'the validator was not restored byte for byte'; end if;
end $c$;
