CREATE OR REPLACE FUNCTION security.lane_paid_hold_v1(p_purpose text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §6: why new paid reading for this Firecrawl purpose is held now, or null. The same rules as the spend
-- check: the monthly plan reserve (security.fc_month_refusal_v1) and today's share for the purpose's group (security.fc_budget_left_v1).
declare v text;
begin
  if p_purpose is null then return null; end if;
  v := security.fc_month_refusal_v1(1);  -- fixed: one credit, the smallest spend
  if v is not null then return 'budget_held: ' || v; end if;
  if security.fc_budget_left_v1(p_purpose) < 1 then  -- fixed: one credit, the smallest spend
    return 'budget_held: no room left in today''s Firecrawl share for ' || security.fc_purpose_group_v1(p_purpose);
  end if;
  return null;
end $function$
