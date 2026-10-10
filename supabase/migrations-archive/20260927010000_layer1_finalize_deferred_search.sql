-- Package 9.1 (R16): the Layer 1 finaliser ran the full consumer search refresh (12–15 s) inside the
-- ingest's API call (8 s limit) and timed out. It now records a refresh request and returns; a
-- background job applies the search refresh (writes only changed documents) within minutes.
create table if not exists search.refresh_requests(
  id bigint generated always as identity primary key,
  requested_at timestamptz not null default now(),
  requested_by text not null,
  processed_at timestamptz,
  result jsonb);
alter table search.refresh_requests enable row level security;
revoke all on search.refresh_requests from public, anon, authenticated;

create or replace function public.svc_layer1_finalize_catalogue()
returns jsonb language plpgsql security definer
set search_path to 'public', 'catalogue', 'search', 'pipeline'
as $$
declare v_generation bigint; v_docs bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into search.refresh_requests(requested_by) values ('svc_layer1_finalize_catalogue');
  select coalesce(max(generation),0) into v_generation from search.projection_state;
  select count(*) into v_docs from search.course_documents;
  return jsonb_build_object(
    'providers', (select count(*) from catalogue.providers),
    'courses', (select count(*) from catalogue.courses),
    'cricos_provider_registrations', (select count(*) from catalogue.provider_registrations where lower(registration_scheme)='cricos'),
    'cricos_course_registrations', (select count(*) from catalogue.course_registrations where lower(scheme)='cricos'),
    'search_documents', v_docs, 'search_generation', v_generation,
    'search_refresh', 'requested (applied by the search-refresh job within minutes)');
end $$;
revoke all on function public.svc_layer1_finalize_catalogue() from public, anon, authenticated;
grant execute on function public.svc_layer1_finalize_catalogue() to service_role;

create or replace function security.search_refresh_requested_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','search'
as $$
declare v_ids bigint[]; r jsonb;
begin
  select array_agg(id) into v_ids from search.refresh_requests where processed_at is null;
  if v_ids is null then return jsonb_build_object('pending',0); end if;
  r := search.refresh_course_documents_v3(true);
  update search.refresh_requests set processed_at=now(), result=jsonb_build_object('base_applied',r->'base'->'applied_rows','base_changed',r->'base'->'changed','generation',r->'base'->'generation') where id = any(v_ids);
  return jsonb_build_object('processed',cardinality(v_ids),'base_applied',r->'base'->'applied_rows');
end $$;
revoke all on function security.search_refresh_requested_v1() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname='search-refresh-requested';
select cron.schedule('search-refresh-requested','6-59/10 * * * *',$c$select security.search_refresh_requested_v1();$c$);
