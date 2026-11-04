CREATE OR REPLACE FUNCTION security.provider_site_followups_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if nullif(btrim(NEW.website), '') is null then
    if TG_OP = 'INSERT' then
      insert into pipeline.coverage_provider_discovery(provider_id, status, requested_at, updated_at) values (NEW.id, 'no_website', now(), now())
      on conflict (provider_id) do nothing;
    end if;
  elsif TG_OP = 'INSERT' or nullif(btrim(OLD.website), '') is distinct from nullif(btrim(NEW.website), '') then
    insert into pipeline.provider_central_search(provider_id, state, requested_at) values (NEW.id, 'queued', now())
    on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, updated_at = now() where pipeline.provider_central_search.state <> 'leased';
  end if;
  return null;
end $function$

