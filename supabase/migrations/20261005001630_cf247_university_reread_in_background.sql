-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 21:20): reading pages again for 61 universities at once stopped at
-- the 8-second limit on screen calls ("canceling statement due to statement timeout"), so nothing was sent.
-- Now the button records the request and returns at once. A job every minute sends the pages back, ten universities
-- at a time, and the screen shows each request's progress. The preview is one pass over the pages.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.university_reread_requests (
  id uuid primary key default gen_random_uuid(),
  provider_ids uuid[] not null,
  done_ids uuid[] not null default '{}',
  which text not null check (which in ('all', 'not_confirmed')),
  central boolean not null default false,
  reason text not null,
  requested_by uuid,
  requested_at timestamptz not null default now(),
  pages int not null default 0,
  central_pages int not null default 0,
  status text not null default 'waiting' check (status in ('waiting', 'sending', 'sent', 'failed')),
  last_error text,
  finished_at timestamptz
);
alter table pipeline.university_reread_requests enable row level security;
revoke all on table pipeline.university_reread_requests from anon, authenticated;

create or replace function security.university_reread_process_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_batch uuid[]; v_pages int; v_cent int; v_n int := 0;
begin
  for r in select * from pipeline.university_reread_requests q where q.status in ('waiting', 'sending') order by q.requested_at for update skip locked loop
    v_batch := array(select x from unnest(r.provider_ids) x where x <> all (r.done_ids) limit 10);
    if cardinality(v_batch) = 0 then
      update pipeline.university_reread_requests set status = 'sent', finished_at = now() where id = r.id;
      continue;
    end if;
    begin
      insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
        select p.course_id, p.provider_id, p.url, p.url, 'read again by a Platform Admin (' || left(r.reason, 300) || ')'
          from security.university_reread_pages_v1(v_batch, r.which) p;
      update pipeline.coverage_course_pages pg set status = 'bound', read_attempts = 0, next_read_at = now(), leased_until = null where pg.course_id in (select p.course_id from security.university_reread_pages_v1(v_batch, r.which) p);
      get diagnostics v_pages = row_count;
      v_cent := 0;
      if r.central then
        update pipeline.provider_fact_sources fs set status = 'found', attempts = 0, updated_at = now() where fs.provider_id = any (v_batch) and fs.kind in ('english_policy', 'intake_calendar');
        get diagnostics v_cent = row_count;
      end if;
      update pipeline.university_reread_requests set done_ids = done_ids || v_batch, pages = pages + v_pages, central_pages = central_pages + v_cent, status = case when cardinality(done_ids || v_batch) >= cardinality(provider_ids) then 'sent' else 'sending' end, finished_at = case when cardinality(done_ids || v_batch) >= cardinality(provider_ids) then now() end where id = r.id;
    exception when others then
      update pipeline.university_reread_requests set status = 'failed', last_error = left(sqlerrm, 300), finished_at = now() where id = r.id;
    end;
    v_n := v_n + 1;
    exit when v_n >= 3;
  end loop;
  return jsonb_build_object('requests', v_n);
end $f$;
revoke all on function security.university_reread_process_v1() from public, anon, authenticated;
select cron.schedule('university-reread-requests', '* * * * *', 'select security.university_reread_process_v1()');

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_university_reread(text,jsonb)'::regprocedure) is distinct from '6da92b56224f240999c12696dbcc9dd6' then
    raise exception 'admin_university_reread changed, not replacing'; end if;
end $p$;

create or replace function public.admin_university_reread(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
  v_ids uuid[]; v_which text := coalesce(nullif(p_args->>'which', ''), 'all'); v_central boolean := coalesce((p_args->>'central')::boolean, false);
  v_res jsonb; v_id uuid;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'requests' then
    return coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'universities', cardinality(q.provider_ids), 'done', cardinality(q.done_ids), 'which', q.which, 'central', q.central,
                       'pages', q.pages, 'central_pages', q.central_pages, 'status', q.status, 'last_error', q.last_error, 'requested_at', q.requested_at, 'finished_at', q.finished_at, 'reason', q.reason) order by q.requested_at desc)
                       from (select * from pipeline.university_reread_requests order by requested_at desc limit 10) q), '[]'::jsonb);
  end if;
  if v_which not in ('all', 'not_confirmed') then raise exception 'which must be all or not_confirmed'; end if;
  v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
  if cardinality(v_ids) = 0 then raise exception 'choose at least one university'; end if;
  if p_action = 'preview' then
    return jsonb_build_object('which', v_which, 'central', v_central,
      'universities', coalesce((
        with pages as materialized (select r.provider_id, count(*) n, count(*) filter (where r.firecrawl_likely) fc from security.university_reread_pages_v1(v_ids, v_which) r group by r.provider_id),
             cent as materialized (select fs.provider_id, count(*) n from pipeline.provider_fact_sources fs where v_central and fs.provider_id = any (v_ids) and fs.kind in ('english_policy', 'intake_calendar') group by fs.provider_id)
        select jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'pages', coalesce(pages.n, 0), 'firecrawl_likely', coalesce(pages.fc, 0), 'central_pages', coalesce(cent.n, 0))
                         order by coalesce(p.display_name, p.canonical_name))
          from catalogue.providers p left join pages on pages.provider_id = p.id left join cent on cent.provider_id = p.id where p.id = any (v_ids)), '[]'::jsonb));
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action <> 'queue' then raise exception 'unknown action'; end if;
  insert into pipeline.university_reread_requests(provider_ids, which, central, reason, requested_by) values (v_ids, v_which, v_central, v_reason, auth.uid()) returning id into v_id;
  v_res := jsonb_build_object('ok', true, 'request_id', v_id, 'universities', cardinality(v_ids), 'status', 'waiting');
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('coverage', 'university_reread', array_to_string(v_ids, ','), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;
revoke all on function public.admin_university_reread(text, jsonb) from public, anon;
grant execute on function public.admin_university_reread(text, jsonb) to authenticated;
