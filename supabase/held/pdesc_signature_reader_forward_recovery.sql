-- HELD (not a migration): forward recovery for 20261110090000 (provider-description evidence signature carries the running reader). Run only if the Platform Admin decides to go back to the
-- text of security.provider_description_signature_v1 before that migration. It restores the body byte for byte (body md5 b48bbd5b345f2e7b9a1fc6df9958163b), guarded by the md5 of what is live now: it stops if the live body is
-- neither that text nor the one the migration wrote (2002daebe8768dc9504b8c53131472e0), and running it again changes nothing.
-- After it a failure recorded under an earlier reader blocks the current reader again (the 10 Nov 2026 state: the identity holds of reader v1 and v2 refuse the reservation as recovery_knowledge_unchanged_failure, with no AI call made).
-- The failed outcomes in pipeline.ops_remedy_outcomes are never touched by either direction.
do $g$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.provider_description_signature_v1(text,text,text)');
  if v is null then raise exception 'security.provider_description_signature_v1 is missing'; end if;
  if v not in ('b48bbd5b345f2e7b9a1fc6df9958163b', '2002daebe8768dc9504b8c53131472e0') then raise exception 'live security.provider_description_signature_v1 differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_signature_v1(p_hash text, p_model text, p_prompt text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $body$
 select md5(coalesce(p_hash,'')||'|'||coalesce(p_model,'')||'|'||coalesce(p_prompt,'provider-description-v2')||'|'||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||coalesce((select jsonb_object_agg(key,value order by key)::text from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('pdesc.min_quote_chars','pdesc.min_sentences','pdesc.max_sentences','pdesc.min_chars','pdesc.max_chars','pdesc.support_min_share','pdesc.duplicate_share','pdesc.source_max_age_days','pdesc.verbatim_span_max_chars','pdesc.claim_words','pdesc.evidence_claim_words','pdesc.superlatives')),''))
$body$;

do $g$
begin
  -- fixed: the restored body must be the recorded one, byte for byte
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.provider_description_signature_v1(text,text,text)'::regprocedure)) <> 'b48bbd5b345f2e7b9a1fc6df9958163b' then raise exception 'the restored body differs from the recorded text'; end if;
end $g$;
