-- CF-247 (3 Oct 2026, 09:05 AEST). Platform Admin, by multiple choice: "Yes, qualify now" for Firecrawl's own AI
-- extraction (its JSON format: Firecrawl fetches and renders the page and returns fields against a schema) as a
-- candidate route for intakes and English, after the 2 Oct choice "Also admit values" for Firecrawl's AI.
-- Qualification only: the worker mode fc_extract_qualify runs each frozen holdout case (l3r-intake-h1, l3r-english-h1)
-- through Firecrawl and records the answer and its outcome here against the gold value. Nothing is admitted; no cascade
-- changes. Firecrawl does not name the model behind its extraction, so a pass would admit it as a provider-level route
-- (one named service, re-tested weekly, paused on a failure), never as a step inside a model cascade (Decision 172).
create table if not exists pipeline.fc_extract_results (
  id bigint generated always as identity primary key,
  run_label text not null,
  case_id uuid not null references pipeline.layer3_holdout_cases(id),
  task_class text not null,
  answer jsonb,
  outcome text not null check (outcome in ('exact', 'exact_not_stated', 'wrong_admitted', 'missed', 'error')),
  quote_in_page boolean,
  credits int not null default 0,
  http int,
  error text,
  created_at timestamptz not null default now(),
  unique (run_label, case_id)
);
alter table pipeline.fc_extract_results enable row level security;
revoke all on pipeline.fc_extract_results from public, anon, authenticated;

create or replace function public.svc_fc_extract_cases(p_task_class text, p_offset int, p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('case_id', c.id, 'task_class', c.task_class, 'url', c.source_url, 'gold', c.gold) order by c.case_key), '[]'::jsonb) into v
    from (select * from pipeline.layer3_holdout_cases where task_class = p_task_class order by case_key offset greatest(0, coalesce(p_offset, 0)) limit greatest(1, least(coalesce(p_limit, 50), 100))) c;
  return v;
end $f$;
revoke all on function public.svc_fc_extract_cases(text, int, int) from public, anon, authenticated;
grant execute on function public.svc_fc_extract_cases(text, int, int) to service_role;

create or replace function public.svc_fc_extract_result(p_run_label text, p_case_id uuid, p_task_class text, p_answer jsonb, p_outcome text, p_quote_in_page boolean, p_credits int, p_http int, p_error text)
returns void language plpgsql security definer set search_path to 'pg_catalog', 'pipeline' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.fc_extract_results(run_label, case_id, task_class, answer, outcome, quote_in_page, credits, http, error)
  values (p_run_label, p_case_id, p_task_class, p_answer, p_outcome, p_quote_in_page, coalesce(p_credits, 0), p_http, left(p_error, 300))
  on conflict (run_label, case_id) do update set answer = excluded.answer, outcome = excluded.outcome, quote_in_page = excluded.quote_in_page,
    credits = excluded.credits, http = excluded.http, error = excluded.error, created_at = now();
end $f$;
revoke all on function public.svc_fc_extract_result(text, uuid, text, jsonb, text, boolean, int, int, text) from public, anon, authenticated;
grant execute on function public.svc_fc_extract_result(text, uuid, text, jsonb, text, boolean, int, int, text) to service_role;

-- the qualification report, read by Pipeline Operator and above
create or replace function public.admin_fc_extract_report()
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('run_label', run_label, 'task_class', task_class, 'cases', n, 'right', ok, 'wrong_admitted', wrong, 'missed', missed, 'errors', errs,
                   'credits', credits, 'pass_80_rule', (n >= 30 and ok::numeric / n >= 0.80 and wrong = 0), 'last', last) order by last desc), '[]'::jsonb)
    from (select run_label, task_class, count(*) n, count(*) filter (where outcome in ('exact', 'exact_not_stated')) ok, count(*) filter (where outcome = 'wrong_admitted') wrong,
                 count(*) filter (where outcome = 'missed') missed, count(*) filter (where outcome = 'error') errs, sum(credits) credits, max(created_at) last
            from pipeline.fc_extract_results group by 1, 2) s);
end $f$;
revoke all on function public.admin_fc_extract_report() from public, anon;
grant execute on function public.admin_fc_extract_report() to authenticated;
