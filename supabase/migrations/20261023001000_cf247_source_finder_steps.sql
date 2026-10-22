-- CF-247 (23 Oct 2026). Course source finder test runs: one university's whole search (Firecrawl maps, robots.txt, site maps, list
-- pages) did not fit in one worker call for slow sites (Waikato 110 s, Université de Montréal over the 120 s limit), and Simon Fraser's
-- known course pages were stored at old addresses that now redirect. The finder now works in steps that carry over between runs, as the
-- other jobs do: 1 map (learn the pattern, home page study sites, Firecrawl map), 2 map_search (a map searched for the course words),
-- 3 sitemap (robots.txt and site maps), 4 lists (the course folder and the usual list addresses). Each run takes one step per university
-- and keeps what was learnt and tried (pipeline.source_find_runs.step and .work); a university part way through goes on first. Known
-- pages are taken at the address they were read at (the evidence copy's source_url).
-- Replaces: public.svc_source_find_next and public.svc_source_find_record (20261022044000; replaced in full, same signatures)
-- Retires: nothing
alter table pipeline.source_find_runs add column if not exists step text;
alter table pipeline.source_find_runs add column if not exists work jsonb;
comment on column pipeline.source_find_runs.step is 'CF-247 23 Oct 2026: the next step for a university part way through (map, map_search, sitemap, lists); null when finished.';
comment on column pipeline.source_find_runs.work is 'CF-247 23 Oct 2026: what the finder learnt so far for the next step (hosts, pattern, test run).';

create or replace function public.svc_source_find_next(p_limit integer default 3, p_provider_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb; v_share numeric := security.pipeline_num_v1('source_find.page_share_below', 0.95);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  create temp table if not exists _sf_pick(provider_id uuid) on commit drop; truncate _sf_pick;
  if p_provider_ids is not null then
    insert into _sf_pick select unnest(p_provider_ids) limit 20;  -- fixed: a test run looks at a handful of universities
  else
    -- 23 Oct 2026: a university part way through its steps goes on first
    insert into _sf_pick
    select r.provider_id from pipeline.source_find_runs r
     where r.step is not null and coalesce(r.leased_until, '-infinity') < now() and coalesce(r.work->>'test', 'false') <> 'true'
     order by r.tried_at nulls first limit greatest(1, least(coalesce(p_limit, 3), 10));  -- fixed: per-call safety cap; the run size is batch.source_find
    insert into _sf_pick
    with cand as (
      select p.id, (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') active,
             (select count(*) from catalogue.courses c join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.status = 'bound' and pg.read_status = 'read'
               where c.provider_id = p.id and c.lifecycle_status = 'active') paged,
             (select count(*) from catalogue.courses c where c.provider_id = p.id) all_courses
        from catalogue.providers p
       where p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active' and p.website is not null
         and security.coverage_country(p.id) in (select x.country_code from pipeline.source_find_countries x where x.enabled)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
         and not exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p.id and l.status <> 'stopped')
         and not exists (select 1 from pipeline.programme_sources s where s.provider_id = p.id and s.status <> 'stopped')
         and not exists (select 1 from pipeline.source_find_runs r where r.provider_id = p.id
                           and (r.state in ('found', 'tested') or coalesce(r.next_try_at, now()) > now() or coalesce(r.leased_until, '-infinity') > now())))
    select c.id from cand c
     where c.all_courses > 0 and (c.active = 0 or c.paged::numeric / c.active < v_share)
       and not exists (select 1 from _sf_pick x where x.provider_id = c.id)
     order by (c.active - c.paged) desc, c.all_courses desc
     limit greatest(0, least(coalesce(p_limit, 3), 10) - (select count(*) from _sf_pick));  -- fixed: per-call safety cap; the run size is batch.source_find
  end if;
  insert into pipeline.source_find_runs as r (provider_id, state, leased_until, attempts)
  select provider_id, 'leased', now() + interval '10 minutes', 1 from _sf_pick  -- fixed: lease for one call
  on conflict (provider_id) do update set state = 'leased', leased_until = excluded.leased_until, attempts = r.attempts + 1;
  select jsonb_build_object(
    'items', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.display_name, 'website', p.website,
                'step', (select r.step from pipeline.source_find_runs r where r.provider_id = p.id),
                'work', (select r.work from pipeline.source_find_runs r where r.provider_id = p.id),
                'tried', (select case when r.step is not null then r.tried end from pipeline.source_find_runs r where r.provider_id = p.id),
                'known', (select coalesce(jsonb_agg(u), '[]'::jsonb) from (
                           select distinct coalesce(e.source_url, pg.url) u from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.provider_id = p.id and pg.status = 'bound' and pg.read_status = 'read' and coalesce(e.source_url, pg.url) is not null
                           union select distinct c.course_url from catalogue.courses c where c.provider_id = p.id and c.course_url ~* '^https?://' and c.lifecycle_status = 'active'
                           limit 400) k))), '[]'::jsonb)  -- fixed: a sample of known course pages is enough to learn the pattern
                from _sf_pick x join catalogue.providers p on p.id = x.provider_id),
    'list_paths', (select coalesce(jsonb_agg(s.value order by s.sort), '[]'::jsonb) from pipeline.source_find_paths s where s.kind = 'list_path' and s.enabled),
    'folder_words', (select coalesce(jsonb_agg(s.value order by s.sort), '[]'::jsonb) from pipeline.source_find_paths s where s.kind = 'folder_word' and s.enabled),
    'settings', jsonb_build_object('min_links', security.pipeline_num_v1('source_find.min_links', 20), 'min_recall', security.pipeline_num_v1('source_find.min_recall', 0.5),
                'max_files', security.pipeline_num_v1('source_find.max_files', 25), 'max_locs', security.pipeline_num_v1('source_find.max_locs', 60000),
                'max_list_tries', security.pipeline_num_v1('source_find.max_list_tries', 8)))
    into v;
  return v;
