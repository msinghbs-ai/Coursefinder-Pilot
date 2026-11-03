-- Live shapes (3 Nov 2026) of what the SS-020 step 1 migration touches
create schema if not exists pipeline; create schema if not exists security;
create table pipeline.automation_catalogue (jobname text primary key, area text not null, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create table pipeline.component_register (kind text not null check (kind in ('job','table','view','edge_function','screen','function')), name text not null, layer text not null,
  area text, purpose text, status text not null default 'active' check (status in ('active','retiring','retired')), replaces text[] default '{}', replaced_by text, retire_after date,
  introduced_in text, note text, updated_at timestamptz default now(), primary key (kind, name));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql as $$ select p_default $$;
insert into pipeline.automation_catalogue(jobname, area) values ('coverage-ai-match-prepare','Layer 3 AI'),('coverage-ai-match','Layer 3 AI'),('fee-period-settle','Layer 3 AI'),('course-page-read','Course pages');
-- rows already in the live register (status active)
insert into pipeline.component_register(kind,name,layer,status,introduced_in) values ('table','pipeline.toolset_sample_runs','L2 read','active','x'),('table','pipeline.toolset_sample_items','L2 read','active','x'),('edge_function','toolset-runner','L2 read','active','x'),('table','pipeline.search_pass_links','L2 read','active','x');
