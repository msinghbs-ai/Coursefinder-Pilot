CREATE OR REPLACE FUNCTION security.provider_description_basic_profile_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the profile the provider holds now, or null. Off (pdesc.registry_upgrade_on = 0), a text a person changed, a later admission of another tier, a withdrawal or a cleared description all give null.
  select jsonb_build_object('admission_id', a.id, 'read_id', a.read_id, 'text', a.after_description, 'admitted_at', a.created_at, 'evidence_id', a.evidence_id)
    from catalogue.providers p
    join pipeline.provider_description_machine_admissions a on a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null and a.tier = 'registry_factual'
   where p.id = p_provider
     and security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1
     and nullif(btrim(p.description), '') is not null and btrim(p.description) = btrim(a.after_description)
     and exists (select 1 from pipeline.provider_description_reads r where r.id = a.read_id and r.state = 'admitted' and r.rule = 'registry_factual' and r.worker = 'registry-factual-v1')
$function$
