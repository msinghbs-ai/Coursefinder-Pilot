CREATE OR REPLACE FUNCTION public.svc_provider_description_reserve_v1(p_item uuid, p_model text, p_max_cost numeric, p_source_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.provider_description_reads%rowtype; v_model text; v_spent numeric; v_today numeric; v_reserved numeric; v_cap numeric; v_daily numeric; v_source_hash text;
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext('cf247 provider description spend')); -- fixed: serialize reservations across reader calls.
 select * into r from pipeline.provider_description_reads where id=p_item for update;
 if r.id is null or r.state<>'reading' or r.leased_until<=now() then return jsonb_build_object('ok',false,'reason','no_active_read_lease'); end if;
 select model_identifier into v_model from pipeline.central_ai_settings where id=1;
 if p_model is distinct from v_model or p_max_cost is null or p_max_cost<=0 then return jsonb_build_object('ok',false,'reason','invalid_pinned_model_price_quote'); end if;
 v_source_hash:=coalesce(nullif(p_source_hash,''),(select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(r.provider_id)));
 if v_source_hash is null then return jsonb_build_object('ok',false,'reason','no_source_version_before_ai'); end if;
 if exists(select 1 from pipeline.provider_description_reads rejected where rejected.provider_id=r.provider_id and rejected.state='rejected' and rejected.content_hash=v_source_hash) then return jsonb_build_object('ok',false,'reason','unchanged_rejected_evidence'); end if;
 if not security.pdesc_on_demand_live_v1(r.checks) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1(v_source_hash,p_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) then return jsonb_build_object('ok',false,'reason','recovery_knowledge_unchanged_failure'); end if;
 if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then return jsonb_build_object('ok',false,'reason','identity_changed_after_lease'); end if;
 if r.reserved_usd>0 then return jsonb_build_object('ok',false,'reason','existing_cost_reservation_uncertain','ai_calls',r.ai_calls,'reserved_usd',r.reserved_usd); end if;
 if security.pipeline_num_v1('pdesc.enabled',0)<1 or not security.ai_use_allowed_v1(case when security.pdesc_on_demand_live_v1(r.checks) then 'provider_description_on_demand' else 'provider_description' end) then /* 20261112010000 */ return jsonb_build_object('ok',false,'reason','ai_refused'); end if;
 select coalesce(sum(cost_usd),0),coalesce(sum(cost_usd) filter(where at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0) into v_spent,v_today from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening';
 select coalesce(sum(reserved_usd),0) into v_reserved from pipeline.provider_description_reads where reserved_usd>0 and id<>r.id;
 v_cap:=security.pipeline_num_v1('pdesc.ai_usd_max',1);
 v_daily:=coalesce((security.toolset_setting('openrouter','guard_provider_description')#>>'{}')::numeric,1);
 if v_spent+v_reserved+p_max_cost>v_cap and not security.pdesc_on_demand_live_v1(r.checks) then /* 20261112010000: on demand is not held by the lane ceiling */ return jsonb_build_object('ok',false,'reason','ai_ceiling','remaining_usd',greatest(0,v_cap-v_spent-v_reserved)); end if;
 if v_today+v_reserved+p_max_cost>v_daily and not security.pdesc_on_demand_live_v1(r.checks) then /* 20261112010000: nor by the lane daily guard */ return jsonb_build_object('ok',false,'reason','ai_daily_guard','remaining_usd',greatest(0,v_daily-v_today-v_reserved)); end if;
 update pipeline.provider_description_reads set reserved_usd=p_max_cost where id=r.id;
 return jsonb_build_object('ok',true,'reserved_usd',p_max_cost,'remaining_usd',greatest(0,v_cap-v_spent-v_reserved-p_max_cost));
end $function$
