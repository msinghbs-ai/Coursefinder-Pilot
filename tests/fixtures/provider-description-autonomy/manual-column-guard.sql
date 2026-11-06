-- Guards: Provider Description mandate §8–9: exact production campus manual-lock trigger dependency.
CREATE OR REPLACE FUNCTION security.manual_column_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new jsonb; v_old jsonb; f text; v_entity text := TG_ARGV[0];
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then return NEW; end if;
  if not exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id) then return NEW; end if;
  v_new := to_jsonb(NEW); v_old := to_jsonb(OLD);
  for f in select l.field from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id loop
    if v_old ? f then v_new := jsonb_set(v_new, array[f], v_old->f); end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_new);
  return NEW;
end $function$;
revoke all on function security.manual_column_guard() from public,anon,authenticated,service_role;
