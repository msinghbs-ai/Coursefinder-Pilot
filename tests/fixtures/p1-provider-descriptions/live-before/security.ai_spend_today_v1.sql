-- live since v2.15.404 (migration 20261102070000, Decision 5 E-7): live md5 0b79a7f732669ee4c59a260e26188d5a
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint)
language sql stable security definer set search_path to '' as $function$
  -- Decision 5 E-7 (2 Nov 2026): the AI cost recorded today, from pipeline.ai_spend_ledger, so each cost counts once, on the day it was
  -- recorded (it was each row's whole cost, dated by the row's last change; the scholarship re-check was not counted)
  with d as (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') t),  -- fixed: the UTC day the OpenRouter guards count
  s as (select x.lane u, sum(x.cost_usd) spent, sum(x.calls) calls from pipeline.ai_spend_ledger x, d where x.at >= d.t group by x.lane)
  select l.u, l.label, round(coalesce(s.spent, 0), 4), (security.toolset_setting('openrouter', 'guard_' || l.u))::text::numeric, coalesce(s.calls, 0)::bigint
    from (values ('scholarship_ai', 'Read scholarship pages with AI', 1), ('adapter_builder', 'Adapter proposals', 2), ('central_ai', 'Central pages with AI', 3),
                 ('course_match', 'AI course-page matching', 4), ('enrich_fields', 'Enrich fields with AI', 5), ('fee_ai', 'Fee reader with AI', 6), ('entry_matrix', 'Entry matrices with AI', 7)) l(u, label, sort)
    left join s on s.u = l.u
   order by l.sort
$function$;
