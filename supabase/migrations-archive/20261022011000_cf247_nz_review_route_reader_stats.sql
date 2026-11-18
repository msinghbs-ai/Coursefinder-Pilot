-- CF-247 (22 Oct 2026). NZ data enrichment review, Platform Admin 07:22; choices "University route change (2)", "Field reader fallbacks
-- (4, 7)" and "Daily toolset sheet (9)". Review figures (live, 22 Oct):
--   - Title search at universities: 584 wrong pages for 1,466 correct; 7 of 8 NZ universities stopped by the wrong-in-a-row rule. Listed
--     pages (the university's own site list, then title match) were right 91% of the time (694 of 761).
--   - AI page match (last 14 days, all countries): first try 249 correct pages of 1,013; second try 10 of 720; third try 0 of 692. The retry
--     rule counted any page the AI chose, not pages that turned out right, so it kept retrying. NZ: 708 calls with one candidate, 0 correct.
--   - AI field reader (NZ): 1,286 answers whose quote was not on the page were dropped without a second chance; 1,033 items were asked
--     again of the same stored page copy that had not stated the field.
-- Changes:
--   2 public.svc_course_link_search_next: for providers whose type is in search.site_list_first_types (["university"]) and that have a site
--     list, a course is searched by title only after matching it against the site list is over (security.site_list_match_done_v1); a
--     search a person asked for still runs at once.
--   7 security.retry_cap_v1('ai_match') counts an attempt as worth repeating only by the pages it found that were then read as correct (the
--     cap falls from 2 to 1 on today's figures). security.coverage_ai_match_prepare_v1 sends a course to the AI only with at least
--     ai_match.min_candidates (2) candidates; fewer is no_candidates (no AI call).
--   4 public.svc_enrich_ai_next passes a hint with an item whose last quote was not on the page; worker v0.36.0 tells the AI and asks once
--     more (then skipped). security.enrich_fields_slice_v1 does not ask the AI again about a field of a course whose same stored page copy
--     did not state it before.
--   9 pipeline.toolset_use_daily: one row a day per provider and tool (course search, page reads, AI page match, AI field reader, fee reader,
--     scholarship AI, other credits, flags raised): used, worked, did not work, credits, US$. security.toolset_use_daily_record_v1(date)
--     writes a Melbourne day (default yesterday); job toolset-use-daily daily at 19:58 UTC; retention.toolset_use_daily_days (120).
--     Seeded for 8 to 21 Oct 2026 from the records' own dates. Read by the "Toolset use" sheet of the daily NZ report.
-- Replaces: public.svc_course_link_search_next (site list first); security.retry_cap_v1 (correct pages); security.coverage_ai_match_prepare_v1 (fewest candidates); public.svc_enrich_ai_next (hint); security.enrich_fields_slice_v1 (same page copy). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted by this migration (old toolset_use_daily days are removed by the job, as for provider_field_daily). Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "bcd7e3a63ae040a9993105a1b858c74a",
                              "public.svc_enrich_ai_next(integer)": "63240ffa03d7b5719b138a4088c5c7c4",
                              "security.enrich_fields_slice_v1(uuid,integer)": "57a788d385a8a89526a4da2733c2931c",
                              "security.retry_cap_v1(text)": "56e6d020e482cc745a2b3296b8d5cf8f",
                              "security.coverage_ai_match_prepare_v1(integer,integer)": "01ad8260df8442e29df2bbfd07af8385"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then raise exception 'live % differs from the definition this change replaces', v_sig; end if;
  end loop;
end $guard$;

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

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'search.site_list_first_types', 'Course-page search: site list first for', 'For providers of these types that have a site list, a course is searched by title only after matching it against the site list is over.', 'list', '["university"]'::jsonb, null, null, 'provider types', 325,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 2 (listed pages 91% right; title search 584 wrong for 1,466 right at universities)', 'Course pages', 'public.svc_course_link_search_next'),
 ('pipeline', 'ai_match.min_candidates', 'AI page match: fewest candidates', 'A course is sent to the AI page match only when the site list gives at least this many candidate pages; fewer is recorded as no candidates (no AI call).', 'number', to_jsonb(2), 1, 25, 'pages', 326,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 7 (NZ: 708 calls with one candidate, none right)', 'Course pages', 'security.coverage_ai_match_prepare_v1'),
 ('pipeline', 'retention.toolset_use_daily_days', 'Keep daily toolset use per provider for', 'Days of per-provider toolset use kept for the daily report; older days are removed by the daily job.', 'number', to_jsonb(120), 30, 730, 'days', 327,
  'CF-247, Platform Admin 22 Oct 2026 07:22 "keep the stat how much of toolset we used"', 'Storage & retention', 'job toolset-use-daily')
on conflict (toolset_key, key) do nothing;

-- fix 2 ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.site_list_match_done_v1(p_course uuid, p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 22 Oct 2026 (NZ review fix 2): true unless the provider is of a site-list-first type with a site list and matching this course
  -- against the list is not over yet (never tried, or a try is waiting). Providers outside the focus list are not matched, so not held.
  select not (
        exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id, pipeline.platform_toolset_settings s
                 where p.id = p_provider and s.toolset_key = 'pipeline' and s.key = 'search.site_list_first_types' and s.value ? t.code)
    and exists (select 1 from pipeline.coverage_provider_urls u where u.provider_id = p_provider)
    and security.enrich_focus_v1(p_provider)
    and (not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = p_course)
         or exists (select 1 from pipeline.coverage_ai_match q where q.course_id = p_course and q.state in ('ready', 'leased'))))
$$;
comment on function security.site_list_match_done_v1(uuid, uuid) is 'CF-247 22 Oct 2026: false while a course of a site-list-first provider (search.site_list_first_types) still waits for its site-list match; title search waits until then.';
revoke all on function security.site_list_match_done_v1(uuid, uuid) from public;

select pg_temp.edit_once('public.svc_course_link_search_next(integer)', 'bcd7e3a63ae040a9993105a1b858c74a', array[
  [$o$       and (s.requested_at is not null or not security.site_few_course_pages_v1(s.provider_id))$o$,
   $n$       and (s.requested_at is not null or not security.site_few_course_pages_v1(s.provider_id))
       -- 22 Oct 2026 (NZ review fix 2): universities: the site list first, title search for what it could not place
       and (s.requested_at is not null or security.site_list_match_done_v1(s.course_id, s.provider_id))$n$]]);

-- fix 7 ---------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.retry_cap_v1(text)', '56e6d020e482cc745a2b3296b8d5cf8f', array[
  [$o$select count(*), count(*) filter (where q.state = 'chosen') into v_n, v_ok$o$,
   $n$-- 22 Oct 2026 (NZ review fix 7): an attempt counts as a success only when the page it chose was then read as the course's page
    select count(*), count(*) filter (where q.state = 'chosen' and exists (select 1 from pipeline.coverage_course_pages g
                                                                         where g.course_id = q.course_id and g.url = q.chosen_url and g.status = 'bound' and g.read_status = 'read')) into v_n, v_ok$n$]]);

