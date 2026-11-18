-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 16:10 item 1: Course page needed through the toolset, bounded batches within the rate and
-- spend caps; the Adelaide University 404s).
-- What was read live (16:20 AEDT): 1,958 courses wait on Layer 4 › Course page needed and none has had another search asked for
-- (searches_requested 0 on every open row). The course-link search lane (course-link-search-worker, run live by the lane dispatcher since
-- PR 3; its own cron row is off for that reason, it is not paused) searches the provider's own hosts by CRICOS or NZQA code and then by
-- title, with Firecrawl inside its own caps, never takes a page refused for the course again, and binds a page only with identity proof.
-- By the binder's last result the 1,958 are: every page found refused 1,568; a 404 page 288 (203 of the 220 Adelaide University 404 rows are
-- addresses the binder guessed from the course title, basis url_pattern, on the live merged domain adelaideuni.edu.au, where 219 other
-- course pages read 200; adelaide.edu.au is already one of the provider's hosts in binding.provider_host_aliases); bound but unread 60;
-- blocked by the site or robots 41.
-- Rule l4-page-needed-search-v1 (job layer4-page-needed-search, hourly at minute 53): for each open item, the existing "Search again" decision
-- (security.course_page_needed_decide_v1, choice search_again) under the system automation account, a 404 or unread page first, then a refused
-- page; at most layer4.page_needed_search_max searches a course, layer4.page_needed_search_batch items a run, so the search lane's queue and
-- its Firecrawl caps set the pace (scheduled work stays held by toolset limits). A page blocked by the site or disallowed by robots is never
-- searched again by this rule: it waits for a person. A course whose search finds and proves its page leaves the list; one whose search
-- finds nothing comes back to it as before.
-- G1: the job is catalogued. G2: switch and batch are settings. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.page_needed_search_rule_on', 'Course page needed: ask another search by rule',
  '1: every hour, rule l4-page-needed-search-v1 asks the course-link search lane to search again for open Course page needed items (a 404 or unread page first, then a refused page), within the search limit per course; blocked and robots-disallowed pages wait for a person. 0: only a person asks.',
  'number', '1'::jsonb, 0, 1, 'switch', 520, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 16:10 item 1', 'Layer 4', 'security.course_page_needed_search_rule_v1, job layer4-page-needed-search'),
 ('pipeline', 'layer4.page_needed_search_batch', 'Course page needed: searches asked per run',
  'How many open Course page needed items one hourly run sends to the course-link search lane. The lane''s own caps and Firecrawl limits decide how fast they are searched.',
  'number', '300'::jsonb, 1, 2000, 'items', 521, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 16:10 item 1', 'Layer 4', 'job layer4-page-needed-search')
on conflict (toolset_key, key) do nothing;

create or replace function security.course_page_needed_search_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_prev text; v_res jsonb;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_lim int := least(greatest(coalesce(p_limit, 0), 0), 2000);  -- fixed: upper bound of the setting's range
        v_max int := security.pipeline_num_v1('layer4.page_needed_search_max', 3)::int;
        v_ok jsonb := '{}'::jsonb; v_fail int := 0; v_held int;
begin
  if security.pipeline_num_v1('layer4.page_needed_search_rule_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:page_needed_search_rule'));  -- fixed: one run at a time
  select count(*) into v_held from pipeline.course_page_needed n join pipeline.coverage_course_pages p on p.course_id = n.course_id
   where n.state = 'open' and p.read_status in ('blocked', 'robots_disallowed');
  for w in
    select n.course_id,
           case when p.http_status in (404, 410) then 'dead_page'
                when p.status = 'bound' and coalesce(p.read_status, '-') in ('fetch_failed', '-', 'needs_render') then 'unread_page'
                else 'refused_page' end cause,
           p.basis
      from pipeline.course_page_needed n
      join catalogue.courses c on c.id = n.course_id
      left join pipeline.coverage_course_pages p on p.course_id = n.course_id
     where n.state = 'open' and c.lifecycle_status = 'active' and n.searches_requested < v_max
       and coalesce(p.read_status, '-') not in ('blocked', 'robots_disallowed')
       and not exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active')
     order by case when p.http_status in (404, 410) then 0 when p.status = 'bound' and coalesce(p.read_status, '-') in ('fetch_failed', '-', 'needs_render') then 1 else 2 end, n.created_at
     limit v_lim
  loop
    v_prev := current_setting('request.jwt.claim.sub', true);
    perform set_config('request.jwt.claim.sub', v_sys::text, true);
    begin
      v_res := security.course_page_needed_decide_v1(w.course_id, 'search_again', null,
        left(format('[rule l4-page-needed-search-v1] Search again: the last page held for this course %s; the course-link search lane looks again on the provider''s own hosts (CRICOS or NZQA code, then title) and never takes a refused page. Approved by Platform Admin 18 Nov 2026 16:10',
          case w.cause when 'dead_page' then 'returns 404' || case when w.basis = 'url_pattern' then ' (an address guessed from the course title)' else '' end
                       when 'unread_page' then 'could not be read' else 'was refused as not this course''s page' end), 1000));
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      v_ok := jsonb_set(v_ok, array[w.cause], to_jsonb(coalesce((v_ok->>w.cause)::int, 0) + 1));
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); v_fail := v_fail + 1;
    end;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'rule_execute', 'l4-page-needed-search-v1', jsonb_build_object('searches_asked', v_ok, 'failed', v_fail, 'held_blocked_or_robots', v_held), v_sys);
  return jsonb_build_object('ok', true, 'searches_asked', v_ok, 'failed', v_fail, 'held_blocked_or_robots', v_held,
    'open', (select count(*) from pipeline.course_page_needed where state = 'open'));
