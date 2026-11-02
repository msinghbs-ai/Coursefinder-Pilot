-- IQ-00043 link reactivation guard: the tables and helpers the guarded functions use, cut to the columns they use (shapes as live, 3 Nov 2026;
-- catalogue.course_links in full, with its live constraints, indexes and the manual_lock_guard trigger). Nothing here is a Supabase project.
create extension if not exists pgcrypto;
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; create role authenticated; create role service_role; end if; end $r$;
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue;
create schema if not exists ref; create schema if not exists search; create schema if not exists auth;
-- Supabase auth: a signed-in person is simulated with the setting fx.uid
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fx.uid', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('fx.role', true), '') $$;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value text, max_value text,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), country_id uuid, canonical_name text, display_name text);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, course_code text, lifecycle_status text default 'active',
  course_url text, updated_at timestamptz);
create table pipeline.coverage_admission_countries (country_id uuid, active boolean, currency_code text);
create table pipeline.sources (id uuid primary key default gen_random_uuid(), source_type text, status text default 'active', url text, country_id uuid);
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), content_hash text);
create table ref.course_link_types (code text primary key, label text);
insert into ref.course_link_types values ('official_course', 'Official course page'), ('regulator_listing', 'Regulator listing');
create table catalogue.course_links (
  id uuid primary key default gen_random_uuid(), course_id uuid references catalogue.courses(id) on delete cascade, link_type text references ref.course_link_types(code),
  url text, audience text, locale text, label text, is_primary boolean default false, status text default 'active', valid_from date, valid_to date,
  source_id uuid references pipeline.sources(id), evidence_id uuid references pipeline.evidence_artifacts(id), confidence numeric,
  last_verified_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now(),
  constraint course_links_course_id_link_type_url_key unique (course_id, link_type, url),
  constraint course_links_status_check check (status = any (array['active', 'inactive', 'deprecated', 'unverified'])),
  constraint course_links_url_not_blank check (btrim(url) <> ''));
create unique index course_links_one_primary_active_idx on catalogue.course_links (course_id) where (is_primary and status = 'active');
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz);
create table pipeline.page_rejections (course_id uuid, url text, provider_id uuid, evidence_id uuid, source text, reason text, signals jsonb,
  rejected_at timestamptz default now(), rejected_by uuid, primary key (course_id, url));
create table pipeline.course_page_blocks (course_id uuid, url text, reason text, created_at timestamptz default now(), primary key (course_id, url));
create table pipeline.course_remediation_holds (id bigserial primary key, course_id uuid, url text, held_at timestamptz default now(), lifted_at timestamptz);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid,
  before_value jsonb, proposed_value jsonb, layer2_state jsonb, layer3_state jsonb, status text, escalation_reason text, change_control_ref text,
  decided_at timestamptz, created_at timestamptz default now());
create table pipeline.layer4_decisions (review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb, proposed_value jsonb, final_value jsonb,
  evidence_id uuid, layer2_state jsonb, layer3_state jsonb, change_control_ref text);
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.component_register (kind text, name text, layer text, area text, purpose text, status text, replaces text[], replaced_by text,
  introduced_in text, note text, updated_at timestamptz, primary key (kind, name));
insert into pipeline.component_register(kind, name, status) values ('function', 'security.coverage_admission_apply_v1', 'active'), ('function', 'security.coverage_apply_course_v1', 'active');
create table search.course_documents (course_id uuid primary key, official_course_url text);
create table search.refresh_requests (id bigserial, requested_by text);
-- the projection's choice of the shown link (primary first, then the newest verified); refreshed on demand here
create function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_force boolean) returns void language sql as $$
  insert into search.course_documents(course_id, official_course_url)
  select c.id, (select l.url from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active'
                 order by l.is_primary desc, l.last_verified_at desc nulls last limit 1)
    from catalogue.courses c where c.id = any(p_ids)
  on conflict (course_id) do update set official_course_url = excluded.official_course_url $$;
-- the integration queue (v2.15.409) is recorded, not modelled
create table pipeline.fx_queue_calls (p jsonb, actor text);
create function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language sql as $$
  insert into pipeline.fx_queue_calls values (p, p_actor) returning jsonb_build_object('ok', true) $$;
-- helpers of the two live functions, reduced to what the cases need
create function security.layer4_entity_or_parent_blocked(p_type text, p_id uuid, p_kind text) returns boolean language sql stable as $$ select false $$;
create function security.coverage_sweep_source(p_provider uuid) returns uuid language sql stable as $$
  select id from pipeline.sources where source_type = 'provider_course_page_sweep' order by id limit 1 $$;
create function security.uni_adapter_excluded(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create function security.consumer_api_snapshot_v1() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create table pipeline.consumer_api_baselines (label text, snapshot jsonb);
create table pipeline.course_fact_source_qualifications (source_id uuid, country_id uuid, source_key text, source_class text, authority_name text, provider_cricos text,
  admitted_domains text[], mapping_strategy text, evidence_strategy text, qualification_status text, notes text, metadata jsonb);
create table search.enrichment_source_gates (projection_code text, domain_code text, source_id uuid, gate_status text, approval_ref text, approved_at timestamptz,
  created_at timestamptz, updated_at timestamptz);
create function public.svc_coursefacts_apply_record(uuid, uuid, text, text, text, text, text, jsonb, boolean) returns jsonb language sql as $$ select '{}'::jsonb $$;
-- the admission plan the rule cases feed (rows of security.coverage_admission_plan_v1)
create table pipeline.fx_plan (course_id uuid, provider_id uuid, provider_cricos text, course_cricos text, evidence_id uuid, content_hash text, page_url text,
  attribute text, action text, current jsonb, proposed jsonb);
create function security.coverage_admission_plan_v1(p_extractor text) returns setof pipeline.fx_plan language sql stable as $$ select * from pipeline.fx_plan $$;
-- the Decision 263 rule: take the proposed page when the fixture says so
create function security.course_page_rule_v1(p_current text, p_proposed text) returns text language sql stable as $$ select 'take:fixture rule' $$;
-- Layer 4 course link apply: the E15 statements of the live security.layer4_course_link_apply_impl (md5 75a53dbbcd5e20e1018a05b61f6763aa), verbatim
create function security.layer4_course_link_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text) returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_item pipeline.layer4_review_items%rowtype; v_url text := p_value->>'url'; v_link uuid; v_retired int := 0;
begin
  select * into v_item from pipeline.layer4_review_items where id = p_item_id;
  update catalogue.course_links set status='inactive',is_primary=false,updated_at=now()
   where course_id=v_item.entity_id and link_type='official_course' and status='active' and url<>v_url;
  get diagnostics v_retired = row_count;
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',true,'active',(select id from pipeline.sources where source_type='layer4_human_review' limit 1),v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',is_primary=true,source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;
  if v_link is null then raise exception 'the course page was not saved (a guard on the course''s links refused it); nothing was changed'; end if;
  update catalogue.courses set course_url=v_url,updated_at=now() where id=v_item.entity_id and course_url is distinct from v_url;
  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true,'superseded_links',v_retired);
end $$;
