CREATE OR REPLACE FUNCTION public.admin_scholarship_country(p_country_code text, p_on boolean, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_refill jsonb; v_cc text := upper(btrim(coalesce(p_country_code, '')));
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from security.scholarship_country_readiness_v1() x where x.country_code = v_cc;
  if r.country_code is null then raise exception 'country % has no onboarding entry, courses or switch', v_cc; end if;
  if p_on and not r.ready then raise exception 'country % is not ready: %', v_cc, array_to_string(r.missing, '; '); end if;
  update ref.countries set scholarship_ingestion_enabled = p_on where iso_alpha2 = v_cc;
  update scholarship.country_onboarding set status = case when p_on then 'enabled' else 'watch' end, decided_by = auth.uid(), decided_at = now(),
         reason = left(p_reason, 500), updated_at = now() where country_code = v_cc;
  if p_on then v_refill := security.scholarship_discovery_refill_v1(30 + coalesce(r.universities, 0)::int); end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', case when p_on then 'scholarship_country_on' else 'scholarship_country_off' end, v_cc,
          jsonb_build_object('reason', left(p_reason, 500), 'readiness', to_jsonb(r), 'discovery', v_refill), auth.uid());
  perform security.scholarship_country_watch_v1();
  return jsonb_build_object('ok', true, 'country', v_cc, 'switched_on', p_on, 'discovery', v_refill);
end $function$
