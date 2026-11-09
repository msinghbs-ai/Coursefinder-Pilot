-- CF-247 Fill fields (Platform Admin directive 9-10 Nov 2026, P0): provider on-demand field enrichment inside the existing Provider Catalogue and Provider Detail screens.
-- No second pipeline and no second dashboard: the Fill fields panel runs the existing Provider description Run & Validate (public.admin_provider_description_run_v1 -> the same cohort tables,
-- the same Run Now job kind, rank and request_key idempotency, the same provider-description-read job). This change adds what the panel and the Catalogue need around it.
--
-- What changes
--   1  pipeline.provider_description_quality (new table, RLS on, no grant to public, anon or authenticated): one row per provider with its Description quality level, the facts it was
--      classified from (security.provider_catalogue_facts_v1: reads, machine admissions, Layer 4, the Website and Zoho feeds) and when the level last changed. The level is one of
--      Missing, Enrichment queued, Enrichment processing, Waiting for human decision, Held (evidence or identity), Basic registry profile, Enriched and admitted, Consumer publication
--      pending, Verified published (and, only where a description is held with no admission record, Description present: admission not recorded).
--      Verified published is per consumer: the Website feed holds the same text (matched) and the Zoho feed holds the same text (matched). A consumer that does not serve the provider
--      (no course documents, Zoho not applicable) is Not applicable and is never counted as a failure; a provider with a description admitted by a Layer 4 decision or the machine rule
--      whose consumers are all Not applicable stays Enriched and admitted (there is nothing to publish to). Pending or missing at either consumer is Consumer publication pending.
--      The table is a snapshot written by security.provider_description_quality_refresh_v1 (the Fill fields panel and the Platform Admin's Refresh action call it for the providers they name,
--      or, with none named, for every provider in one statement: the whole-set read the Catalogue's filters already do). The Provider Catalogue never reads the snapshot: its column, filter and sort work the level out live from the same facts.
--   2  Functions (all read only except the refresh, which writes only the new table): security.provider_description_quality_class_v1 (the rule, immutable), _publication_v1 (per consumer),
--      security.provider_missing_fields_v1 (provider fields with no value, informational), _quality_v1 (the level and its facts for a set of providers), _quality_counts_v1 (live counts),
--      _quality_refresh_v1 (the writer), _fill_status_v1 (the panel's status read, with the task that last included each provider), _publication_read_v1 (actual Website and Zoho read-back for the
--      panel's Verify publication), security.provider_description_cohort_cap_v1 (the one cohort cap), security.provider_description_selection_multi_v1 (a named set of providers, selected one at a
--      time by the existing security.provider_description_selection_v1, which this change does not edit).
--   3  public.admin_provider_description_run_v1 (md5-guarded edit): preview and prepare accept provider_ids (a named set) and fill_mode (missing, upgrade_basic) and use the multi selection. The upgrade mode passes the argument `upgrade` that the register-profile upgrade change (migration 20261110040000, a separate pull request) defines for
--      security.provider_description_selection_v1; that change honours it only behind its own Platform Admin switch (pdesc.registry_upgrade_on, shipped off). This change reads that switch and creates no setting: while it is off
--      (or machine admission is off) the mode answers the exact refusal upgrade_switched_off and queues nothing; a lock answers manual_lock; a provider that is not a basic profile answers not_a_basic_registry_profile;
--      capabilities.max_size and the Run Now cap check both come from security.provider_description_cohort_cap_v1 (least of Provider descriptions: cohort size per run, review limit,
--      Run Now pilot cap and queue cap), so the screen's limit and the server's can never differ; new actions fill_caps, provider_status, provider_publication (verify), quality_counts,
--      quality_refresh. Every existing action keeps its answer.
--   4  security.admin_providers_page_v3 (md5-guarded edit): the filter quality (basic, enriched, missing, held and each single level), the sort quality and missing_fields, and, in each
--      item's pdesc, quality, website_publication, zoho_publication and missing_fields. Every request the page accepted gives the same rows, order and total as before.
--   5  pipeline.admin_table_columns: two Provider Catalogue columns, Description quality level (sort quality) and Missing enrichment fields (sort missing_fields). Both off by default.
--      The other columns the directive names already exist: Description populated, Description source, Last successful page read, Last description admitted, Held or declined reason,
--      Next retry, Website feed sync and Zoho publication.
--   6  no new setting (Platform Admin, 10 Nov 2026 05:40: keep human-maintained settings to the minimum). The panel's limits come from settings that exist: the cohort cap
--      (security.provider_description_cohort_cap_v1) bounds the providers a status read or a cohort may name, and the panel reads a running task again about four times in the reader's own
--      window (pdesc.every_minutes), never faster than twice a minute.
--
-- Not changed: security.provider_description_selection_v1, provider_description_machine_blocked_v1 and machine_admit_v1 (the eligibility rewrite is a separate change); the reader, the worker, the
-- provider-description-read job and its schedule, Layer 4, any setting value that exists, any manual lock. The reader produces only the description: other missing provider fields are
-- shown to the person as information and no new lane reads them.
-- No job is added (G1): the snapshot is written when a person asks (the panel, the Refresh action); a catalogued refresh job is a separate decision for the Platform Admin.
-- Consumer API (G3): nothing in public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, schema api, the tables they read or the five edge functions is
-- created, altered, dropped or renamed. The feeds' own tables (pipeline.website_sync_items, pipeline.zoho_sync_items) and the existing consumer read wrapper
-- security.provider_description_consumer_read_v1 are read only. Consumer API change approved: not applicable (no change).
-- Nothing is dropped, deleted or renamed by this migration. Forward recovery (the two edited bodies back, byte for byte): supabase/held/provider_fill_fields_forward_recovery.sql.
--
-- Live definitions read 10 Nov 2026 (project fxcwkweaxjtknorudmwp; body md5 = pg_proc.prosrc):
--   security.admin_providers_page_v3(jsonb)                 body f3eb9fc6f8efa37566c36ac5ef2e8f0e  -> 2c906a2b1f7c346522ef7742d74039f1
--   public.admin_provider_description_run_v1(text,jsonb)    body b397cf320a689b6e981aa6747e7156b8  -> 93af85a25c3f6c01334feeee8b7a355f
--   security.provider_catalogue_facts_v1(uuid[],boolean)     body abc1345d4cdb341deba65bfd0a38277f  (read, not edited)
-- Both edits are guarded: the migration stops if a live body is neither the one it replaces nor the one it writes.
-- Order: apply after 20261109220000 (Provider Catalogue filter speed) and 20261110020000. It does not depend on the eligibility rewrite; the upgrade mode shows the exact eligibility
-- reason the selection returns, whatever that is.
-- Replaces: the cap expression written three times in public.admin_provider_description_run_v1 (now security.provider_description_cohort_cap_v1); the bodies of security.admin_providers_page_v3 and public.admin_provider_description_run_v1 (same signatures)
-- Retires: nothing

do $g$
declare v_page text; v_run text; v_facts text;
begin
  if to_regclass('pipeline.admin_table_columns') is null or to_regclass('pipeline.platform_toolset_settings') is null or to_regclass('pipeline.component_register') is null
     or to_regclass('pipeline.provider_description_cohorts') is null or to_regclass('pipeline.provider_description_cohort_members') is null or to_regclass('pipeline.provider_description_reads') is null then
    raise exception 'Fill fields: a required table is missing';
  end if;
  select md5(p.prosrc) into v_page from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)');
  select md5(p.prosrc) into v_run from pg_proc p where p.oid = to_regprocedure('public.admin_provider_description_run_v1(text,jsonb)');
  select md5(p.prosrc) into v_facts from pg_proc p where p.oid = to_regprocedure('security.provider_catalogue_facts_v1(uuid[],boolean)');
  if v_page is null or v_run is null or v_facts is null then raise exception 'Fill fields: a required function is missing'; end if;
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc); a second run finds the new text and rewrites it unchanged
  if v_page not in ('f3eb9fc6f8efa37566c36ac5ef2e8f0e', '2c906a2b1f7c346522ef7742d74039f1') then raise exception 'live security.admin_providers_page_v3 differs from the definition this change replaces (body md5 %)', v_page; end if;
  if v_run not in ('b397cf320a689b6e981aa6747e7156b8', '93af85a25c3f6c01334feeee8b7a355f') then raise exception 'live public.admin_provider_description_run_v1 differs from the definition this change replaces (body md5 %)', v_run; end if;
  if v_facts <> 'abc1345d4cdb341deba65bfd0a38277f' then raise exception 'live security.provider_catalogue_facts_v1 differs from the definition this change reads (body md5 %)', v_facts; end if;
end $g$;

