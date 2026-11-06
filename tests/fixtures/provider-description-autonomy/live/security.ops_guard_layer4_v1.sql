CREATE OR REPLACE FUNCTION security.ops_guard_layer4_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- While a remedy runs a Layer 4 item may only stay pending or be superseded (duplicate reconciliation); approving, rejecting, returning or
-- deleting is a decision (mandate §10: technical repair authority is not admission authority).
begin
  if TG_OP = 'DELETE' or new.status not in ('pending', 'superseded') or (TG_OP = 'UPDATE' and old.status <> 'pending' and new.status is distinct from old.status) then
    raise exception 'ops guard: a remedy cannot decide or admit a Layer 4 item' using errcode = '42501';
  end if;
  return new;
end $function$

