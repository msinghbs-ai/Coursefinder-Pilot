-- live since v2.15.404 (migration 20261102070000): live md5 07b6387d6a30be8a0f86b90b602b6d08
create or replace function security.ai_use_allowed_v1(p_use text) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
begin
  -- Decision 5 E-7 (2 Nov 2026): one rule for every lane (credit floor, daily ceiling, lane guard), in security.ai_use_refusal_v1
  return security.ai_use_refusal_v1(p_use) is null;
end $function$;
