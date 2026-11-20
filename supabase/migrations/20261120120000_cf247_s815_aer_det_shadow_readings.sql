-- CF-247 S1-AER s815 (Platform Admin 20 Nov 2026 10:51 AEDT, Decision 2: "$0 deterministic extraction against the stored pages in Main DB"; Decision 1: Boost and AI readings stay shadow-only).
-- Replaces: nothing. Retires: nothing.
-- What this adds, all beside the existing model (nothing the website or Zoho reads is touched; G3 unchanged at 75 functions and 48 tables):
--   pipeline.aer_det_pages     one row for each stored page the deterministic reader (worker mode aer_det_read, aer-det-reader.ts, version aer-det-v1.0) has read, with how many readings it gave;
--   pipeline.aer_det_readings  each reading: the English test or academic qualification, its value and its verbatim quote, as a SHADOW reading (status shadow). Nothing here admits anything;
--   security.aer_det_record_v1 the one idempotent writer (called by the workflow aer-det-read.yml through the Management API); it never writes to catalogue.* or Layer 4;
--   setting batch.aer_det_read pages sent to the worker in one call (G2).
-- The completeness gate, audit sample, page identity, manual locks and no-overwrite are not touched: a shadow reading is evidence beside Layer 4, never an admission (Decision 276).
set local lock_timeout = '5s';

create table if not exists pipeline.aer_det_pages (
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  chars       integer,
  sha256      text,
  readings    integer not null default 0,
  read_at     timestamptz not null default now(),
  primary key (course_id, evidence_id, extractor)
);
comment on table pipeline.aer_det_pages is 'CF-247 s815: each stored course page the deterministic English and academic entry reader has read (no model, no fetch), by extractor version. Lets a run resume where it stopped and counts pages that state nothing. Shadow only.';
alter table pipeline.aer_det_pages enable row level security;
revoke all on pipeline.aer_det_pages from public, anon, authenticated;

create table if not exists pipeline.aer_det_readings (
  id          bigint generated always as identity primary key,
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  kind        text not null check (kind in ('english_test', 'academic_entry')),
  test_key    text not null check (test_key in ('ielts','toefl_ibt','pte','oet','celpip','cambridge','atar','year12','ncea_l3','university_entrance','ca_secondary','bachelor_gpa')),
  value       jsonb not null,
  quote       text not null check (length(quote) between 8 and 400),
  strength    text not null check (strength in ('stated_minimum', 'mentioned')),
  status      text not null default 'shadow' check (status in ('shadow', 'rejected')),
  created_at  timestamptz not null default now()
);
comment on table pipeline.aer_det_readings is 'CF-247 s815: shadow readings of English tests and academic entry qualifications read deterministically from a stored course page, each with its verbatim quote. Never admitted by this table: Layer 4 and the AER gates decide (Decision 276).';
create unique index if not exists aer_det_readings_one on pipeline.aer_det_readings (course_id, evidence_id, extractor, test_key, md5(quote));
create index if not exists aer_det_readings_course on pipeline.aer_det_readings (course_id);
alter table pipeline.aer_det_readings enable row level security;
revoke all on pipeline.aer_det_readings from public, anon, authenticated;

create or replace function security.aer_det_record_v1(p_pages jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare v_pages int := 0; v_readings int := 0; p jsonb; r jsonb; v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  for p in select * from jsonb_array_elements(p_pages) loop
    if p ? 'error' or not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = (p->>'course_id')::uuid and g.evidence_id = (p->>'evidence_id')::uuid) then continue; end if;
    insert into pipeline.aer_det_pages (course_id, evidence_id, extractor, chars, sha256, readings)
    values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', (p->>'chars')::int, p->>'sha256', jsonb_array_length(coalesce(p->'readings', '[]'::jsonb)))
    on conflict (course_id, evidence_id, extractor) do nothing;
    get diagnostics v_n = row_count; v_pages := v_pages + v_n;
    for r in select * from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) loop
      insert into pipeline.aer_det_readings (course_id, evidence_id, extractor, kind, test_key, value, quote, strength)
      values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', r->>'kind', r->>'key', r->'value', r->>'quote', r->>'strength')
      on conflict do nothing;
      get diagnostics v_n = row_count; v_readings := v_readings + v_n;
    end loop;
  end loop;
  return jsonb_build_object('pages', v_pages, 'readings', v_readings);
end $f$;
comment on function security.aer_det_record_v1(jsonb) is 'CF-247 s815: records pages read by the deterministic reader and their shadow readings, idempotently. Writes only pipeline.aer_det_pages and pipeline.aer_det_readings.';
revoke all on function security.aer_det_record_v1(jsonb) from public, anon, authenticated;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'batch.aer_det_read', 'Deterministic entry reader: pages a call',
  'The deterministic English and academic entry reader (workflow aer-det-read) sends this many stored course pages to the worker in one call, and records them in one statement. No AI or Firecrawl spend.',
  'number', to_jsonb(20), 5, 40, 'pages', 644, 'Admission checks', 'aer-det-read workflow; coverage-sweep mode aer_det_read',
  'CF-247 s815 (Platform Admin 20 Nov 2026 10:51): small, indexed, low-IOPS batches')
on conflict do nothing;

do $c$
begin
  if to_regclass('pipeline.aer_det_pages') is null or to_regclass('pipeline.aer_det_readings') is null then raise exception 'post-check: a table is missing'; end if;
  if security.pipeline_num_v1('batch.aer_det_read', 0) <> 20 then raise exception 'post-check: setting batch.aer_det_read is missing'; end if;
  if (select count(*) from pipeline.aer_det_readings) <> 0 then raise exception 'post-check: readings should start empty'; end if;
end $c$;
