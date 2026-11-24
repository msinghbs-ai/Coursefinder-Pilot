-- CF-247 s1037 (S2-Scholarship-Readers; Platform Admin 24 Nov 2026 13:09 and 13:12 AEDT: label-and-tier splitter, then register, enqueue and link): the label-and-tier award
-- splitter goes live (coverage-sweep worker v1.0.38, catalogue.ts labelSections), and the university-wide merit wording the course scope rule reads is widened.
-- Measured live 24 Nov 2026 13:05 to 13:50 AEDT (rolled-back read-backs, head 20261124140000, then 20261124150000 after s1035):
-- - Charles Darwin University: its two international listing pages read (HTTP 200) and gave 2 link items each; its 8 awards are bold labels under two h2 groups, so none became a
--   candidate (s1035's heading split on that layout gives the two group headings, not the awards). 5 scholarship records, 0 mapped but the Vice-Chancellor's High Achievers award
--   (169 candidate courses, scope decision none yet); the CDU Global Merit and Bachelor of Nursing awards are not recorded at all.
-- - Lincoln University: international page `failed` (waiting_scraper) because its flagship tiers are plain blocks under one heading, so the direct read found no item and the scraper was refused.
-- - The course scope rule (security.scholarship_scope_auto_decide_v1, scholarship.scope_auto_on = 1) already links an award to every course of its university when its words match
--   scholarship.scope_all_patterns and name no level or subject; it did not name "Global Merit", "High Achiever" or "Flagship".
-- Changes:
-- 1. Setting scholarship.label_sections_on (G2, default on): the worker splits a listing page by heading, bold label or tier block (a page needs two awards, two with a stated value).
-- 2. scholarship.scope_all_patterns gains "Global Merit", "High Achiever" and "Flagship" (kept: every existing pattern). An award with a level or subject in its own words still gets
--    the filtered scope; only a university-wide award with none is linked to all of its courses. Applied by the existing scope tick, no new path, no new job.
-- 3. The Charles Darwin and Lincoln listing pages are read now (next_read_at null: the listing picker takes those first), as s992 did.
-- G1: no job. G2: one setting. G3: no consumer object (75/48 before and after). Manual locks untouched. Nothing dropped or deleted. Firecrawl: none used here ($0 direct reads first).
-- Replaces: nothing (the s1035 heading split stays as the fallback).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the setting rows and listing pages

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'scholarship.scope_all_patterns' and kind = 'list') then
    raise exception 'guard: setting scholarship.scope_all_patterns is not the expected list';
  end if;
end $g$;
create temp table s1037_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1037_cron on commit drop as select count(*) n from cron.job where active;

-- 1. the switch for label-and-tier award sections
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'scholarship.label_sections_on', 'Scholarship listings: split pages by award label and tier',
        'On (1): a scholarship listing page whose awards carry no code is split into one award per heading, bold label (under a group heading) or tier block, when it gives at least two awards and two of them state a value. Off (0): only coded awards and the heading split are used.',
        'number', to_jsonb(1), 0, 1, 'on/off', 345, 'Scholarships', 'coverage-sweep scholarship_listing (worker v1.0.38)', 'CF-247 s1037: Platform Admin 24 Nov 2026 13:09 (label-and-tier splitter for Charles Darwin and Lincoln)')
on conflict do nothing;

-- 2. university-wide merit wording for the course scope rule
do $p$
declare v_old jsonb; v_new jsonb; v_add text[] := array['Global Merit', 'High Achiever', 'Flagship']; p text;
begin
  select value into v_old from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'scholarship.scope_all_patterns' for update;
  v_new := v_old;
  foreach p in array v_add loop
    if not exists (select 1 from jsonb_array_elements_text(v_new) x where lower(x) = lower(p)) then v_new := v_new || to_jsonb(p); end if;
  end loop;
  if v_new <> v_old then
    update pipeline.platform_toolset_settings set value = v_new, updated_at = now(),
           reason = 'CF-247 s1037 (Platform Admin 24 Nov 2026 13:09): university-wide merit wording "Global Merit", "High Achiever", "Flagship" added; an award that names a level or subject still gets the filtered scope'
     where toolset_key = 'pipeline' and key = 'scholarship.scope_all_patterns';
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'scholarship.scope_all_patterns', 'before', v_old, 'after', v_new,
            'reason', 'Platform Admin 24 Nov 2026 13:09: university-wide merit wording (s1037)', 'migration', '20261124160000'), security.system_actor_id());
  end if;
end $p$;

-- 3. Charles Darwin and Lincoln listing pages are read now
do $r$
declare v_n int;
begin
  update pipeline.scholarship_listing_pages set next_read_at = null
   where active and status <> 'suggested'
     and provider_id in ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', '248374d1-0629-41cd-a6f4-0804c422a4ff');
  get diagnostics v_n = row_count;
  if v_n > 40 then raise exception 'guard: % listing pages would be queued, more than expected', v_n; end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'read_now', 'cdu-lincoln', jsonb_build_object('listing_pages', v_n, 'reason', 'Platform Admin 24 Nov 2026 13:09: label-and-tier award sections for Charles Darwin and Lincoln (s1037)', 'migration', '20261124160000'), security.system_actor_id());
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1037_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1037_cron) then raise exception 'post-check: active cron jobs changed'; end if;
  if security.pipeline_num_v1('scholarship.label_sections_on', 0) <> 1 then raise exception 'post-check: scholarship.label_sections_on is not 1'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings s, jsonb_array_elements_text(s.value) x where s.key = 'scholarship.scope_all_patterns' and x = 'Global Merit') then
    raise exception 'post-check: the university-wide merit wording was not added';
  end if;
end $c$;
