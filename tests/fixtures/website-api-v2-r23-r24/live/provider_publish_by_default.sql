CREATE OR REPLACE FUNCTION security.provider_publish_by_default()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.lifecycle_status = 'active' then new.publication_status := 'published'; end if;
  return new;
end $function$
