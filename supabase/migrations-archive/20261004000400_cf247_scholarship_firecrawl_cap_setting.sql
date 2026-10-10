-- CF-247 (4 Oct 2026, 02:10 AEST). Platform Admin, 01:57: "Show the credit cap in layer 2 that can [be] maintain[ed] in
-- UI ... UI needs complete control of variable no hard coding in the scripts or code." Decision 251 (continued).
-- Found: the scholarship Firecrawl cap (3,000 credits, all time) and the reserve kept for re-reading held scholarships'
-- pages (800) were constants in the coverage-sweep worker; 2,685 of the 3,000 were used, so pages that refuse a direct
-- read were no longer retried.
--   1. Two Layer 2 settings: firecrawl_cap and firecrawl_reserve (values unchanged: 3,000 and 800).
--   2. public.svc_scholarship_fc_budget(): the worker reads cap, reserve and credits used from here each run (service
--      role only). If it cannot be read, the worker spends nothing on scholarships.
--   3. Layer 2 › Scholarships shows credits used, left, the reserve and use by purpose over 7 days.

insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit, reason) values
  ('firecrawl_cap', 2, 'Firecrawl credits for scholarships (all time)', 'Scholarship work (mapping university sites, searching and reading pages that refuse a direct read) stops using Firecrawl once this many credits have been used in total. The Firecrawl account''s own limit still applies.', 3000, 0, 100000, 'credits', 'Constant in the worker until 4 Oct 2026'),
  ('firecrawl_reserve', 2, 'Credits kept for re-reading held scholarships', 'Newly found pages that refuse a direct read are read through Firecrawl only while more than this many scholarship credits are left; the rest is kept for re-reading the pages of scholarships we already hold.', 800, 0, 10000, 'credits', 'Constant in the worker until 4 Oct 2026')
on conflict (key) do nothing;

create or replace function public.svc_scholarship_fc_budget() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
    'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
    'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'));
end $f$;
revoke all on function public.svc_scholarship_fc_budget() from public, anon, authenticated;
grant execute on function public.svc_scholarship_fc_budget() to service_role;

do $g$ declare v_oid oid := 'public.admin_scholarship_layer_read(int)'::regprocedure; v_def text; o text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '1591c16ac9a21ed5d93db250405833f3' then raise exception 'admin_scholarship_layer_read changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$      from ref.countries k where k.scholarship_ingestion_enabled and exists (select 1 from catalogue.providers p where p.country_id = k.id)),$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o);
  if c <> 1 then raise exception 'layer 2 snippet found % times', c; end if;
  v_def := replace(v_def, o, o || $x$
      'firecrawl', jsonb_build_object(
        'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
        'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
        'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
        'by_purpose', (select coalesce(jsonb_object_agg(z.purpose, jsonb_build_object('all', z.n, 'last_7_days', z.n7)), '{}'::jsonb)
                         from (select u.purpose, sum(u.units) n, coalesce(sum(u.units) filter (where u.at > now() - interval '7 days'), 0) n7 from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape') group by 1) z)),$x$);
  execute v_def;
end $g$;
