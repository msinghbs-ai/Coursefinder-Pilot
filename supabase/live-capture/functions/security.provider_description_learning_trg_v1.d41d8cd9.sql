CREATE OR REPLACE FUNCTION security.provider_description_learning_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_sig text; v_human boolean;
begin
 if new.rule in ('review_full','recovery_knowledge_unchanged_failure','source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') or new.state is not distinct from old.state or new.content_hash is null or new.state not in ('proposed','held','rejected','admitted','verified') then return new; end if;
 v_sig:=security.provider_description_signature_v1(new.content_hash,new.model,new.prompt_version);
 v_human:=new.state='admitted';
 perform security.ops_learning_record_v1(jsonb_build_object('code',case when v_human then 'provider_description:human_admission' else 'provider_description:official_about' end,
 'entity',new.provider_id::text,'evidence_signature',v_sig,'performed_by',case when v_human then 'layer4_human' else 'platform' end,
 'success',new.state in ('proposed','admitted','verified'),'stage_advanced',new.state in ('proposed','admitted','verified'),
 'cost_usd',case when v_human then 0 else new.cost_usd end,'expected',case when v_human then 'Authorised exact description admitted; consumer verification separate' else 'Official evidence-backed description proposal' end,
 'observed',jsonb_build_object('read_id',new.id,'state',new.state,'rule',new.rule,'review_item_id',new.review_item_id,'admitted',new.state='admitted','website_published',new.published_at is not null),
 'evidence',jsonb_build_object('evidence_id',new.evidence_id,'content_hash',new.content_hash,'model',new.model,'prompt_version',new.prompt_version,'reason',new.reason)));
 return new;
end $function$
