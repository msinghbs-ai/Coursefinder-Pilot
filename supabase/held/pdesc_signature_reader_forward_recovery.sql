-- HELD (not a migration): forward recovery for 20261110090000 (provider-description evidence signature carries the running reader; the picker offers a no-AI recovery-knowledge refusal again). Run only if the Platform Admin decides to go back to the
-- text of the two functions before that migration. It restores them byte for byte (security.provider_description_signature_v1 body md5 b48bbd5b345f2e7b9a1fc6df9958163b, security.provider_description_selection_v1 body md5 41c9e5ffaba74453c699fd84e9135648,
-- the text 20261110040000 leaves), guarded by the md5 of what is live now: it stops, and changes nothing, if either live body is neither its earlier text nor the one the migration wrote (2002daebe8768dc9504b8c53131472e0 and 7f4a7aa8fea1b81bbf8c1742d749502e), and running it again changes nothing.
-- After it a failure recorded under an earlier reader blocks the current reader again (the 10 Nov 2026 state: the identity holds of reader v1 and v2 refuse the reservation as recovery_knowledge_unchanged_failure, with no AI call made) and such a hold is parked again.
-- The failed outcomes in pipeline.ops_remedy_outcomes are never touched by either direction.
do $g$
declare v_s text; v_p text;
begin
  select md5(p.prosrc) into v_s from pg_proc p where p.oid = to_regprocedure('security.provider_description_signature_v1(text,text,text)');
  select md5(p.prosrc) into v_p from pg_proc p where p.oid = to_regprocedure('security.provider_description_selection_v1(jsonb)');
  if v_s is null or v_p is null then raise exception 'the provider-description signature or selection function is missing'; end if;
  if v_s not in ('b48bbd5b345f2e7b9a1fc6df9958163b', '2002daebe8768dc9504b8c53131472e0') then raise exception 'live security.provider_description_signature_v1 differs from both texts this recovery knows (body md5 %)', v_s; end if;
  if v_p not in ('41c9e5ffaba74453c699fd84e9135648', '7f4a7aa8fea1b81bbf8c1742d749502e') then raise exception 'live security.provider_description_selection_v1 differs from both texts this recovery knows (body md5 %)', v_p; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_signature_v1(p_hash text, p_model text, p_prompt text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $body$
 select md5(coalesce(p_hash,'')||'|'||coalesce(p_model,'')||'|'||coalesce(p_prompt,'provider-description-v2')||'|'||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||coalesce((select jsonb_object_agg(key,value order by key)::text from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('pdesc.min_quote_chars','pdesc.min_sentences','pdesc.max_sentences','pdesc.min_chars','pdesc.max_chars','pdesc.support_min_share','pdesc.duplicate_share','pdesc.source_max_age_days','pdesc.verbatim_span_max_chars','pdesc.claim_words','pdesc.evidence_claim_words','pdesc.superlatives')),''))
$body$;

CREATE OR REPLACE FUNCTION security.provider_description_selection_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $body$
declare v_size int := coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int);
 v_max int := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then security.pipeline_num_v1('pdesc.queue_cap',60)::int else least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int end;
 v_cc text := upper(nullif(btrim(p_args->>'country'),'')); v_type text := nullif(btrim(coalesce(p_args->>'provider_type',p_args->>'type')),'');
 v_provider uuid := nullif(p_args->>'provider_id','')::uuid; v_filter text := coalesce(nullif(coalesce(p_args->>'description_state',p_args->>'filter'),''),'missing');
 v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb; v_scanned jsonb; v_pat text[]:=security.pdesc_about_like_patterns_v1(); v_cur text:=security.pdesc_reader_behaviour_v1(); v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);
 -- upgrade mode (pdesc.registry_upgrade_on, argument upgrade): the list is the providers that hold a register-fact profile, not the providers with no description
 v_upg boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'upgrade')::boolean,false);
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
    and security.provider_description_scope_v1(p.id) and case when v_upg then security.provider_description_basic_profile_v1(p.id) is not null else nullif(btrim(p.description),'') is null end and p.publication_status='published'
    and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))
    and (not v_upg or ((nullif(btrim(p.website),'') is not null or security.provider_description_stored_candidate_v1(p.id,v_pat))))
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
            and (r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) and not (r.state='held' and coalesce(r.checks ? 'identity_hold',false) and coalesce((security.provider_description_identity_v1(p.id,coalesce(a.source_url,p.website))->>'ok')::boolean,false)) then 'retry_wait'
  when r.state in ('admitted','verified') and r.proposal->'sentences' is not null and a.id is not null
   and security.provider_description_validate_v1(p.id,r.source_url,r.source_captured_at,jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))->>'outcome' not in ('propose','verified')
   then case when coalesce(a.content_hash,a.id::text) is distinct from r.content_hash then 'invalid_description' else 'invalid_description_unchanged_evidence' end
  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) and not (v_upg and security.provider_description_basic_profile_v1(p.id) is not null) then 'description_current'
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
end $body$;

do $g$
begin
  -- fixed: the restored bodies must be the recorded ones, byte for byte
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.provider_description_signature_v1(text,text,text)'::regprocedure)) <> 'b48bbd5b345f2e7b9a1fc6df9958163b' then raise exception 'the restored signature body differs from the recorded text'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.provider_description_selection_v1(jsonb)'::regprocedure)) <> '41c9e5ffaba74453c699fd84e9135648' then raise exception 'the restored selection body differs from the recorded text'; end if;
end $g$;
