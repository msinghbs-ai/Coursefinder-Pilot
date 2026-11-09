-- HELD (not a migration): forward recovery for 20261110040000 (register-fact profiles stay eligible for source-backed enrichment; queued reads that fail the identity test are held).
-- Run only if the Platform Admin decides to go back to the text of the five functions before that migration. It restores them byte for byte (body md5 below), each guarded by the md5 of what is live now
-- (the text before the migration, or the text the migration wrote); a function that differs from both is refused and nothing is changed. Switch pdesc.registry_upgrade_on to 0 first if an upgrade has to stop without going back.
-- Descriptions already upgraded stay as they are (each keeps its earlier version in pipeline.provider_description_machine_admissions). The four settings and security.provider_description_basic_profile_v1 are left in place (harmless);
-- to remove the function too, paste the one commented line at the end (a drop is for the Platform Admin to run).

do $g$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.provider_description_machine_blocked_v1(uuid)');
  if v is null then raise exception 'security.provider_description_machine_blocked_v1(uuid) is missing'; end if;
  if v not in ('46634e38c0469cbcbd6c23158dfadc94', 'e23fa20639a882233ad07c44299de4c0') then raise exception 'live security.provider_description_machine_blocked_v1(uuid) differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.provider_description_machine_admit_v1(uuid)');
  if v is null then raise exception 'security.provider_description_machine_admit_v1(uuid) is missing'; end if;
  if v not in ('5decbd99c8ecd5e0b072d22ed6f68962', 'af12eeb05ee313b9f9543f6176eeab25') then raise exception 'live security.provider_description_machine_admit_v1(uuid) differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.provider_description_selection_v1(jsonb)');
  if v is null then raise exception 'security.provider_description_selection_v1(jsonb) is missing'; end if;
  if v not in ('04acb9419b9965b5d6aab420059c7e84', '29c99ddfe50791de28a150978c709872') then raise exception 'live security.provider_description_selection_v1(jsonb) differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.provider_description_enqueue_v1()');
  if v is null then raise exception 'security.provider_description_enqueue_v1() is missing'; end if;
  if v not in ('803478538da3dd9594ba08be38284c3e', 'e97170e51cb27dee62db0cef3e07bb43') then raise exception 'live security.provider_description_enqueue_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('public.svc_provider_description_next(integer)');
  if v is null then raise exception 'public.svc_provider_description_next(integer) is missing'; end if;
  if v not in ('7583808609dc2dea1d3fc251607405a1', '34d7c83ffa3ba81107a1b7a4bc176f4f') then raise exception 'live public.svc_provider_description_next(integer) differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_machine_blocked_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER COST 500
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v_find text;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null then return jsonb_build_object('rule', 'provider_not_live', 'reason', 'There is no such provider.'); end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')) then
    return jsonb_build_object('rule', 'manual_lock', 'reason', 'The description is locked by hand.'); end if;
  if nullif(btrim(p.description), '') is not null then
    return jsonb_build_object('rule', 'description_already_held', 'reason', 'The provider already holds a description; the machine rule admits a first description only.'); end if;
  if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null) then
    return jsonb_build_object('rule', 'description_cleared_after_admission', 'reason', 'A machine description was admitted for this provider and the description has since been cleared by hand; a person decides the next one.'); end if;
  if exists (select 1 from pipeline.layer4_review_items li where li.entity_type = 'provider' and li.entity_id = p.id and li.field_code = 'provider_description' and li.status = 'rejected') then
    return jsonb_build_object('rule', 'prior_human_rejection', 'reason', 'A person rejected an earlier description for this provider.'); end if;
  if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is not null
               and not exists (select 1 from pipeline.provider_description_machine_admissions b where b.provider_id = p.id and b.outcome = 'admitted' and b.created_at > a.withdrawn_at)) then
    return jsonb_build_object('rule', 'withdrawn_awaiting_review', 'reason', 'A machine description for this provider was withdrawn; a person decides the next one.'); end if;
  select f.check_code into v_find from pipeline.provider_identity_findings f where f.provider_id = p.id and f.state = 'open' order by f.check_code limit 1;
  if v_find is not null then return jsonb_build_object('rule', 'identity_' || v_find, 'reason', 'An open provider identity finding needs a person: ' || v_find); end if;
  if (nullif(btrim(p.canonical_name), '') is not null and security.pdesc_clean_name_v1(p.canonical_name) is null)
     or (nullif(btrim(p.display_name), '') is not null and security.pdesc_clean_name_v1(p.display_name) is null)
     or (security.pdesc_clean_name_v1(p.canonical_name) is null and security.pdesc_clean_name_v1(p.display_name) is null) then
    return jsonb_build_object('rule', 'name_not_clean', 'reason', 'A provider name is a placeholder, too short or still holds web-page markup, so the identity proof is not reliable; a person decides.'); end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_description_machine_admit_v1(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; v_read pipeline.provider_description_reads%rowtype; v_tier text; v_text text; v_gate jsonb; v_check jsonb; v_prof jsonb; v_now text; v_pub jsonb; v_shown text; v_key text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'pdesc-machine-v1'; v_ref text := 'CF-247 F-PDESC; Platform Admin decision 9 Nov 2026 (source-verified machine admission, tiers 1 to 4)'; v_dec uuid; v_facts jsonb := '[]'::jsonb; v_codes jsonb := '[]'::jsonb;
        v_url text; v_hash text; v_reason text; v_decline text;
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item_id for update;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'not_a_waiting_provider_description'); end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'proposed' for update;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  v_tier := coalesce(nullif(v_read.checks->>'tier', ''), v_read.read_via, i.proposed_value->>'tier');
  v_decline := null;
  if v_read.id is null then v_decline := 'no_proposed_read';
  elsif v_tier not in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_decline := 'unknown_tier';
  end if;
  if v_decline is null then
    if v_tier = 'registry_factual' then
      -- rebuilt from the verified record now: the text, the register evidence and the facts must be exactly what was proposed
      v_prof := security.provider_description_registry_profile_v1(i.entity_id);
      if not coalesce((v_prof->>'ok')::boolean, false) then v_decline := 'profile_' || coalesce(v_prof->>'rule', 'not_ok');
      elsif v_prof->>'text' is distinct from v_text or (v_prof->>'evidence_id')::uuid is distinct from i.evidence_id then v_decline := 'profile_changed_since_proposed';
      elsif not exists (select 1 from catalogue.provider_registrations rr where rr.id = (v_prof->>'registration_id')::uuid and rr.provider_id = i.entity_id and rr.status = 'active' and rr.evidence_id = i.evidence_id) then v_decline := 'register_listing_changed';
      end if;
      v_facts := coalesce(v_prof->'facts', '[]'::jsonb); v_codes := coalesce(v_prof->'codes', '[]'::jsonb); v_url := v_prof->>'source_url'; v_hash := v_prof->>'source_hash';
    else
      -- the same lineage, identity and quote checks the human path makes, proved again now
      if v_read.evidence_id is distinct from i.evidence_id or not exists (select 1 from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
           where a.id = i.evidence_id and s.provider_id = i.entity_id and a.source_url = v_read.source_url and coalesce(a.content_hash, a.id::text) = v_read.content_hash) then v_decline := 'evidence_lineage_changed';
      elsif not (security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'ok')::boolean then v_decline := 'identity_' || coalesce(security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'rule', 'not_clear');
      elsif v_read.checks->'identity_snapshot' is not null and v_read.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(i.entity_id) then v_decline := 'identity_changed_since_read';
      elsif v_read.checks->'identity_snapshot' is null and not exists (select 1 from catalogue.providers p cross join lateral jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) sentence
           where p.id = i.entity_id and exists (select 1 from unnest(array[p.canonical_name, p.display_name]) nm where nullif(btrim(nm), '') is not null
             and position(regexp_replace(lower(nm), '[^a-z0-9]+', '', 'g') in regexp_replace(lower(sentence->>'quote'), '[^a-z0-9]+', '', 'g')) > 0)) then v_decline := 'legacy_proposal_name_not_in_quote';
      else
        v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', i.proposed_value->'sentences'));
        if v_check->>'outcome' not in ('propose', 'verified') or v_check->>'text' is distinct from v_text then v_decline := 'validation_' || coalesce(v_check->>'rule', 'changed'); end if;
      end if;
      v_url := v_read.source_url; v_hash := v_read.content_hash;
      v_facts := coalesce((select jsonb_agg(jsonb_build_object('sentence', s->>'text', 'quote', s->>'quote', 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'evidence_id', v_read.evidence_id,
                    'captured_at', v_read.source_captured_at, 'model', v_read.model, 'prompt_version', v_read.prompt_version, 'worker', v_read.worker)) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s), '[]'::jsonb);
    end if;
  end if;
  if v_decline is null then
    v_gate := security.provider_description_machine_gate_v1(i.entity_id, v_text, jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end));
    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
  end if;
  if v_decline is null and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;
  if v_decline is null then
    select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
    if v_now is not null then v_decline := 'description_already_held'; end if;
  end if;
  if v_decline is not null then
    v_reason := coalesce(v_reason, 'The automatic rule did not admit this description (' || v_decline || '); a person decides in Layer 4.');
    insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now();
    update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^.]*\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
     where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '.%';
    return jsonb_build_object('ok', false, 'rule', v_decline, 'reason', v_reason);
  end if;
  -- write the one description, settle the item as a machine decision, record everything
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- proved on the row: a guard that put the old text back must stop the admission, not leave an audit that says it was published
  if (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = i.entity_id) is distinct from v_text then raise exception 'description_not_written: the catalogue kept the earlier text'; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
  v_reason := format('Auto (%s, tier %s): %s. Not a person''s decision.', v_rule, v_tier,
                     case when v_tier = 'registry_factual' then 'built only from the verified register listing, provider record and active catalogue courses; every sentence tied to its facts'
                          else 'official page ' || coalesce(v_url, '') || ' (hash ' || left(coalesce(v_hash, ''), 12) || '); identity, evidence lineage and every sentence''s quote proved again at admission' end); -- fixed: a short hash prefix is shown for reading, the full hash is stored
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine'), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'provider_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'provider_id', i.entity_id, 'auto', true,
          'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code), v_sys);
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin v_pub := public.website_v2_provider(v_key); v_shown := v_pub->'item'->>'description'; exception when others then v_shown := null; end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(), published_at = case when v_shown = v_text then now() end, updated_at = now(),
         checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') where id = v_read.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now() where provider_id = i.entity_id and state = 'admitted' and id <> v_read.id;
  insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description, evidence_id, source_url, source_hash, facts, checks, actor)
  values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', v_reason, null, v_text, i.evidence_id, v_url, v_hash, v_facts,
          jsonb_build_object('decision_id', v_dec, 'published', v_shown = v_text, 'validation', coalesce(v_check->'checks', v_prof->'facts'),
          'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end))), v_sys);
  return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier, 'rule', v_rule, 'decision_id', v_dec, 'description_chars', length(v_text), 'published', v_shown = v_text);
