-- CF-247 (20 Oct 2026). Platform Admin 10:35: "Rework layer 2 into layer 2/3 so its cleared it has combined operations. Suggest tabs and nav
-- items that can retire as well. Only actionable and operation relative information and items should be retained." Choices (10:5x):
-- "Operations first (Recommended)"; retire "Old Layer 4 tabs now", "Priority queue", "Counsellor reports tab", "Scrapers & fetchers page".
-- 1 pipeline.automation_catalogue.layer23_stage: which Layer 2/3 stage a scheduled job serves (find website, find course pages, build
--   adapter, admit and enrich, scholarships). Layer 2/3 › Operations groups the jobs by it. Jobs outside Layer 2/3 (registers, delivery,
--   upkeep, reports) have none.
-- 2 public.admin_layer23(action, args), Curator and above, read only:
--   'operations'   per stage: universities working now, waiting, and stopped for a person (Layer 4 Inbox items of that stage's kinds),
--                  with the stage's jobs; universities done; onboarding settings in brief.
--   'universities' one row per university with an adapter, in the Firecrawl targets or in onboarding: the Adapters row (public.admin_adapters
--                  'list', unchanged) plus its onboarding stage, stop reason and note, and how many Inbox items it has.
-- 3 Screen use is measured from now on: public.admin_screen_open(page, tab) is called by the admin shell when a person opens a page or tab
--   (one row per day, page, tab and person, counted); public.admin_screen_usage(days) (Platform Admin) lists opens and people per page and
--   tab. Retiring a screen is then decided on its use, not on API logs (admin_read serves many screens and its body is not logged).
-- 5 Counsellor reports are closed in the Inbox (Fixed, Not changed), through public.admin_counsellor_reports('close') with its own role check.
-- 6 Provider departures (a provider whose every registered course left the register: closed, merged or still operating) were decided
--   only on the retired Review queue; 10 wait. They are an Inbox kind now (provider_departure), decided through
--   public.layer4_provider_departure_decide with its own checks (Platform Admin; a merger names its successor by name or code).
-- 4 public.admin_layer4_inbox('decided'): the decisions taken in the Inbox, newest first (who, when, choice, reason), so the old Review queue
--   history is not needed (md5-guarded edit; nothing else changes).
-- Replaces: public.admin_layer4_inbox(text,jsonb) (action 'decided'; counsellor reports and provider departures decided); security.layer4_inbox_kinds_v1()
--   (counsellor report choices, provider departure kind); security.layer4_inbox_items_v1() (provider departures added)
-- Retires: nothing here (the UI release retires the Layer 2 Onboarding and Adapters tabs into Universities, the old Layer 4 tabs, Scheduled
--   jobs › Priority queue, Coverage › Counsellor reports and the Scrapers & fetchers page; their addresses redirect)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

-- 1 ------------------------------------------------------------------------------------------------------------------------------------
alter table pipeline.automation_catalogue add column if not exists layer23_stage text;
comment on column pipeline.automation_catalogue.layer23_stage is 'CF-247 20 Oct 2026: the Layer 2/3 stage this job serves (website, pages, adapter, enrich, scholarships); shown grouped on Layer 2/3 › Operations. Null for jobs outside Layer 2/3.';
update pipeline.automation_catalogue set layer23_stage = s.stage
  from (values
   ('coverage-find-site','website'),('provider-website-check','website'),('provider-contact-page','website'),('cricos-peo','website'),
   ('coverage-discover','pages'),('coverage-discover-2','pages'),('course-link-search','pages'),('course-link-search-worker','pages'),('coverage-ai-match','pages'),
   ('coverage-ai-match-prepare','pages'),('coverage-bind','pages'),('course-relink','pages'),('link-refresh','pages'),('coverage-reidentify','pages'),
   ('coverage-reextract','pages'),('better-page-revert','pages'),('enrich-focus-refresh','pages'),('course-link-reverse','pages'),('coverage-read','pages'),
   ('coverage-read-2','pages'),('provider-facts','pages'),('firecrawl-runs','pages'),
   ('provider-onboarding','adapter'),('adapter-build-readiness','adapter'),('central-ai','adapter'),('central-find','adapter'),
   ('coverage-admit','enrich'),('coverage-admit-intakes','enrich'),('adapter-overwrite','enrich'),('policy-auto-approve','enrich'),('provider-english-defaults','enrich'),
   ('provider-calendar-intakes','enrich'),('provider-calendar-defaults','enrich'),('provider-rule-admit','enrich'),('provider-basis-rule-admit','enrich'),
   ('provider-fee-profiles-apply','enrich'),('fee-wording-rules','enrich'),('exit-awards-apply','enrich'),('host-pages-apply','enrich'),('companion-read','enrich'),
   ('policy-add-tests','enrich'),('university-reread-requests','enrich'),('fee-period-settle','enrich'),('l4-rule-fee-year-align','enrich'),
   ('l4-rule-low-agreement','enrich'),('l4-rule-unofficial-source','enrich'),
   ('scholarship-discover','scholarships'),('scholarship-discover-refill','scholarships'),('scholarship-listing','scholarships'),('scholarship-read','scholarships'),
   ('scholarship-ai-extract','scholarships'),('scholarship-recheck','scholarships'),('scholarship-auto-publish','scholarships'),('scholarship-publication-review','scholarships'),
   ('scholarship-ai-backfill','scholarships'),('scholarship-audience','scholarships'),('scholarship-nationality','scholarships'),('scholarship-savings','scholarships'),
   ('scholarship-fee-alignment','scholarships'),('scholarship-course-attribute','scholarships'),('scholarship-course-attribute-full','scholarships'),
   ('scholarship-reread-cadence','scholarships')) s(job, stage)
 where automation_catalogue.jobname = s.job and automation_catalogue.layer23_stage is null;

-- 2 ------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_layer23(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_out jsonb; v_list jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v1() i;
  create temp table if not exists _l23_ob on commit drop as
    select distinct on (o.provider_id) o.id, o.provider_id, o.status, o.stop_reason, o.note, o.result, o.updated_at,
           security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage
      from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc;

  if p_action = 'operations' then
    with st(key, label, ord, kinds, what) as (values
      ('website', 'Find the website', 1, array['website_needed', 'site_down'], 'The official website is found and checked.'),
      ('pages', 'Find course pages', 2, array['pages_not_found', 'too_few_pages'], 'Each course''s own page is found by its CRICOS code or the university''s listing, and read.'),
      ('adapter', 'Build the adapter', 3, array['nothing_ready', 'onboarding_failed'], 'Sample pages are captured, the AI proposes the adapter, it is applied and qualified.'),
      ('enrich', 'Admit and enrich', 4, array['central_to_approve', 'course_link', 'fee_check', 'not_offered', 'not_on_site', 'counsellor_report'], 'Fields that pass are admitted, central pages fill what pages do not say, courses are enriched.'),
      ('scholarships', 'Scholarships', 5, array['held_scholarship'], 'Scholarship pages are found, read and checked by the AI before they are published.')),
    n as (select
      count(*) filter (where o.status = 'website') website_run, count(*) filter (where o.status = 'queued') website_wait,
      count(*) filter (where o.status in ('course_pages', 'waiting_courses')) pages_run,
      count(*) filter (where o.status in ('capturing', 'proposing', 'applying', 'qualifying')) adapter_run,
      count(*) filter (where o.status = 'scholarships' and o.result->>'phase' = 'enrich') enrich_run, count(*) filter (where o.status = 'waiting_admit') enrich_wait,
      count(*) filter (where o.status = 'scholarships' and coalesce(o.result->>'phase', '') <> 'enrich') sch_run,
      count(*) filter (where o.status = 'done') done, count(*) filter (where o.status = 'stopped') stopped
      from _l23_ob o)
    select jsonb_build_object('as_at', now(), 'can_manage', v_rank >= 6, 'rank', v_rank,
      'done', n.done, 'stopped_onboarding', n.stopped,
      'enrich_review', (select count(*) from pipeline.field_enrich_items f where f.state = 'review'),
      'settings', (select jsonb_build_object('enabled', s.enabled, 'auto_admit', s.auto_admit, 'max_active', s.max_active) from pipeline.provider_onboarding_settings s limit 1),
      'stages', (select jsonb_agg(jsonb_build_object('key', st.key, 'label', st.label, 'order', st.ord, 'what', st.what, 'kinds', to_jsonb(st.kinds),
          'running', case st.key when 'website' then n.website_run when 'pages' then n.pages_run when 'adapter' then n.adapter_run when 'enrich' then n.enrich_run else n.sch_run end,
          'waiting', case st.key when 'website' then n.website_wait
                                 when 'pages' then (select count(*) from pipeline.coverage_provider_discovery d where d.status = 'pending')
                                 when 'adapter' then (select count(*) from pipeline.adapter_builds b where b.wave is not null and coalesce(b.ready, 0) = 0 and b.checked_at is null)
                                 when 'enrich' then n.enrich_wait
                                 else (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and coalesce(r.recheck->>'state', 'none') in ('queued', 'leased')) end,
          'stopped', (select count(*) from _l23_inbox i where i.kind = any(st.kinds)),
          'stopped_by_kind', (select coalesce(jsonb_object_agg(k.kind, k.c), '{}'::jsonb) from (select i.kind, count(*) c from _l23_inbox i where i.kind = any(st.kinds) group by 1) k),
          'jobs', (select coalesce(jsonb_agg(a.jobname order by a.sort), '[]'::jsonb) from pipeline.automation_catalogue a where a.layer23_stage = st.key))
        order by st.ord) from st))
      into v_out from n;
    return v_out;
  end if;

  if p_action = 'universities' then
    -- Adapters (Operator and above) as on the old Adapters tab; a Curator sees the universities in onboarding only
    v_list := case when v_rank >= 4 then public.admin_adapters('list', '{}'::jsonb) else jsonb_build_object('can_manage', false, 'can_qualify', false, 'adapters', '[]'::jsonb) end;
    with a as (select x from jsonb_array_elements(coalesce(v_list->'adapters', '[]'::jsonb)) x),
    ids as (select (x->>'provider_id')::uuid provider_id from a),
    extra as (  -- universities in onboarding with no adapter and not in the Firecrawl targets
      select jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'state', s.code,
               'university', true, 'adapter', null, 'target', null, 'qualify', null,
               'pages', (select count(*) from pipeline.coverage_course_pages g where g.provider_id = p.id),
               'pages_read', (select count(*) from pipeline.coverage_course_pages g where g.provider_id = p.id and g.read_status = 'read')) x
        from _l23_ob o join catalogue.providers p on p.id = o.provider_id
        left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
       where o.provider_id not in (select provider_id from ids)),
    allrows as (select x from a union all select x from extra),
    inbox as (select provider_id, count(*) n, jsonb_object_agg(kind, c) by_kind from (select provider_id, kind, count(*) c from _l23_inbox where provider_id is not null group by 1, 2) z group by 1)
    select jsonb_build_object('as_at', now(), 'can_manage', v_list->'can_manage', 'can_qualify', v_list->'can_qualify', 'can_onboard', v_rank >= 6, 'settings', v_list->'settings',
      'adapters', coalesce(jsonb_agg(r.x || jsonb_build_object(
          'onboarding', case when o.id is null then null else jsonb_build_object('id', o.id, 'status', o.status, 'stage', o.stage, 'phase', o.result->>'phase', 'stop_reason', o.stop_reason, 'note', o.note, 'updated_at', o.updated_at) end,
          'inbox', coalesce(i.n, 0), 'inbox_kinds', coalesce(i.by_kind, '{}'::jsonb))
        order by r.x->>'name'), '[]'::jsonb))
      into v_out
      from allrows r left join _l23_ob o on o.provider_id = (r.x->>'provider_id')::uuid left join inbox i on i.provider_id = (r.x->>'provider_id')::uuid;
    return v_out;
  end if;
  raise exception 'unknown action %', p_action;
end $function$;
revoke execute on function public.admin_layer23(text, jsonb) from public, anon;
grant execute on function public.admin_layer23(text, jsonb) to authenticated;
comment on function public.admin_layer23(text, jsonb) is 'CF-247 20 Oct 2026: Layer 2/3 › Operations (stages, jobs, stopped for a person) and Universities (adapter and onboarding per university). Read only.';

-- 3 ------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.admin_screen_opens (
  day date not null default (now() at time zone 'Australia/Melbourne')::date,
  page text not null,
  tab text not null default '',
  user_id uuid not null,
  opens integer not null default 1,
  last_at timestamptz not null default now(),
  primary key (day, page, tab, user_id)
);
comment on table pipeline.admin_screen_opens is 'CF-247 20 Oct 2026: admin screen use, one row per Melbourne day, page, tab and person (counted). Used to decide which screens retire; read on Platform health.';
alter table pipeline.admin_screen_opens enable row level security;

CREATE OR REPLACE FUNCTION public.admin_screen_open(p_page text, p_tab text DEFAULT '')
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then return; end if;
  if p_page is null or p_page !~ '^[A-Za-z0-9_-]{1,40}$' or coalesce(p_tab, '') !~ '^[A-Za-z0-9_-]{0,40}$' then return; end if;  -- fixed: page and tab keys only
  insert into pipeline.admin_screen_opens(page, tab, user_id) values (p_page, coalesce(p_tab, ''), auth.uid())
  on conflict (day, page, tab, user_id) do update set opens = pipeline.admin_screen_opens.opens + 1, last_at = now();
end $function$;
revoke execute on function public.admin_screen_open(text, text) from public, anon;
grant execute on function public.admin_screen_open(text, text) to authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'usage.screen_window_days', 'Screen use window', 'Platform health › Screen use counts opens over this many days.', 'number', to_jsonb(14), 1, 90, 'days', 742, 'CF-247, Platform Admin 20 Oct 2026 10:35 "suggest not used navigation items"', 'Housekeeping', 'public.admin_screen_usage (Platform health › Screen use)')
on conflict (toolset_key, key) do nothing;

