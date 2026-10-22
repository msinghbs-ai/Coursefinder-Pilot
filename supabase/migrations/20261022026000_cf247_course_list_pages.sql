-- CF-247 (22 Oct 2026). Platform Admin 16:30, choice "Course list page per provider (Recommended)": for the 192 published providers with
-- courses but no adapter (most stopped in onboarding for too few course pages), "paste the provider's course finder page (e.g.
-- waikato.ac.nz/study/qualifications). All its course links are read from it in one go, in any language. A weekly job retries the stopped
-- ones." Earlier (15:05): "will that be helpful in case of website being searched for courses and not finding it - especially different
-- language and nz based".
-- Found: the AI page match draws its candidates from the provider's site addresses (pipeline.coverage_provider_urls) and, in Australia, only
-- for the focus providers; a course that had no candidates is never prepared again; title search is held for automatic requests since
-- this morning. So a stopped provider had nothing left that would find its pages, although its note said it carries on by itself.
-- 1 pipeline.provider_course_lists: a provider's own course list page, entered by a person (Adapter builder 2.1, Pipeline Operator and
--   above, with a reason). public.admin_course_list: list, add, stop, read_now.
-- 2 Job course-list-read (every 10 minutes, only when a list is due): worker mode course_list_read reads the page directly, through the
--   scraper when the direct read finds too few links (pages drawn by the browser), follows the list's next pages, and records every
--   course link with its link text. public.svc_course_list_record adds them to the provider's site addresses (source course_list).
-- 3 The AI page match (security.coverage_ai_match_prepare_v1) runs for a provider with a read course list wherever it is, and gives each
--   of its courses one more attempt after each read of the list (a course that had no candidates before is prepared again).
-- 4 Weekly: a read list is read again after course_list.reread_days (7), so stopped providers get new candidates and one more attempt
--   each week; onboarding carries on by itself once 3 of their pages are read (v2.15.260 rule).
-- Replaces: security.coverage_ai_match_prepare_v1 (course list providers; one more attempt after a list read). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

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

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.course_list_read', 'Course list pages read per run', 'Each run of the course-list-read job reads this many due course list pages (a provider''s own course finder page, entered by a person).', 'number', to_jsonb(5), 1, 50, 'pages', 317, 'CF-247 22 Oct 2026 (course list page per provider)', 'Enrichment', 'job course-list-read; coverage-sweep course_list_read'),
 ('pipeline', 'course_list.max_pages', 'Course list: next pages followed', 'A course list split over several pages is followed through this many of its own next pages.', 'number', to_jsonb(10), 1, 50, 'pages', 318, 'CF-247 22 Oct 2026', 'Enrichment', 'public.svc_course_list_next'),
 ('pipeline', 'course_list.min_links', 'Course list: links before the scraper is used', 'When the direct read of a course list page finds fewer links than this, the page is read through the scraper (it is probably drawn by the browser).', 'number', to_jsonb(20), 1, 500, 'links', 319, 'CF-247 22 Oct 2026', 'Enrichment', 'public.svc_course_list_next'),
 ('pipeline', 'course_list.reread_days', 'Course list read again after', 'A course list page that was read is read again after this many days; its courses without a page get one more AI page match after each read (the weekly retry).', 'number', to_jsonb(7), 1, 90, 'days', 320, 'CF-247 22 Oct 2026', 'Enrichment', 'public.svc_course_list_record'),
 ('pipeline', 'course_list.retry_hours', 'Course list tried again after', 'A course list page that could not be read is tried again after this many hours.', 'number', to_jsonb(12), 1, 168, 'hours', 321, 'CF-247 22 Oct 2026', 'Enrichment', 'public.svc_course_list_record'),
 ('pipeline', 'course_list.max_attempts', 'Course list attempts', 'A course list page is given up after this many failed reads in a row (it shows as failed; Read now tries again).', 'number', to_jsonb(4), 1, 20, 'reads', 322, 'CF-247 22 Oct 2026', 'Enrichment', 'public.svc_course_list_next')
on conflict (toolset_key, key) do nothing;

-- 1 ---------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.provider_course_lists (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  url text not null,
  status text not null default 'due' check (status in ('due', 'read', 'failed', 'blocked', 'gone', 'stopped')),
  http_status int,
  fetched_via text,
  pages_read int not null default 0,
  links_found int not null default 0,
  links_new int not null default 0,
  read_attempts int not null default 0,
  read_at timestamptz,
  next_read_at timestamptz not null default now(),
  leased_until timestamptz,
  reason text not null,
  added_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_id, url)
);
comment on table pipeline.provider_course_lists is 'CF-247 22 Oct 2026: a provider''s own course list or course finder page entered by a person; read by job course-list-read for its course links (with their link text), which are added to the provider''s site addresses (pipeline.coverage_provider_urls, source course_list) for the page matchers. Read again every course_list.reread_days.';
alter table pipeline.provider_course_lists enable row level security;