select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', '01ad8260df8442e29df2bbfd07af8385', array[
  [$o$case when count(rk.url) = 0 then 'no_candidates' else 'ready' end$o$,
   $n$case when count(rk.url) < greatest(1, security.pipeline_num_v1('ai_match.min_candidates', 2)::int) then 'no_candidates' else 'ready' end$n$]]);

-- fix 4 ---------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_enrich_ai_next(integer)', '63240ffa03d7b5719b138a4088c5c7c4', array[
  [$o$'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field))) x$o$,
   $n$'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field,
                                    'hint', case when u.reason = 'the quote is not on the page' then 'last time the quote given for this field was not found on the page' end))) x$n$]]);

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '57a788d385a8a89526a4da2733c2931c', array[
  [$o$        if v_path is null then continue; end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;$o$,
   $n$        if v_path is null then continue; end if;
        -- 22 Oct 2026 (NZ review fix 4): the same stored page copy did not state this field before: not asked again
        if it.course_id is not null and v_ev is not null and exists (
             select 1 from pipeline.field_enrich_items o where o.course_id = it.course_id and o.field = it.field and o.evidence_id = v_ev and o.id <> it.id
                and o.state = 'skipped' and o.reason in ('the page does not state it', 'the page names no campus', 'only a site-wide line mentions international', 'no campus named on the page')) then
          update pipeline.field_enrich_items set reason = 'the same page copy was read for this before and did not state it' where id = it.id;
          continue;
        end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;$n$]]);

