-- Fixture helpers (workstream F cost and yield): fixed providers, courses and a reset. Fixture data only.
create or replace function fx.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FAILED: %', p_what; end if;
  raise notice 'ok %', p_what;
end $$;
create or replace function fx.set(p_key text, p_value numeric) returns void language sql as $$
  insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', p_key, 'number', to_jsonb(p_value))
  on conflict (toolset_key, key) do update set value = excluded.value $$;
-- P1 an ordinary provider; P2 search-stopped; P3 scholarship-ineligible; P4 on search.skip_providers
create or replace function fx.p(n int) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0000-00000000000' || n)::uuid $$;
create or replace function fx.c(n int) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid $$;
create or replace function fx.reset() returns void language plpgsql as $$
begin
  truncate pipeline.coverage_vendor_usage, pipeline.firecrawl_budget_refusals, pipeline.firecrawl_refusals_by_provider, pipeline.evidence_artifacts, pipeline.ai_spend_ledger,
    pipeline.enrich_plan_runs, pipeline.scholarship_pages, pipeline.field_enrich_items, pipeline.scholarship_ai_queue, pipeline.scholarship_ai_extractions, pipeline.coverage_ai_match,
    pipeline.coverage_course_pages, pipeline.course_link_search, pipeline.course_page_proofs, pipeline.course_attribute_coverage, pipeline.scholarship_page_candidates,
    pipeline.scholarship_discovery_providers, pipeline.admin_jobs, pipeline.enrichment_flags, pipeline.enrichment_flag_events, fx.knobs, fx.ineligible, fx.stopped,
    catalogue.courses, catalogue.providers cascade;
  insert into catalogue.providers(id, stable_key) values (fx.p(1), 'provider:p:1'), (fx.p(2), 'provider:p:2'), (fx.p(3), 'provider:p:3'), (fx.p(4), 'provider:skip:1');
  insert into catalogue.courses(id, provider_id) select fx.c(g), fx.p(1) from generate_series(1, 10) g;
  insert into fx.stopped values (fx.p(2)); insert into fx.ineligible values (fx.p(3));
end $$;
-- a spend through the live entry point (as the worker calls it)
create or replace function fx.spend(p_purpose text, p_provider uuid, p_url text, p_units numeric default 1) returns boolean language sql as $$
  select public.svc_fc_spend(p_units, p_purpose, p_provider, p_url) $$;
