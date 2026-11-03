-- CF-247 P0 workstream A follow-ups (20261104100000) on isolated fixtures: the live shapes the AI guards read, beyond ../ops-controller.
-- Columns as live (read-only, 3 Nov 2026). Scratch PostgreSQL only.
create table if not exists pipeline.platform_toolsets(key text primary key, enforcement text);
insert into pipeline.platform_toolsets(key, enforcement) values ('openrouter', 'stop') on conflict do nothing;
create table if not exists pipeline.layer3_openrouter_observations(id bigserial primary key, kind text, remaining_usd numeric, observed_at timestamptz not null default now());
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('openrouter', 'credit_floor_usd', 'number', '5') on conflict do nothing;
-- security.ai_spend_today_v1 in its live shape: it sums only the lanes it lists (fx.lanes stands for the VALUES list of the live definition)
create table fx.lanes(u text primary key, sort int);
insert into fx.lanes values ('scholarship_ai', 1), ('adapter_builder', 2), ('central_ai', 3), ('course_match', 4), ('enrich_fields', 5), ('fee_ai', 6), ('entry_matrix', 7), ('provider_description', 8);
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint) language sql stable as $f$
  with s as (select x.lane u, sum(x.cost_usd) spent, sum(x.calls) calls from pipeline.ai_spend_ledger x where x.at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') group by x.lane)
  select l.u, l.u, round(coalesce(s.spent, 0), 4), (security.toolset_setting('openrouter', 'guard_' || l.u))::text::numeric, coalesce(s.calls, 0)::bigint
    from fx.lanes l left join s on s.u = l.u order by l.sort $f$;
