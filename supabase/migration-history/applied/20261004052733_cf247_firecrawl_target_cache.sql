-- CF-247 Decision 253 (4 Oct 2026). The worker asks for the target universities at the start of every call. Worked out
-- live this took 4 to 8 seconds under load and hit the API time limit, so the worker saw no targets and (setting on)
-- made no Firecrawl calls at all from 05:21 UTC. The list is now kept in a small table refreshed every minute (and
-- whenever it is more than 5 minutes old). Also: the page format Firecrawl returns is a setting (raw HTML keeps the
-- page title, which the identity check uses).
-- No text value in this file contains a semicolon.

create table if not exists pipeline.firecrawl_target_cache (
  provider_id uuid primary key,
  included boolean not null,
  refreshed_at timestamptz not null default now()
);
alter table pipeline.firecrawl_target_cache enable row level security;
revoke all on pipeline.firecrawl_target_cache from anon, authenticated;

create or replace function security.firecrawl_targets_refresh_v1() returns int
language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  insert into pipeline.firecrawl_target_cache(provider_id, included, refreshed_at)
    select t.provider_id, t.included, now() from security.firecrawl_targets_v1() t
  on conflict (provider_id) do update set included = excluded.included, refreshed_at = now() where pipeline.firecrawl_target_cache.provider_id = excluded.provider_id;
  get diagnostics n = row_count;
  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;
  return n;
end $f$;
revoke all on function security.firecrawl_targets_refresh_v1() from public, anon, authenticated;

create or replace function public.svc_fc_targets() returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.firecrawl_target_cache c where c.refreshed_at > now() - interval '5 minutes') then perform security.firecrawl_targets_refresh_v1(); end if;
  return jsonb_build_object('target_only', coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true),
                            'ids', coalesce((select jsonb_agg(c.provider_id) from pipeline.firecrawl_target_cache c where c.included), '[]'::jsonb));
end $f$;
revoke all on function public.svc_fc_targets() from public, anon, authenticated;
grant execute on function public.svc_fc_targets() to service_role;

select security.firecrawl_targets_refresh_v1();
select cron.schedule('firecrawl-targets', '* * * * *', 'select security.firecrawl_targets_refresh_v1()');
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('firecrawl-targets', 2, now()) on conflict (jobname) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'read_formats', 'Page format', 'What Firecrawl returns: rawHtml (the whole page, with its title), html (cleaned) or markdown. The identity check needs the title, so rawHtml is the default.', 'list', '["rawHtml"]', null, null, null, 116, 'Decision 253 pilot', 'Read pages')
on conflict (toolset_key, key) do nothing;
