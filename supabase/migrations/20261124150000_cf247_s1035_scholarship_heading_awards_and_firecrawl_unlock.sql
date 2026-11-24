-- CF-247 s1035 (S2-Scholarship-Readers, Platform Admin 24 Nov 2026 13:08 AEDT: "Platform leadership has lifted all artificial budget/toolset gates on reader building for Scholarships ... Firecrawl credits freely").
-- Measured live 24 Nov 2026 13:05 (rolled-back read-back, head 20261124140000): firecrawl.daily_budget_total = 5, so svc_fc_spend refuses every render (scholarship listing pages of
-- Adelaide, Notre Dame, Lincoln and Monash sit at error waiting_scraper); award headings with no code and no link are dropped when a listing is recorded.
-- Changes (the worker part is coverage-sweep catalogue.ts and scholarship.ts, deployed in the same release; the worker file index.ts is unchanged):
-- 1. Heading awards: a page that prints several awards under headings (no code, no page of their own) is split by heading (scholarship.ts headingAwardSections). Its key is
--    "S-<SLUG>" and its section address "<page>#award-s-<slug>". Two live functions accept that key beside the four-letter-four-digit code (md5-guarded, one anchored edit each):
--    public.svc_scholarship_listing_record_v2 (listing members) and security.scholarship_admit_from_provider_page_v1 (section address kept as the record's own address).
-- 2. Firecrawl: firecrawl.daily_budget_total 5 -> 1500 credits a day (the plan of s903 was 4,000; scholarship share 1,500), reason recorded (G2, Settings > Toolsets & limits). svc_fc_spend
--    still enforces the total and its shares; nothing in code changes. Every call is logged by svc_fc_spend; the usage is reported after each batch.
-- 3. Batch 1 hubs are read now: every active listing page of the Batch 1 universities gets next_read_at null (the picker takes those first).
-- G1: no job. G2: the only value is the existing setting. G3: no consumer object (75/48 before and after). Manual locks untouched. Nothing dropped or removed.
-- Replaces: nothing (two live functions edited in place, md5-guarded)
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the setting and listing rows

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1035_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- 1. heading award keys in the two live functions
do $f$
declare
  v_rec regprocedure := 'public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)'::regprocedure;
  v_adm regprocedure := 'security.scholarship_admit_from_provider_page_v1(bigint)'::regprocedure;
  v_def text;
  a1 text := 'elsif v_code ~ ''^[A-Z]{4}[0-9]{4}$'' then';
  b1 text := 'elsif v_code ~ ''^[A-Z]{4}[0-9]{4}$'' or v_code ~ ''^S-[A-Z0-9-]{3,60}$'' then';
  a2 text := 'c.url_norm ~ ''#award-[a-z]{4}[0-9]{4}$''';
  b2 text := 'c.url_norm ~ ''#award-([a-z]{4}[0-9]{4}|s-[a-z0-9-]{3,60})$''';
begin
  v_def := pg_get_functiondef(v_rec);
  if strpos(v_def, b1) = 0 then
    if md5(v_def) <> '97b5f8cefd83b74c7e09f27a391ab69c' then raise exception 'guard: svc_scholarship_listing_record_v2 changed since the live read-back; rebase and re-verify'; end if;
    if (length(v_def) - length(replace(v_def, a1, ''))) <> length(a1) then raise exception 'guard: listing record anchor absent or repeated'; end if;
    execute replace(v_def, a1, b1);
    if strpos(pg_get_functiondef(v_rec), b1) = 0 then raise exception 'post-check: listing record edit not applied'; end if;
  end if;
  v_def := pg_get_functiondef(v_adm);
  if strpos(v_def, b2) = 0 then
    if md5(v_def) <> '5d6bbedfdf4e268f755132c4a31e92e1' then raise exception 'guard: scholarship_admit_from_provider_page_v1 changed since the live read-back; rebase and re-verify'; end if;
    if (length(v_def) - length(replace(v_def, a2, ''))) <> length(a2) then raise exception 'guard: admit anchor absent or repeated'; end if;
    execute replace(v_def, a2, b2);
    if strpos(pg_get_functiondef(v_adm), b2) = 0 then raise exception 'post-check: admit edit not applied'; end if;
  end if;
end $f$;

-- 2. Firecrawl daily total (credits)
update pipeline.platform_toolset_settings set value = to_jsonb(1500), updated_at = now(),
       reason = 'CF-247 s1035 (Platform Admin 24 Nov 2026 13:08): scholarship and AER readers may use Firecrawl for rendered hubs; svc_fc_spend still enforces the total and logs every call'
 where toolset_key = 'firecrawl' and key = 'daily_budget_total' and value = to_jsonb(5);
insert into pipeline.admin_control_events (area, action, target, detail, actor)
values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'firecrawl.daily_budget_total', 'before', 5, 'after', 1500,
        'reason', 'Platform Admin 24 Nov 2026 13:08: reader building without artificial budget holds (s1035)', 'migration', '20261124150000'), security.system_actor_id());

-- 3. Batch 1 hubs read now
do $r$
declare v_n int;
begin
  update pipeline.scholarship_listing_pages l set next_read_at = null
   where l.active and l.status <> 'suggested' and l.provider_id in (
     select id from catalogue.providers
      where id in ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2','248374d1-0629-41cd-a6f4-0804c422a4ff','de2201a1-69ee-40ff-b6aa-0e54e535e6c0','1822b40a-8b13-44dc-8c37-106ae31bb447',
                   'dce54a01-39c1-4bdf-877d-b67da3afc81e','543b87b8-f0dd-4bc7-80d6-76252cfaabec','229dc07d-c573-44a3-b5dc-cc423cc2c300','bac82321-ded7-4e10-a71d-b18f3ae4d1c7','0f5373c8-d724-4303-9267-739530a5ce53')
         or canonical_name ~* '^(university of auckland|unsw|the university of new south wales|university of new south wales)( |$|,)');
  get diagnostics v_n = row_count;
  if v_n > 250 then raise exception 'guard: % listing pages would be queued, more than expected', v_n; end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'read_now', 'batch1', jsonb_build_object('listing_pages', v_n, 'reason', 'Platform Admin 24 Nov 2026 13:08: Batch 1 scholarship hubs (s1035)', 'migration', '20261124150000'), security.system_actor_id());
end $r$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1035_locks) then raise exception 'post-check: manual locks changed'; end if;
  if security.fc_setting_num_v1('daily_budget_total', 15000) <> 1500 then raise exception 'post-check: the Firecrawl daily total is not 1500'; end if;
end $p$;
