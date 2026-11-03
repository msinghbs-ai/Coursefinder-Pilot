CREATE OR REPLACE FUNCTION security.fc_month_refusal_v1(p_units numeric)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Decision 5 E-8 F2 (2 Nov 2026): why a Firecrawl spend of p_units is refused by the monthly plan limit, or null. The rule is
-- security.layer2_provider_budget_status's: the vendor's balance read in the last 2 hours less the platform's use since (the vendor's own
-- billing period, from the 2nd), otherwise the counted UTC calendar month; refused when what is left after this spend is under
-- billing_config.stop_at_vendor_units_remaining. With a fresh balance it is computed here without the month count, which that function
-- also works out (a whole month of use on every spend); without one, that function answers.
declare p pipeline.layer2_acquisition_providers%rowtype; v_stop numeric; v_unit numeric; v_rem numeric; v_at timestamptz; st jsonb;
begin
  select * into p from pipeline.layer2_acquisition_providers x where x.provider_key = 'firecrawl';
  if p.id is null or nullif(p.billing_config->>'monthly_vendor_units_limit', '') is null then return null; end if;
  select o.remaining_units, o.observed_at into v_rem, v_at from pipeline.vendor_credit_observations o
   where o.provider_id = p.id and o.observed_at > now() - interval '2 hours'  -- fixed: the freshness layer2_provider_budget_status trusts (Decision 253)
   order by o.observed_at desc limit 1;
  if v_at is null then
    st := security.layer2_provider_budget_status(p.id, p_units);
    if coalesce((st->>'allowed')::boolean, true) then return null; end if;
    return format('Firecrawl monthly limit: %s of %s credits left this month (UTC, counted; no vendor balance in the last 2 hours), %s kept in reserve',
                  st->>'remaining_units', st->>'limit_units', st->>'stop_at_remaining_units');
  end if;
  v_stop := coalesce(nullif(p.billing_config->>'stop_at_vendor_units_remaining', '')::numeric, 0);
  v_unit := coalesce(nullif(p.request_template->>'fixed_credit_units', '')::numeric, 1);
  v_rem := greatest(v_rem
    - coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.acquisition_provider_id = p.id and u.at > v_at), 0)
    - (select count(*)::numeric * v_unit from pipeline.layer2_provider_attempts a where a.acquisition_provider_id = p.id and a.started_at > v_at), 0);
  if v_rem - greatest(coalesce(p_units, v_unit), 0) >= v_stop then return null; end if;
  return format('Firecrawl monthly limit: about %s credits left on the plan (vendor balance read %s less use since), %s kept in reserve',
                v_rem, to_char(v_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), v_stop);
end $function$
