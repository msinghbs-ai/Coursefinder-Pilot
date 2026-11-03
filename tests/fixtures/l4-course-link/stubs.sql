-- CF-247 Layer 4 course link (migration 20261104150000) on isolated fixtures: the live shapes this change reads or writes beyond
-- ../p1-provider-descriptions/stubs.sql, which run.sh loads first with the live Layer 4 functions. Columns read from information_schema on
-- production (read-only, 3 Nov 2026 20:50-21:00 AEDT). Run on a scratch PostgreSQL only (never on a Supabase project). Nothing here is live data.

-- columns the p1 stubs leave out (live columns)
alter table catalogue.courses add column if not exists open_to_international boolean, add column if not exists course_url text, add column if not exists updated_at timestamptz default now();
alter table scholarship.scholarships add column if not exists publication_status text, add column if not exists lifecycle_status text default 'active';
alter table pipeline.scholarship_ai_reviews add column if not exists scholarship_id uuid, add column if not exists decided_at timestamptz, add column if not exists note text,
  add column if not exists decision jsonb, add column if not exists candidate_id bigint, add column if not exists storage_path text, add column if not exists decided_by uuid;

-- the list-setting reader (live md5 c33c2152bbadc8d01625ced9bf2c9bda; repository migration 20261103140000)
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb default '[]'::jsonb) returns text[]
language sql stable security definer set search_path to '' as $function$
  select array(select jsonb_array_elements_text(coalesce(
           (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key and jsonb_typeof(s.value) = 'array'),
           case when jsonb_typeof(p_default) = 'array' then p_default else '[]'::jsonb end)))
$function$;

-- catalogue and pipeline tables (live columns)
create table catalogue.course_links(id uuid primary key default gen_random_uuid(), course_id uuid not null, link_type text not null, url text not null, audience text, locale text,
  label text, is_primary boolean not null default false, status text not null default 'active', source_id uuid, evidence_id uuid, confidence numeric, last_verified_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (course_id, link_type, url));
create table pipeline.page_rejections(course_id uuid not null, url text not null, provider_id uuid, evidence_id uuid, source text, reason text, signals jsonb,
  rejected_at timestamptz not null default now(), rejected_by uuid, primary key (course_id, url));
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, basis text, status text, evidence_id uuid, identity_basis text, read_status text);
create table pipeline.course_no_page(course_id uuid primary key, provider_id uuid, kind text check (kind in ('no_page', 'conjoint')),
  state text check (state in ('proposed', 'confirmed', 'confirmed_auto', 'conjoint', 'rejected', 'reopened')), basis jsonb, inventory_at timestamptz, review_item_id uuid,
  proposed_at timestamptz, decided_at timestamptz, reopened_at timestamptz, reopened_reason text, updated_at timestamptz);
create table pipeline.course_link_search(course_id uuid primary key, provider_id uuid, stage text, state text, query text, req_id bigint, attempts int default 0, results jsonb,
  candidates jsonb, cand_idx int, bound_url text, queued_at timestamptz default now(), sent_at timestamptz, done_at timestamptz, requested_at timestamptz);
create table pipeline.coverage_vendor_usage(id bigserial primary key, acquisition_provider_id uuid, units numeric not null, purpose text not null, provider_id uuid, url text,
  at timestamptz not null default now(), on_demand_run uuid);

-- workstream L4's identity key (live since v2.15.438; repository migration 20261104120000) is loaded by run.sh from that migration

-- stand-ins for the destinations the new choices call (their live behaviour is not changed here): the course edit sets the page as a
-- person's value with its locks; the scholarship review refuses the held item
create function public.admin_course_edit(p_course_id uuid, p_action text, p_args jsonb default '{}') returns jsonb language plpgsql as $f$
begin
  if p_action <> 'set_official_url' then raise exception 'stand-in handles set_official_url only'; end if;
  insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values (p_course_id, 'official_course', p_args->>'url', true, 'active')
  on conflict (course_id, link_type, url) do update set status = 'active', is_primary = true;
  insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', p_course_id, 'official_url', 'value'), ('course', p_course_id, 'course_url', 'value');
  return jsonb_build_object('ok', true, 'url', p_args->>'url');
end $f$;
create function public.admin_scholarship_ai(p_action text, p_args jsonb default '{}') returns jsonb language plpgsql as $f$
begin
  if p_action <> 'review_decide' then raise exception 'stand-in handles review_decide only'; end if;
  update pipeline.scholarship_ai_reviews set status = case when p_args->>'decision' = 'admit' then 'admitted' else 'refused' end, decided_at = now(), note = p_args->>'reason'
   where id = (p_args->>'review_id')::bigint and status = 'pending';
  return jsonb_build_object('applied', jsonb_build_object('review_id', p_args->>'review_id', 'decision', p_args->>'decision'));
end $f$;

-- the countries and the three providers of the approved rules (ids as live), so the migration seeds the rules as it does live
insert into ref.countries(id, iso_alpha2) values ('f0000000-0000-0000-0000-0000000000a1', 'AU'), ('f0000000-0000-0000-0000-0000000000c1', 'CA'), ('f0000000-0000-0000-0000-0000000000e1', 'NZ');
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
 ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'adelaide', 'Adelaide University', 'f0000000-0000-0000-0000-0000000000a1'),
 ('0e1532b8-de30-4761-87fe-460684608633', 'canberra', 'University of Canberra', 'f0000000-0000-0000-0000-0000000000a1'),
 ('d47b6006-396a-4785-b2ae-15186c3e7709', 'sfu', 'Simon Fraser University (SFU)', 'f0000000-0000-0000-0000-0000000000c1');

-- who is signed in, as live: auth.uid() reads the request's subject claim (the p1 stand-in reads fx.uid; both are kept), and the system
-- automation account (Decision 263 rule decisions) holds the Pipeline Operator role, rank 4, as live
create or replace function auth.uid() returns uuid language sql stable as
  $f$ select coalesce(nullif(current_setting('fx.uid', true), ''), nullif(current_setting('request.jwt.claim.sub', true), ''))::uuid $f$;
create or replace function security.current_role_rank() returns int language sql stable as
  $f$ select coalesce(nullif(current_setting('fx.rank', true), '')::int,
                      case when auth.uid() = 'c0ffee00-0000-4000-8000-000000000150'::uuid then 4 end, 0) $f$;

create schema if not exists fx;
-- what the existing course-link apply calls (stand-ins): the reference list of non-course sites, the scoped search refresh
create table if not exists fx.reference_hosts(host text primary key, use text not null);
create or replace function security.reference_url_has_use(p_url text, p_use text) returns boolean language sql stable as
  $f$ select exists (select 1 from fx.reference_hosts h where h.use = p_use and h.host = lower(substring(p_url from '^https?://([^/]+)'))) $f$;
create or replace function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_force boolean) returns jsonb language sql as $f$ select '{}'::jsonb $f$;

-- the binding check's level reading (live security.course_page_check_v1; stand-in answering from a table)
create table fx.page_levels(course_id uuid, url text, course_levels jsonb, page_levels jsonb, primary key (course_id, url));
create or replace function security.course_page_check_v1(p_course uuid, p_url text, p_title text default null, p_identity text default null) returns jsonb language sql stable as
  $f$ select jsonb_build_object('verdict', 'pass', 'checks', jsonb_strip_nulls(jsonb_build_object('course_levels', l.course_levels, 'page_levels', l.page_levels)))
        from (select 1) one left join fx.page_levels l on l.course_id = p_course and l.url = p_url $f$;