end $function$;
revoke all on function public.svc_source_find_next(integer, uuid[]) from public, anon, authenticated;
grant execute on function public.svc_source_find_next(integer, uuid[]) to service_role;

create or replace function public.svc_source_find_record(p_provider_id uuid, p_result jsonb, p_test boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_ch jsonb := p_result->'chosen'; v_active int; v_added text; v_state text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- 23 Oct 2026: a step done and more to try: what was learnt and tried is kept, and the next run takes the next step
  if p_result ? 'step_next' then
    insert into pipeline.source_find_runs as r (provider_id, state, tried_at, step, work, tried, known, pattern, pattern_basis, worker)
    values (p_provider_id, 'leased', now(), p_result->>'step_next', coalesce(p_result->'work', '{}'::jsonb) || jsonb_build_object('test', p_test),
            coalesce(p_result->'tried', '[]'::jsonb), (p_result->>'known')::int, left(p_result->>'pattern', 500), p_result->>'pattern_basis', p_result->>'worker')
    on conflict (provider_id) do update set state = 'leased', tried_at = now(), leased_until = null, next_try_at = null, step = excluded.step, work = excluded.work,
           tried = excluded.tried, known = excluded.known, pattern = excluded.pattern, pattern_basis = excluded.pattern_basis, worker = excluded.worker;
    return jsonb_build_object('state', 'leased', 'step', p_result->>'step_next');
  end if;
  select count(*) into v_active from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active';
  if jsonb_typeof(v_ch) = 'object' and v_ch->>'url' ~* '^https?://' then
    v_state := case when p_test then 'tested' else 'found' end;
    if not p_test then
      if v_active < security.pipeline_num_v1('source_find.programme_below', 1) then
        insert into pipeline.programme_sources(provider_id, url, kind, url_pattern, child_pattern, read_via, reason)
        values (p_provider_id, v_ch->>'url', case when v_ch->>'kind' = 'list' then 'list' else 'sitemap' end, coalesce(v_ch->>'link_pattern', p_result->>'pattern'), v_ch->>'child_pattern',
                case when v_ch->>'kind' = 'map' then 'map' end,
                'Found by the course source finder (' || coalesce(v_ch->>'matches', '?') || ' programme addresses)')
        on conflict (provider_id, url) do nothing;
        v_added := 'programme_list';
      else
        insert into pipeline.provider_course_lists(provider_id, url, reason, added_by, link_pattern, child_pattern, read_via)
        values (p_provider_id, v_ch->>'url', 'Found by the course source finder (' || coalesce(v_ch->>'matches', '?') || ' course addresses)', null,
                case when v_ch->>'kind' in ('sitemap', 'map') then coalesce(v_ch->>'link_pattern', p_result->>'pattern') end, case when v_ch->>'kind' = 'sitemap' then v_ch->>'child_pattern' end,
                case when v_ch->>'kind' = 'map' then 'map' end)
        on conflict (provider_id, url) do nothing;
        v_added := 'course_list';
      end if;
    end if;
  else
    v_state := case when p_result->>'error' is not null then 'failed' else 'none' end;
  end if;
  insert into pipeline.source_find_runs as r (provider_id, state, step, work, tried_at, next_try_at, leased_until, known, pattern, pattern_basis, chosen, tried, reason, added, worker)
  values (p_provider_id, v_state, null, null, now(),
          case when v_state in ('none', 'failed') then now() + make_interval(days => security.pipeline_num_v1('source_find.retry_days', 14)::int) end, null,
          (p_result->>'known')::int, left(p_result->>'pattern', 500), p_result->>'pattern_basis', v_ch, coalesce(p_result->'tried', '[]'::jsonb),
          left(coalesce(p_result->>'reason', p_result->>'error'), 500), v_added, p_result->>'worker')
  on conflict (provider_id) do update set state = excluded.state, step = null, work = null, tried_at = excluded.tried_at, next_try_at = excluded.next_try_at, leased_until = null,
         known = excluded.known, pattern = excluded.pattern, pattern_basis = excluded.pattern_basis, chosen = excluded.chosen, tried = excluded.tried,
         reason = excluded.reason, added = excluded.added, worker = excluded.worker;
  return jsonb_build_object('state', v_state, 'added', v_added);
end $function$;
revoke all on function public.svc_source_find_record(uuid, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.svc_source_find_record(uuid, jsonb, boolean) to service_role;

select 'source finder works in steps' ok;
