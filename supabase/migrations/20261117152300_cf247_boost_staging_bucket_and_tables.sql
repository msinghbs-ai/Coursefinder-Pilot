-- CF-247 S1-Build (Platform Admin 17 Nov 2026 14:12): the Boost bulk-ingestion prerequisites in production.
--   1. The PRIVATE Storage bucket staging-boost (admin repo docs/paste/PASTE-20261116-staging-boost-bucket.sql, same values and the same check):
--      the Boost exporter writes to outbound/ and the Boost Worker writes results to inbound/. Service role only: no storage.objects policy names it,
--      and the block refuses if the bucket is public or a policy for anon or authenticated could reach it.
--   2. pipeline.boost_inbound_staging (one row per item the Boost Worker answered) and pipeline.boost_model_qualifications (the lane, provider and
--      model pairs whose answers may be admitted), from admin repo sql/boost-ingestion/001_boost_inbound_staging.sql, with row-level security on
--      and no grant to anon or authenticated (as every recent pipeline table).
-- Nothing is switched on: no job, no promotion function (002 is not applied), and boost_model_qualifications starts empty; a passing qualification
-- never switches anything on by itself, a Platform Admin adds a row with a reason. The quiet-window and batch settings come with the promotion
-- function. Tested on the throwaway test project and a local Postgres stand-in (admin docs/platform/CF-WORKER-BOOST-AND-PROD-LAUNCH.md §12).
-- G1: no job. G2: no operational value in a job or function (the bucket's file size limit is the Storage bucket's own property).
-- G3: no consumer API object is read or changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

-- 1. The bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('staging-boost', 'staging-boost', false, 52428800, array['application/x-ndjson', 'application/json', 'text/plain'])
on conflict (id) do nothing;

do $bucket$
declare v_public boolean; v_bad text;
begin
  select public into v_public from storage.buckets where id = 'staging-boost';
  if v_public is null then raise exception 'refused: staging-boost was not created'; end if;
  if v_public then raise exception 'refused: staging-boost must be private (it is public)'; end if;
  select string_agg(policyname, ', ') into v_bad
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (roles && array['anon', 'authenticated', 'public']::name[])
     and (coalesce(qual, '') ~* 'staging-boost' or coalesce(with_check, '') ~* 'staging-boost'
          or (coalesce(qual, '') !~* 'bucket_id' and coalesce(with_check, '') !~* 'bucket_id'));
  if v_bad is not null then raise exception 'refused: storage.objects policies would let anon or authenticated reach staging-boost: %', v_bad; end if;
end $bucket$;

-- 2. The staging and qualification tables
create table if not exists pipeline.boost_inbound_staging (
  id              bigint generated always as identity primary key,
  batch_id        text not null,
  item_key        text not null,
  lane            text not null check (lane in ('study_load', 'provider_accreditations', 'aer_entry', 'course_description', 'course_fees')),
  entity          text not null check (entity in ('course', 'provider')),
  entity_id       uuid not null,
  evidence_id     uuid,
  source_url      text,
  provider        text,
  model           text,
  prompt_id       text not null,
  prompt_version  text not null,
  prompt_sha256   text not null check (prompt_sha256 ~ '^[0-9a-f]{64}$'),
  selector        text,
  answer          jsonb,
  verdict         jsonb not null,
  worker_status   text not null check (worker_status in ('verified', 'rejected', 'failed')),
  attempts        jsonb not null default '[]'::jsonb,
  worker_at       timestamptz not null,
  loaded_at       timestamptz not null default now(),
  promotion_state text not null default 'staged'
                  check (promotion_state in ('staged', 'shadow', 'proposed', 'admitted', 'refused')),
  promotion_note  text,
  promoted_at     timestamptz,
  unique (batch_id, item_key)
);
comment on table pipeline.boost_inbound_staging is 'CF-247 Boost (Platform Admin 16 Nov 2026 20:31; production 17 Nov 2026 14:12): one row per item answered by the Boost Worker (free-tier failover chain), loaded from staging-boost/inbound. '
  'Every row names the one provider and model that answered (provider and model are null when every step failed). Nothing here is catalogue data: the promotion function, '
  'when it is added, decides in the quiet window what is admitted (only lanes and models in pipeline.boost_model_qualifications), proposed, kept as a shadow reading, or refused.';
create index if not exists boost_inbound_staging_state_idx on pipeline.boost_inbound_staging (promotion_state, lane);
create index if not exists boost_inbound_staging_entity_idx on pipeline.boost_inbound_staging (entity_id);

create table if not exists pipeline.boost_model_qualifications (
  lane         text not null check (lane in ('study_load', 'provider_accreditations', 'course_description', 'course_fees')),
  provider     text not null,
  model        text not null,
  qualified_by uuid,
  qualified_at timestamptz not null default now(),
  reason       text not null check (length(btrim(reason)) > 0),
  primary key (lane, provider, model)
);
comment on table pipeline.boost_model_qualifications is 'CF-247 Boost: the (lane, provider, model) pairs whose verified answers the Boost promotion may admit. Rows are added only by the Platform Admin '
  'after the model passes that lane''s qualification; never by a job or a benchmark run. aer_entry is not a lane here: AER is admitted only by its own rule.';

alter table pipeline.boost_inbound_staging enable row level security;
alter table pipeline.boost_model_qualifications enable row level security;
revoke all on pipeline.boost_inbound_staging, pipeline.boost_model_qualifications from anon, authenticated;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.boost_inbound_staging', 'Layer 2', 'Boost', 'Boost Worker results waiting for promotion', 'active', '{}', '20261117152300'),
  ('table', 'pipeline.boost_model_qualifications', 'Layer 2', 'Boost', 'Models whose Boost answers may be admitted, per lane', 'active', '{}', '20261117152300')
on conflict do nothing;

-- Post-checks
do $c$
begin
  if not exists (select 1 from storage.buckets where id = 'staging-boost' and not public) then raise exception 'post-check: staging-boost is not a private bucket'; end if;
  if to_regclass('pipeline.boost_inbound_staging') is null or to_regclass('pipeline.boost_model_qualifications') is null then raise exception 'post-check: a Boost table is missing'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.boost_inbound_staging'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'pipeline.boost_model_qualifications'::regclass) then raise exception 'post-check: row-level security is off'; end if;
  if has_table_privilege('anon', 'pipeline.boost_inbound_staging', 'select') or has_table_privilege('authenticated', 'pipeline.boost_model_qualifications', 'select') then
    raise exception 'post-check: anon or authenticated can read a Boost table';
  end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'; end if;
  if exists (select 1 from cron.job where command ilike '%boost%') then raise exception 'post-check: no Boost job may run'; end if;
end $c$;
