-- Production table shapes read 5 Nov 2026 09:24 AEDT (columns, defaults, not null, constraints and indexes of project fxcwkweaxjtknorudmwp),
-- added to the intake fixture database (tests/fixtures/intake-ui, kept by RUN_NOW_KEEP). The intake fixture's loose stub of
-- pipeline.provider_policy_proposals (nullable fact_source_id, no unique key, no checks) is brought to the production shape: the #872 lesson
-- (Platform Admin 5 Nov 2026 §9) is that a test database without production constraints proves nothing.
\set ON_ERROR_STOP on
alter table catalogue.providers add column if not exists publication_status text default 'published';
create or replace view security.provider_hidden_v1 as
 SELECT id AS provider_id
   FROM catalogue.providers p
  WHERE ((publication_status IS DISTINCT FROM 'published'::text) OR (lifecycle_status IS DISTINCT FROM 'active'::text));

create table if not exists pipeline.provider_fact_sources (id uuid default gen_random_uuid() not null, provider_id uuid not null, kind text not null, url text not null, title text, rank integer default 1 not null, found_via text default 'search'::text not null, status text default 'found'::text not null, http_status integer, evidence_id uuid, content_hash text, read_at timestamp with time zone, parse_summary jsonb, attempts integer default 0 not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, linked_from uuid, decision text, decided_by uuid, decided_at timestamp with time zone, decision_note text, apply_summary jsonb);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_key UNIQUE (provider_id, kind, url);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_pkey PRIMARY KEY (id);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES pipeline.evidence_artifacts(id);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_linked_from_fkey FOREIGN KEY (linked_from) REFERENCES pipeline.provider_fact_sources(id);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES catalogue.providers(id);
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text])));
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_found_via_check CHECK ((found_via = ANY (ARRAY['search'::text, 'manual'::text])));
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_kind_check CHECK ((kind = ANY (ARRAY['fee_schedule'::text, 'english_policy'::text, 'intake_calendar'::text])));
alter table pipeline.provider_fact_sources add constraint provider_fact_sources_status_check CHECK ((status = ANY (ARRAY['found'::text, 'reading'::text, 'read'::text, 'parsed'::text, 'no_values'::text, 'failed'::text, 'rejected'::text])));

-- the stub proposals: one fact source each (as production holds), then the production constraints
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, status, evidence_id, content_hash)
select gen_random_uuid(), p.provider_id, p.kind, coalesce(p.url, 'https://fixture.example/' || p.id), 'parsed',
       (select e.id from pipeline.evidence_artifacts e where e.id = p.evidence_id), coalesce(p.content_hash, md5(p.id::text))
  from pipeline.provider_policy_proposals p where p.fact_source_id is null
on conflict (provider_id, kind, url) do nothing;
update pipeline.provider_policy_proposals p set fact_source_id = f.id, url = f.url
  from pipeline.provider_fact_sources f where p.fact_source_id is null and f.provider_id = p.provider_id and f.kind = p.kind and f.url = coalesce(p.url, 'https://fixture.example/' || p.id);
alter table pipeline.provider_policy_proposals add column if not exists plan_summary jsonb, add column if not exists plan_at timestamp with time zone;
alter table pipeline.provider_policy_proposals alter column fact_source_id set not null, alter column url set not null;
alter table pipeline.provider_policy_proposals add constraint provider_policy_proposals_key UNIQUE (fact_source_id, parser, content_hash);
alter table pipeline.provider_policy_proposals add constraint provider_policy_proposals_fact_source_id_fkey FOREIGN KEY (fact_source_id) REFERENCES pipeline.provider_fact_sources(id);
alter table pipeline.provider_policy_proposals add constraint provider_policy_proposals_kind_check CHECK ((kind = ANY (ARRAY['english_policy'::text, 'intake_calendar'::text])));
alter table pipeline.provider_policy_proposals add constraint provider_policy_proposals_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'no_values'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
create index if not exists provider_policy_proposals_provider on pipeline.provider_policy_proposals using btree (provider_id, kind, status);

create sequence if not exists pipeline.central_ai_queue_id_seq;
create table if not exists pipeline.central_ai_queue (id bigint default nextval('pipeline.central_ai_queue_id_seq'::regclass) not null, fact_source_id uuid not null, provider_id uuid not null, kind text not null, content_hash text, state text default 'queued'::text not null, attempts integer default 0 not null, leased_until timestamp with time zone, created_at timestamp with time zone default now() not null, done_at timestamp with time zone, status text, cost_usd numeric, error text);
alter table pipeline.central_ai_queue add constraint central_ai_queue_pkey PRIMARY KEY (id);
alter table pipeline.central_ai_queue add constraint central_ai_queue_fact_source_id_fkey FOREIGN KEY (fact_source_id) REFERENCES pipeline.provider_fact_sources(id) ON DELETE CASCADE;
alter table pipeline.central_ai_queue add constraint central_ai_queue_kind_check CHECK ((kind = ANY (ARRAY['english_policy'::text, 'intake_calendar'::text])));
alter table pipeline.central_ai_queue add constraint central_ai_queue_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'leased'::text, 'done'::text, 'failed'::text])));
CREATE UNIQUE INDEX central_ai_queue_one_open ON pipeline.central_ai_queue USING btree (fact_source_id) WHERE (state = ANY (ARRAY['queued'::text, 'leased'::text]));
CREATE INDEX central_ai_queue_state_idx ON pipeline.central_ai_queue USING btree (state, id);

