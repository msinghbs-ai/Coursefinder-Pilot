-- CF-247 s1043 (S1-Scholarship-Claude; Platform Admin brief 24 Nov 2026 14:53 AEDT: widen the Adelaide scholarship host, register the Charles Darwin international hub):
-- Adelaide University's scholarship pages sit on adelaide.edu.au while its provider website is adelaideuni.edu.au, so security.url_on_provider_sites refused them for
-- scholarships (s1038 added the alias for AER only). Charles Darwin's eight bold-label international awards sit on /international/scholarships, which s1037 now splits.
-- Measured live 24 Nov 2026 14:50 AEDT (read-only): scholarship_discovery_providers allowed_hosts is empty for Adelaide (website and site_origin adelaideuni.edu.au);
-- Adelaide has two suggested listing rows (adelaide.edu.au/study/scholarships, /int) and one failed row (research scholarships, waiting_scraper); the Charles Darwin international
-- listing pages were last read 23 Nov 08:22 (before the s1037 splitter) with 2 link items each.
-- Changes (data only, idempotent):
-- 1. pipeline.scholarship_discovery_providers.allowed_hosts for Adelaide University gains adelaide.edu.au (the host check reads this list; no function changed).
-- 2. Adelaide's scholarship hub https://adelaide.edu.au/study/scholarships/ is registered (manual, waiting) and its suggested row is activated; its failed row is retried.
-- 3. Charles Darwin's /international/scholarships and /international/how-apply/scholarships are registered (manual, waiting) and read now, so the s1037 splitter reads the awards.
-- Replaces: nothing
-- Retires: nothing
-- Consumer API change approved: none (G3 untouched). No lock, cron job or admitted record is touched; $0 (plain-HTTP direct reads, no Firecrawl, no model).

create temp table s1043_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1043_cron on commit drop as select count(*) n from cron.job where active;

do $a$
declare
  v_ade uuid; v_cdu uuid; v_url text; v_n int;
begin
  select id into v_ade from catalogue.providers where stable_key = 'provider:cricos:04249j';
  select id into v_cdu from catalogue.providers where stable_key = 'provider:cricos:00300k';
  if v_ade is null or v_cdu is null then raise exception 'guard: Adelaide or Charles Darwin provider not found'; end if;

  -- 1. Adelaide host for scholarships
  update pipeline.scholarship_discovery_providers set allowed_hosts = coalesce(allowed_hosts, '{}') || array['adelaide.edu.au']
   where provider_id = v_ade and not ('adelaide.edu.au' = any (coalesce(allowed_hosts, '{}')));
  get diagnostics v_n = row_count;
  if v_n > 1 then raise exception 'guard: % discovery rows changed', v_n; end if;
  if not security.url_on_provider_sites('https://adelaide.edu.au/study/scholarships/', v_ade) then raise exception 'post-check: adelaide.edu.au is still not on the provider sites'; end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'allow_host', v_ade::text, jsonb_build_object('host', 'adelaide.edu.au', 'reason', 'Platform Admin 24 Nov 2026 14:53: Adelaide scholarship pages on adelaide.edu.au (s1043, matching s1038 for AER)', 'migration', '20261124173000'), security.system_actor_id());

  -- 2. Adelaide hub registered, suggested row activated, failed rows retried
  v_url := 'https://adelaide.edu.au/study/scholarships/';
  insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
  values (v_ade, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', null, security.system_actor_id())
  on conflict (provider_id, url_norm) do update set active = true, next_read_at = null,
     source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
     status = case when pipeline.scholarship_listing_pages.status in ('suggested', 'failed') then 'waiting' else pipeline.scholarship_listing_pages.status end;
  update pipeline.scholarship_listing_pages set status = 'waiting', next_read_at = null
   where provider_id = v_ade and active and status = 'failed' and error = 'waiting_scraper';
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'add_listing', v_ade::text, jsonb_build_object('url', v_url, 'reason', 'Platform Admin 24 Nov 2026 14:53: Adelaide scholarship hub (s1043)', 'migration', '20261124173000'), security.system_actor_id());

  -- 3. Charles Darwin international hubs registered and read now
  foreach v_url in array array['https://www.cdu.edu.au/international/scholarships', 'https://www.cdu.edu.au/international/how-apply/scholarships'] loop
    if not security.url_on_provider_sites(v_url, v_cdu) then raise exception 'guard: % is not on the provider''s own website', v_url; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (v_cdu, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', null, security.system_actor_id())
    on conflict (provider_id, url_norm) do update set active = true, next_read_at = null, status = 'waiting';
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scholarship_coverage', 'read_now', v_cdu::text, jsonb_build_object('url', v_url, 'reason', 'Platform Admin 24 Nov 2026 14:53: Charles Darwin international awards through the s1037 splitter (s1043)', 'migration', '20261124173000'), security.system_actor_id());
  end loop;
end $a$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1043_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1043_cron) then raise exception 'post-check: active cron jobs changed'; end if;
end $c$;
