create schema if not exists extensions;
create schema if not exists ref;
create schema if not exists catalogue;
create schema if not exists pim;
create schema if not exists scholarship;
create schema if not exists integration;
create schema if not exists pipeline;
create schema if not exists search;
create schema if not exists publishing;
create schema if not exists workflow;
create schema if not exists security;
create schema if not exists api;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector with schema extensions;

comment on schema ref is 'Global controlled reference data';
comment on schema catalogue is 'Canonical providers, campuses, course collections, courses and structured course facts';
comment on schema pim is 'PIM families, groups, attributes, options, categories, values and completeness';
comment on schema scholarship is 'Scholarships, scopes, criteria, awards and coverage';
comment on schema integration is 'External systems, scraper, LLM/model and routing definitions';
comment on schema pipeline is 'Sources, policies, jobs, evidence and lineage';
comment on schema search is 'Read-optimised search profiles, documents, embeddings and cache';
comment on schema publishing is 'Publication channels and state';
comment on schema workflow is 'Layer 4 review, suggestions, import/export and validation';
comment on schema security is 'Application roles and permissions';
comment on schema api is 'Curated API-facing functions/views only';
