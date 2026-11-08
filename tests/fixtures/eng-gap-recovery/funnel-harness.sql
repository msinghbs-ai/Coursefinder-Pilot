-- Guards: Platform Admin 8 Nov 2026 14:06 (English gap recovery): the stand-ins the gap funnel (20261108120000) and the withdrawn-reading default (20261108121000) need on top of the
-- production-parity English fixture (tests/fixtures/english-requirements/run.sh, EN_KEEP=1). Each is a LOCAL STAND-IN for a production object outside the captured English path.
-- Isolated local PostgreSQL only.
-- pipeline.field_enrich_items / pipeline.course_attribute_coverage: the columns the funnel reads (production has more)
create table if not exists pipeline.field_enrich_items (id bigserial primary key, course_id uuid, field text, state text, updated_at timestamptz not null default now());
create table if not exists pipeline.course_attribute_coverage (course_id uuid, attribute text, state text);
-- security.provider_fact_refusal_v1: stand-in for the production test of a fact-source error that is a refusal, not a try (budget, credits, target list, no key, time budget)
create or replace function security.provider_fact_refusal_v1(p_error text) returns boolean language sql immutable as $$
  select coalesce(p_error, '') ~* '(budget|credits_refused|credits_reserve|target_list_refused|no_firecrawl_key)' $$;
