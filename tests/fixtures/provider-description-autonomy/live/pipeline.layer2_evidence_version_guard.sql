CREATE OR REPLACE FUNCTION pipeline.layer2_evidence_version_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_job_version uuid;
begin
  if new.job_id is not null then
    select source_profile_version_id into v_job_version from pipeline.jobs where id=new.job_id;
    if v_job_version is not null then
      if new.source_profile_version_id is null then new.source_profile_version_id:=v_job_version;
      elsif new.source_profile_version_id<>v_job_version then raise exception 'Evidence configuration version does not match Job configuration version' using errcode='23514';
      end if;
    end if;
  end if;
  return new;
end
$function$