-- 1. settings: none (Platform Admin, 10 Nov 2026 05:40: keep human-maintained settings to the minimum). Every limit below is worked out from a setting that already exists (the cohort cap,
-- the reader's own window pdesc.every_minutes) or from the data, or is a technical constant marked '-- fixed: <why>'.

-- 2. the snapshot table
create table if not exists pipeline.provider_description_quality (
  provider_id uuid primary key,
  quality_class text not null check (quality_class in ('missing', 'queued', 'processing', 'waiting_decision', 'held', 'basic_registry', 'unrecorded', 'enriched_admitted', 'consumer_pending', 'verified_published')),
  description_present boolean not null,
  admission_state text,
  source_tier text,
  reader_state text,
  reader_rule text,
  l4_status text,
  hold_reason text,
  next_retry_at timestamptz,
  last_read_ok_at timestamptz,
  admitted_at timestamptz,
  website_state text,
  zoho_state text,
  website_publication text check (website_publication in ('verified', 'pending', 'not_applicable')),
  zoho_publication text check (zoho_publication in ('verified', 'pending', 'not_applicable')),
  readback_at timestamptz,
  missing_fields text[] not null default '{}',
  class_since timestamptz not null default now(),
  computed_at timestamptz not null default now()
);
comment on table pipeline.provider_description_quality is 'CF-247 Fill fields (Platform Admin 9-10 Nov 2026): one row per provider with its Description quality level (missing, queued, processing, waiting_decision, held, basic_registry, unrecorded, enriched_admitted, consumer_pending, verified_published), the facts it was worked out from (security.provider_catalogue_facts_v1: reads, machine admissions, Layer 4, the Website and Zoho feeds), the provider fields with no value, when the level last changed and when it was worked out. A snapshot written by security.provider_description_quality_refresh_v1 for the Fill fields panel; the Provider Catalogue works the level out live and never reads it. Never read by the consumer API.';
create index if not exists provider_description_quality_class_idx on pipeline.provider_description_quality (quality_class);
alter table pipeline.provider_description_quality enable row level security;
revoke all on table pipeline.provider_description_quality from public, anon, authenticated;

-- 3. the rule, the per-consumer verdict, the missing fields, the cohort cap
create or replace function security.provider_description_quality_classes_v1() returns text[]
language sql immutable parallel safe set search_path to ''
as $function$
  -- the order of the pipeline, from nothing to published; the Provider Catalogue sorts by it
  select array['missing', 'queued', 'processing', 'waiting_decision', 'held', 'basic_registry', 'unrecorded', 'enriched_admitted', 'consumer_pending', 'verified_published']::text[]
$function$;

create or replace function security.provider_description_publication_v1(p_state text) returns text
language sql immutable parallel safe set search_path to ''
as $function$
  -- one consumer: matched = verified; the feed holds other text or has no item yet = pending; a consumer that does not serve the provider = not applicable (never a failure); not worked out = null
  select case p_state when 'matched' then 'verified' when 'pending' then 'pending' when 'missing' then 'pending' when 'not_applicable' then 'not_applicable' end
$function$;

create or replace function security.provider_description_quality_class_v1(p_filled boolean, p_adm text, p_tier text, p_reader text, p_l4 text, p_web text, p_zoho text, p_feeds boolean default true) returns text
language sql immutable parallel safe set search_path to ''
as $function$
  select case
    when coalesce(p_filled, false) then
      case when p_adm = 'admitted' and p_tier = 'registry_factual' then
             case when p_reader = 'reading' then 'processing' when p_reader = 'queued' then 'queued' when p_reader = 'proposed' then 'waiting_decision' else 'basic_registry' end
           when p_adm = 'admitted' then
             case when not coalesce(p_feeds, false) or security.provider_description_publication_v1(p_web) is null or security.provider_description_publication_v1(p_zoho) is null then null
                  when 'pending' in (security.provider_description_publication_v1(p_web), security.provider_description_publication_v1(p_zoho)) then 'consumer_pending'
                  when 'verified' in (security.provider_description_publication_v1(p_web), security.provider_description_publication_v1(p_zoho)) then 'verified_published'
                  else 'enriched_admitted' end
           else 'unrecorded' end
    else
      case when p_adm = 'pending' and (p_reader = 'proposed' or p_l4 = 'pending') then 'waiting_decision'
           when p_adm = 'pending' and p_reader = 'reading' then 'processing'
           when p_adm = 'pending' then 'queued'
           when p_adm in ('held', 'declined') then 'held'
           else 'missing' end
  end
$function$;

create or replace function security.provider_missing_fields_v1(p catalogue.providers) returns text[]
language sql stable parallel safe set search_path to ''
as $function$
  -- informational: provider fields with no value. The reader fills only the description; no lane reads the others.
  select array_remove(array[
    case when nullif(btrim(p.description), '') is null then 'description' end,
    case when nullif(btrim(p.website), '') is null then 'website' end,
    case when nullif(btrim(p.primary_city), '') is null then 'city' end,
    case when p.subdivision_id is null then 'state_region' end,
    case when p.provider_type_id is null then 'provider_type' end,
    case when nullif(btrim(p.phone), '') is null then 'phone' end,
    case when nullif(btrim(p.email), '') is null then 'email' end,
    case when nullif(btrim(p.address_line1), '') is null then 'address' end,
    case when p.established_year is null then 'established_year' end], null)
$function$;

create or replace function security.provider_description_cohort_cap_v1() returns integer
language sql stable security definer set search_path to ''
as $function$
  -- the one cap on a cohort: the screen's limit (capabilities.max_size) and the server's Run Now check are this same number
  select least(security.pipeline_num_v1('pdesc.queue_per_run', 10), security.pipeline_num_v1('pdesc.pending_max', 10), security.pipeline_num_v1('run_now.pilot_cap', 20), security.pipeline_num_v1('pdesc.queue_cap', 60))::int
$function$;

-- 4. a named set of providers, selected one at a time by the existing governed selection
create or replace function security.provider_description_selection_multi_v1(p_args jsonb) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_ids uuid[]; v_cap int := security.provider_description_cohort_cap_v1(); v_fill text := coalesce(nullif(p_args->>'fill_mode', ''), 'missing'); v_id uuid;
  v_rows jsonb := '[]'::jsonb; v_one jsonb; v_f record; v_name text;
  -- the refresh of a basic profile is a Platform Admin policy switch (pdesc.registry_upgrade_on with machine admission); read here, never created here
  v_up_on boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1 and security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1;
begin
  if jsonb_typeof(p_args->'provider_ids') is distinct from 'array' then return security.provider_description_selection_v1(p_args); end if;
  select coalesce(array_agg(distinct e::uuid), array[]::uuid[]) into v_ids from jsonb_array_elements_text(p_args->'provider_ids') e;
  if cardinality(v_ids) < 1 or cardinality(v_ids) > v_cap then raise exception 'cohort size must be between 1 and %', v_cap using errcode = '22023'; end if;
  if v_fill not in ('missing', 'upgrade_basic') then raise exception 'unsupported fill mode' using errcode = '22023'; end if;
  for v_id in select unnest(v_ids) loop
    select f.description_filled, f.admission_state, f.source_tier into v_f from security.provider_catalogue_facts_v1(array[v_id], false) f;
    select coalesce(pp.display_name, pp.canonical_name) into v_name from catalogue.providers pp where pp.id = v_id;
    if v_name is null then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', null, 'name', null, 'eligible', false, 'eligibility_reason', 'unknown_provider', 'state', 'missing'));
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = v_id and l.field in ('description', 'p_description', 'all')) then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'manual_lock', 'state', case when coalesce(v_f.description_filled, false) then 'admitted' else 'missing' end));
    elsif v_fill = 'missing' and coalesce(v_f.description_filled, false) then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'description_already_present', 'state', 'admitted'));
    elsif v_fill = 'upgrade_basic' and not (coalesce(v_f.description_filled, false) and v_f.admission_state = 'admitted' and v_f.source_tier = 'registry_factual') then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'not_a_basic_registry_profile', 'state', case when coalesce(v_f.description_filled, false) then 'admitted' else 'missing' end));
    elsif v_fill = 'upgrade_basic' and not v_up_on then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'upgrade_switched_off', 'state', 'admitted'));
    else
      v_one := security.provider_description_selection_v1((p_args - 'provider_ids' - 'fill_mode') || jsonb_build_object('provider_id', v_id, 'size', 1,
                 'description_state', case when v_fill = 'upgrade_basic' then 'stale' else 'missing' end, 'upgrade', v_fill = 'upgrade_basic'));
      if jsonb_array_length(coalesce(v_one->'providers', '[]'::jsonb)) = 0 then
        v_rows := v_rows || jsonb_build_array(jsonb_build_object('provider_id', v_id, 'provider', v_name, 'name', v_name, 'eligible', false, 'eligibility_reason', 'not_selected_by_governed_policy', 'state', 'missing'));
      else
        v_rows := v_rows || (v_one->'providers');
      end if;
    end if;
  end loop;
  return jsonb_build_object('providers', v_rows, 'selected', (select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),
    'eligible', (select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean), 'bounded', true, 'size', cardinality(v_ids), 'as_at', now(), 'fill_mode', v_fill,
    'exclusions', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', x->>'provider_id', 'provider', x->>'provider', 'reason', x->>'eligibility_reason')), '[]'::jsonb) from jsonb_array_elements(v_rows) x where not (x->>'eligible')::boolean));
end
$function$;

-- 5. the level and its facts for a set of providers; the counts; the snapshot writer
create or replace function security.provider_description_quality_v1(p_ids uuid[] default null, p_feeds boolean default true)
 returns table(provider_id uuid, quality_class text, description_filled boolean, admission_state text, source_tier text, evidence_id uuid, source_url text, reader_state text, reader_rule text, reader_tries integer,
               l4_status text, hold_reason text, next_retry_at timestamptz, last_read_ok_at timestamptz, admitted_at timestamptz, admitted_by text, website_state text, zoho_state text,
               website_publication text, zoho_publication text, readback_at timestamptz, missing_fields text[])
 language plpgsql stable security definer set search_path to ''
 -- fixed: a plan setting, not an operational value (see security.provider_catalogue_facts_v1: the facts are planned with the actual p_ids)
 set plan_cache_mode to 'force_custom_plan'
as $function$
#variable_conflict use_column
begin
  return query
  select f.provider_id, security.provider_description_quality_class_v1(f.description_filled, f.admission_state, f.source_tier, f.reader_state, f.l4_status, f.website_state, f.zoho_state, p_feeds),
         f.description_filled, f.admission_state, f.source_tier, f.evidence_id, f.source_url, f.reader_state, f.reader_rule, f.reader_tries, f.l4_status, f.hold_reason, f.next_retry_at, f.last_read_ok_at,
         f.admitted_at, f.admitted_by, f.website_state, f.zoho_state,
         security.provider_description_publication_v1(f.website_state), security.provider_description_publication_v1(f.zoho_state), f.readback_at, security.provider_missing_fields_v1(p)
    from security.provider_catalogue_facts_v1(p_ids, p_feeds) f join catalogue.providers p on p.id = f.provider_id;
end
$function$;

create or replace function security.provider_description_quality_counts_v1() returns jsonb
language sql stable security definer set search_path to ''
as $function$
  with q as (select * from security.provider_description_quality_v1(null, true)),
       c as (select coalesce(quality_class, 'unknown') k, count(*) n from q group by 1),
       s as (select count(*) n, min(computed_at) oldest, max(computed_at) newest from pipeline.provider_description_quality)
  select jsonb_build_object('as_at', now(), 'total', (select count(*) from q),
    'classes', coalesce((select jsonb_object_agg(k, n) from c), '{}'::jsonb),
    'with_description', (select count(*) from q where description_filled),
    'website_publication', coalesce((select jsonb_object_agg(coalesce(website_publication, 'none'), n) from (select website_publication, count(*) n from q where description_filled group by 1) w), '{}'::jsonb),
    'zoho_publication', coalesce((select jsonb_object_agg(coalesce(zoho_publication, 'none'), n) from (select zoho_publication, count(*) n from q where description_filled group by 1) z), '{}'::jsonb),
    'snapshot', (select jsonb_build_object('rows', s.n, 'oldest', s.oldest, 'newest', s.newest) from s))
$function$;

create or replace function security.provider_description_quality_refresh_v1(p_ids uuid[] default null) returns jsonb
language plpgsql security definer set search_path to ''
as $function$
declare v_ids uuid[]; v_total bigint; v_n int; v_by jsonb;
begin
  if p_ids is null then
    select coalesce(array_agg(x.id), array[]::uuid[]) into v_ids from (
      select p.id from catalogue.providers p) x;
  else
    select coalesce(array_agg(x.id), array[]::uuid[]) into v_ids from (select distinct i id from unnest(p_ids) i) x;
  end if;
  select count(*) into v_total from catalogue.providers;
  insert into pipeline.provider_description_quality as t(provider_id, quality_class, description_present, admission_state, source_tier, reader_state, reader_rule, l4_status, hold_reason, next_retry_at, last_read_ok_at,
                                                         admitted_at, website_state, zoho_state, website_publication, zoho_publication, readback_at, missing_fields, class_since, computed_at)
  select q.provider_id, q.quality_class, q.description_filled, q.admission_state, q.source_tier, q.reader_state, q.reader_rule, q.l4_status, q.hold_reason, q.next_retry_at, q.last_read_ok_at,
         q.admitted_at, q.website_state, q.zoho_state, q.website_publication, q.zoho_publication, q.readback_at, coalesce(q.missing_fields, '{}'), now(), now()
    from security.provider_description_quality_v1(v_ids, true) q where q.quality_class is not null
  on conflict (provider_id) do update set
    quality_class = excluded.quality_class, description_present = excluded.description_present, admission_state = excluded.admission_state, source_tier = excluded.source_tier,
    reader_state = excluded.reader_state, reader_rule = excluded.reader_rule, l4_status = excluded.l4_status, hold_reason = excluded.hold_reason, next_retry_at = excluded.next_retry_at,
    last_read_ok_at = excluded.last_read_ok_at, admitted_at = excluded.admitted_at, website_state = excluded.website_state, zoho_state = excluded.zoho_state,
    website_publication = excluded.website_publication, zoho_publication = excluded.zoho_publication, readback_at = excluded.readback_at, missing_fields = excluded.missing_fields,
    class_since = case when t.quality_class is distinct from excluded.quality_class then now() else t.class_since end, computed_at = now();
  get diagnostics v_n = row_count;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_by from (select quality_class k, count(*) n from pipeline.provider_description_quality where provider_id = any(v_ids) group by 1) z;
  return jsonb_build_object('refreshed', v_n, 'asked', cardinality(v_ids), 'providers_total', v_total, 'by_class', v_by, 'as_at', now());
end
$function$;

-- 6. the panel: status of a named set of providers (with the task that last included each), and the actual consumer read-back
create or replace function security.provider_description_fill_status_v1(p_ids uuid[], p_feeds boolean, p_actor uuid) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
begin
  return (
    with q as (select * from security.provider_description_quality_v1(p_ids, p_feeds)),
    lr as (
      select distinct on (r.provider_id) r.provider_id, r.id read_id, r.state, r.rule, r.reason, r.tries, r.updated_at, r.next_try_at, r.review_item_id, r.evidence_id, r.source_url, r.read_via
        from pipeline.provider_description_reads r where r.provider_id = any(p_ids) order by r.provider_id, r.created_at desc, r.id desc
    ), lt as (
      select distinct on (m.provider_id) m.provider_id, c.id cohort_id, c.state cohort_state, c.run_id, c.created_at, c.reason, (c.requested_by = p_actor) mine, c.selection->>'fill_mode' fill_mode,
             j.state run_state, j.outcome run_outcome, j.finished_at run_finished_at
        from pipeline.provider_description_cohort_members m
        join pipeline.provider_description_cohorts c on c.id = m.cohort_id
        left join pipeline.admin_jobs j on j.id = c.run_id
       where m.provider_id = any(p_ids) order by m.provider_id, c.created_at desc, c.id desc
    )
    select jsonb_build_object('as_at', now(), 'feeds', p_feeds, 'providers', coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'stable_key', p.stable_key, 'country', k.iso_alpha2::text, 'type', pt.code,
      'lifecycle_status', p.lifecycle_status, 'publication_status', p.publication_status,
      'description_present', q.description_filled, 'current_description', p.description, 'quality_class', q.quality_class,
      'source_tier', q.source_tier, 'admission_state', q.admission_state, 'admitted_at', q.admitted_at, 'admitted_by', q.admitted_by, 'evidence_id', coalesce(q.evidence_id, lr.evidence_id), 'source_url', coalesce(q.source_url, lr.source_url),
      'reader', jsonb_build_object('read_id', lr.read_id, 'state', lr.state, 'rule', lr.rule, 'reason', lr.reason, 'tries', lr.tries, 'updated_at', lr.updated_at, 'read_via', lr.read_via),
      'hold_reason', coalesce(q.hold_reason, case when lr.state in ('held', 'rejected', 'dead_letter') then coalesce(nullif(lr.reason, ''), lr.rule) end), 'next_retry_at', coalesce(q.next_retry_at, case when lr.state in ('queued', 'held') then lr.next_try_at end),
      'last_read_ok_at', q.last_read_ok_at, 'l4_status', q.l4_status, 'review_item_id', lr.review_item_id,
      'website_state', q.website_state, 'zoho_state', q.zoho_state, 'website_publication', q.website_publication, 'zoho_publication', q.zoho_publication, 'readback_at', q.readback_at,
      'missing_fields', to_jsonb(q.missing_fields),
      'locked', exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')),
      'latest_task', case when lt.cohort_id is null then null else jsonb_build_object('cohort_id', lt.cohort_id, 'state', lt.cohort_state, 'run_id', lt.run_id, 'created_at', lt.created_at, 'reason', lt.reason,
        'requested_by_me', lt.mine, 'fill_mode', lt.fill_mode, 'run_state', lt.run_state, 'run_outcome', lt.run_outcome, 'run_finished_at', lt.run_finished_at) end
    ) order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb))
    from q join catalogue.providers p on p.id = q.provider_id join ref.countries k on k.id = p.country_id left join ref.provider_types pt on pt.id = p.provider_type_id
    left join lr on lr.provider_id = p.id left join lt on lt.provider_id = p.id
  );