end $function$;
revoke all on function security.course_page_needed_search_rule_v1(integer) from public, anon, authenticated;
comment on function security.course_page_needed_search_rule_v1(integer) is 'CF-247 rule l4-page-needed-search-v1 (Platform Admin 18 Nov 2026 16:10): asks the course-link search lane to search again for open Course page needed items through the existing decision, under the system automation account; blocked and robots-disallowed pages wait for a person.';

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('layer4-page-needed-search', 'Layer 4', 32, 'Course page needed: search again by rule',
  'Every hour at minute 53, when setting layer4.page_needed_search_rule_on is 1 (Settings > Pipeline settings > Layer 4): rule l4-page-needed-search-v1 sends up to layer4.page_needed_search_batch open Course page needed items back to the course-link search lane (a 404 or unread page first, then a refused page), at most layer4.page_needed_search_max times a course. The lane''s own caps and Firecrawl limits set the pace. Blocked and robots-disallowed pages wait for a person.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('layer4-page-needed-search', '53 * * * *',
  'select security.course_page_needed_search_rule_v1(security.pipeline_num_v1(''layer4.page_needed_search_batch'', 300)::int)')
where not exists (select 1 from cron.job where jobname = 'layer4-page-needed-search');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'layer4-page-needed-search', 'Layer 4', 'Course links', 'Course page needed: another search asked by rule every hour', 'active', '{}', '20261118190000'),
  ('function', 'security.course_page_needed_search_rule_v1', 'Layer 4', 'Course links', 'One run of rule l4-page-needed-search-v1', 'active', '{}', '20261118190000')
on conflict do nothing;

create temp table cf_run on commit drop as select security.course_page_needed_search_rule_v1(security.pipeline_num_v1('layer4.page_needed_search_batch', 300)::int) r;

do $c$
declare v jsonb := (select r from cf_run);
begin
  if (v->>'failed')::int > 0 then raise exception 'post-check: % searches could not be asked: %', v->>'failed', v; end if;
  if exists (select 1 from pipeline.course_page_needed n join pipeline.coverage_course_pages p on p.course_id = n.course_id
              where n.state = 'search_requested' and n.decision->>'reason' like '[rule l4-page-needed-search-v1]%' and p.read_status in ('blocked', 'robots_disallowed')) then
    raise exception 'post-check: a blocked or robots-disallowed page was searched again by the rule';
  end if;
  if not exists (select 1 from cron.job where jobname = 'layer4-page-needed-search' and active) then raise exception 'post-check: the job is not scheduled'; end if;
  raise notice 'Rule l4-page-needed-search-v1 first run: %', v;
end $c$;
