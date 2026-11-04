CREATE OR REPLACE FUNCTION security.provider_onboarding_new_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.lifecycle_status = 'active' and coalesce((select s.auto_start_new from pipeline.provider_onboarding_settings s where s.id = 1), false) then
    insert into pipeline.provider_onboarding(provider_id, source, reason, priority) values (new.id, 'new_provider', 'Added to the catalogue', 100)
    on conflict do nothing;
  end if;
  return new;
end $function$

