-- CF-247 (11 Oct 2026, Platform Admin: "Always use scraper for Scholarships ... use the evidence read like courses to read
-- scholarship asap. This can be controlled via ui"). Scholarship pages and provider listing pages are read through the scraper
-- (Firecrawl, rendered page) first, for every provider, while the new Layer 2 setting "Read scholarship pages through the scraper"
-- is on; a direct read is the fallback. The worker (coverage-sweep v0.17.40) reads the setting with its credit budget.
-- The scholarship credit cap goes from 6,000 to 12,000 (about 2,000 were left; one full pass is about 1,600), and every active
-- scholarship page and listing page is queued to be read again now. Nothing is dropped or deleted; md5-checked before and after.
do $guard$
declare v_expected jsonb := '{"public.svc_scholarship_fc_budget()": "2faa5eac7d0703f160d7931ca42eacf8"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_fc_budget()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
    'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
    'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
    -- 11 Oct 2026: read scholarship pages through the scraper first (1 = on, 0 = off)
    'scraper', coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = 'read_via_scraper'), 1));
end $function$;

-- 1. The switch, on the scholarship settings (Layer 2): Scholarships > Coverage > Settings and jobs, and Scholarships > Layer 2
insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit, updated_at, reason)
values ('read_via_scraper', 2, 'Read scholarship pages through the scraper',
        'On: every scholarship page and listing page is read through Firecrawl first (the rendered page, as course pages are read), for every provider, within the scholarship credit cap; a direct read is used only when the scraper cannot be used. Off: pages are read directly and Firecrawl is used only when a site refuses. 1 = on, 0 = off.',
        1, 0, 1, 'on/off', now(), 'Platform Admin 11 Oct 2026: "Always use scraper for Scholarships"')
on conflict (key) do nothing;
update pipeline.scholarship_jobs set setting_keys = setting_keys || array['read_via_scraper']
 where jobname in ('scholarship-read', 'scholarship-listing') and not ('read_via_scraper' = any(setting_keys));

-- 2. Credit cap for scholarship work: 6,000 to 12,000 (the plan has about 450,000 left this period)
update pipeline.scholarship_layer_settings set value = 12000, updated_at = now(),
       reason = 'Platform Admin 11 Oct 2026: scholarships read through the scraper; was 6000'
 where key = 'firecrawl_cap' and value < 12000;

-- 3. Read everything again now through the scraper (oldest first; about 480 pages an hour at 40 a run)
update pipeline.scholarship_pages p set next_read_at = now(), attempts = 0, leased_until = null
  from scholarship.scholarships s
 where s.id = p.scholarship_id and s.lifecycle_status = 'active';
update pipeline.scholarship_listing_pages set next_read_at = now() where active;

do $post$
declare v_expected jsonb := '{"public.svc_scholarship_fc_budget()": "5a58bfd5a6f3001fdb9e1387ed046650"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