-- fix 9 ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.toolset_use_daily (
  snapshot_date date not null,
  provider_id uuid not null,
  country_code text,
  tool text not null,
  used int not null default 0,
  ok int not null default 0,
  failed int not null default 0,
  credits numeric not null default 0,
  cost_usd numeric not null default 0,
  computed_at timestamptz not null default now(),
  primary key (snapshot_date, provider_id, tool)
);
create index if not exists toolset_use_daily_country on pipeline.toolset_use_daily(country_code, snapshot_date);
comment on table pipeline.toolset_use_daily is 'CF-247 22 Oct 2026 (Platform Admin "keep the stat how much of toolset we used used successfully and failed"): one row a Melbourne day per provider and tool: times used, worked, did not work, scraper credits and AI US$. Tools: course_search, page_reads, ai_page_match, ai_field_reader, fee_reader, scholarship_ai, other_credits, flags_raised. Outcomes are as held when the day is recorded. Written by job toolset-use-daily; read by the daily NZ report.';
alter table pipeline.toolset_use_daily enable row level security;

create or replace function security.toolset_use_daily_record_v1(p_date date default null)
 returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare v_date date := coalesce(p_date, (now() at time zone 'Australia/Melbourne')::date - 1);
        v_from timestamptz := (v_date::timestamp at time zone 'Australia/Melbourne');
        v_to timestamptz := ((v_date + 1)::timestamp at time zone 'Australia/Melbourne');
        v_n int; v_old int;
