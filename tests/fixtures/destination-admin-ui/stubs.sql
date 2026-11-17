-- Extra objects that 20261117131500_cf247_rm0f_destination_admin_ui.sql builds on (fixtures only, never a Supabase project).
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_url text, captured_at timestamptz default now(), storage_path text);
create table pipeline.admin_control_events (id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}', actor uuid, created_at timestamptz not null default now());
create table pipeline.layer4_inbox_kind_hooks (kind text not null, mode text not null default 'kind', kind_fn text, counts_fn text, page_fn text, detail_fn text, decide_fn text,
  enabled boolean not null default true, owner text, note text, created_at timestamptz not null default now(), primary key (kind, mode));
create table pipeline.automation_catalogue (jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
alter table catalogue.providers add column if not exists display_name text, add column if not exists country_id uuid;
alter table catalogue.campuses add column if not exists postcode text, add column if not exists status text, add column if not exists country_id uuid,
  add column if not exists is_primary boolean, add column if not exists primary_basis text, add column if not exists stable_key text, add column if not exists subdivision_id uuid;
create table catalogue.course_registrations (id uuid primary key default gen_random_uuid(), course_id uuid, scheme text, registration_code text, status text, valid_to date);
create table catalogue.provider_registrations (id uuid primary key default gen_random_uuid(), provider_id uuid, registration_scheme text, registration_code text, status text);
-- the v2 Zoho provider answer the v3 wrapper decorates
create function public.zoho_v2_provider(p_identifier text) returns jsonb language sql stable as $$
  select jsonb_build_object('api_version', 'zoho-v2', 'item', jsonb_build_object('provider_id', p_identifier,
           'campuses', coalesce((select jsonb_agg(jsonb_build_object('campus_id', k.id, 'name', k.name, 'postcode', k.postcode, 'country_code', 'AU') order by k.name)
                                   from catalogue.campuses k join catalogue.providers p on p.id = k.provider_id where p.stable_key = p_identifier), '[]'::jsonb))) $$;