create or replace function security.course_list_read_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $function$
  select exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p_provider and l.status = 'read' and l.links_found > 0)
$function$;
comment on function security.course_list_read_v1(uuid) is 'CF-247 22 Oct 2026: the provider has a course list page that was read with links.';
revoke all on function security.course_list_read_v1(uuid) from public;

create or replace function security.course_list_bonus_v1(p_course uuid, p_provider uuid) returns int
language sql stable security definer set search_path = '' as $function$
  -- one more AI page match for a course after each read of its provider's course list
  select case when exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p_provider and l.status = 'read' and l.links_found > 0
                             and l.read_at > coalesce((select max(q.created_at) from pipeline.coverage_ai_match q where q.course_id = p_course), '-infinity'::timestamptz))
              then 1 else 0 end
$function$;
comment on function security.course_list_bonus_v1(uuid, uuid) is 'CF-247 22 Oct 2026: 1 when the provider''s course list was read after the course''s last AI page match (one more attempt), else 0.';
revoke all on function security.course_list_bonus_v1(uuid, uuid) from public;

create or replace function public.admin_course_list(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_url text := btrim(coalesce(p_args->>'url', '')); v_id uuid;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object('lists', (select coalesce(jsonb_agg(to_jsonb(l) - 'leased_until' order by l.created_at), '[]'::jsonb) from pipeline.provider_course_lists l where l.provider_id = v_pid),
                              'can_manage', v_rank >= 4);
  end if;
  if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'add' then
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if v_url !~ '^https?://[^ ]+\.[^ ]+$' or length(v_url) > 1000 then raise exception 'give the full page address (http or https)'; end if;
    insert into pipeline.provider_course_lists(provider_id, url, reason, added_by) values (v_pid, v_url, v_reason, auth.uid())
    on conflict (provider_id, url) do update set status = 'due', read_attempts = 0, next_read_at = now(), reason = excluded.reason, updated_at = now()
    returning id into v_id;
  elsif p_action in ('stop', 'read_now') then
    update pipeline.provider_course_lists l set status = case when p_action = 'stop' then 'stopped' else 'due' end, read_attempts = 0,
           next_read_at = case when p_action = 'stop' then 'infinity'::timestamptz else now() end, updated_at = now()
     where l.id = nullif(p_args->>'id', '')::uuid returning l.id, l.provider_id into v_id, v_pid;
    if v_id is null then raise exception 'unknown course list page'; end if;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('course_lists', p_action, v_pid::text, jsonb_build_object('id', v_id, 'url', nullif(v_url, ''), 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id, 'note', case when p_action = 'stop' then 'Stopped.' else 'Read within about 10 minutes; its links then go to the page matcher.' end);
end $function$;
comment on function public.admin_course_list(text, jsonb) is 'CF-247 22 Oct 2026: a provider''s course list pages: list (Curator and above), add, stop, read_now (Pipeline Operator and above, with a reason, logged).';
revoke all on function public.admin_course_list(text, jsonb) from public, anon;
grant execute on function public.admin_course_list(text, jsonb) to authenticated;

-- 2 ---------------------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_course_list_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select l.id from pipeline.provider_course_lists l
     where l.status <> 'stopped' and l.next_read_at <= now() and (l.leased_until is null or l.leased_until < now())
       and l.read_attempts < security.pipeline_num_v1('course_list.max_attempts', 4)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = l.provider_id)  -- unpublished providers wait
     order by l.next_read_at
     limit greatest(1, least(coalesce(p_limit, 5), 50))  -- fixed: per-call safety cap; the run size is batch.course_list_read
     for update skip locked),
  upd as (update pipeline.provider_course_lists l set leased_until = now() + interval '10 minutes', updated_at = now()  -- fixed: lease for one call
            from pick where l.id = pick.id returning l.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url,
           'max_pages', security.pipeline_num_v1('course_list.max_pages', 10)::int, 'min_links', security.pipeline_num_v1('course_list.min_links', 20)::int)), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;
revoke all on function public.svc_course_list_next(integer) from public, anon, authenticated;

