-- CF-247 s965 (Lane 2 S2-Data-Destination-Continuous; Platform Admin 22 Nov 2026 00:11 AEDT, IR-008 approved: RM1I living costs from
-- Migration Tasmania, Tasmania-wide, into draft figures at $0, attributed to Migration Tasmania, ready for the Platform Admin's terms sign-off).
--
-- Source (read 22 Nov 2026 00:20 AEDT as plain HTML, $0, no Firecrawl, no AI): Migration Tasmania (Tasmanian Government), "Live in Tasmania",
-- https://www.migration.tas.gov.au/live_and_work/live_in_tasmania (page last updated 28 July 2026). Verbatim:
--   "All the costs below are approximate only and in Australian Dollars (AUD)."
--   "If you are renting a whole house you could expect to pay around $550 a week. If you are living in shared accommodation or renting a single
--    room expect to pay $150-$250 a week."
--   "Other weekly expenses may include. Utility bills (water, electricity, gas) –$30-$50 . Internet – $15 to $25 . Phone –$25-$35 . Public transport
--    –$20-$45 . Grocery items – $70-$150 . Food and entertainment (eating out, watching movies etc.) – $50-$150"
-- The figures are Tasmania-wide: they are written as draft living-cost figures for every Tasmanian locality the platform holds (ABS Significant
-- Urban Areas whose code starts with the Tasmanian state digit 6, read from destination.localities, not a list), each labelled Tasmania-wide.
-- Weekly ranges keep their original interval and currency; each range is two figures (low and high); "around $550" is one figure.
-- Status draft: the Platform Admin signs the terms off and approves the edition with admin_destination_figures_bulk_approve. Nothing is approved here.
-- Nothing is dropped or deleted. G3 (75/48) untouched.
-- Replaces: nothing.
-- Retires: nothing.

do $g$ begin
  if (select (security.consumer_api_check_v1()->>'functions')::int) <> 75 or (select (security.consumer_api_check_v1()->>'relations')::int) <> 48
     or jsonb_array_length(security.consumer_api_check_v1()->'drift') <> 0 then raise exception 'pre-check: consumer API is not 75/48 without drift'; end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'pre-check: manual locks are not 7,585'; end if;
  if not exists (select 1 from destination.localities l where l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code like '6%') then
    raise exception 'pre-check: no Tasmanian locality is held'; end if;
end $g$;

-- the source, in the Layer 1 Register under Australia
insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
select 'web', c.id, 'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania', 'Migration Tasmania: Live in Tasmania (weekly living costs)', 1, 'active',
       jsonb_build_object('layer', 'layer1', 'source_system', 'DESTINATION', 'dataset_class', 'living_cost', 'destination_mode', 'figures',
         'parser', 'Static page; figures read verbatim (approximate weekly ranges, AUD)', 'publisher', 'Migration Tasmania (Tasmanian Government)',
         'licence', 'Tasmanian Government copyright and disclaimer (tas.gov.au/stds/codi.htm); terms to be signed off by the Platform Admin',
         'attribution', 'Living costs: Migration Tasmania, Live in Tasmania (migration.tas.gov.au), Tasmanian Government; approximate, Tasmania-wide.',
         'destination_edition', 'Migration Tasmania weekly living costs (Tasmania-wide), page of 28 Jul 2026', 'operational_surface', 'Destination data',
         'authority_domains', jsonb_build_array('migration.tas.gov.au', 'www.migration.tas.gov.au'),
         'decision', 'Platform Admin 22 Nov 2026 00:11 AEDT (IR-008 approved; Lane 2, s965): Tasmania-wide living costs as draft figures')
  from ref.countries c
 where c.iso_alpha2 = 'AU'
   and not exists (select 1 from pipeline.sources s where s.url = 'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania' and s.metadata->>'source_system' = 'DESTINATION');

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
       verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, auto_ingest, next_verification_at, change_reason)
select s.id, s.metadata->>'publisher', array['migration.tas.gov.au', 'www.migration.tas.gov.au'], 'Static HTML page', 'figures', true, false,
       30, 30, 20, 60, false, null,  -- monthly; variance warn 20%, block 60% (as the other destination sources); not auto-ingested
       'Registered 22 Nov 2026 (20261122100000, s965): RM1I Tasmania-wide weekly living costs, draft figures'
  from pipeline.sources s
 where s.url = 'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania' and s.metadata->>'source_system' = 'DESTINATION'
   and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