begin
  delete from pipeline.toolset_use_daily where snapshot_date = v_date;  -- a second run the same day replaces that day
  insert into pipeline.toolset_use_daily(snapshot_date, provider_id, country_code, tool, used, ok, failed, credits, cost_usd)
  select v_date, x.provider_id, security.coverage_country(x.provider_id), x.tool, sum(x.used), sum(x.ok), sum(x.failed), sum(x.credits), sum(x.cost)
    from (
      -- course-page search: calls and credits; pages it bound that day, right or wrong
      select v.provider_id, 'course_search' tool, count(*)::int used, 0 ok, 0 failed, sum(v.units) credits, 0::numeric cost
        from pipeline.coverage_vendor_usage v where v.purpose = 'course_link_search' and v.at >= v_from and v.at < v_to and v.provider_id is not null group by 1
      union all
      select g.provider_id, 'course_search', 0, count(*) filter (where g.status = 'bound' and g.read_status = 'read')::int, count(*) filter (where g.status = 'mismatch')::int, 0, 0
        from pipeline.coverage_course_pages g where g.basis in ('title_search', 'firecrawl_search', 'serper_search', 'cricos_search') and g.bound_at >= v_from and g.bound_at < v_to group by 1
      union all
      -- course page reads: credits for scraper reads; pages read that day, read or not readable
      select v.provider_id, 'page_reads', 0, 0, 0, sum(v.units), 0 from pipeline.coverage_vendor_usage v
       where v.purpose in ('scrape', 'fc_read') and v.at >= v_from and v.at < v_to and v.provider_id is not null group by 1
      union all
      select g.provider_id, 'page_reads', count(*)::int, count(*) filter (where g.read_status = 'read')::int,
             count(*) filter (where g.read_status in ('fetch_failed', 'blocked', 'needs_render', 'robots_disallowed'))::int, 0, 0
        from pipeline.coverage_course_pages g where g.read_at >= v_from and g.read_at < v_to group by 1
      union all
      -- AI page match: a try worked when the page it chose was then read as the course's page
      select q.provider_id, 'ai_page_match', count(*)::int,
             count(*) filter (where q.state = 'chosen' and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = q.course_id and g.url = q.chosen_url and g.status = 'bound' and g.read_status = 'read'))::int,
             count(*) filter (where q.state in ('none', 'no_candidates', 'error'))::int, 0, coalesce(sum(q.cost_usd), 0)
        from pipeline.coverage_ai_match q where q.decided_at >= v_from and q.decided_at < v_to group by 1
      union all
      -- AI field reader: items settled that day
      select e.provider_id, 'ai_field_reader', count(*)::int, count(*) filter (where e.state = 'filled')::int, count(*) filter (where e.state in ('skipped', 'failed'))::int, 0, coalesce(sum(e.cost_usd), 0)
        from pipeline.field_enrich_items e where e.state in ('filled', 'skipped', 'failed', 'review') and e.updated_at >= v_from and e.updated_at < v_to group by 1
      union all
      select f.provider_id, 'fee_reader', count(*)::int, count(*) filter (where f.state = 'done' and coalesce(f.rows_found, 0) > 0)::int,
             count(*) filter (where not (f.state = 'done' and coalesce(f.rows_found, 0) > 0))::int, 0, coalesce(sum(f.cost_usd), 0)
        from pipeline.fee_reader_queue f where f.finished_at >= v_from and f.finished_at < v_to group by 1
      union all
      select s.provider_id, 'scholarship_ai', count(*)::int, count(*) filter (where s.applied is not null and s.applied not in ('null'::jsonb, '{}'::jsonb))::int,
             count(*) filter (where s.error is not null)::int, 0, coalesce(sum(s.cost_usd), 0)
        from pipeline.scholarship_ai_extractions s where s.at >= v_from and s.at < v_to and s.provider_id is not null group by 1
      union all
      select v.provider_id, 'other_credits', count(*)::int, 0, 0, sum(v.units), 0 from pipeline.coverage_vendor_usage v
       where v.purpose not in ('course_link_search', 'scrape', 'fc_read') and v.at >= v_from and v.at < v_to and v.provider_id is not null group by 1
      union all
      select f.provider_id, 'flags_raised', count(*)::int, 0, 0, 0, 0 from pipeline.enrichment_flags f
       where f.flagged_at >= v_from and f.flagged_at < v_to and f.provider_id is not null group by 1
    ) x
   where x.provider_id is not null
   group by x.provider_id, x.tool;
  get diagnostics v_n = row_count;
  delete from pipeline.toolset_use_daily where snapshot_date < v_date - security.pipeline_num_v1('retention.toolset_use_daily_days', 120)::int;
  get diagnostics v_old = row_count;
  return jsonb_build_object('date', v_date, 'rows', v_n, 'removed', v_old);
end $function$;
revoke execute on function security.toolset_use_daily_record_v1(date) from public, anon, authenticated;

-- seed 8 to 21 Oct 2026
do $seed$ declare d date; begin
  for d in select generate_series('2026-10-08'::date, '2026-10-21'::date, interval '1 day')::date loop
    perform security.toolset_use_daily_record_v1(d);
  end loop;
end $seed$;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('toolset-use-daily', 'Reporting', 41, 'Daily toolset use per provider', 'Daily at 6:58 am Melbourne (daylight time): records the day before''s use of each tool per provider (course search, page reads, AI page match, AI field reader, fee reader, scholarship AI, other credits, flags raised): used, worked, did not work, credits and US$. Keeps Settings › Pipeline settings › Storage & retention days.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('toolset-use-daily', '58 19 * * *', $$select security.toolset_use_daily_record_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.toolset_use_daily', 'Reporting', 'Daily toolset use per provider', 'active', '20261022011000'),
 ('function', 'security.toolset_use_daily_record_v1', 'Reporting', 'Writes a day of toolset use per provider', 'active', '20261022011000'),
 ('job', 'toolset-use-daily', 'Reporting', 'Daily toolset use per provider', 'active', '20261022011000')
on conflict (kind, name) do nothing;