end
$function$;

create or replace function security.provider_description_publication_read_v1(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
begin
  -- the actual consumer reads (security.provider_description_consumer_read_v1 -> the Website and Zoho provider reads), one provider at a time so a failed read never hides the rest.
  -- A consumer that answers NOT_FOUND does not serve the provider: not_served, never an error. 'feed' is what the Catalogue's own Website and Zoho state says the sync expects (verified, pending or
  -- not_applicable); the read-back is what the consumer returns now, and the two can differ.
  return (
    with f as (select ff.provider_id, ff.website_state, ff.zoho_state from security.provider_catalogue_facts_v1(p_ids, true) ff) -- one call for the whole set: it runs both feed scans once, not once a provider
    select jsonb_build_object('as_at', now(), 'providers', coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name),
      'catalogue', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'no_description' else 'present' end),
      'website', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'awaiting_description' when w.body->'error'->>'code' = 'NOT_FOUND' then 'not_served' when w.body ? 'error' then 'error'
                                                   when w.body->'item' is null or jsonb_typeof(w.body->'item') <> 'object' then 'not_served'
                                                   when w.body->'item'->>'provider_id' = p.stable_key and w.body->'item'->>'description' = p.description then 'verified' else 'mismatch' end,
                                   'description', w.body->'item'->>'description', 'error', w.body->'error', 'feed', security.provider_description_publication_v1(f.website_state)),
      'zoho', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'awaiting_description' when z.body->'error'->>'code' = 'NOT_FOUND' then 'not_served' when z.body ? 'error' then 'error'
                                                when z.body->'item' is null or jsonb_typeof(z.body->'item') <> 'object' then 'not_served'
                                                when z.body->'item'->>'provider_id' = p.stable_key and z.body->'item'->>'description' = p.description then 'verified' else 'mismatch' end,
                                 'description', z.body->'item'->>'description', 'error', z.body->'error', 'feed', security.provider_description_publication_v1(f.zoho_state))) order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb))
      from catalogue.providers p
      left join lateral (select security.provider_description_consumer_read_v1('website', p.stable_key) body where nullif(btrim(p.description), '') is not null) w on true
      left join lateral (select security.provider_description_consumer_read_v1('zoho', p.stable_key) body where nullif(btrim(p.description), '') is not null) z on true
      left join f on f.provider_id = p.id
     where p.id = any(p_ids)
  );
