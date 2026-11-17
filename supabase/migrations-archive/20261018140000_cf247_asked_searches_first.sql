-- CF-247 (18 Oct 2026, v2.15.290). Platform Admin 22:25 "proceed with recommended choice": course-page searches a person asked for jump the
-- queue. Found while checking it: since the focus rule of 15 Oct (security.enrich_focus_v1, the 50 Australian focus providers) the worker
-- takes no search for any other Australian provider, even one a person asked for in the Adapter builder (Find course pages, a website
-- change). Sydney Film School's 4 searches, queued by the website change at 21:47, could never run; no course-page search has been sent
-- since 13 Oct.
-- 1 public.svc_course_link_search_next: a search a person asked for (requested_at set: Find course pages, a website change) runs for any
--   provider and goes first, oldest request first. Every other check stays: Firecrawl target universities only, a stopped or held search,
--   directory sites, the monthly cap and the day's share for course search. Searches nobody asked for keep the focus rule.
-- 2 security.provider_website_change_apply_v1: every queued search of the provider is marked as asked for after a website change.
-- 3 public.admin_course_search_queue(provider): for the Adapter builder guide, whether this provider's searches will run and how many
--   asked-for searches are ahead, so the guide never says "running by itself" for searches that are waiting on a rule.
-- Both replacements are guarded: the live definition must be the one this change was written against, and each edit must apply once.
-- Replaces: the focus filter and order in public.svc_course_link_search_next (asked-for searches exempt and first)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $edit$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure);
  if md5(v_def) <> '8b6c6f829d6269a0448ed9e6faff5aa0' then raise exception 'live public.svc_course_link_search_next differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, '       and security.enrich_focus_v1(s.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)', ''))) / length('       and security.enrich_focus_v1(s.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)') <> 1
     or (length(v_def) - length(replace(v_def, '     order by security.fc_provider_tier_v1(s.provider_id), ', ''))) / length('     order by security.fc_provider_tier_v1(s.provider_id), ') <> 1 then
    raise exception 'svc_course_link_search_next: each edited line must appear exactly once';
  end if;
  v_new := replace(v_def, '       and security.enrich_focus_v1(s.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)',
    '       and (security.enrich_focus_v1(s.provider_id) or s.requested_at is not null)  -- CF-247 15 Oct: focus providers only (Waste rules); 18 Oct: a search a person asked for runs for any provider');
  v_new := replace(v_new, '     order by security.fc_provider_tier_v1(s.provider_id), ',
    '     order by (s.requested_at is null), s.requested_at, security.fc_provider_tier_v1(s.provider_id), ');
  execute v_new;

  v_def := pg_get_functiondef('security.provider_website_change_apply_v1(uuid)'::regprocedure);
  if md5(v_def) <> '9c20438a5f48d19e7d163a8ad2e3b603' then raise exception 'live security.provider_website_change_apply_v1 differs from the definition this change edits'; end if;
  v_new := replace(v_def, E'  get diagnostics v_requeued = row_count;\n',
    E'  get diagnostics v_requeued = row_count;\n  -- 18 Oct: every queued search of this provider counts as asked for, so it runs first and for any provider\n  update pipeline.course_link_search set requested_at = now() where provider_id = v_c.provider_id and state = ''queued'' and requested_at is null;\n');
  if v_new = v_def then raise exception 'provider_website_change_apply_v1: the edit did not apply'; end if;
  execute v_new;
end $edit$;

CREATE OR REPLACE FUNCTION public.admin_course_search_queue(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_queued int; v_asked int; v_sent int; v_first timestamptz; v_ahead int; v_focus boolean; v_target boolean; v_stopped boolean; v_left numeric; v_on boolean; v_why text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select count(*) filter (where s.state = 'queued'), count(*) filter (where s.state = 'queued' and s.requested_at is not null), count(*) filter (where s.state = 'sent'),
         min(s.requested_at) filter (where s.state = 'queued')
    into v_queued, v_asked, v_sent, v_first from pipeline.course_link_search s where s.provider_id = p_provider_id;
  select count(*) into v_ahead from pipeline.course_link_search s
   where s.state = 'queued' and s.requested_at is not null and s.provider_id <> p_provider_id and s.requested_at < coalesce(v_first, now());
  v_focus := security.enrich_focus_v1(p_provider_id);
  v_target := not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
              or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = p_provider_id and tc.included);
  v_stopped := p_provider_id = any (array(select x.provider_id from security.fc_search_stopped_v1() x));
  v_left := security.fc_budget_left_v1('course_link_search');
  select enabled into v_on from pipeline.course_link_search_settings where id = 1;
  v_why := case when v_queued + v_sent = 0 then null
                when not coalesce(v_on, false) then 'course-page search is switched off (Firecrawl settings)'
                when v_stopped then 'the search for this university is stopped or held: press Search again on Firecrawl credits by university'
                when not v_target then 'this university is not a Firecrawl target university, so it is not searched'
                when v_left < 2 then 'today''s Firecrawl share for course search is used up; it continues tomorrow'
                when v_asked = 0 and v_sent = 0 and not v_focus then 'waiting: outside the focus providers, so it runs only when asked for; press Find every missing page'
                else null end;
  return jsonb_build_object('queued', v_queued, 'asked', v_asked, 'sent', v_sent, 'ahead', v_ahead, 'in_focus', v_focus, 'target', v_target,
                            'stopped', v_stopped, 'budget_left', v_left, 'runs', v_why is null and v_queued + v_sent > 0, 'why', v_why);
end $function$;
revoke execute on function public.admin_course_search_queue(uuid) from public, anon;
grant execute on function public.admin_course_search_queue(uuid) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_course_search_queue', 'L2 read', 'Adapter builder guide: whether a provider''s course-page searches will run, and how many asked-for searches are ahead', 'active', '20261018140000')
on conflict (kind, name) do nothing;

-- Sydney Film School's searches were queued by the website change at 21:47 before this rule: mark them as asked for
update pipeline.course_link_search s set requested_at = now()
 where s.state = 'queued' and s.requested_at is null
   and exists (select 1 from pipeline.provider_website_checks c where c.provider_id = s.provider_id and c.action = 'change' and c.applied);

do $post$
declare v text;
begin
  v := pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure);
  if position('or s.requested_at is not null)' in v) = 0 or position('order by (s.requested_at is null), s.requested_at, security.fc_provider_tier_v1' in v) = 0 then raise exception 'post-check: svc_course_link_search_next not as intended'; end if;
  if position('and requested_at is null;' in pg_get_functiondef('security.provider_website_change_apply_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: apply not as intended'; end if;
end $post$;
