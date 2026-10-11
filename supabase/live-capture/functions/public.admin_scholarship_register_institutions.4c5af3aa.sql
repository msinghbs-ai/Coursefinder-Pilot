CREATE OR REPLACE FUNCTION public.admin_scholarship_register_institutions(p_register text, p_provider_ids uuid[], p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r scholarship.registers; v_bad int; v_out jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from scholarship.registers where code = p_register and role = 'record';
  if r.code is null then raise exception 'not a record register: %', p_register; end if;
  select count(*) into v_bad from unnest(coalesce(p_provider_ids,'{}')) x
   where not exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = x and c.iso_alpha2 = r.country_code and p.lifecycle_status = 'active');
  if v_bad > 0 then raise exception '% provider(s) are not active providers in %', v_bad, r.country_code; end if;
  update scholarship.registers set provider_ids = (select array_agg(distinct x) from unnest(r.provider_ids || coalesce(p_provider_ids,'{}')) x), updated_at = now()
   where code = p_register;
  v_out := public.svc_scholarship_register_record_profile(p_register);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'register_institutions_set', p_register, jsonb_build_object('added', to_jsonb(p_provider_ids), 'reason', left(p_reason, 500), 'profile', v_out), auth.uid());
  return v_out;
end $function$