end
$function$;

revoke all on function security.provider_description_quality_classes_v1(), security.provider_description_publication_v1(text),
  security.provider_description_quality_class_v1(boolean, text, text, text, text, text, text, boolean), security.provider_missing_fields_v1(catalogue.providers),
  security.provider_description_cohort_cap_v1(), security.provider_description_selection_multi_v1(jsonb), security.provider_description_quality_v1(uuid[], boolean),
  security.provider_description_quality_counts_v1(), security.provider_description_quality_refresh_v1(uuid[]), security.provider_description_fill_status_v1(uuid[], boolean, uuid),
  security.provider_description_publication_read_v1(uuid[]) from public, anon, authenticated;

-- 7. providers_page, version 3: the Description quality level (filter, sort, item), the missing fields (sort, item). The same function, signature and settings; every earlier request answers the same.
CREATE OR REPLACE FUNCTION security.admin_providers_page_v3(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
 -- fixed: a plan setting, not an operational value. Without it the page statement is planned once with its filters unknown after five calls on a connection
 -- (measured: 0.3 s becomes 4 to 10 s for the Admission, Website and Zoho filters), the same defect as in the facts function.
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'provider'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_query text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_country text:=nullif(trim(coalesce(p_args->>'country_code','')),'');
  v_subdivision text:=nullif(trim(coalesce(p_args->>'subdivision_code','')),'');
  v_lifecycle text:=nullif(trim(coalesce(p_args->>'lifecycle_status','')),'');
  v_publication text:=nullif(trim(coalesce(p_args->>'publication_status','')),'');
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_adapter text:=nullif(trim(coalesce(p_args->>'adapter','')),'');
  v_desc text:=nullif(lower(trim(coalesce(p_args->>'description',''))),'');
  v_adm text:=nullif(lower(trim(coalesce(p_args->>'admission',''))),'');
  v_tier text:=nullif(lower(trim(coalesce(p_args->>'source_tier',''))),'');
  v_web text:=nullif(lower(trim(coalesce(p_args->>'website',''))),'');
  v_zoho text:=nullif(lower(trim(coalesce(p_args->>'zoho',''))),'');
  v_type text:=nullif(trim(coalesce(p_args->>'provider_type','')),'');
  v_quality text:=nullif(lower(trim(coalesce(p_args->>'quality',''))),'');
  v_qset text[];
  v_need_facts boolean;
  v_scan_feeds boolean;
  v_page_feeds boolean;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_desc is not null and v_desc not in ('filled','missing') then raise exception 'unsupported description filter: %',v_desc using errcode='22023'; end if;
  if v_adm is not null and v_adm not in ('pending','held','declined','admitted') then raise exception 'unsupported admission filter: %',v_adm using errcode='22023'; end if;
  if v_tier is not null and v_tier not in ('stored','direct','firecrawl','registry_factual','unknown') then raise exception 'unsupported source tier filter: %',v_tier using errcode='22023'; end if;
  if v_web is not null and v_web not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported website filter: %',v_web using errcode='22023'; end if;
  if v_zoho is not null and v_zoho not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported zoho filter: %',v_zoho using errcode='22023'; end if;
  if v_type is not null and v_type<>'unclassified' and not exists (select 1 from ref.provider_types pt where pt.code=v_type) then raise exception 'unsupported provider type filter: %',v_type using errcode='22023'; end if;
  -- Description quality level (Fill fields, Platform Admin directive 9-10 Nov 2026): the four groups the screen offers (basic, enriched, missing, held) and each single class
  if v_quality is not null then
    v_qset:=case v_quality
      when 'basic' then array['basic_registry'] when 'enriched' then array['enriched_admitted','consumer_pending','verified_published'] when 'missing' then array['missing'] when 'held' then array['held']
      when 'queued' then array['queued'] when 'processing' then array['processing'] when 'waiting_decision' then array['waiting_decision'] when 'basic_registry' then array['basic_registry']
      when 'enriched_admitted' then array['enriched_admitted'] when 'consumer_pending' then array['consumer_pending'] when 'verified_published' then array['verified_published'] when 'unrecorded' then array['unrecorded'] end;
    if v_qset is null then raise exception 'unsupported quality filter: %',v_quality using errcode='22023'; end if;
  end if;
  -- the description facts are worked out for every provider only when a filter or a sort needs them
  -- Description (filled, missing) and the Description sort read the provider's own description column, so they need no facts. The pipeline facts are worked out
  -- only for a filter or sort that needs them, and only for the providers that already pass the filters on the provider's own columns.
  v_need_facts:=coalesce(v_adm,v_tier,v_web,v_zoho,v_quality) is not null
    or v_sort in ('admission','source','desc_admitted','reader','last_read','next_retry','layer4','canonical','website','zoho','mismatch','quality');

  -- The two feed candidate scans read every provider, so they run only when a Website or Zoho filter or sort needs them across the whole set, or when the
  -- screen shows a feed column (it then sends feeds=true) for the rows of the page. Otherwise those three fields come back null.
  -- the quality level of an enriched provider depends on the two feeds, so a quality sort, or a filter on a class that includes the enriched ones, scans them too
  v_scan_feeds:=coalesce(v_web,v_zoho) is not null or v_sort in ('website','zoho','mismatch','quality')
    or coalesce(v_quality in ('enriched','enriched_admitted','consumer_pending','verified_published'),false);
  v_page_feeds:=v_scan_feeds or lower(coalesce(p_args->>'feeds',''))='true';

  return (
    -- Same design as v2 (CF-247 W34): the page is chosen first on the light columns; the per-provider counts, the adapter status, the evidence count and
    -- the new columns are worked out for the rows of the page only. The adapter status is worked out for every matching provider only when the Adapter
    -- filter or sort needs it, the course count only for the Courses sort, the registration, scholarship and coverage values only for their own sort.
    with cand as (
      -- the providers that pass the filters on the provider's own columns (query, country, state, lifecycle, publication, group, type, Description)
      select p.id
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        left join ref.subdivisions ps on ps.id=p.subdivision_id
       where
        (
          v_query is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||v_query||'%'
          or coalesce(p.stable_key,'') ilike '%'||v_query||'%'
          or coalesce(p.primary_city,'') ilike '%'||v_query||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||v_query||'%'
          or coalesce(c.name,'') ilike '%'||v_query||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||v_query||'%'
          or coalesce(ps.code,'') ilike '%'||v_query||'%'
          or coalesce(ps.name,'') ilike '%'||v_query||'%'
        )
        and (v_country is null or c.iso_alpha2::text=upper(v_country))
        and (v_subdivision is null or ps.code=upper(v_subdivision))
        and (v_lifecycle is null or p.lifecycle_status=v_lifecycle)
        and (v_publication is null or p.publication_status=v_publication)
        and (v_group is null or p.id in (select security.university_group_provider_ids(v_group)))
        and (v_type is null or (v_type='unclassified' and p.provider_type_id is null) or p.provider_type_id=(select pt.id from ref.provider_types pt where pt.code=v_type))
        and (v_desc is null or (v_desc='filled')=(nullif(btrim(p.description),'') is not null))
    ), facts as materialized (
      select * from security.provider_catalogue_facts_v1(array(select x.id from cand x), v_scan_feeds) where v_need_facts
    ), base as (
      select
        p.id,p.display_name,p.canonical_name,c.iso_alpha2::text country_code,c.default_currency_code::text currency_code,
        ps.name subdivision_name,p.primary_city city,p.last_verified_at,p.provider_type_id,p.lifecycle_status,p.publication_status,p.updated_at,
        case when v_adapter is not null or v_sort='adapter' then security.provider_adapter_status_v1(p.id) end adapter_status,
        case when v_sort='courses' then (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) end course_count,
        case when v_sort='scholarships' then (select count(*)::bigint from scholarship.scholarships sc where sc.provider_id=p.id) end scholarship_count,
        case when v_sort='registration' then (select lower(pr.registration_scheme||' '||pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=p.id order by pr.checked_at desc nulls last,pr.id limit 1) end registration_key,
        case when v_sort='coverage' then (select ac.disposition from pipeline.aer_provider_coverage ac where ac.provider_id=p.id) end coverage_key,
        (nullif(btrim(p.description),'') is not null) description_filled,f.admission_state,f.source_tier,f.admitted_at,f.reader_state,f.last_read_ok_at,f.next_retry_at,f.l4_status,f.canonical_status,f.website_state,f.zoho_state,f.mismatch,
        -- the quality level and the number of missing provider fields, only where a filter or sort needs them across the whole set
        case when v_need_facts then security.provider_description_quality_class_v1(f.description_filled,f.admission_state,f.source_tier,f.reader_state,f.l4_status,f.website_state,f.zoho_state,v_scan_feeds) end quality_class,
        case when v_sort='missing_fields' then cardinality(security.provider_missing_fields_v1(p)) end missing_count
      from cand x
      join catalogue.providers p on p.id=x.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      left join facts f on f.provider_id=p.id
      where
        (v_adm is null or f.admission_state=v_adm)
        and (v_tier is null or f.source_tier=v_tier)
        and (v_web is null or f.website_state=v_web)
        and (v_zoho is null or f.zoho_state=v_zoho)
    ), filtered as (
      select * from base
       where v_adapter is null
          or (v_adapter = 'any' and adapter_status not in ('none', 'no_courses'))
          or adapter_status = v_adapter
    ), qfiltered as (
      select * from filtered where v_quality is null or quality_class = any(v_qset)
    ), numbered as (
      select f.id,count(*) over()::bigint total_count,row_number() over (order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(f.display_name,f.canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(f.display_name,f.canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then f.country_code end asc,
        case when v_sort='country' and v_dir='desc' then f.country_code end desc,
        case when v_sort='currency' and v_dir='asc' then f.currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then f.currency_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(f.subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(f.subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(f.city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(f.city,'')) end desc,
        case when v_sort='type' and v_dir='asc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'~') end asc,
        case when v_sort='type' and v_dir='desc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'') end desc,
        case when v_sort='courses' and v_dir='asc' then f.course_count end asc,
        case when v_sort='courses' and v_dir='desc' then f.course_count end desc,
        case when v_sort='adapter' and v_dir='asc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end asc,
        case when v_sort='adapter' and v_dir='desc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end desc,
        case when v_sort='verified' and v_dir='asc' then f.last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then f.last_verified_at end desc nulls last,
        -- the new sorts. Unknown (no value held) is last in both directions, as on the Course catalogue's time sorts.
        case when v_sort='registration' and v_dir='asc' then f.registration_key end asc nulls last,
        case when v_sort='registration' and v_dir='desc' then f.registration_key end desc nulls last,
        case when v_sort='scholarships' and v_dir='asc' then f.scholarship_count end asc,
        case when v_sort='scholarships' and v_dir='desc' then f.scholarship_count end desc,
        case when v_sort='coverage' and v_dir='asc' then f.coverage_key end asc nulls last,
        case when v_sort='coverage' and v_dir='desc' then f.coverage_key end desc nulls last,
        case when v_sort='lifecycle' and v_dir='asc' then f.lifecycle_status end asc,
        case when v_sort='lifecycle' and v_dir='desc' then f.lifecycle_status end desc,
        case when v_sort='publication' and v_dir='asc' then f.publication_status end asc,
        case when v_sort='publication' and v_dir='desc' then f.publication_status end desc,
        case when v_sort='modified' and v_dir='asc' then f.updated_at end asc nulls last,
        case when v_sort='modified' and v_dir='desc' then f.updated_at end desc nulls last,
        case when v_sort='description' and v_dir='asc' then f.description_filled::int end asc,
        case when v_sort='description' and v_dir='desc' then f.description_filled::int end desc,
        case when v_sort='admission' and v_dir='asc' then f.admission_state end asc nulls last,
        case when v_sort='admission' and v_dir='desc' then f.admission_state end desc nulls last,
        case when v_sort='source' and v_dir='asc' then f.source_tier end asc nulls last,
        case when v_sort='source' and v_dir='desc' then f.source_tier end desc nulls last,
        case when v_sort='desc_admitted' and v_dir='asc' then f.admitted_at end asc nulls last,
        case when v_sort='desc_admitted' and v_dir='desc' then f.admitted_at end desc nulls last,
        case when v_sort='reader' and v_dir='asc' then f.reader_state end asc nulls last,
        case when v_sort='reader' and v_dir='desc' then f.reader_state end desc nulls last,
        case when v_sort='last_read' and v_dir='asc' then f.last_read_ok_at end asc nulls last,
        case when v_sort='last_read' and v_dir='desc' then f.last_read_ok_at end desc nulls last,
        case when v_sort='next_retry' and v_dir='asc' then f.next_retry_at end asc nulls last,
        case when v_sort='next_retry' and v_dir='desc' then f.next_retry_at end desc nulls last,
        case when v_sort='layer4' and v_dir='asc' then f.l4_status end asc nulls last,
        case when v_sort='layer4' and v_dir='desc' then f.l4_status end desc nulls last,
        case when v_sort='canonical' and v_dir='asc' then f.canonical_status end asc nulls last,
        case when v_sort='canonical' and v_dir='desc' then f.canonical_status end desc nulls last,
        case when v_sort='website' and v_dir='asc' then f.website_state end asc nulls last,
        case when v_sort='website' and v_dir='desc' then f.website_state end desc nulls last,
        case when v_sort='zoho' and v_dir='asc' then f.zoho_state end asc nulls last,
        case when v_sort='zoho' and v_dir='desc' then f.zoho_state end desc nulls last,
        case when v_sort='mismatch' and v_dir='asc' then f.mismatch end asc nulls last,
        case when v_sort='mismatch' and v_dir='desc' then f.mismatch end desc nulls last,
        -- Description quality level: the order of the pipeline, from Missing to Verified published (a level the page could not work out is last)
        case when v_sort='quality' and v_dir='asc' then array_position(array['missing','queued','processing','waiting_decision','held','basic_registry','unrecorded','enriched_admitted','consumer_pending','verified_published'], f.quality_class) end asc nulls last,
        case when v_sort='quality' and v_dir='desc' then array_position(array['missing','queued','processing','waiting_decision','held','basic_registry','unrecorded','enriched_admitted','consumer_pending','verified_published'], f.quality_class) end desc nulls last,
        case when v_sort='missing_fields' and v_dir='asc' then f.missing_count end asc,
        case when v_sort='missing_fields' and v_dir='desc' then f.missing_count end desc,
        lower(coalesce(f.display_name,f.canonical_name)),f.id) ord
      from qfiltered f
    ), keys as (
      select n.id,n.total_count,n.ord from numbered n where n.ord>v_offset and n.ord<=v_offset+v_limit
    ), pfacts as (
      -- the page's rows only: array(...) is an empty array, never null, when the page is empty (null would mean every provider)
      select * from security.provider_catalogue_facts_v1(array(select k.id from keys k), v_page_feeds)
    ), reg as (
      select distinct on (pr.provider_id) pr.provider_id,jsonb_build_object('scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'checked_at',pr.checked_at) j
        from catalogue.provider_registrations pr where pr.provider_id in (select k.id from keys k)
       order by pr.provider_id,pr.checked_at desc nulls last,pr.id
    ), sch as (
      select s.provider_id,jsonb_build_object('total',count(*),'published',count(*) filter (where s.publication_status='published' and s.lifecycle_status='active')) j
        from scholarship.scholarships s where s.provider_id in (select k.id from keys k) group by s.provider_id
    ), cov as (
      select ac.provider_id,jsonb_build_object('disposition',ac.disposition,'discovery',ac.discovery_state,'extraction',ac.extraction_state,'admission',ac.admission_state,
               'matrix_active',ac.matrix_active,'course_requirements_active',ac.course_req_active,'as_at',ac.updated_at) j
        from pipeline.aer_provider_coverage ac where ac.provider_id in (select k.id from keys k)
    ), page as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select pt.code from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_code,
        (select pt.name from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_name,
        p.provider_type_basis,
        exists (select 1 from pipeline.manual_locks ml where ml.entity='provider' and ml.entity_id=p.id and ml.field='provider_type_id') provider_type_locked,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        security.provider_adapter_status_v1(p.id) adapter_status,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count,
        p.description description_text,
        security.provider_missing_fields_v1(p) missing_fields,
        k.ord
      from keys k
      join catalogue.providers p on p.id=k.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
    )
    select jsonb_build_object(
      'items',coalesce((select jsonb_agg((to_jsonb(o)-'ord'-'description_text'-'missing_fields')||jsonb_build_object(
                'university_groups',security.provider_university_groups(o.id),
                'registration',(select r.j from reg r where r.provider_id=o.id),
                'scholarships',coalesce((select s.j from sch s where s.provider_id=o.id),jsonb_build_object('total',0,'published',0)),
                'entry_coverage',(select cv.j from cov cv where cv.provider_id=o.id),
                'pdesc',coalesce((select (to_jsonb(pf)-'provider_id')||jsonb_build_object('quality',security.provider_description_quality_class_v1(pf.description_filled,pf.admission_state,pf.source_tier,pf.reader_state,pf.l4_status,pf.website_state,pf.zoho_state,v_page_feeds),
                   'website_publication',security.provider_description_publication_v1(pf.website_state),'zoho_publication',security.provider_description_publication_v1(pf.zoho_state)) from pfacts pf where pf.provider_id=o.id),'{}'::jsonb)
                   ||jsonb_build_object('text',o.description_text,'missing_fields',to_jsonb(o.missing_fields))) order by o.ord) from page o),'[]'::jsonb),
      'total',coalesce((select max(total_count) from keys),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir,
      'columns_profile','provider_columns_v1'
    )
  );
end
$function$;

-- 8. the Provider description Run & Validate service: a named set, a fill mode, the one cap, and the Fill fields reads. Every earlier action answers the same.
create or replace function public.admin_provider_description_run_v1(p_action text,p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid:=auth.uid(); v_rank int:=security.current_role_rank(); c pipeline.provider_description_cohorts%rowtype;
 v_res jsonb; v_preview jsonb; v_fresh jsonb; x jsonb; v_id uuid; v_reason text:=btrim(coalesce(p_args->>'reason','')); v_n int:=0; v_run uuid; v_why text;
 v_mode text; v_args jsonb; v_ids uuid[]; v_history jsonb; v_rule text; v_diagnosis jsonb; v_context jsonb; v_issue bigint; v_ai_request bigint; v_ai_model text; v_ai_why text; v_job pipeline.automation_catalogue%rowtype; v_dispatch_error text; v_dispatch_sqlstate text;
begin
 if v_actor is null or v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_job from pipeline.automation_catalogue where jobname='provider-description-read';
 if p_action='verify' and v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
 if p_action='capabilities' then
 return jsonb_build_object('contract','provider-description-run-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
 'can_explain',v_rank>=coalesce(v_job.control_rank,6),'can_diagnose',security.pipeline_num_v1('ops.ai_diagnosis_on',0)>=1 and security.ai_use_allowed_v1('ops_diagnose') and nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','') is not null,'ai_diagnosis_reason','AI assistance requires the existing approved Operations diagnosis switch, model and spending guards plus an existing open issue linked to this exact provider and evidence. Explain evidence always uses stored checks.',
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',k.iso_alpha2,'label',coalesce(to_jsonb(k)->>'name',to_jsonb(k)->>'country_name',k.iso_alpha2::text),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.countries'),'[]')?k.iso_alpha2::text)) from ref.countries k where k.iso_alpha2 in ('AU','NZ','CA')),'[]'),
 'provider_types',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'label',coalesce(to_jsonb(t)->>'label',to_jsonb(t)->>'name',t.code),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.provider_types'),'[]')?t.code)) from ref.provider_types t),'[]'),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.id,'name',coalesce(p.display_name,p.canonical_name),'country',k.iso_alpha2,'type',t.code) order by coalesce(p.display_name,p.canonical_name)) from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id where security.provider_description_scope_v1(p.id)),'[]'),
 'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),'default_size',security.pipeline_num_v1('batch.provider_description',3)::int,
 'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
 'model',(select model_identifier from pipeline.central_ai_settings where id=1),'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,
 'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
 'policy',jsonb_build_object('countries',security.toolset_setting('pipeline','pdesc.countries'),'types',security.toolset_setting('pipeline','pdesc.provider_types'),'provider_keys',security.toolset_setting('pipeline','pdesc.provider_keys'),'ai_usd_max',security.pipeline_num_v1('pdesc.ai_usd_max',1),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'reserved_usd',(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads),'remaining_usd',greatest(0,security.pipeline_num_v1('pdesc.ai_usd_max',1)-(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')-(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads)),'actual_ai_calls',(select coalesce(sum(ai_calls),0) from pipeline.provider_description_reads),'recorded_billable_calls',(select coalesce(sum(calls),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'recorded_cost_usd',(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'ai_call_counter_scope','reported model calls since provider-description-autonomy instrumentation; ledger calls are separate recorded billable calls','budget_period','lifetime pilot','required_approval','Individual human Layer 4 decision'));
 elsif p_action='preview' then
 v_args:=p_args||jsonb_build_object('mode',coalesce(nullif(p_args->>'mode',''),'stored'));
 -- Fill fields (Provider Catalogue and Provider Detail): the screen names what it wants to do; the governed selection gets the same description state it always had.
 if nullif(p_args->>'fill_mode','') is not null then
  if p_args->>'fill_mode' not in ('missing','upgrade_basic') then raise exception 'unsupported fill mode' using errcode='22023'; end if;
  v_args:=v_args||jsonb_build_object('description_state',case p_args->>'fill_mode' when 'upgrade_basic' then 'stale' else 'missing' end,'upgrade',p_args->>'fill_mode'='upgrade_basic');
 end if;
 v_res:=security.provider_description_selection_multi_v1(v_args);
 insert into pipeline.provider_description_cohorts(requested_by,selection,snapshot,expires_at)
 values(v_actor,v_args,v_res,now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int)) returning id into v_id;
 return v_res||jsonb_build_object('token',v_id,'preview_token',v_id,'expires_at',now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int));
 elsif p_action='prepare' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason is shorter than the governed minimum' using errcode='22023'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'preview_token','')::uuid and requested_by=v_actor for update;
 if c.id is null then raise exception 'unknown owned preview' using errcode='42501'; end if;
 if c.state in ('prepared','started') then return security.provider_description_run_result_v1(c.id); end if;
 if c.expires_at<now() then raise exception 'preview expired; preview again' using errcode='22023'; end if;
 v_fresh:=security.provider_description_selection_multi_v1(c.selection);
 for x in select * from jsonb_array_elements(c.snapshot->'providers') where (value->>'eligible')::boolean loop
  if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where f->>'provider_id'=x->>'provider_id' and (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description' and f->>'last_read_id' is not distinct from x->>'last_read_id') then raise exception 'preview changed; preview again' using errcode='22023'; end if;
  v_n:=v_n+1;
  insert into pipeline.provider_description_cohort_members(cohort_id,provider_id,evidence_id,pick,snapshot) values(c.id,(x->>'provider_id')::uuid,(x->>'evidence_id')::uuid,v_n,x);
 end loop;
 if v_n=0 then raise exception 'no eligible provider with approved evidence in this preview' using errcode='22023'; end if;
 update pipeline.provider_description_cohorts set state='prepared',reason=v_reason,prepared_at=now() where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','cohort_prepare',c.id::text,jsonb_build_object('selected',v_n,'reason',v_reason,'selection',c.selection),v_actor);
 return security.provider_description_run_result_v1(c.id);
 elsif p_action='run' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot start this job' using errcode='42501'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'cohort_id','')::uuid and requested_by=v_actor for update;
 if c.id is null or c.state='preview' then raise exception 'unknown owned fixed cohort' using errcode='42501'; end if;
 if c.run_id is not null then return security.provider_description_run_result_v1(c.id)||jsonb_build_object('repeat',true); end if;
 if (select count(*) from pipeline.provider_description_cohort_members where cohort_id=c.id)>security.provider_description_cohort_cap_v1() then
   raise exception 'current_cap_changed: the fixed cohort exceeds the current governed cap; prepare a new cohort' using errcode='22023';
 end if;
 -- Same task kind, catalogue permission, pause/spend/review rules and provider-description job. Never a second scheduler.
 v_why:=case when not coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read' then 'job_not_allowlisted'
 when v_job.jobname is null then 'job_not_catalogued'
 when not exists(select 1 from cron.job where jobname='provider-description-read' and active) then 'job_paused'
 when security.pipeline_num_v1('pdesc.enabled',0)<1 then 'reader_off'
 when not security.ai_use_allowed_v1('provider_description') then 'ai_refused'
 when (select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')>=security.pipeline_num_v1('pdesc.ai_usd_max',1) then 'ai_ceiling'
 when (select count(*) from pipeline.layer4_review_items where field_code='provider_description' and status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then 'review_full' end;
 -- Policy/capacity holds are durable: the fixed cohort stays recoverable and the existing scheduled job resumes it.
 for x in select m.snapshot from pipeline.provider_description_cohort_members m where m.cohort_id=c.id order by m.pick loop
   v_fresh:=security.provider_description_selection_v1(c.selection||jsonb_build_object('provider_id',x->>'provider_id','size',1));
   if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description') then
     update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('eligibility_reason','selection_changed_before_run','eligible',false) where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid; continue;
   end if;
   insert into pipeline.provider_description_reads(provider_id) values((x->>'provider_id')::uuid) on conflict do nothing returning id into v_id;
   if v_id is null then select id into v_id from pipeline.provider_description_reads where provider_id=(x->>'provider_id')::uuid and state in ('queued','reading','proposed') order by created_at desc limit 1; end if;
   update pipeline.provider_description_cohort_members set read_id=v_id where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid;
   v_n:=v_n+1; v_id:=null;
 end loop;
 update pipeline.provider_description_cohorts set state='started' where id=c.id;
 if v_why is null and v_n>0 then
   perform set_config('cf.pdesc_run_now',c.id::text,true);
   begin
     v_res:=security.provider_description_fire_v1();
   exception when others then
     -- OTHERS deliberately excludes query cancellation: the caller's statement/lock limits remain authoritative.
     get stacked diagnostics v_dispatch_error=message_text,v_dispatch_sqlstate=returned_sqlstate;
     v_res:=jsonb_build_object('sent',0,'parked',true,'reason','reader_dispatch_failed','error',v_dispatch_error,'sqlstate',v_dispatch_sqlstate,'retry_strategy','existing provider-description-read schedule resumes this saved queued cohort');
   end;
 else v_res:=jsonb_build_object('sent',0,'parked',true,'reason',coalesce(v_why,'selection_changed_before_run')); end if;
 insert into pipeline.admin_jobs(kind,lane,state,title,args,result,error,requested_by,reason,started_at,finished_at,scope,outcome)
 values('job_run_now','run_now',case when v_dispatch_error is not null then 'failed' when v_why is null then 'done' else 'cancelled' end,'Provider descriptions: bounded Run Now',jsonb_build_object('job','provider-description-read','cohort_id',c.id,'idempotency_key',c.request_key),v_res||jsonb_build_object('selected',v_n,'admitted',0,'publication_measured_separately',true),v_dispatch_error,v_actor,c.reason,now(),clock_timestamp(),'cohort:'||c.id,case when v_dispatch_error is not null then 'failed_retryable' when v_why is not null then 'blocked_policy' else 'succeeded_no_movement' end) returning id into v_run;
 update pipeline.provider_description_cohorts set run_id=v_run where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','run_now','provider-description-read',jsonb_build_object('cohort_id',c.id,'run_id',v_run,'dispatch',v_res,'reason',c.reason),v_actor);
 return security.provider_description_run_result_v1(c.id)||jsonb_build_object('dispatch',v_res);
  elsif p_action='fill_caps' then
 -- Fill fields: what the panel needs to know before it asks anything. No provider list (capabilities carries every provider in scope; the panel does not need it).
 return jsonb_build_object('contract','provider-description-fill-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
  'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),
  'cap',jsonb_build_object('queue_per_run',security.pipeline_num_v1('pdesc.queue_per_run',10),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'pilot_cap',security.pipeline_num_v1('run_now.pilot_cap',20),'queue_cap',security.pipeline_num_v1('pdesc.queue_cap',60),'effective',security.provider_description_cohort_cap_v1()),
  'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
  'run_now_allowed',coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read',
  'poll_seconds',greatest(30,security.pipeline_num_v1('pdesc.every_minutes',60)::int*15) /* fixed: a quarter of the reader's own window (minutes x 60 / 4), never faster than twice a minute */,'status_max',security.provider_description_cohort_cap_v1(),
  'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
  'fill_modes',jsonb_build_array('missing','upgrade_basic','preview_only','verify_publication'),
  'upgrade_basic_on',security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1,
  'quality_classes',to_jsonb(security.provider_description_quality_classes_v1()));
 elsif p_action in ('provider_status','provider_publication') then
 -- Fill fields, read only: the state of up to the governed number of providers, and the task that last included each. Needs no saved cohort, so it works after the browser was closed.
 select coalesce(array_agg(distinct (e)::uuid),array[]::uuid[]) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 if cardinality(v_ids)=0 or cardinality(v_ids)>security.provider_description_cohort_cap_v1() then raise exception 'name between 1 and % providers',security.provider_description_cohort_cap_v1() using errcode='22023'; end if;
 if p_action='provider_publication' then
  if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
  v_res:=security.provider_description_publication_read_v1(v_ids);
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify_provider_publication',array_to_string(v_ids,','),jsonb_build_object('providers',cardinality(v_ids),'as_at',now(),'reason','Operator requested actual catalogue and consumer read-back from Fill fields'),v_actor);
  return v_res;
 end if;
 return security.provider_description_fill_status_v1(v_ids,coalesce((p_args->>'feeds')::boolean,false),v_actor);
 elsif p_action='quality_counts' then
 return security.provider_description_quality_counts_v1();
 elsif p_action='quality_refresh' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot refresh the quality snapshot' using errcode='42501'; end if;
 select array_agg(distinct (e)::uuid) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 return security.provider_description_quality_refresh_v1(v_ids);
 elsif p_action in ('saved','verify','diagnose') then
 if p_action='diagnose' and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor;
 elsif nullif(p_args->>'cohort_id','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'cohort_id')::uuid and requested_by=v_actor;
 else select * into c from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc,id desc limit 1; end if;
 if p_action='diagnose' then
   if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot diagnose this job' using errcode='42501'; end if;
   if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason required'; end if;
   if c.id is null and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor; end if;
   if c.id is null then raise exception 'owned saved evidence required' using errcode='42501'; end if;
   select coalesce(r.rule,m.snapshot->>'eligibility_reason'),coalesce(r.reason,m.snapshot->>'reason') into v_rule,v_why from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid;
   if v_rule is null then select x->>'eligibility_reason',x->>'reason' into v_rule,v_why from jsonb_array_elements(c.snapshot->'providers') x where x->>'provider_id'=p_args->>'provider_id'; end if;
   if v_rule is null then raise exception 'provider is not in owned saved evidence' using errcode='42501'; end if;
   v_diagnosis:=jsonb_build_object('method','stored_checks','rule',v_rule,'explanation',coalesce(v_why,case v_rule when 'no_verified_stored_source' then 'A current official About/Overview page stored against this exact provider is needed.' when 'unchanged_unsuitable_evidence' then 'The same evidence previously failed or was rejected. A changed approved source is needed before another AI read.' when 'review_full' then 'The validated proposal is parked until Layer 4 capacity becomes available; no further AI read is needed.' else 'Inspect the official source, identity references and validation checks. Only the existing human Layer 4 decision can authorise admission.' end),'ai_used',false,'cost_usd',0,'ai_reason','Provider-description AI diagnostics have no approved existing route.','at',now());
   -- AI is advice through the existing Operations lane only, bound to an already recorded issue and the exact stored source.
   select coalesce((select m.snapshot||jsonb_build_object('evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'checks',r.checks,'sentences',r.proposal->'sentences') from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid),
     (select z from jsonb_array_elements(c.snapshot->'providers') z where z->>'provider_id'=p_args->>'provider_id')) into v_context;
   v_ai_model:=nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','');
   v_ai_why:=case when security.pipeline_num_v1('ops.ai_diagnosis_on',0)<1 then 'ops.ai_diagnosis_on is 0'
      when v_ai_model is null then 'no approved Operations diagnosis model'
      when not security.ai_use_allowed_v1('ops_diagnose') then 'existing Operations AI spending guard refuses assistance'
      when nullif(v_context->>'evidence_id','') is null then 'no exact stored evidence reference for an existing issue' end;
   if v_ai_why is null then
    select i.id into v_issue from pipeline.integration_issues i where i.status not in ('closed','superseded') and (p_args->>'provider_id')::uuid=any(i.provider_ids)
      and jsonb_path_exists(i.evidence,'$.**.evidence_id ? (@ == $id)',jsonb_build_object('id',v_context->>'evidence_id')) order by i.id desc limit 1;
    if v_issue is null then v_ai_why:='no existing open integration issue links this exact provider and stored evidence'; end if;
   end if;
   if v_ai_why is null then
    perform pg_advisory_xact_lock(hashtext('cf247 pdesc diagnosis '||v_issue::text)); -- fixed: duplicate request suppression for the existing issue/evidence.
    select q.id into v_ai_request from pipeline.ops_ai_diagnosis_requests q where q.issue_id=v_issue and q.context->>'provider_description_evidence_id'=v_context->>'evidence_id' and q.state in ('queued','leased','answered','refused') order by q.id desc limit 1;
    if v_ai_request is null then
     insert into pipeline.ops_ai_diagnosis_requests(issue_id,context,model,note)
     values(v_issue,jsonb_build_object('issue',v_issue,'provider_id',p_args->>'provider_id','provider_description_evidence_id',v_context->>'evidence_id','evidence',v_context,'question','Explain why this official source or claim is unsuitable and which evidence is missing. Advice only; do not authorise a description or change any setting.',
       'deterministic',v_diagnosis,'root_causes',(select jsonb_agg(jsonb_build_object('code',rc.code,'class',rc.class,'title',rc.title,'description',rc.description)) from pipeline.ops_root_causes rc)),v_ai_model,'Provider description evidence explanation; advice through existing Operations diagnosis') returning id into v_ai_request;
    end if;
    v_diagnosis:=v_diagnosis||jsonb_build_object('request_id',v_ai_request,'request_status','queued','integration_issue_id',v_issue,'model',v_ai_model,'ai_reason','Queued through the existing Operations diagnosis worker; no approval or settings authority.');
   else v_diagnosis:=v_diagnosis||jsonb_build_object('ai_reason',v_ai_why); end if;
   update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('diagnosis',v_diagnosis) where cohort_id=c.id and provider_id=(p_args->>'provider_id')::uuid;
   update pipeline.provider_description_cohorts set snapshot=jsonb_set(snapshot,'{providers}',(select jsonb_agg(case when z->>'provider_id'=p_args->>'provider_id' then z||jsonb_build_object('diagnosis',v_diagnosis) else z end) from jsonb_array_elements(snapshot->'providers') z)) where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','explain_evidence',c.id::text,jsonb_build_object('provider_id',p_args->>'provider_id','reason',v_reason,'diagnosis',v_diagnosis),v_actor);
   return v_diagnosis;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('cohort_id',h.id,'state',h.state,'created_at',h.created_at,'reason',h.reason,'run_id',h.run_id) order by h.created_at desc),'[]') into v_history from (select * from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int) h;
 if c.state='preview' then
   v_preview:=jsonb_set(c.snapshot,'{providers}',coalesce((select jsonb_agg(z||case when z->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(z->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',z->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(z->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end) from jsonb_array_elements(c.snapshot->'providers') z),'[]'::jsonb));
   return jsonb_build_object('preview',v_preview||jsonb_build_object('token',c.id,'expires_at',c.expires_at),'scope',c.selection,'history',v_history);
 end if;
 if c.id is null then return jsonb_build_object('history',v_history,'providers','[]'::jsonb,'runs','[]'::jsonb); end if;
 v_res:=security.provider_description_run_result_v1(c.id);
 if p_action='verify' then
   update pipeline.provider_description_cohorts set verified_at=now(),verification=v_res-'last_verification' where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify',c.id::text,jsonb_build_object('totals',v_res->'totals','as_at',now(),'reason','Operator requested actual catalogue and consumer read-back'),v_actor);
 end if;
 return v_res||jsonb_build_object('history',v_history);
 end if;
 raise exception 'unknown provider-description action %',p_action using errcode='22023';
end $function$;

-- 9. the Provider Catalogue's two columns (the registry the saved layout is checked against; src/catalogue-columns.js is checked equal by its spec)
insert into pipeline.admin_table_columns(screen, key, grp, label, sort, sort_key, default_visible, default_width, min_width, always_visible) values
 ('providers', 'description_quality', 'Pipeline and enrichment', 'Description quality level', 132, 'quality', false, 210, 130, false),
 ('providers', 'missing_fields', 'Pipeline and enrichment', 'Missing enrichment fields', 138, 'missing_fields', false, 240, 130, false)
on conflict (screen, key) do nothing;

-- 10. the component register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_description_quality', 'Platform', 'Fill fields: the Description quality level of each provider and the facts it was worked out from (a snapshot; the Provider Catalogue works the level out live)', 'active', '{}', '20261110030000'),
 ('function', 'security.provider_description_quality_v1', 'Platform', 'Fill fields: the Description quality level and its facts for a set of providers, read only', 'active', '{}', '20261110030000'),
 ('function', 'security.provider_description_quality_refresh_v1', 'Platform', 'Fill fields: the only writer of pipeline.provider_description_quality', 'active', '{}', '20261110030000'),
 ('function', 'security.provider_description_selection_multi_v1', 'Platform', 'Fill fields: a named set of providers selected one at a time by the governed selection', 'active', '{}', '20261110030000'),
 ('function', 'security.provider_description_cohort_cap_v1', 'Platform', 'Fill fields: the one cap on a Provider description cohort (screen limit and Run Now check)', 'active', '{}', '20261110030000')
on conflict do nothing;
update pipeline.component_register
   set note = coalesce(note || '; ', '') || 'Fill fields 20261110030000 (body replaced; same signature)'
 where kind = 'function' and name in ('security.admin_providers_page_v3', 'public.admin_provider_description_run_v1') and coalesce(note, '') not like '%20261110030000%';

-- post-check
do $$
declare v_page text; v_run text;
begin
  select md5(p.prosrc) into v_page from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)');
  select md5(p.prosrc) into v_run from pg_proc p where p.oid = to_regprocedure('public.admin_provider_description_run_v1(text,jsonb)');
  if v_page <> '2c906a2b1f7c346522ef7742d74039f1' then raise exception 'Fill fields post-check: page body md5 % is not the text this change writes', v_page; end if;
  if v_run <> '93af85a25c3f6c01334feeee8b7a355f' then raise exception 'Fill fields post-check: run body md5 % is not the text this change writes', v_run; end if;
  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)') and p.proconfig @> array['plan_cache_mode=force_custom_plan']) then raise exception 'Fill fields post-check: the page function is no longer set to custom plans'; end if;
  if (select count(*) from pipeline.admin_table_columns where screen = 'providers') <> 34 then raise exception 'Fill fields post-check: the Provider registry is not 34 columns'; end if;
  if (select count(*) from pipeline.admin_table_columns where screen = 'providers' and default_visible) <> 13 then raise exception 'Fill fields post-check: default Provider columns are not today''s 13'; end if;
  if exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('pdesc.quality_refresh_max', 'pdesc.quality_stale_minutes', 'pdesc.fill_poll_seconds', 'pdesc.fill_status_max')) then
    raise exception 'Fill fields post-check: this change adds no setting, but one of its earlier draft settings exists';
  end if;
  if has_table_privilege('authenticated', 'pipeline.provider_description_quality', 'select') or has_table_privilege('anon', 'pipeline.provider_description_quality', 'select') then raise exception 'Fill fields post-check: the quality table is readable by an API role'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.provider_description_quality'::regclass) then raise exception 'Fill fields post-check: row level security is off on the quality table'; end if;
  if has_function_privilege('authenticated', 'security.provider_description_quality_refresh_v1(uuid[])', 'execute') or has_function_privilege('anon', 'security.provider_description_selection_multi_v1(jsonb)', 'execute') then raise exception 'Fill fields post-check: a function is callable by a user directly'; end if;
  if security.provider_description_cohort_cap_v1() < 1 then raise exception 'Fill fields post-check: the cohort cap is below one'; end if;
end $$;
