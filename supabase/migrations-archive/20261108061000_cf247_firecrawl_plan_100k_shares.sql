-- CF-247 Firecrawl plan raised to 100,000 credits a month: the platform's plan record and daily shares are re-sized from the 500,000-credit plan they were sized for.
-- Guards: the account owner's instruction (chat, Sun 8 Nov 2026 12:06 and 12:09 Melbourne: Standard plan, 100,000 credits a month, $99 a month, billing period 8 Nov to 8 Dec 2026, credits remaining 100,251 of 100,000; the vendor balance reading confirms it),
--   Platform Admin Firecrawl priority order 8 Nov 2026 (AER entry pages and reads first, then English / provider facts, scholarships, course search last), G2 (every value
--   stays a setting inside its range), G3 (no consumer API object, table or column is touched), Decision 260 (housekeeping), "nothing is dropped or deleted by an applied migration".
-- Replaces: nothing
-- Retires: nothing
--
-- What this changes (each change only while the current value still equals the old value it was written against; otherwise a notice and no change; a second run says "already applied"):
--   1. pipeline.layer2_acquisition_providers (provider_key firecrawl).billing_config: monthly_vendor_units_limit 500000 -> 100000, plan_tier 'growth_500k' -> 'standard_100k',
--      plan_note -> 'Standard plan, 100,000 credits a month ($99 a month), billing period 8 Nov to 8 Dec 2026, as shown on the Firecrawl billing page by the account owner on 8 Nov 2026 12:09 (the vendor balance reading confirms)'. Every other key
--      (stop_at_vendor_units_remaining 0, safety_reserve_percent 2, no_silent_paid_fallback, entitlement_basis, plan_confirmed_at, ...) is left as it is.
--   2. Daily shares (settings firecrawl / daily_*), in the Platform Admin's priority order, adding up to the day's total:
--        daily_budget_total              25000 -> 4000
--        daily_share_central              2500 -> 1000   (AER entry pages, English policy, provider facts)
--        daily_share_reads                5000 -> 1200
--        daily_share_scholarships         3500 -> 800
--        daily_share_course_search       13000 -> 800    (lowest priority; the priority floor from migration 20261108060000 also keeps credits back from it)
--        daily_share_other                1000 -> 200
-- Not changed: subscription_cost_usd, monetary_cost_basis, unit_cost_usd, usd_per_1k_credits and ops_cost.* (cost reporting is a separate decision), stop_at_vendor_units_remaining, the priority floor setting, schedules, lanes, any other setting; nothing is switched on or off.
-- Audit: one event per change in pipeline.admin_control_events (area firecrawl; action plan_limit for the plan record, daily_shares for each share), with the values before and after.

do $apply$
declare
  v_reason constant text := 'account owner moved the plan to the Standard 100,000 credits a month, 8 Nov 2026';
  v_note constant text := 'Standard plan, 100,000 credits a month ($99 a month), billing period 8 Nov to 8 Dec 2026, as shown on the Firecrawl billing page by the account owner on 8 Nov 2026 12:09 (the vendor balance reading confirms)';
  v_bc jsonb; v_id uuid; v_n int; r record; v_set pipeline.platform_toolset_settings%rowtype;
begin
  -- 1. the plan record --------------------------------------------------------------------------------------------------------------------------
  select p.id, p.billing_config into v_id, v_bc from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl';
  if v_id is null then raise notice 'plan record: provider firecrawl not found; nothing changed';
  elsif v_bc->>'monthly_vendor_units_limit' = '100000' and v_bc->>'plan_tier' = 'standard_100k' and v_bc->>'plan_note' = v_note then
    raise notice 'plan record: already applied';
  elsif v_bc->>'monthly_vendor_units_limit' = '500000' and v_bc->>'plan_tier' = 'growth_500k' then
    update pipeline.layer2_acquisition_providers
       set billing_config = jsonb_set(jsonb_set(jsonb_set(billing_config, '{monthly_vendor_units_limit}', '100000'::jsonb), '{plan_tier}', '"standard_100k"'::jsonb), '{plan_note}', to_jsonb(v_note)),
           updated_at = now()
     where id = v_id and billing_config->>'monthly_vendor_units_limit' = '500000' and billing_config->>'plan_tier' = 'growth_500k';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'plan record: updated %, expected 1', v_n; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('firecrawl', 'plan_limit', 'pipeline.layer2_acquisition_providers/firecrawl/billing_config',
            jsonb_build_object('reason', v_reason, 'migration', '20261108061000',
                               'before', jsonb_build_object('monthly_vendor_units_limit', 500000, 'plan_tier', 'growth_500k', 'plan_note', v_bc->>'plan_note'),
                               'after', jsonb_build_object('monthly_vendor_units_limit', 100000, 'plan_tier', 'standard_100k', 'plan_note', v_note),
                               'unchanged', jsonb_build_array('stop_at_vendor_units_remaining', 'safety_reserve_percent', 'no_silent_paid_fallback')), null);
    raise notice 'plan record: applied';
  else
    raise notice 'plan record: the current values are not (500000, growth_500k) (limit %, tier %); nothing changed', v_bc->>'monthly_vendor_units_limit', v_bc->>'plan_tier';
  end if;

  -- 2. the daily shares -------------------------------------------------------------------------------------------------------------------------
  for r in select * from (values ('daily_budget_total', 25000, 4000), ('daily_share_central', 2500, 1000), ('daily_share_reads', 5000, 1200),
                                 ('daily_share_scholarships', 3500, 800), ('daily_share_course_search', 13000, 800), ('daily_share_other', 1000, 200)) t(k, old_v, new_v) loop
    select * into v_set from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = r.k;
    if v_set.key is null then raise notice '%: setting not found; nothing changed', r.k;
    elsif v_set.value = to_jsonb(r.new_v) then raise notice '%: already applied', r.k;
    elsif v_set.value <> to_jsonb(r.old_v) then raise notice '%: the current value is % (not %); nothing changed', r.k, v_set.value, r.old_v;
    elsif r.new_v < coalesce(v_set.min_value, r.new_v) or r.new_v > coalesce(v_set.max_value, r.new_v) then raise notice '%: % is outside the range % to %; nothing changed', r.k, r.new_v, v_set.min_value, v_set.max_value;
    else
      update pipeline.platform_toolset_settings set value = to_jsonb(r.new_v), updated_at = now(), reason = v_reason
       where toolset_key = 'firecrawl' and key = r.k and value = to_jsonb(r.old_v);
      get diagnostics v_n = row_count;
      if v_n <> 1 then raise exception '%: updated %, expected 1', r.k, v_n; end if;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('firecrawl', 'daily_shares', 'firecrawl/' || r.k, jsonb_build_object('reason', v_reason, 'migration', '20261108061000', 'before', r.old_v, 'after', r.new_v), null);
      raise notice '%: applied (% -> %)', r.k, r.old_v, r.new_v;
    end if;
  end loop;
end $apply$;