CREATE OR REPLACE FUNCTION public.admin_screen_usage(p_days integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_days int;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  v_days := coalesce(p_days, security.pipeline_num_v1('usage.screen_window_days', 14)::int);
  return jsonb_build_object('days', v_days, 'since', (select min(day) from pipeline.admin_screen_opens),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('page', z.page, 'tab', z.tab, 'opens', z.opens, 'people', z.people, 'days_used', z.days_used, 'last_at', z.last_at) order by z.opens desc)
                        from (select page, tab, sum(opens) opens, count(distinct user_id) people, count(distinct day) days_used, max(last_at) last_at
                                from pipeline.admin_screen_opens where day > (now() at time zone 'Australia/Melbourne')::date - v_days group by 1, 2) z), '[]'::jsonb));
end $function$;
revoke execute on function public.admin_screen_usage(integer) from public, anon;
grant execute on function public.admin_screen_usage(integer) to authenticated;

-- 4 ------------------------------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'dee3ec8cb61735ae4f1df2ed136ecf8e', array[
  array['v_det jsonb; v_out jsonb;', 'v_det jsonb; v_out jsonb; v_ids uuid[];'],
  array[$o$  elsif v_choice = 'website' then$o$,
        $n$  elsif v_kind = 'provider_departure' then  -- CF-247 20 Oct 2026: from the retired Review queue (Provider departures); Platform Admin
    if v_choice = 'merged' then
      select array_agg(p.id) into v_ids from catalogue.providers p
       where p.lifecycle_status = 'active' and p.id <> v_pid and p.country_id = (select q.country_id from catalogue.providers q where q.id = v_pid)
         and (lower(coalesce(p.display_name, p.canonical_name)) = lower(v_value)
              or p.id in (select r.provider_id from catalogue.provider_registrations r where upper(r.registration_code) = upper(v_value)));
      if coalesce(array_length(v_ids, 1), 0) <> 1 then raise exception 'enter the successor''s exact name or its CRICOS or NZQA code (% found)', coalesce(array_length(v_ids, 1), 0); end if;
    end if;
    v_r := public.layer4_provider_departure_decide(v_ref::bigint, v_choice, case when v_choice = 'merged' then v_ids[1] end, v_reason);
  elsif v_kind = 'counsellor_report' then  -- CF-247 20 Oct 2026: closed here (Coverage › Counsellor reports retired); Zoho reads the outcome back
    v_r := public.admin_counsellor_reports('close', jsonb_build_object('ids', jsonb_build_array(v_ref), 'outcome', case v_choice when 'report_fixed' then 'fixed' else 'not_changed' end, 'reason', v_reason));
  elsif v_choice = 'website' then$n$],
  array[$o$  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$o$,
        $n$  -- CF-247 20 Oct 2026: the decisions taken here, newest first (replaces the old Review queue history)
  if p_action = 'decided' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.detail->>'kind', 'choice', e.detail->>'choice', 'value', e.detail->>'value',
             'reason', e.detail->>'reason', 'provider_id', e.detail->>'provider_id',
             'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id::text = e.detail->>'provider_id'),
             'by', (select u.email from auth.users u where u.id::text = e.actor::text)) order by e.id desc)
           from (select * from pipeline.admin_control_events x where x.area = 'layer4' and x.action = 'inbox_decide' order by x.id desc limit v_lim offset v_off) e), '[]'::jsonb));
  end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$n$]
]);

