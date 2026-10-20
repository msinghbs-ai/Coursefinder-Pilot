CREATE OR REPLACE FUNCTION security.enrichment_flags_sync_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(current_setting('cf.flag_fn', true), '') = '1' then new.updated_at := now(); return new; end if;  -- the flag functions keep their own state
  if tg_op = 'INSERT' then
    new.state := case when new.cleared_at is null then 'raised' else 'released' end;
    if new.state = 'released' then new.released_at := new.cleared_at; new.release_kind := 'auto'; new.released_by := new.source; end if;
  elsif new.cleared_at is distinct from old.cleared_at then
    if new.cleared_at is null then
      if old.release_kind = 'person' then new.cleared_at := old.cleared_at; return new; end if;  -- a person's release stands against automatic re-raising
      new.state := 'raised'; new.tries := old.tries + 1; new.released_at := null;
    else
      new.state := 'released'; new.released_at := new.cleared_at; new.release_kind := coalesce(new.release_kind, 'auto'); new.released_by := coalesce(new.released_by, new.source);
    end if;
  end if;
  new.updated_at := now();
  return new;
end $function$
