CREATE OR REPLACE FUNCTION public.svc_provider_description_cohort_next(p_limit integer, p_cohort uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 if not exists(select 1 from pipeline.provider_description_cohorts c where c.id=p_cohort and c.state='started') then raise exception 'unknown started cohort'; end if;
 perform set_config('cf.pdesc_cohort',p_cohort::text,true);
 perform set_config('cf.pdesc_worker_protocol','provider-description-reserve-v1',true); -- only the reservation-capable worker calls this (new in this release)
 return public.svc_provider_description_next(p_limit);
end $function$
