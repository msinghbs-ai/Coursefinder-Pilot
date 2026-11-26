-- CF-247 s1215 (S1-API-Frontend-Delivery; Atlas brief 26 Nov 2026 12:02 AEDT). One small read for the portal's Entry Requirements screen:
-- public.portal_study_levels_v1() returns the live study levels the screen offers as its Study level filter, so no list is written into
-- the screen (s930). It lists the top-level active levels that have at least one course in the portal's scope, in the table's own order;
-- a top-level level also matches its children (for example masters matches masters_coursework), as portal_aer_list_v1 (s1214, S2-Build) filters.
-- Viewer rank and above; anon and public refused. Read only; no table is written.
-- Not the consumer API: no consumer function, table or column is changed (G3 checked). G1: no job. G2: no setting needed. Locks untouched.
-- Nothing dropped. No AI or Firecrawl call; US$0.
-- Replaces: nothing (new read).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function create

create temp table s1215_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

create or replace function public.portal_study_levels_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return (select coalesce(jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name) order by s.sort_order nulls last, s.name), '[]'::jsonb)
            from ref.study_levels s
           where s.status = 'active' and s.parent_id is null
             and exists (select 1 from search.course_documents d where d.study_level_code = s.code or d.study_level_code like s.code || '\_%'));
end $function$;

comment on function public.portal_study_levels_v1() is 'CF-247 s1215: the live study levels for the portal Entry Requirements filter (Viewer and above).';

revoke all on function public.portal_study_levels_v1() from public, anon;
grant execute on function public.portal_study_levels_v1() to authenticated;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'public.portal_study_levels_v1', 'Service', 'Portal', 'Portal Entry requirements: the live study levels for the filter', 'active', '{}', '20261129090000')
on conflict do nothing;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1215_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1215_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.portal_study_levels_v1()', 'execute') or not has_function_privilege('authenticated', 'public.portal_study_levels_v1()', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  select jsonb_agg(jsonb_build_object('code', s.code)) into x from ref.study_levels s
   where s.status = 'active' and s.parent_id is null and exists (select 1 from search.course_documents d where d.study_level_code = s.code or d.study_level_code like s.code || '\_%');
  if x is null or jsonb_array_length(x) < 5 then raise exception 'post-check: too few study levels: %', x; end if;
end $post$;
