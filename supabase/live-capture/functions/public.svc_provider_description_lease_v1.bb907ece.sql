CREATE OR REPLACE FUNCTION public.svc_provider_description_lease_v1(p_limit integer, p_cohort uuid DEFAULT NULL::uuid, p_protocol text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 if p_protocol is distinct from 'provider-description-reserve-v1' then return jsonb_build_object('idle',true,'reason','worker_protocol_required','items','[]'::jsonb); end if;
 if p_cohort is not null then return public.svc_provider_description_cohort_next(p_limit,p_cohort); end if;
 perform set_config('cf.pdesc_worker_protocol',p_protocol,true);
 return public.svc_provider_description_next(p_limit);
end $function$