-- the draft figures: every Tasmanian locality held, each weekly figure, AUD per week
insert into destination.locality_metrics(locality_id, metric_category, metric_key, numeric_value, unit, currency_code, reference_period,
       dataset_edition, source_url, attribution_text, status, status_reason)
select l.id, 'living_cost', f.metric_key, f.v, 'AUD per week', 'AUD', 'Page last updated 28 Jul 2026 (read 22 Nov 2026)',
       'Migration Tasmania weekly living costs (Tasmania-wide), page of 28 Jul 2026',
       'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania',
       'Living costs: Migration Tasmania, Live in Tasmania (migration.tas.gov.au), Tasmanian Government. Approximate weekly costs for Tasmania as a whole (Tasmania-wide), not specific to ' || l.name || '.',
       'draft', 'Draft (s965, 22 Nov 2026): read verbatim from the page: "' || f.quote || '"'
  from destination.localities l
  cross join (values
    ('rent_whole_house_week',           550, 'If you are renting a whole house you could expect to pay around $550 a week.'),
    ('rent_shared_or_single_room_week_low', 150, 'If you are living in shared accommodation or renting a single room expect to pay $150-$250 a week.'),
    ('rent_shared_or_single_room_week_high', 250, 'If you are living in shared accommodation or renting a single room expect to pay $150-$250 a week.'),
    ('utilities_week_low',               30, 'Utility bills (water, electricity, gas) –$30-$50'),
    ('utilities_week_high',              50, 'Utility bills (water, electricity, gas) –$30-$50'),
    ('internet_week_low',                15, 'Internet – $15 to $25'),
    ('internet_week_high',               25, 'Internet – $15 to $25'),
    ('phone_week_low',                   25, 'Phone –$25-$35'),
    ('phone_week_high',                  35, 'Phone –$25-$35'),
    ('public_transport_week_low',        20, 'Public transport –$20-$45'),
    ('public_transport_week_high',       45, 'Public transport –$20-$45'),
    ('groceries_week_low',               70, 'Grocery items – $70-$150'),
    ('groceries_week_high',             150, 'Grocery items – $70-$150'),
    ('food_entertainment_week_low',      50, 'Food and entertainment (eating out, watching movies etc.) – $50-$150'),
    ('food_entertainment_week_high',    150, 'Food and entertainment (eating out, watching movies etc.) – $50-$150')
  ) f(metric_key, v, quote)
 where l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code like '6%'
on conflict (locality_id, metric_key, reference_period, dataset_edition) do nothing;

-- post-checks
do $p$ declare v_loc int; v_rows int; begin
  select count(*) into v_loc from destination.localities l where l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code like '6%';
  select count(*) into v_rows from destination.locality_metrics m
   where m.dataset_edition = 'Migration Tasmania weekly living costs (Tasmania-wide), page of 28 Jul 2026' and m.status = 'draft'
     and m.numeric_value is not null and nullif(btrim(m.attribution_text), '') is not null;
  if v_rows <> 15 * v_loc then raise exception 'post-check: expected % draft figures (15 for each of % Tasmanian localities), found %', 15 * v_loc, v_loc, v_rows; end if;
  if exists (select 1 from destination.locality_metrics m where m.dataset_edition = 'Migration Tasmania weekly living costs (Tasmania-wide), page of 28 Jul 2026' and m.status <> 'draft') then
    raise exception 'post-check: a figure is not draft'; end if;
  if (select count(*) from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
       where s.url = 'https://www.migration.tas.gov.au/live_and_work/live_in_tasmania') <> 1 then raise exception 'post-check: the source is not registered'; end if;
  if (select (security.consumer_api_check_v1()->>'functions')::int) <> 75 or (select (security.consumer_api_check_v1()->>'relations')::int) <> 48
     or jsonb_array_length(security.consumer_api_check_v1()->'drift') <> 0 then raise exception 'post-check: consumer API is not 75/48 without drift'; end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks are not 7,585'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active jobs'; end if;
  raise notice 's965: % draft living-cost figures for % Tasmanian localities; G3 75/48; locks 7,585', v_rows, v_loc;
end $p$;