create or replace function public.svc_course_list_record(p_id uuid, p_status text, p_http integer, p_via text, p_links jsonb, p_pages integer) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare l pipeline.provider_course_lists%rowtype; v_new int := 0; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into l from pipeline.provider_course_lists where id = p_id for update;
  if l.id is null then return jsonb_build_object('error', 'unknown course list'); end if;
  if p_status = 'read' then
    v_n := coalesce(jsonb_array_length(p_links), 0);
    with ins as (
      insert into pipeline.coverage_provider_urls(provider_id, url, title, tokens, title_tokens, source)
      select l.provider_id, left(e->>'url', 1000), left(e->>'title', 300), security.coverage_text_tokens(security.coverage_slug(e->>'url')),
             security.coverage_text_tokens(regexp_replace(coalesce(e->>'title', ''), '\s[|–—]\s.*$', '')), 'course_list'
        from jsonb_array_elements(coalesce(p_links, '[]'::jsonb)) e where coalesce(e->>'url', '') ~ '^https?://'
      on conflict (provider_id, url) do update set last_seen_at = now(),
             title = coalesce(nullif(pipeline.coverage_provider_urls.title, ''), excluded.title),
             title_tokens = case when cardinality(pipeline.coverage_provider_urls.title_tokens) = 0 then excluded.title_tokens else pipeline.coverage_provider_urls.title_tokens end
      returning (xmax = 0) inserted)
    select count(*) filter (where inserted) into v_new from ins;
  end if;
  update pipeline.provider_course_lists set
         status = case when p_status in ('read', 'failed', 'blocked', 'gone', 'due') then p_status else 'failed' end,
         http_status = p_http, fetched_via = p_via, leased_until = null, updated_at = now(), pages_read = coalesce(p_pages, 0),
         links_found = case when p_status = 'read' then v_n else links_found end, links_new = case when p_status = 'read' then v_new else links_new end,
         read_at = case when p_status = 'read' then now() else read_at end,
         read_attempts = case when p_status = 'read' then 0 when p_status = 'due' then read_attempts else read_attempts + 1 end,
         next_read_at = case when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('course_list.reread_days', 7)::int)
                             when p_status = 'due' then now()
                             else now() + make_interval(hours => security.pipeline_num_v1('course_list.retry_hours', 12)::int) end
   where id = p_id;
  return jsonb_build_object('links', v_n, 'new', v_new);
end $function$;
revoke all on function public.svc_course_list_record(uuid, text, integer, text, jsonb, integer) from public, anon, authenticated;

-- 3 ---------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', '7ee31f407e29af54aa32e5cd6104f294', array[
  [$o$         and security.enrich_focus_v1(co.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)$o$,
   $n$         and (security.enrich_focus_v1(co.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)
              or security.course_list_read_v1(co.provider_id))  -- 22 Oct 2026: and any provider with a read course list page$n$],
  [$o$         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
       group by 1)$o$,
   $n$         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and (q.state in ('ready', 'leased')
                           or (q.state = 'no_candidates' and security.course_list_bonus_v1(co.id, co.provider_id) = 0)))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap + security.course_list_bonus_v1(co.id, co.provider_id)  -- 22 Oct 2026: one more after a course list read
       group by 1)$n$],
  [$o$         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
       order by$o$,
   $n$         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and (q.state in ('ready', 'leased')
                           or (q.state = 'no_candidates' and security.course_list_bonus_v1(co.id, co.provider_id) = 0)))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap + security.course_list_bonus_v1(co.id, co.provider_id)
       order by$n$]]);

-- 4 job ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('course-list-read', 'Enrichment', 49, 'Course list pages', 'Every 10 minutes when one is due: reads the course list pages people entered for providers (directly, or through the scraper when the page is drawn by the browser), follows their next pages and adds every course link with its link text to the provider''s site addresses for the page matchers. Each list is read again weekly (course_list.reread_days), giving its courses without a page one more AI page match.', 4, true, 'pages')
on conflict (jobname) do nothing;
select cron.schedule('course-list-read', '3-59/10 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'course_list_read', 'limit', security.pipeline_num_v1('batch.course_list_read', 5)::int)) where exists (select 1 from pipeline.provider_course_lists l where l.status <> 'stopped' and l.next_read_at <= now())$c$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_course_lists', 'Layer 2', 'A provider''s own course list page, entered by a person', 'active', '{}', '20261022026000'),
 ('function', 'public.admin_course_list', 'Layer 2', 'Course list pages: list, add, stop, read now', 'active', '{}', '20261022026000'),
 ('function', 'public.svc_course_list_next', 'Layer 2', 'Due course list pages for the worker', 'active', '{}', '20261022026000'),
 ('function', 'public.svc_course_list_record', 'Layer 2', 'Course list links into the provider''s site addresses', 'active', '{}', '20261022026000'),
 ('function', 'security.course_list_read_v1', 'Layer 2', 'Provider has a read course list', 'active', '{}', '20261022026000'),
 ('function', 'security.course_list_bonus_v1', 'Layer 2', 'One more AI page match after a course list read', 'active', '{}', '20261022026000')
on conflict (kind, name) do nothing;