select pg_temp.edit_once('security.layer4_inbox_kinds_v1()', '30afc348fd153720eb65561571ee1faa', array[
  array['"returns": "Enter its page on the course"}]}',
        '"returns": "Enter its page on the course"}]},
   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [
     {"key": "closed", "label": "Closed: archive it", "rank": 6, "returns": "Archived through the clean-up workflow and hidden from the consumer API"},
     {"key": "merged", "label": "Merged into another provider", "rank": 6, "input": "provider", "returns": "Archived, and the merger recorded with its successor"},
     {"key": "reviewed", "label": "Still operating: keep it", "rank": 6, "returns": "Closed; the provider stays as it is"}]}'],
  array['{"key": "reports", "label": "Open the report", "link": "reports", "returns": "Close it as Fixed or Not changed; Zoho shows the outcome"}',
        '{"key": "report_fixed", "label": "Fixed", "returns": "Closed as fixed with your note; Zoho shows the outcome to the counsellor"},
     {"key": "report_not_changed", "label": "Not changed", "returns": "Closed as not changed with your reason; Zoho shows it to the counsellor"},
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Correct the value on the course, then close the report here"}']
]);

select pg_temp.edit_once('security.layer4_inbox_items_v1()', '75c5f26774638ca49d3fae47ed66b358', array[
  array[$o$    from pipeline.data_flags d where d.flag_code = 'reported' and d.status = 'open'
$o$, $n$    from pipeline.data_flags d where d.flag_code = 'reported' and d.status = 'open'
  union all
  -- CF-247 20 Oct 2026: providers whose every registered course left the register (from the retired Review queue)
  select 'provider_departure', d.id::text, d.provider_id, coalesce(p.display_name, p.canonical_name),
         'Every registered course left the register (' || d.courses_retired || ' course' || case when d.courses_retired = 1 then '' else 's' end || '). Closed, merged into another provider, or still operating?',
         null, d.created_at, jsonb_build_object('departure_id', d.id, 'courses_retired', d.courses_retired, 'note', d.note)
    from pipeline.layer1_provider_departures d left join catalogue.providers p on p.id = d.provider_id where d.status = 'needs_review'
$n$]
]);

-- retired screens (the UI release removes them; their addresses redirect)
update pipeline.component_register r set status = 'retired', replaced_by = s.by, note = coalesce(r.note || '; ', '') || 'retired v2.15.300 (Platform Admin 20 Oct 2026)', updated_at = now()
  from (values
   ('Layer 2 Discovery & reading', 'Layer 2/3 Build & enrich'),
   ('Layer 2 Discovery & reading › Adapters', 'Layer 2/3 Build & enrich › Universities'),
   ('Layer 2 Discovery & reading › Onboarding', 'Layer 2/3 Build & enrich › Universities and Operations'),
   ('Layer 2 Discovery & reading › Adapter builder', 'Layer 2/3 Build & enrich › Adapter builder (opened from a university)'),
   ('Layer 2 Discovery & reading › Build adapter', 'Layer 2/3 Build & enrich › Build adapter'),
   ('Layer 2 Discovery & reading › Enrich fields', 'Layer 2/3 Build & enrich › Enrich fields'),
   ('Layer 2 Discovery & reading › Scholarships', 'Layer 2/3 Build & enrich › Scholarships'),
   ('Layer 4 Review › Review queue', 'Layer 4 Review › Inbox (Course link)'),
   ('Layer 4 Review › AI could not decide', 'Layer 4 Review › Inbox (Held scholarship)'),
   ('Layer 4 Review › Websites to find', 'Layer 4 Review › Inbox (Website needed)'),
   ('Scheduled jobs › Priority queue', 'Focus list and Layer 2/3 › Build adapter waves; search cap on Models & services › Toolsets & limits'),
   ('Coverage & completeness › Counsellor reports', 'Layer 4 Review › Inbox (Counsellor report)'),
   ('Scrapers & fetchers', 'Models & services › Fetchers')) s(name, by)
 where r.kind = 'screen' and r.name = s.name and r.status <> 'retired';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_layer23', 'Layer 2/3', 'Layer 2/3 › Operations and Universities (read only)', 'active', '20261020060000'),
 ('function', 'public.admin_screen_open', 'Platform', 'Counts admin screen opens per day, page, tab and person', 'active', '20261020060000'),
 ('function', 'public.admin_screen_usage', 'Platform', 'Screen use over the window (Platform health › Screen use)', 'active', '20261020060000'),
 ('table', 'pipeline.admin_screen_opens', 'Platform', 'Admin screen opens per day, page, tab and person', 'active', '20261020060000')
on conflict (kind, name) do nothing;