end $function$;

CREATE OR REPLACE FUNCTION security.provider_description_selection_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_size int := coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int);
 v_max int := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then security.pipeline_num_v1('pdesc.queue_cap',60)::int else least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int end;
 v_cc text := upper(nullif(btrim(p_args->>'country'),'')); v_type text := nullif(btrim(coalesce(p_args->>'provider_type',p_args->>'type')),'');
 v_provider uuid := nullif(p_args->>'provider_id','')::uuid; v_filter text := coalesce(nullif(coalesce(p_args->>'description_state',p_args->>'filter'),''),'missing');
 v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb; v_scanned jsonb; v_pat text[]:=security.pdesc_about_like_patterns_v1(); v_cur text:=security.pdesc_reader_behaviour_v1(); v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);
 -- QA B2: with prefilter (automatic mode only; the default there for the missing-description list of every caller, and always for the reader) the stored page and identity are worked out for a bounded slice of the providers that can still be read, not for the whole catalogue
 v_pre boolean := security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'prefilter')::boolean,v_filter='missing' and v_provider is null);
 v_slice int := least(security.pipeline_num_v1('pdesc.scan_max',150)::int, greatest(coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int),1)*security.pipeline_num_v1('pdesc.scan_factor',3)::int);
begin
 if v_size < 1 or v_size > v_max then raise exception 'cohort size must be between 1 and %',v_max using errcode='22023'; end if;
 if v_mode not in ('stored','approved') then raise exception 'unsupported processing mode' using errcode='22023'; end if;
 if v_mode='approved' and security.pipeline_num_v1('pdesc.acquire_direct',0)<1 then raise exception 'acquisition has not been authorised' using errcode='42501'; end if;
 if v_filter not in ('missing','stale','failed','all') then raise exception 'unsupported description selection' using errcode='22023'; end if;
 with pre as materialized (
  select q.id from (select p.id,coalesce(m.scanned_at,'-infinity'::timestamptz) sc,(select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') ac,coalesce(p.display_name,p.canonical_name) nm
   from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id left join pipeline.provider_description_scan_marks m on m.provider_id=p.id
   where v_pre and (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
    and security.provider_description_scope_v1(p.id) and nullif(btrim(p.description),'') is null and p.publication_status='published'
    and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))
    and (v_mode<>'stored' or security.provider_description_stored_candidate_v1(p.id,v_pat))
   order by sc,ac desc,nm limit v_slice) q
 ), candidates as materialized (
 select p.*,k.iso_alpha2::text cc,t.code typ,
  (select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') active_course_count,
  security.provider_description_stored_v1(p.id) stored_id
 from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id
 where (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
  -- Scope is governed by the existing policy. The UI selector can narrow it, never widen it.
  and security.provider_description_scope_v1(p.id)
  and (not v_pre or p.id in (select pre.id from pre))
 ), rows as (
 select p.*,r.id last_read_id,r.state read_state,r.rule read_rule,r.reason read_reason,r.proposal,r.checks,r.review_item_id,(select li.created_at from pipeline.layer4_review_items li where li.id=r.review_item_id) review_created_at,r.model,r.cost_usd,r.tries,r.updated_at read_updated_at,r.last_verified_at read_last_verified_at,
 a.source_url,a.id evidence_id,coalesce(a.captured_at,a.created_at) source_captured_at,coalesce(a.content_hash,a.id::text) source_hash,
 case
  when v_pre and security.provider_description_machine_blocked_v1(p.id) is not null then 'machine_'||(security.provider_description_machine_blocked_v1(p.id)->>'rule')
  when p.lifecycle_status<>'active' then 'provider_inactive'
  when p.publication_status<>'published' or exists(select 1 from security.provider_hidden_v1 h where h.provider_id=p.id) then 'provider_not_published'
  when exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p.id and l.field in ('description','p_description','all')) then 'manual_lock'
  when nullif(btrim(p.description),'') is not null and security.provider_description_approved_lineage_v1(p.id,p.description) is null then 'manual_description'
  when nullif(btrim(p.description),'') is not null and (select z.proposal->>'description' from pipeline.provider_description_reads z where z.provider_id=p.id and z.state in ('admitted','verified') order by coalesce(z.last_verified_at,z.updated_at) desc,z.id desc limit 1) is distinct from p.description then 'manual_description_changed'
  when r.state in ('queued','reading','proposed') then 'existing_work'
  when r.state='dead_letter' then 'dead_letter_requires_retry'
  when coalesce(r.reserved_usd,0)>0 then 'cost_reservation_uncertain'
  when r.state='held' and r.rule='review_full' then 'review_capacity_parked'
  when r.state='held' and r.rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') then 'policy_retry_parked'
  when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'unchanged_unsuitable_evidence'
  when r.state in ('held','rejected') and r.updated_at>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int)
   and not (r.updated_at<=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int) and a.id is not null
            and coalesce(a.content_hash,a.id::text) is distinct from r.content_hash
            and (r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'retry_wait'
  when r.state in ('admitted','verified') and r.proposal->'sentences' is not null and a.id is not null
   and security.provider_description_validate_v1(p.id,r.source_url,r.source_captured_at,jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))->>'outcome' not in ('propose','verified')
   then case when coalesce(a.content_hash,a.id::text) is distinct from r.content_hash then 'invalid_description' else 'invalid_description_unchanged_evidence' end
  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'
  when a.id is not null and not (security.provider_description_identity_v1(p.id,a.source_url)->>'ok')::boolean then security.provider_description_identity_v1(p.id,a.source_url)->>'rule'
  when a.id is not null and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select model_identifier from pipeline.central_ai_settings where id=1),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'recovery_knowledge_unchanged_failure'
  when v_mode='stored' and a.id is null then 'no_verified_stored_source'
  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is null then 'description_lost'
  else 'eligible' end eligibility_reason
 from candidates p left join lateral(select x.* from pipeline.provider_description_reads x where x.provider_id=p.id order by x.created_at desc,x.id desc limit 1) r on true
 left join pipeline.evidence_artifacts a on a.id=p.stored_id
 ), shaped as (
 select jsonb_build_object('provider_id',rows.id,'provider',coalesce(display_name,canonical_name),'name',coalesce(display_name,canonical_name),'stable_key',stable_key,
 'registration',coalesce((select jsonb_agg(jsonb_build_object('registration_id',pr.id,'scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'valid_to',pr.valid_to,'checked_at',pr.checked_at,'source_id',pr.source_id,'evidence_id',pr.evidence_id) order by pr.registration_scheme,pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=rows.id),'[]'::jsonb),'country',cc,'type',typ,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
 'active_course_count',active_course_count,'current_description',description,'proposed_description',proposal->>'description','sentences',proposal->'sentences','checks',checks,
 'source_url',source_url,'evidence_id',evidence_id,'source_hash',source_hash,'source_captured_at',source_captured_at,'source_age_days',extract(epoch from (now()-source_captured_at))/86400,
 'evidence_version',source_hash,'approval_status',case when read_state='proposed' then 'pending' else read_state end,'manual_locked',eligibility_reason='manual_lock','last_read_id',last_read_id,'state',coalesce(read_state,'missing'),'rule',read_rule,'reason',read_reason,'review_item_id',review_item_id,'review_created_at',review_created_at,
 'model',coalesce(model,(select c.model_identifier from pipeline.central_ai_settings c where c.id=1)),'cost_usd',cost_usd,'tries',tries,
 'eligible',eligibility_reason in ('eligible','invalid_description','description_lost'),'eligibility_reason',eligibility_reason,'required_approval','Individual human Layer 4 decision','last_verified_at',read_last_verified_at) row,
 eligibility_reason,active_course_count,coalesce(display_name,canonical_name) nm
 from rows where v_filter='all' or (v_filter='missing' and nullif(btrim(description),'') is null)
 or (v_filter='stale' and nullif(btrim(description),'') is not null)
 or (v_filter='failed' and read_state in ('held','dead_letter','rejected'))
 ) select coalesce(jsonb_agg(row order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm),'[]'::jsonb),(select coalesce(jsonb_agg(z.row->>'provider_id'),'[]'::jsonb) from shaped z where z.eligibility_reason not in ('eligible','invalid_description','description_lost')) into v_rows,v_scanned
 from (select * from shaped order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm limit v_size) b;
 return jsonb_build_object('providers',v_rows,'selected',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),
 'eligible',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),'bounded',true,'size',v_size,'scanned',case when v_pre then v_scanned end,'as_at',now(),
 'exclusions',(select coalesce(jsonb_agg(jsonb_build_object('provider_id',x->>'provider_id','reason',x->>'eligibility_reason')),'[]') from jsonb_array_elements(v_rows) x where not (x->>'eligible')::boolean));
end $function$;

CREATE OR REPLACE FUNCTION security.provider_description_enqueue_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
 declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
  -- automatic mode: each country is its own bounded queue, sized from the providers still to do and the observed rate; each looks at a bounded slice (QA B2)
  v_n:=0; v_t:=security.provider_description_throughput_v1();
  for v_cc,v_share in select e.key,e.value::int from jsonb_each_text(coalesce(v_t->'share','{}'::jsonb)) e order by e.key loop
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',v_share,'country',v_cc,'prefilter',true,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end));
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(v_sel->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
   -- the providers looked at that cannot be read yet, and those returned, go to the back of the rotation
   insert into pipeline.provider_description_scan_marks(provider_id,scanned_at,last_reason)
   select u.pid::uuid,now(),'looked at' from (select jsonb_array_elements_text(coalesce(v_sel->'scanned','[]'::jsonb)) pid union select y->>'provider_id' from jsonb_array_elements(coalesce(v_sel->'providers','[]'::jsonb)) y) u
   on conflict (provider_id) do update set scanned_at=excluded.scanned_at,last_reason=excluded.last_reason;
  end loop;
  return v_n;
 end if;
 insert into pipeline.provider_description_reads(provider_id)
 select (x->>'provider_id')::uuid from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,
 'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end))->'providers') x
 where (x->>'eligible')::boolean on conflict do nothing;
 get diagnostics v_n=row_count; return v_n;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric; v_fc_res int; v_fc_left int; v_ws text[]; v_stored jsonb; v_reoffer uuid[]; v_tries numeric := security.pipeline_num_v1('pdesc.tries', 3); v_acq boolean := security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1; -- the two settings the pick tests on every due read, read once
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
  pick as (select l.id from (
             -- lazy pick (9 Nov 2026, lease and record time-outs): the cheap tests and the order are worked out for every due read (inner query), then the dear per-provider tests
             -- (scope, recovery memory, identity, hidden) run only on the reads taken in that order until the limit is reached. The same reads in the same order as before; the whole queue is no longer tested on every call.
             select c.id from (
               select r.id, r.provider_id, r.prompt_version from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < v_tries
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when v_acq then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 offset 0) c -- offset 0 is an optimisation fence: the dear tests below are not moved under the sort, so they stop with the limit
              where security.provider_description_scope_v1(c.provider_id)
                and (c.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',c.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(c.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=c.provider_id)) o
           -- the row lock, as before: skip a read another call holds; the due test is repeated on the locked row, as the lock of the old single query re-tested it
           cross join lateral (select q.id from pipeline.provider_description_reads q where q.id = o.id
                                  and ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'reading' and q.leased_until < now()))
                                  and q.tries < v_tries
                                for update skip locked) l
           limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))),
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
end $function$;

-- optional, Platform Admin only:
-- drop function if exists security.provider_description_basic_profile_v1(uuid);
