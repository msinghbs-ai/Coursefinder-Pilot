CREATE OR REPLACE FUNCTION security.layer2_evidence_lineage_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_lineage jsonb;
begin
  if new.job_id is null then return new; end if;
  v_lineage:=security.layer2_lineage_for_job(new.job_id);
  if v_lineage is not null then
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object('layer2_lineage',v_lineage);
  end if;
  return new;
end $function$

