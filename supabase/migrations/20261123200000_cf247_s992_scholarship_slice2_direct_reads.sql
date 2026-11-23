-- CF-247 s992 (S2-Build, scholarships owner; Platform Admin 23 Nov 2026 15:39, 17:45 and 17:49 AEDT: "Run Slice 2 ($0 direct read of Charles
-- Darwin and Lincoln listing pages) to lift both off 0 published scholarships"; queue rows claimed by admin #826).
-- Measured live 23 Nov 2026 16:40 to 17:55 AEDT (rolled-back read-backs; head 20261123170000):
-- - Charles Darwin University: 0 published. Its finder (stapps.cdu.edu.au/apex/f?p=1000:600) is an APEX app that lists nothing without a browser
--   session (read 20 Nov: 0 items). Its international awards are on server-rendered official pages that are not listing sources:
--   /international/how-apply/scholarships (CDU Global Merit Scholarship and the other international awards) and /international/scholarships
--   (CDU International College awards). The Vice-Chancellor's High Achievers record is held for want of a stated value.
-- - Lincoln University: 0 published (the CSC PhD award is closed). Its international page (listing source #10) prints the Flagship and automatic
--   master's awards in sections; its next read is 15 Dec.
-- - Listing pages are read through the scraper first (coverage-sweep, rendered catalogues), and the scholarship Firecrawl lane is refused
--   (S3 s976: firecrawl.daily_budget_total = 0 refuses scheduled and on-demand spend). While the lane is held the picker took only items with a
--   stored copy (lanes.stored_first_on, 3 Nov 2026), although since 12 Nov the worker reads every scholarship page directly first and an item it
--   cannot read directly gives its try back and waits (retry.sch_ai_wait_minutes); 39 admit items had waited since 03:21 AEDT.
-- Changes (the worker part is coverage-sweep worker v1.0.35 in the same release: a listing page is read directly first, used when it gives at
-- least one item or award section, otherwise the scraper as before):
-- 1. lanes.stored_first_on 1 -> 0 (Platform Admin 17:49: copy-less pages are taken and read directly). The setting is read only by the three
--    scholarship lanes (security.scholarship_ai_fire_v1, public.svc_scholarship_ai_next, public.svc_scholarship_recheck_next). Firecrawl stays
--    governed by public.svc_fc_spend: with the daily total at 0 every fallback is refused, so the change is $0.
-- 2. The two Charles Darwin international pages become listing sources (source 'manual', the same row the Add listing page action writes,
--    checked to be on the provider's own website), read first: next_read_at null, which the listing picker takes first (order next_read_at nulls
--    first); 367 sources are due and the lane reads about 36 pages an hour, so a source set to now() would wait about 10 hours.
-- 3. Lincoln's international listing source (#10) is read first the same way, so it is read with the direct-first reader.
-- G1: no job. G2: no new value (existing setting). G3: no consumer object (75/48 before and after). Manual locks untouched. $0 Firecrawl; AI only
-- through the existing scheduled extraction within its ceiling. Nothing dropped or removed.
-- Replaces: the scholarship stored-first rule while the Firecrawl lane is held (now direct reads); the scraper-first listing read (worker v1.0.35).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the setting and listing rows

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if security.fc_setting_num_v1('daily_budget_total', 15000) <> 0 then
    raise exception 'guard: the Firecrawl daily total is not 0, so a direct-read fallback could spend; this change assumes S3 s976 hard zero';
  end if;
end $g$;
create temp table s992_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- 1. copy-less scholarship pages are taken and read directly while the Firecrawl lane is held
update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(),
       reason = 'CF-247 s992 (Platform Admin 23 Nov 2026 17:49): scholarship pages without a stored copy are read directly ($0) while the Firecrawl lane is held; Firecrawl stays governed by svc_fc_spend'
 where toolset_key = 'pipeline' and key = 'lanes.stored_first_on' and value = to_jsonb(1);
insert into pipeline.admin_control_events (area, action, target, detail, actor)
values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'lanes.stored_first_on', 'before', 1, 'after', 0,
        'reason', 'Platform Admin 23 Nov 2026 17:49: direct reads for scholarship pages without a stored copy (s992)', 'migration', '20261123200000'), security.system_actor_id());

-- 2 and 3. Charles Darwin's international pages as listing sources; Lincoln's international source read now
do $l$
declare v_cdu uuid := '6f5cb7f7-7c70-4c06-970f-f368c3a786e2'; v_lin uuid := '248374d1-0629-41cd-a6f4-0804c422a4ff'; v_url text;
begin
  foreach v_url in array array['https://www.cdu.edu.au/international/how-apply/scholarships', 'https://www.cdu.edu.au/international/scholarships'] loop
    if not security.url_on_provider_sites(v_url, v_cdu) then raise exception 'guard: % is not on the provider''s own website', v_url; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (v_cdu, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', null, security.system_actor_id())
    on conflict (provider_id, url_norm) do update set active = true, next_read_at = null,
       source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
       status = case when pipeline.scholarship_listing_pages.status = 'suggested' then 'waiting' else pipeline.scholarship_listing_pages.status end;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scholarship_coverage', 'add_listing', v_cdu::text, jsonb_build_object('url', v_url, 'reason', 'Platform Admin 23 Nov 2026 17:49: Charles Darwin international awards (s992)', 'migration', '20261123200000'), security.system_actor_id());
  end loop;
  update pipeline.scholarship_listing_pages set next_read_at = null
   where provider_id = v_lin and url_norm = security.scholarship_url_norm('https://www.lincoln.ac.nz/study/scholarships/international-scholarships') and active;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'read_now', v_lin::text, jsonb_build_object('url', 'https://www.lincoln.ac.nz/study/scholarships/international-scholarships', 'reason', 'Platform Admin 23 Nov 2026 17:49: Lincoln international awards (s992)', 'migration', '20261123200000'), security.system_actor_id());
end $l$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s992_locks) then raise exception 'post-check: manual locks changed'; end if;
  if security.pipeline_num_v1('lanes.stored_first_on', 1) <> 0 then raise exception 'post-check: lanes.stored_first_on is not 0'; end if;
  if (select count(*) from pipeline.scholarship_listing_pages where provider_id = '6f5cb7f7-7c70-4c06-970f-f368c3a786e2' and active and url_norm in
      (security.scholarship_url_norm('https://www.cdu.edu.au/international/how-apply/scholarships'), security.scholarship_url_norm('https://www.cdu.edu.au/international/scholarships'))) <> 2 then
    raise exception 'post-check: the Charles Darwin listing sources are not both active';
  end if;
end $p$;