create table if not exists pipeline.central_ai_settings (id integer default 1 not null, enabled boolean default true not null, model_code text not null, model_identifier text not null, calls_at_once integer default 2 not null, reason text, changed_by uuid, changed_at timestamp with time zone default now() not null);
alter table pipeline.central_ai_settings add constraint central_ai_settings_pkey PRIMARY KEY (id);
alter table pipeline.central_ai_settings add constraint central_ai_settings_calls_at_once_check CHECK (((calls_at_once >= 0) AND (calls_at_once <= 6)));
alter table pipeline.central_ai_settings add constraint central_ai_settings_id_check CHECK ((id = 1));
insert into pipeline.central_ai_settings(id, enabled, model_code, model_identifier, calls_at_once) values (1, true, 'gpt-4.1-mini', 'openai/gpt-4.1-mini', 2);

create table if not exists pipeline.enrich_focus_providers (provider_id uuid not null, rank integer not null, gaps integer not null, in_focus boolean not null, set_at timestamp with time zone default now() not null);
alter table pipeline.enrich_focus_providers add constraint enrich_focus_providers_pkey PRIMARY KEY (provider_id);
alter table pipeline.enrich_focus_providers add constraint enrich_focus_providers_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES catalogue.providers(id);

create sequence if not exists pipeline.enrichment_flags_id_seq;
create table if not exists pipeline.enrichment_flags (id bigint default nextval('pipeline.enrichment_flags_id_seq'::regclass) not null, entity text not null, entity_key text not null, provider_id uuid, field text default ''::text not null, reason_code text not null, reason text not null, source text not null, flagged_at timestamp with time zone default now() not null, cleared_at timestamp with time zone, kind text default 'hard'::text not null, state text default 'raised'::text not null, tries integer default 1 not null, checks integer default 0 not null, evidence jsonb default '{}'::jsonb not null, next_check_at timestamp with time zone, input_mark text, raised_by_kind text default 'auto'::text not null, released_at timestamp with time zone, released_by text, release_kind text, release_reason text, updated_at timestamp with time zone default now() not null, first_flagged_at timestamp with time zone);
alter table pipeline.enrichment_flags add constraint enrichment_flags_entity_entity_key_field_reason_code_key UNIQUE (entity, entity_key, field, reason_code);
alter table pipeline.enrichment_flags add constraint enrichment_flags_pkey PRIMARY KEY (id);
alter table pipeline.enrichment_flags add constraint enrichment_flags_kind_check CHECK ((kind = ANY (ARRAY['hard'::text, 'soft'::text])));
alter table pipeline.enrichment_flags add constraint enrichment_flags_state_check CHECK ((state = ANY (ARRAY['counting'::text, 'raised'::text, 'released'::text])));

-- referenced by the live functions on paths the fixture does not test (onboarding note, English refresh): minimal stand-ins
create table if not exists pipeline.provider_onboarding (provider_id uuid primary key, status text, stop_reason text, note text, updated_at timestamptz);
create or replace function security.provider_policy_refresh_one_v1(uuid) returns jsonb language sql as $$ select '{}'::jsonb $$;
create or replace function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb default '{}'::jsonb) returns bigint language sql as $$ select 0::bigint $$;

-- search.course_documents (the Website API source) carries provider_id in production; the intake fixture's projection stand-in does not
alter table search.course_documents add column if not exists provider_id uuid;
update search.course_documents d set provider_id = c.provider_id from catalogue.courses c where c.id = d.course_id and d.provider_id is null;
-- pg_cron's run history (production extension table), read by the process measurement for the last run and last success
create table if not exists cron.job_run_details (jobid bigint, runid bigint, job_pid integer, database text, username text, command text, status text, return_message text, start_time timestamptz, end_time timestamptz);
-- production invariant: every active course has its Website projection row (the #876 dense load created courses without one)
insert into search.course_documents(course_id, country_code, provider_id)
select c.id, 'AU', c.provider_id from catalogue.courses c where not exists (select 1 from search.course_documents d where d.course_id = c.id);
-- production invariant (read 5 Nov 2026 10:02: top 10 universities, 5,399 active intakes, 0 without a source, 0 from a source without an
-- approved course_intake publication gate): the fixture's sourceless intake rows take the fixture's gated adapter source
update catalogue.course_intakes i set source_id = (select g.source_id from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_intake' and g.gate_status = 'approved' order by g.source_id limit 1)
 where i.source_id is null;

-- pipeline.component_register as production holds it (read 5 Nov 2026 11:10): replaces text[] default '{}' not null, usage jsonb default '{}' not null,
-- status default 'active' not null, kind and status checks. The intake fixture's stand-in allowed a null "replaces", which let a migration that
-- production refuses pass (deploy of v2.15.480, 5 Nov 2026 11:05: 23502 on component_register.replaces).
update pipeline.component_register set replaces = '{}' where replaces is null;
alter table pipeline.component_register alter column replaces set default '{}', alter column replaces set not null;
alter table pipeline.component_register add column if not exists usage jsonb default '{}'::jsonb not null;
alter table pipeline.component_register alter column status set default 'active', alter column status set not null;
do $c$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.component_register'::regclass and pg_get_constraintdef(oid) like '%kind = ANY%') then
    alter table pipeline.component_register add constraint component_register_kind_check check (kind = any (array['job','table','view','edge_function','screen','function']));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.component_register'::regclass and pg_get_constraintdef(oid) like '%status = ANY%') then
    alter table pipeline.component_register add constraint component_register_status_check check (status = any (array['active','retiring','retired']));
  end if;
end $c$;
