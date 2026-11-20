-- CF-247 s904 to s909 (session S1-ELR-Bands-And-Crawl, Platform Admin 21 Nov 2026 09:00 AEDT): "Fix the 'band 6.0' IELTS sub-score false-positive hold label, add a deterministic
-- English-band-to-course reader (Band A/B/C, Band 1-4) at $0 AI spend, and fetch the 70 already-discovered central English URLs (346 courses) so they parse".
-- English language requirements only.
--
-- Found live (rolled-back probes, 21 Nov 2026 09:05 to 09:40 AEDT; head 20261121093000; G3 75/48; manual locks 7,585; 135 active cron jobs):
--   * The v1.1 "bands" flag fired on 27 of 63 pages read; in every sampled line the trigger was IELTS score wording ("IELTS Band 4", "no band less than 6.0").
--     No sampled page named a band scheme ("Band A", "English band 2").
--   * Universities with gap courses, a central English page found but none stored: 89 (561 active courses with no English requirement). Their 137 pages: 71 failed on the
--     old daily budget, 63 were refused because the university is not on the scheduled Firecrawl target list, 1 answered 403, 2 had no content, 1 is a site Firecrawl does not
--     support. The scheduled provider-facts job is off. Several found pages are not admission pages (IELTS preparation classes, blog posts, a research case study).
--   * Firecrawl credit left on the plan 67,193; the model account is not used by this change.
--
-- What changes:
--   (s904) reader elr-central-v1.2: IELTS sub-score wording is no longer an English band scheme; pages are read again by v1.2 (reads keyed by reader version, $0).
--   (s905) the values a central page gives each named band ("band A", "band 2", "English level 3") are kept in pipeline.elr_band_defs. Never a study-level default.
--   (s906) elr-band-v1.0: course pages of those universities are read for the band they name; a course whose page names exactly one defined band gets that band's values
--          (insert only, key elr-band:<band>:<test>), through the s842 gates (identity, refused page, Layer 4, no overwrite, 7,585 manual locks). More than one band, values
--          that differ between pages, a regulated discipline (nursing, midwifery, medicine, allied health, teaching and education, law, social work), a shared page and the
--          audit sample go to Layer 4; an undefined band or no band is held.
--   (s907) the one-off bounded fetch: up to elr_central_fetch.max (100) known, unstored central English pages of those universities are queued (old budget and target-list
--          refusals only; not a 403, a site Firecrawl does not support, an empty page, or a page whose address does not name a requirement, proficiency,
--          admission, entry or policy page or shows it is a test-preparation, class, blog or news page), under one on-demand
--          request ('claude_session', Firecrawl only, scope central, 6 hours). elr-det-sweep fetches 10 a run and closes the request when the queue is empty.
--          Estimate: one Firecrawl credit a page (a PDF or long page can cost more); no model.
--   (s908, s909) the tick, the status read (security.elr_band_status_v1) and the specs.
-- G1: no new job (elr-det-sweep carries it). G2: five new settings, every value read with security.pipeline_num_v1. G3 stays 75/48.
-- Spend: US$0 AI. Firecrawl: only the one-off fetch, under its on-demand request, at most 100 pages.
-- Parity: head 20261121093000 read live 21 Nov 2026 09:05 AEDT; this file is numbered strictly above it and above the open S1-Coverage-Unlock files (20261121100000 to 102000).
-- Replaces: the elr-central-v1.1 page reads and its bands flag (pages are read again by v1.2; v1.1 rows stay as history).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: elr_band.on 0 and elr_central_fetch.on 0 stop the new work; the on-demand request lapses after 6 hours; a band row is removed by a person like any other.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the post-check reads the claims and the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1(); r record;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  for r in select * from (values ('security.elr_central_claim_v1(integer)', '41ad1af0f4e92763cbd4a906c420e42b'), ('security.elr_central_record_v1(jsonb,text)', '53cb89fe0e2b9173b4366860491b2e42'),
                                 ('security.elr_det_sweep_tick_v1()', 'a82317fb3f481021336b4fb45d5bf461')) v(f, h) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.h then raise exception 'guard: % is not the text this change was written against', r.f; end if;
  end loop;
end $g$;
create temp table s904_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s904_cron on commit drop as select count(*) n from cron.job where active;

-- (s905, s906, s907) tables: internal, no foreign keys (the sweep's own tables, written by one job; no lock waits on busy tables)
create table if not exists pipeline.elr_band_defs (
  fact_source_id  uuid not null,
  provider_id     uuid not null,
  extractor       text not null,
  band            text not null,
  test_code       text not null,
  overall_score   numeric not null,
  component_scores jsonb not null default '{}'::jsonb,
  quote           text not null,
  current         boolean not null default true,
  read_at         timestamptz not null default now(),
  primary key (fact_source_id, band, test_code, extractor)
);
comment on table pipeline.elr_band_defs is 'CF-247 s905: the test values a university''s stored central English page gives each named English band ("band A", "band 2", "level 3"), read by elr-central-v1.2, with the verbatim quote. A band is never a study-level default: it is used only for a course whose own page names that band (security.elr_band_record_v1). current is false once a newer read of the page no longer states it.';
create index if not exists elr_band_defs_provider on pipeline.elr_band_defs (provider_id) where current;
alter table pipeline.elr_band_defs enable row level security;
revoke all on pipeline.elr_band_defs from public, anon, authenticated;

create table if not exists pipeline.elr_band_pages (
  course_id   uuid not null,
  evidence_id uuid not null,
  extractor   text not null,
  outcome     text not null default 'sent' check (outcome in ('sent', 'read', 'lost', 'failed')),
  bands       text[] not null default '{}',
  quote       text,
  result      text,
  request_id  bigint,
  sent_at     timestamptz not null default now(),
  read_at     timestamptz,
  primary key (course_id, evidence_id, extractor)
);
comment on table pipeline.elr_band_pages is 'CF-247 s906: each stored course page the English requirement sweep read for the English band it names (elr-band-v1.0), at a university whose central page defines bands; the bands found, the quote and what the writer decided (promoted, Layer 4 or held with its reason).';
create index if not exists elr_band_pages_request on pipeline.elr_band_pages (request_id) where outcome = 'sent';
alter table pipeline.elr_band_pages enable row level security;
revoke all on pipeline.elr_band_pages from public, anon, authenticated;

create table if not exists pipeline.elr_band_requests (
  id           bigint primary key,
  pages        integer not null,
  status       text not null default 'sent' check (status in ('sent', 'done', 'lost', 'failed')),
  submitted_at timestamptz not null default now(),
  finished_at  timestamptz,
  result       jsonb
);
comment on table pipeline.elr_band_requests is 'CF-247 s906: each call the English requirement sweep made to the coverage-sweep worker for course-page English bands (mode elr_band_read), by its pg_net request id.';
create index if not exists elr_band_requests_open on pipeline.elr_band_requests (submitted_at) where status = 'sent';
alter table pipeline.elr_band_requests enable row level security;
revoke all on pipeline.elr_band_requests from public, anon, authenticated;

create table if not exists pipeline.elr_central_fetches (
  fact_source_id uuid primary key,
  provider_id    uuid not null,
  url            text not null,
  on_demand_id   uuid,
  status         text not null default 'queued' check (status in ('queued', 'sent', 'stored', 'failed', 'refused', 'lost')),
  request_id     bigint,
  queued_at      timestamptz not null default now(),
  sent_at        timestamptz,
  done_at        timestamptz,
  result         jsonb
);
comment on table pipeline.elr_central_fetches is 'CF-247 s907 (Platform Admin 21 Nov 2026 09:00): the one-off, bounded list of known but unstored central English pages fetched once under an on-demand request (Firecrawl, scope central). Each page is sent once; a page whose call is lost is not sent again by itself. A stored page is read by the central English sweep.';
alter table pipeline.elr_central_fetches enable row level security;
revoke all on pipeline.elr_central_fetches from public, anon, authenticated;

create table if not exists pipeline.elr_central_fetch_requests (
  id           bigint primary key,
  pages        integer not null,
  status       text not null default 'sent' check (status in ('sent', 'done', 'lost', 'failed')),
  submitted_at timestamptz not null default now(),
  finished_at  timestamptz,
  result       jsonb
);
comment on table pipeline.elr_central_fetch_requests is 'CF-247 s907: each call the English requirement sweep made to the coverage-sweep worker to fetch known central English pages (mode elr_central_fetch), by its pg_net request id.';
create index if not exists elr_central_fetch_requests_open on pipeline.elr_central_fetch_requests (submitted_at) where status = 'sent';
alter table pipeline.elr_central_fetch_requests enable row level security;
revoke all on pipeline.elr_central_fetch_requests from public, anon, authenticated;

create table if not exists pipeline.elr_central_fetch_state (
  on_demand_id uuid primary key,
  opened_at    timestamptz not null default now(),
  estimate     jsonb,
  closed_at    timestamptz,
  report       jsonb
);
comment on table pipeline.elr_central_fetch_state is 'CF-247 s907: the on-demand request the one-off central English fetch ran under: its estimate when opened and its report (actual Firecrawl use, credit left) when the sweep closed it.';
alter table pipeline.elr_central_fetch_state enable row level security;
revoke all on pipeline.elr_central_fetch_state from public, anon, authenticated;

-- (G2) settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'elr_band.on', 'English requirement sweep: read English bands on course pages',
  '1: each run of elr-det-sweep reads the English band named on course pages of universities whose central English page defines bands, and writes the band''s values for a course whose page names exactly one defined band. 0: it does not.',
  'number', to_jsonb(1), 0, 1, 'switch', 663, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s906 (Platform Admin 21 Nov 2026 09:00): deterministic English band to course matching'),
 ('pipeline', 'batch.elr_band', 'English requirement sweep: course pages a run (English bands)',
  'Course pages read for their English band in one run (one call).', 'number', to_jsonb(40), 1, 40, 'pages', 664, 'Admission checks',
  'security.elr_det_sweep_tick_v1; security.elr_band_claim_v1', 'CF-247 s906: bounded, low-IOPS batches'),
 ('pipeline', 'elr_central_fetch.on', 'English requirement sweep: fetch known central English pages',
  '1: while its on-demand request is open, each run of elr-det-sweep fetches a few of the known, unstored central English pages queued by s907. 0: it does not (the request then lapses by itself).',
  'number', to_jsonb(1), 0, 1, 'switch', 665, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s907 (Platform Admin 21 Nov 2026 09:00): one-off bounded fetch'),
 ('pipeline', 'batch.elr_central_fetch', 'English requirement sweep: central pages fetched a run',
  'Known central English pages fetched in one run (one call, Firecrawl).', 'number', to_jsonb(10), 1, 12, 'pages', 666, 'Admission checks',
  'security.elr_det_sweep_tick_v1; security.elr_central_fetch_claim_v1', 'CF-247 s907: bounded, one call a run'),
 ('pipeline', 'elr_central_fetch.max', 'English requirement sweep: most central pages in the one-off fetch',
  'The most known, unstored central English pages queued for the one-off fetch (s907).', 'number', to_jsonb(100), 0, 100, 'pages', 667, 'Admission checks',
  'migration 20261121110000 (s907 queue)', 'CF-247 s907 (Platform Admin 21 Nov 2026 09:00): "a one-off bounded crawl (<= 100 pages)"')
on conflict do nothing;

-- (s905) the values each named band states, from a central page read by elr-central-v1.2
create or replace function security.elr_band_defs_record_v1(p_pages jsonb, p_extractor text) returns integer
language plpgsql security definer set search_path to ''
as $f$
declare pg jsonb; b record; r jsonb; v_n int := 0; v_k int; v_src uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' or p_extractor is distinct from 'elr-central-v1.2' then return 0; end if;
  for pg in select * from jsonb_array_elements(p_pages) loop
    continue when pg ? 'error' or nullif(pg->>'fact_source_id', '') is null;
    v_src := (pg->>'fact_source_id')::uuid;
    update pipeline.elr_band_defs d set current = false where d.fact_source_id = v_src and d.extractor = p_extractor and d.current;
    continue when jsonb_typeof(pg->'reading'->'band_defs') is distinct from 'object';
    for b in select key band, value reqs from jsonb_each(pg->'reading'->'band_defs') loop
      continue when b.band !~ '^(band [A-F1-9]|level [1-9])$' or jsonb_typeof(b.reqs) <> 'array';
      for r in select * from jsonb_array_elements(b.reqs) loop
        continue when coalesce(jsonb_typeof(r->'overall_score'), '') <> 'number' or length(coalesce(r->>'quote', '')) not between 8 and 400
                   or not exists (select 1 from ref.english_tests et where et.code = r->>'test_code');
        insert into pipeline.elr_band_defs as d (fact_source_id, provider_id, extractor, band, test_code, overall_score, component_scores, quote, current, read_at)
        values (v_src, (pg->>'provider_id')::uuid, p_extractor, b.band, r->>'test_code', (r->>'overall_score')::numeric, coalesce(r->'component_scores', '{}'::jsonb), r->>'quote', true, now())
        on conflict (fact_source_id, band, test_code, extractor) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores, quote = excluded.quote,
               current = true, read_at = now();
        get diagnostics v_k = row_count; v_n := v_n + v_k;
      end loop;
    end loop;
  end loop;
  return v_n;
end $f$;
comment on function security.elr_band_defs_record_v1(jsonb, text) is 'CF-247 s905: keeps the test values a stored central English page gives each named English band (elr-central-v1.2 band_defs) in pipeline.elr_band_defs; a band or test the newer read no longer states stops being current. Writes no course row.';
revoke all on function security.elr_band_defs_record_v1(jsonb, text) from public, anon, authenticated;

-- (s906) the next course pages to read for their English band: gap courses of universities with current band definitions, page not yet read by elr-band-v1.0
create or replace function security.elr_band_claim_v1(p_limit integer) returns table (course_id uuid, evidence_id uuid, storage_path text, bands text[])
language plpgsql stable security definer set search_path to ''
as $f$
declare v_prov uuid[];
begin
  -- the universities with current band definitions first (usually none or a few), so the course query only ever looks at their courses
  select array_agg(distinct d.provider_id) into v_prov from pipeline.elr_band_defs d where d.current;
  if v_prov is null then return; end if;
  return query
  select g.course_id, g.evidence_id, e.storage_path, (select array_agg(distinct d.band order by d.band) from pipeline.elr_band_defs d where d.provider_id = c.provider_id and d.current)
    from catalogue.courses c
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound' and g.read_status = 'read' and g.evidence_id is not null
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
   where c.provider_id = any (v_prov) and c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')
     and not exists (select 1 from pipeline.elr_band_pages b where b.course_id = g.course_id and b.evidence_id = g.evidence_id and b.extractor = 'elr-band-v1.0' and b.outcome <> 'lost')
   order by g.course_id limit greatest(p_limit, 0);
end $f$;
comment on function security.elr_band_claim_v1(integer) is 'CF-247 s906: the next stored course pages to read for the English band they name: active courses with no English requirement, at universities whose central page defines bands (pipeline.elr_band_defs), page not yet read by elr-band-v1.0. Read only.';
revoke all on function security.elr_band_claim_v1(integer) from public, anon, authenticated;

-- (s906) the band writer: records the page, then writes the named band's values for the course only when every gate passes
create or replace function security.elr_band_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-band-v1.0';
  p jsonb; g record; d record; v_course uuid; v_ev uuid; v_bands text[]; v_quote text; v_reason text; v_review text; v_disc text; v_defs jsonb; v_n int; v_wrote int;
  v_audit int := security.pipeline_num_v1('elr_det.audit_pct', 5)::int;
  v_promote boolean := security.pipeline_num_v1('elr_det.promote_on', 1) >= 1;
  v_pages int := 0; v_promoted int := 0; v_rows int := 0; v_review_n int := 0; v_held int := 0; v_failed int := 0; v_done uuid[] := '{}'; v_search text := 'none';
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  for p in select * from jsonb_array_elements(p_pages) loop
    v_course := nullif(p->>'course_id', '')::uuid; v_ev := nullif(p->>'evidence_id', '')::uuid;
    continue when v_course is null or v_ev is null;
    if p ? 'error' then
      update pipeline.elr_band_pages b set outcome = 'failed', result = left(p->>'error', 160), read_at = now() where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
      v_failed := v_failed + 1; continue;
    end if;
    select coalesce(array_agg(distinct m->>'band'), '{}'), (array_agg(m->>'quote'))[1] into v_bands, v_quote
      from jsonb_array_elements(coalesce(p->'mentions', '[]'::jsonb)) m where (m->>'band') ~ '^(band [A-F1-9]|level [1-9])$';
    insert into pipeline.elr_band_pages as b (course_id, evidence_id, extractor, outcome, bands, quote, read_at)
    values (v_course, v_ev, v_x, 'read', v_bands, left(v_quote, 300), now())
    on conflict (course_id, evidence_id, extractor) do update set outcome = 'read', bands = excluded.bands, quote = excluded.quote, read_at = now();
    v_pages := v_pages + 1;
    -- the same page and course gates as the course-page reader (s842)
    select c.id, c.provider_id, c.lifecycle_status, c.canonical_title t, g2.status gs, g2.read_status grs, g2.evidence_id gev, g2.identity_basis ib, g2.basis gb, g2.url,
           exists (select 1 from pipeline.coverage_admission_countries a join catalogue.providers pr on pr.country_id = a.country_id where pr.id = c.provider_id and a.active) adm
      into g from catalogue.courses c left join pipeline.coverage_course_pages g2 on g2.course_id = c.id where c.id = v_course;
    v_reason := case
      when g.id is null or g.lifecycle_status <> 'active' then 'course not active'
      when not g.adm then 'country has no admission rule'
      when g.gs is distinct from 'bound' or g.grs is distinct from 'read' or g.gev is distinct from v_ev then 'page is no longer the course''s bound, read page'
      when not (coalesce(g.gb, '') = 'manual' or g.ib in ('manual', 'cricos_code', 'nzqa_code', 'adapter_code') or (g.ib is not null and security.coverage_identity_allowed(g.provider_id, g.ib, 'english'))) then 'page identity not accepted for English (' || coalesce(g.ib, 'none') || ')'
      when security.page_refused_v1(v_course, g.url) then 'page refused'
      when security.layer4_entity_or_parent_blocked('course', v_course, 'operational') then 'course held by Layer 4'
      when exists (select 1 from catalogue.course_english_requirements e where e.course_id = v_course and e.status = 'active') then 'course already holds an English requirement (no overwrite)'
      when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_course and l.field in ('english', 'english_requirements', 'course_english')) then 'English set by hand (manual lock)'
      when exists (select 1 from pipeline.layer4_review_items i where i.entity_id = v_course and i.field_code = 'course_english' and i.status = 'pending') then 'English already waiting in Layer 4'
      when cardinality(v_bands) = 0 then 'course page names no English band'
      end;
    if v_reason is not null then
      update pipeline.elr_band_pages b set result = 'held: ' || v_reason where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
      v_held := v_held + 1; continue;
    end if;
    -- the named band's values: current definitions of this university, one value per test across its pages
    v_defs := null;
    if cardinality(v_bands) = 1 then
      select case when bool_and(x.nv = 1) then jsonb_agg(jsonb_build_object('test_code', x.test_code, 'overall_score', x.overall, 'component_scores', x.comps, 'quote', x.q) order by x.test_code) end
        into v_defs
        from (select d.test_code, count(distinct (d.overall_score, d.component_scores)) nv, min(d.overall_score) overall, (array_agg(d.component_scores order by d.read_at desc))[1] comps,
                     (array_agg(d.quote order by d.read_at desc))[1] q
                from pipeline.elr_band_defs d where d.provider_id = g.provider_id and d.current and d.band = v_bands[1] group by d.test_code) x;
    end if;
    v_disc := case when g.t ~* '\mnurs' then 'nursing' when g.t ~* '\mmidwi' then 'midwifery' when g.t ~* '\m(medicine|medical|mbbs)\M' then 'medicine'
                   when g.t ~* '\m(allied health|physiotherap\w*|occupational therap\w*|speech patholog\w*|pharmac\w*|dentist\w*|dental|optometr\w*|podiatr\w*|paramedic\w*|radiograph\w*|dietetic\w*|psycholog\w*)' then 'allied health'
                   when g.t ~* '\m(teach\w*|education)\M' then 'education' when g.t ~* '\m(laws?|juris doctor|legal practice)\M' then 'law' when g.t ~* '\msocial work' then 'social work' end;
    v_review := case
      when cardinality(v_bands) > 1 then 'The course page names more than one English band (' || array_to_string(v_bands, ', ') || '); choose the one for this course.'
      when not exists (select 1 from pipeline.elr_band_defs d where d.provider_id = g.provider_id and d.current and d.band = v_bands[1]) then null
      when v_defs is null then 'The university''s central pages give different values for English ' || v_bands[1] || '; choose the one for this course.'
      when v_disc is not null then 'Regulated discipline (' || v_disc || '): the course page names English ' || v_bands[1] || '; check the band''s values against the course''s own registration requirement before use.'
      when (select count(*) from pipeline.coverage_course_pages s where s.evidence_id = v_ev and s.status = 'bound') > 1 then 'The course page is shared by several courses; check that this English band applies to this course.'
      when abs(hashtext(v_course::text || v_x)) % 100 < v_audit then 'Audit sample: check the English band read from the course page and its values before they are used.'
      end;
    if v_review is null and not exists (select 1 from pipeline.elr_band_defs d where d.provider_id = g.provider_id and d.current and d.band = v_bands[1]) then
      update pipeline.elr_band_pages b set result = 'held: the band is not defined on the university''s central page' where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
      v_held := v_held + 1; continue;
    end if;
    if v_review is not null then
      insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)
      values ('course', v_course, 'course_english', v_ev, '{}'::jsonb,
              jsonb_build_object('english_requirements', coalesce(v_defs, '[]'::jsonb), 'bands_named', to_jsonb(v_bands), 'course_page_says', v_quote, 'source', v_x),
              jsonb_build_object('source', 'elr_band', 'extractor', v_x, 'page', g.url, 'identity_basis', g.ib, 'run', p_run),
              v_review, 'CF-CHG-20260915-247');
      update pipeline.elr_band_pages b set result = 'review' where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
      v_review_n := v_review_n + 1; continue;
    end if;
    if not v_promote then
      update pipeline.elr_band_pages b set result = 'held: promotion off (elr_det.promote_on)' where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
      v_held := v_held + 1; continue;
    end if;
    -- promote: insert only (no overwrite); the manual lock trigger still has the last word
    v_wrote := 0;
    for d in select x->>'test_code' code, x from jsonb_array_elements(v_defs) x loop
      insert into catalogue.course_english_requirements (course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                         source_requirement_key, status, last_verified_at)
      select v_course, et.id, (d.x->>'overall_score')::numeric, coalesce(d.x->'component_scores', '{}'::jsonb),
             'The course page names English ' || v_bands[1] || ' (' || v_x || '): ' || left(v_quote, 160) || ' | The university''s central English page gives ' || v_bands[1] || ': ' || left(d.x->>'quote', 200),
             e.source_id, v_ev, 1, 'elr-band:' || replace(v_bands[1], ' ', '-') || ':' || lower(d.code), 'active', now()
        from ref.english_tests et, pipeline.evidence_artifacts e where et.code = d.code and e.id = v_ev
      on conflict (course_id, english_test_id) do nothing;
      get diagnostics v_n = row_count; v_wrote := v_wrote + v_n;
    end loop;
    update pipeline.elr_band_pages b set result = case when v_wrote > 0 then 'promoted ' || v_wrote else 'held: nothing written (a row or a lock holds it)' end
     where b.course_id = v_course and b.evidence_id = v_ev and b.extractor = v_x;
    if v_wrote > 0 then v_promoted := v_promoted + 1; v_rows := v_rows + v_wrote; v_done := v_done || v_course; else v_held := v_held + 1; end if;
  end loop;
  if cardinality(v_done) > 0 then
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock for search.course_documents (W27)
      perform search.refresh_course_enrichment_scoped_v1(v_done, true); v_search := 'refreshed';
    else v_search := 'deferred'; end if;
  end if;
  return jsonb_build_object('pages', v_pages, 'promoted_courses', v_promoted, 'rows_written', v_rows, 'review', v_review_n, 'held', v_held, 'failed', v_failed, 'search', v_search, 'extractor', v_x);
end $f$;
comment on function security.elr_band_record_v1(jsonb, text) is 'CF-247 s906: the one writer of English band matching. Records each course page''s named bands (pipeline.elr_band_pages); writes the values its university''s central page gives that band into catalogue.course_english_requirements (insert only, source key elr-band:<band>:<test>) only when the page names exactly one defined band, the course passes the s842 gates (identity, refused page, Layer 4, no overwrite, manual locks) and is not a regulated discipline, a shared page or the audit sample; those go to Layer 4 (course_english). An undefined band is held.';
revoke all on function security.elr_band_record_v1(jsonb, text) from public, anon, authenticated;

-- (s907) the next queued pages of the one-off fetch, only while their on-demand request is open
create or replace function security.elr_central_fetch_claim_v1(p_limit integer) returns table (fact_source_id uuid, provider_id uuid, url text, country text)
language sql stable security definer set search_path to ''
as $f$
  select f.fact_source_id, f.provider_id, f.url, null::text
    from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id and r.state = 'open' and r.expires_at > now()
   where f.status = 'queued'
   order by f.queued_at, f.fact_source_id limit greatest(least(p_limit, 12), 0)
$f$;
comment on function security.elr_central_fetch_claim_v1(integer) is 'CF-247 s907: the next queued pages of the one-off central English fetch, only while the on-demand request they were queued under is open. Read only.';
revoke all on function security.elr_central_fetch_claim_v1(integer) from public, anon, authenticated;

-- (s909) one read of the lane's progress for the record and the probes
create or replace function security.elr_band_status_v1() returns jsonb
language sql stable security definer set search_path to ''
as $f$
  select jsonb_build_object(
    'band_defs', jsonb_build_object('universities', (select count(distinct provider_id) from pipeline.elr_band_defs where current), 'bands', (select count(distinct (provider_id, band)) from pipeline.elr_band_defs where current), 'values', (select count(*) from pipeline.elr_band_defs where current)),
    'band_pages', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select outcome || coalesce(':' || split_part(result, ':', 1), '') k, count(*) n from pipeline.elr_band_pages group by 1) x),
    'band_rows', (select count(*) from catalogue.course_english_requirements where source_requirement_key like 'elr-band:%'),
    'fetch', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from pipeline.elr_central_fetches group by 1) x),
    'fetch_requests', (select jsonb_build_object('n', count(*), 'open', count(*) filter (where status = 'sent')) from pipeline.elr_central_fetch_requests),
    'on_demand', (select jsonb_agg(jsonb_build_object('id', s.on_demand_id, 'state', r.state, 'expires_at', r.expires_at, 'estimate', s.estimate, 'closed_at', s.closed_at, 'report', s.report))
                    from pipeline.elr_central_fetch_state s left join pipeline.on_demand_requests r on r.id = s.on_demand_id))
$f$;
comment on function security.elr_band_status_v1() is 'CF-247 s909: English band matching and the one-off central English fetch at a glance (definitions, course pages by outcome, rows written, fetch by status, the on-demand request and its report). Read only.';
revoke all on function security.elr_band_status_v1() from public, anon, authenticated;

-- (s904) the central claim: pages not yet read by elr-central-v1.2
create or replace function security.elr_central_claim_v1(p_providers integer) returns table (fact_source_id uuid, provider_id uuid, evidence_id uuid, storage_path text)
language sql stable security definer set search_path to ''
as $f$
  with pv as (
    select f.provider_id from pipeline.provider_fact_sources f
      join catalogue.providers p on p.id = f.provider_id
      join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where f.kind = 'english_policy' and f.evidence_id is not null and f.status <> 'rejected' and f.decision is distinct from 'rejected'
       and not exists (select 1 from pipeline.elr_central_reads r where r.fact_source_id = f.id and r.extractor = 'elr-central-v1.2' and r.outcome <> 'lost')
       and not exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = f.provider_id and o.kind = 'english_policy' and o.parser = 'elr-central-v1.0' and o.status in ('proposed', 'approved'))
       and exists (select 1 from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active'
                    and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active'))
     group by f.provider_id order by f.provider_id limit greatest(p_providers, 0))
  select f.id, f.provider_id, f.evidence_id, e.storage_path
    from pv join pipeline.provider_fact_sources f on f.provider_id = pv.provider_id and f.kind = 'english_policy' and f.evidence_id is not null
              and f.status <> 'rejected' and f.decision is distinct from 'rejected'
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   order by f.provider_id, f.rank
$f$;
comment on function security.elr_central_claim_v1(integer) is 'CF-247 s885, s896, s904 (pages are read again by elr-central-v1.2): the stored central English pages of the next universities that still have courses with no English requirement and no elr-central policy. Reads only.';
revoke all on function security.elr_central_claim_v1(integer) from public, anon, authenticated;

-- (s904) the central writer: reads by v1.2; a page with band values says so
create or replace function security.elr_central_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-central-v1.2';      -- s904: the reader version of the page reads
  v_route constant text := 'elr-central-v1.0';  -- s896: the governed route's parser name, unchanged (policy-auto-approve and the apply runs know it)
  pv record; pg jsonb; b record; t text; v_tiers text[] := array['undergraduate', 'postgraduate', 'research', 'vet'];
  v_merged jsonb; v_conf jsonb; v_disc jsonb; v_defaults jsonb; v_base_tiers text[]; v_best jsonb; v_best_n int; v_n int; v_id uuid; v_reason text;
  v_read int := 0; v_failed int := 0; v_proposed int := 0; v_none int := 0; v_skipped int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  -- every page first: read or failed
  for pg in select * from jsonb_array_elements(p_pages) loop
    continue when nullif(pg->>'fact_source_id', '') is null;
    insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, sha256, reading, result, read_at)
    values ((pg->>'fact_source_id')::uuid, v_x, (pg->>'provider_id')::uuid, nullif(pg->>'evidence_id', '')::uuid, case when pg ? 'error' then 'failed' else 'read' end,
            pg->>'sha256', pg->'reading', case when pg ? 'error' then left(pg->>'error', 160) end, now())
    on conflict (fact_source_id, extractor) do update set outcome = excluded.outcome, sha256 = excluded.sha256, reading = excluded.reading, result = excluded.result, read_at = now();
    if pg ? 'error' then v_failed := v_failed + 1; else v_read := v_read + 1; end if;
  end loop;
  -- then one decision a university
  for pv in select distinct (e->>'provider_id')::uuid provider_id from jsonb_array_elements(p_pages) e where nullif(e->>'provider_id', '') is not null and not (e ? 'error') loop
    v_reason := null;
    if exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.parser = v_route and o.status in ('proposed', 'approved')) then
      v_reason := 'the university already has an elr-central reading';
    end if;
    -- the approved policy in force for the university (not an elr-central one): its tiers are never replaced
    select o.* into b from pipeline.provider_policy_proposals o
     where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.parser is distinct from v_route order by o.decided_at desc nulls last limit 1;
    v_base_tiers := coalesce((select array_agg(k) from jsonb_each(coalesce(b.proposal->'defaults', '{}'::jsonb)) d(k, v) where jsonb_typeof(d.v) = 'array' and jsonb_array_length(d.v) > 0), '{}');
    -- merge the university's pages: one value per tier and test, else a conflict
    v_defaults := '{}'::jsonb; v_conf := '[]'::jsonb;
    for t in select unnest(v_tiers) loop
      with q as (
        select r->>'test_code' code, r from jsonb_array_elements(p_pages) e, jsonb_array_elements(case when jsonb_typeof(e->'reading'->'defaults'->t) = 'array' then e->'reading'->'defaults'->t else '[]'::jsonb end) r
         where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error')),
      g as (select code, count(distinct (r->>'overall_score')::numeric) nv, (array_agg(r))[1] r1 from q group by code)
      select coalesce(jsonb_agg(g.r1) filter (where g.nv = 1), '[]'::jsonb), coalesce(jsonb_agg(jsonb_build_object('tier', t, 'test_code', g.code)) filter (where g.nv > 1), '[]'::jsonb)
        into v_merged, v_disc from g;
      v_conf := v_conf || v_disc
             || coalesce((select jsonb_agg(c) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'conflicts', '[]'::jsonb)) c
                          where (e->>'provider_id')::uuid = pv.provider_id and c->>'tier' = t), '[]'::jsonb);
      if jsonb_array_length(v_merged) > 0 and not (t = any (v_base_tiers)) then v_defaults := v_defaults || jsonb_build_object(t, v_merged); end if;
    end loop;
    v_disc := coalesce((select jsonb_agg(distinct d) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'discipline_higher', '[]'::jsonb)) d
                         where (e->>'provider_id')::uuid = pv.provider_id), '[]'::jsonb);
    if v_reason is null and v_defaults = '{}'::jsonb then
      v_reason := case when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and (e->'reading'->>'readings')::int > 0)
                       then 'no tier the approved policy lacks (or every value conflicts)'
                       -- s896: values on the page but none tied to a study level (for example a page that sorts courses into English bands): held, never spread across levels
                       -- s905: the values a page gives each named English band are kept as band definitions and used only for a course whose own page names that band
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and jsonb_typeof(e->'reading'->'band_defs') = 'object'
                                      and e->'reading'->'band_defs' <> '{}'::jsonb)
                       then 'values by English band: used only for courses whose page names the band (elr-band-v1.0)'
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and (e->'reading'->>'bands')::boolean)
                       then 'values without a study level: the page sorts courses into English bands or levels'
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and coalesce((e->'reading'->>'values_found')::int, 0) > 0)
                       then 'values without a study level'
                       else 'the page states no English test requirement by tier' end;
    end if;
    if v_reason is not null then
      update pipeline.elr_central_reads r set result = v_reason where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
      if v_reason like 'the university already%' then v_skipped := v_skipped + 1; else v_none := v_none + 1; end if;
      continue;
    end if;
    -- the page that gives the most of these tiers is the proposal's document
    v_best := null; v_best_n := -1;
    for pg in select e from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error') loop
      select count(*) into v_n from jsonb_object_keys(v_defaults) k where jsonb_typeof(pg->'reading'->'defaults'->k) = 'array';
      if v_n > v_best_n then v_best := pg; v_best_n := v_n; end if;
    end loop;
    insert into pipeline.provider_policy_proposals (provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
    select pv.provider_id, f.id, 'english_policy', v_route, v_best->>'sha256', f.evidence_id, f.url, 'level_default',
           jsonb_build_object('parser', v_route, 'reader', v_x, 'style', 'level_default', 'defaults', v_defaults,
                              'named', coalesce(b.proposal->'named', '[]'::jsonb), 'exceptions', coalesce(b.proposal->'exceptions', '[]'::jsonb),
                              'discipline_higher', v_disc, 'conflicts', v_conf, 'caveats', jsonb_build_array('read_deterministically'), 'signals', '[]'::jsonb,
                              'supplements', b.id, 'run', p_run,
                              'source_note', 'Read deterministically from the stored central English page (no AI, no Firecrawl); only the study-level tiers the approved policy does not already give'),
           'proposed'
      from pipeline.provider_fact_sources f where f.id = (v_best->>'fact_source_id')::uuid
    returning id into v_id;
    update pipeline.elr_central_reads r set proposal_id = v_id, result = 'proposed: ' || (select string_agg(k, ', ') from jsonb_object_keys(v_defaults) k)
     where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
    v_proposed := v_proposed + 1;
  end loop;
  return jsonb_build_object('pages_read', v_read, 'pages_failed', v_failed, 'proposed', v_proposed, 'no_new_tier', v_none, 'skipped', v_skipped, 'extractor', v_x);
end $f$;
comment on function security.elr_central_record_v1(jsonb, text) is 'CF-247 s885, s896, s904 (reads by elr-central-v1.2; values without a study level are held with their reason; band values are kept by s905): records the central English pages the deterministic central reader read, then makes at most one english_policy proposal a university (parser elr-central-v1.0, status proposed) holding only the study-level tiers its approved policy does not give, with that policy''s named courses and exceptions, the conflicts and the regulated disciplines the page gives higher bands for. Approval is the governed route (security.policy_auto_approve_v1 or a person).';
revoke all on function security.elr_central_record_v1(jsonb, text) from public, anon, authenticated;

-- (s908) the sweep: band definitions, band course pages and the one-off fetch
create or replace function security.elr_det_sweep_tick_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_pages int := 0;
  v_open int; v_room int; v_batch int; v_per int; v_cur uuid; v_all jsonb; v_items jsonb; v_id bigint; v_claimed int; v_last uuid; i int;
  v_t0 timestamptz := clock_timestamp(); v_c jsonb := '{}'::jsonb; v_bid bigint; v_bpages jsonb; v_fid bigint; v_fitems jsonb; v_od uuid; v_bd int := 0; v_cid bigint; v_cpages jsonb; v_capp int := 0; v_cw int := 0; v_cl4 int := 0; ap record; v_ap jsonb; v_l4 int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:elr_det_sweep')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1. answered calls
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_det_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-det-v1.0' then
      v_rec := security.elr_det_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_det_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_det_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_det_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 1b. answered central-page calls (s886)
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_central_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' in ('elr-central-v1.0', 'elr-central-v1.1', 'elr-central-v1.2') then
      v_rec := security.elr_central_record_v1(v_res->'pages', 'request:' || q.id);
      v_bd := v_bd + security.elr_band_defs_record_v1(v_res->'pages', v_res->>'extractor');  -- s905: the values each named band states
      update pipeline.elr_central_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_central_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_central_reads set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 1c. answered band calls (s906) and fetch calls (s907)
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_band_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-band-v1.0' then
      v_rec := security.elr_band_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_band_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_band_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_band_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_central_fetch_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-central-fetch-v1.0' then
      update pipeline.elr_central_fetches f set status = case x->>'outcome' when 'read' then 'stored' when 'refused' then 'refused' else 'failed' end,
             done_at = now(), result = x - 'id'
        from jsonb_array_elements(coalesce(v_res->'fetched', '[]'::jsonb)) x where f.fact_source_id = (x->>'id')::uuid and f.request_id = q.id;
      update pipeline.elr_central_fetch_requests set status = 'done', finished_at = now(), result = jsonb_build_object('fetched', jsonb_array_length(coalesce(v_res->'fetched', '[]'::jsonb)), 'ms', v_res->'ms') where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_central_fetch_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    -- a page the answer does not name is not fetched again (it may have been charged): it is marked lost for a person to look at
    update pipeline.elr_central_fetches set status = 'lost', done_at = now() where request_id = q.id and status = 'sent';
  end loop;
  -- 2. calls with no answer in time are given up; their pages go back to the queue
  with l as (update pipeline.elr_det_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_det_pages d set outcome = 'lost' from l where d.request_id = l.id and d.outcome = 'sent';
  get diagnostics v_lost = row_count;
  with l as (update pipeline.elr_central_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_central_reads c set outcome = 'lost' from l where c.request_id = l.id and c.outcome = 'sent';
  with l as (update pipeline.elr_band_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_band_pages b set outcome = 'lost' from l where b.request_id = l.id and b.outcome = 'sent';
  -- a fetch call with no answer is never sent again by itself (the pages may have been charged)
  with l as (update pipeline.elr_central_fetch_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_central_fetches f set status = 'lost', done_at = now() from l where f.request_id = l.id and f.status = 'sent';
  -- 3. the next batch
  if security.pipeline_num_v1('elr_det.sweep_on', 1) < 1 then
    return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'sent', 0, 'sweep', 'off', 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  end if;
  select count(*) into v_open from pipeline.elr_det_requests where status = 'sent';
  v_per := greatest(5, least(40, security.pipeline_num_v1('elr_det.pages_per_call', 25)::int));
  v_room := security.pipeline_num_v1('elr_det.in_flight_max', 8)::int - v_open;
  v_batch := least(security.pipeline_num_v1('batch.elr_det_sweep', 200)::int, greatest(v_room, 0) * v_per);
  if v_batch > 0 then
    select s.cursor_id into v_cur from pipeline.elr_det_state s where s.id = 1 for update;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path) order by c.course_id), '[]'::jsonb)
      into v_all from security.elr_det_claim_v1(v_cur, v_batch) c;
    v_claimed := jsonb_array_length(v_all);
    v_last := case when v_claimed > 0 then (v_all->(v_claimed - 1)->>'course_id')::uuid end;
    i := 0;
    while i * v_per < v_claimed loop
      select jsonb_agg(e.v order by e.n) into v_items from jsonb_array_elements(v_all) with ordinality e(v, n) where e.n > i * v_per and e.n <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_det_read', 'items', v_items));
      insert into pipeline.elr_det_requests (id, pages) values (v_id, jsonb_array_length(v_items));
      insert into pipeline.elr_det_pages as d (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-det-v1.0', 'sent', v_id, now() from jsonb_array_elements(v_items) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where d.outcome = 'lost';
      v_sent := v_sent + 1; v_pages := v_pages + jsonb_array_length(v_items); i := i + 1;
    end loop;
    update pipeline.elr_det_state set cursor_id = case when v_claimed < v_batch then '00000000-0000-0000-0000-000000000000'::uuid else v_last end,
           passes = passes + case when v_claimed < v_batch then 1 else 0 end, updated_at = now() where id = 1;
  end if;
  -- 4. central English pages (s886): one call a run for the next universities, only when none is waiting
  if security.pipeline_num_v1('elr_central.on', 1) >= 1 then
    if not exists (select 1 from pipeline.elr_central_requests where status = 'sent') then
      select coalesce(jsonb_agg(jsonb_build_object('fact_source_id', c.fact_source_id, 'provider_id', c.provider_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path)), '[]'::jsonb)
        into v_cpages from security.elr_central_claim_v1(security.pipeline_num_v1('batch.elr_central', 6)::int) c;
      if jsonb_array_length(v_cpages) > 0 then
        v_cid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_central_read', 'items', v_cpages));
        insert into pipeline.elr_central_requests (id, pages) values (v_cid, jsonb_array_length(v_cpages));
        insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, request_id, sent_at)
        select (e->>'fact_source_id')::uuid, 'elr-central-v1.2', (e->>'provider_id')::uuid, (e->>'evidence_id')::uuid, 'sent', v_cid, now() from jsonb_array_elements(v_cpages) e
        on conflict (fact_source_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where r.outcome = 'lost';
        v_c := v_c || jsonb_build_object('central_pages_sent', jsonb_array_length(v_cpages));
      end if;
    end if;
    -- 5. apply approved central policies, a few a run; send their regulated-discipline holds to Layer 4
    for ap in select o.id, o.evidence_id, o.url, o.proposal from pipeline.provider_policy_proposals o left join pipeline.elr_central_applies a on a.proposal_id = o.id
               where o.kind = 'english_policy' and o.status = 'approved' and o.parser = 'elr-central-v1.0'
                 and (a.applied_at is null or a.applied_at < now() - make_interval(hours => security.pipeline_num_v1('elr_central.reapply_hours', 6)::int))
               order by a.applied_at nulls first, o.decided_at limit security.pipeline_num_v1('elr_central.apply_per_run', 2)::int loop
      begin
        v_ap := security.provider_english_apply_v1(ap.id);
        with h as (
          select pl.course_id, substring(pl.reason from '^regulated discipline \(([^)]+)\)') disc
            from security.provider_english_plan_v1(ap.id) pl
           where pl.outcome = 'held' and pl.reason like 'regulated discipline%'
             and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = pl.course_id and r.status = 'active')
             and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = pl.course_id and i.field_code = 'course_english' and i.status = 'pending')
           limit security.pipeline_num_v1('elr_central.l4_per_run', 50)::int)
        insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)
        select 'course', h.course_id, 'course_english', ap.evidence_id, '{}'::jsonb,
               jsonb_build_object('english_requirements', '[]'::jsonb, 'source', 'elr-central-v1.0', 'policy_id', ap.id,
                                  'central_page_says', (select coalesce(jsonb_agg(d), '[]'::jsonb) from jsonb_array_elements(coalesce(ap.proposal->'discipline_higher', '[]'::jsonb)) d where d->>'discipline' = h.disc)),
               jsonb_build_object('source', 'elr_central', 'policy', ap.id, 'page', ap.url, 'discipline', h.disc),
               'Regulated discipline (' || h.disc || '): the university''s central English page gives higher English bands for these courses, so the general default is not used. Set this course''s requirement from its course or faculty page.',
               'CF-CHG-20260915-247'
          from h;
        get diagnostics v_l4 = row_count;
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, written, layer4)
        values (ap.id, now(), 1, coalesce((v_ap->>'written')::int, 0), v_l4)
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, written = a.written + excluded.written, layer4 = a.layer4 + excluded.layer4, last_error = null;
        v_capp := v_capp + 1; v_cw := v_cw + coalesce((v_ap->>'written')::int, 0); v_cl4 := v_cl4 + v_l4;
      exception when others then
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, last_error) values (ap.id, now(), 1, left(sqlerrm, 200))
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, last_error = excluded.last_error;
      end;
    end loop;
    v_c := v_c || jsonb_build_object('central_applied', v_capp, 'central_written', v_cw, 'central_layer4', v_cl4, 'band_defs', v_bd);
  end if;
  -- 6. course pages of universities whose central page defines English bands (s906): one call a run, only when none is waiting
  if security.pipeline_num_v1('elr_band.on', 1) >= 1 and not exists (select 1 from pipeline.elr_band_requests where status = 'sent') then
    select coalesce(jsonb_agg(jsonb_build_object('course_id', b.course_id, 'evidence_id', b.evidence_id, 'storage_path', b.storage_path, 'bands', to_jsonb(b.bands))), '[]'::jsonb)
      into v_bpages from security.elr_band_claim_v1(security.pipeline_num_v1('batch.elr_band', 40)::int) b;
    if jsonb_array_length(v_bpages) > 0 then
      v_bid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_band_read', 'items', v_bpages));
      insert into pipeline.elr_band_requests (id, pages) values (v_bid, jsonb_array_length(v_bpages));
      insert into pipeline.elr_band_pages as p (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-band-v1.0', 'sent', v_bid, now() from jsonb_array_elements(v_bpages) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where p.outcome = 'lost';
      v_c := v_c || jsonb_build_object('band_pages_sent', jsonb_array_length(v_bpages));
    end if;
  end if;
  -- 7. the one-off fetch of known, unstored central English pages (s907): one call a run while its on-demand request is open; closed when the queue is empty
  if security.pipeline_num_v1('elr_central_fetch.on', 1) >= 1 and not exists (select 1 from pipeline.elr_central_fetch_requests where status = 'sent') then
    select coalesce(jsonb_agg(jsonb_build_object('id', f.fact_source_id, 'provider_id', f.provider_id, 'url', f.url, 'country', f.country)), '[]'::jsonb)
      into v_fitems from security.elr_central_fetch_claim_v1(security.pipeline_num_v1('batch.elr_central_fetch', 10)::int) f;
    if jsonb_array_length(v_fitems) > 0 then
      v_fid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_central_fetch', 'items', v_fitems));
      insert into pipeline.elr_central_fetch_requests (id, pages) values (v_fid, jsonb_array_length(v_fitems));
      update pipeline.elr_central_fetches f set status = 'sent', request_id = v_fid, sent_at = now() from jsonb_array_elements(v_fitems) e where f.fact_source_id = (e->>'id')::uuid and f.status = 'queued';
      v_c := v_c || jsonb_build_object('central_fetch_sent', jsonb_array_length(v_fitems));
    else
      -- nothing left to send for an open request: close it and keep its report (actual use and the credit left)
      for v_od in select distinct f.on_demand_id from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id
                   where r.state = 'open' and not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status in ('queued', 'sent')) loop
        insert into pipeline.elr_central_fetch_state as s (on_demand_id, closed_at, report) values (v_od, now(), security.on_demand_close_v1(v_od))
        on conflict (on_demand_id) do update set closed_at = now(), report = excluded.report;
        v_c := v_c || jsonb_build_object('central_fetch_closed', v_od);
      end loop;
    end if;
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'calls_sent', v_sent, 'pages_sent', v_pages, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000)) || v_c;
end $f$;
comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842, s886, s896, s904 to s907: one run of the job elr-det-sweep. Also keeps the values central pages give each named English band (s905), reads the band named on course pages of those universities (worker mode elr_band_read, security.elr_band_record_v1), and runs the one-off bounded fetch of known central English pages under its on-demand request (worker mode elr_central_fetch, s907). Also reads stored central English pages (security.elr_central_claim_v1, worker mode elr_central_read, security.elr_central_record_v1), applies approved elr-central policies a few a run and sends their regulated-discipline holds to Layer 4. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';
revoke all on function security.elr_det_sweep_tick_v1() from public, anon, authenticated;

-- (s907) the queue and its on-demand request
insert into pipeline.elr_central_fetches (fact_source_id, provider_id, url)
select x.id, x.provider_id, x.url from (
  select f.id, f.provider_id, f.url, f.rank,
         (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active'
             and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')) gap
    from pipeline.provider_fact_sources f
    join catalogue.providers p on p.id = f.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
   where f.kind = 'english_policy' and f.evidence_id is null and f.status in ('found', 'failed') and f.decision is distinct from 'rejected'
     and coalesce(f.http_status, 0) not in (401, 403, 404, 410, 451)
     and coalesce(f.parse_summary->>'error', '') in ('', 'budget', 'time budget', 'target_list_refused', 'credits_reserve', 'credits_refused')
     -- an address that shows the page is not an admission page (test preparation, a class, a blog or news post, a lesson, research) is not fetched
     and f.url !~* '(ielts[-_ ]?(mock|exam|prep|class|writing|vs|eap)|test[-_]prep|preparatorio|exam[-_]preparation|/blogs?/|/news|/lessons?/|/20[0-9]{2}/[0-9]{2}/|last[-_]week|book[-_]english[-_]test|intensive[-_]english|eap[-_]ielts|foundation[-_]il|study[-_]english|common[-_]mistakes|how[-_]to[-_]pass|case[-_]stud|english[-_]language[-_]providers|/marcs/)'
     -- and an address that names a requirement, proficiency, admission, entry or policy page
     and f.url ~* '(requirement|proficien|admission|entry|polic|english[-_]language[-_]test)'
     and not exists (select 1 from pipeline.provider_fact_sources s where s.provider_id = f.provider_id and s.kind = 'english_policy' and s.evidence_id is not null)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)) x
 where x.gap > 0
 order by x.gap desc, x.provider_id, x.rank
 limit security.pipeline_num_v1('elr_central_fetch.max', 100)::int
on conflict do nothing;

do $od$
declare v_ids uuid[]; v_n int; v_id uuid; v_est jsonb; v_reason text := 'CF-247 s907 (Platform Admin 21 Nov 2026 09:00): one-off fetch of known, unstored central English pages for the English requirement sweep';
begin
  select array_agg(distinct provider_id), count(*) into v_ids, v_n from pipeline.elr_central_fetches where status = 'queued' and on_demand_id is null;
  if coalesce(v_n, 0) = 0 then return; end if;
  v_est := jsonb_build_object('pages', v_n, 'firecrawl_credits', v_n, 'firecrawl_credits_most', ceil(v_n * 1.5), 'basis', 'one credit a page; a PDF or long page can cost more');
  perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl']);
  select r.id into v_id from pipeline.on_demand_requests r where r.requested_via = 'claude_session' and r.reason = v_reason and r.state = 'open' order by r.opened_at desc limit 1;
  if v_id is null then raise exception 's907: the on-demand request was not opened'; end if;
  perform security.on_demand_scope_v1(v_id, array['central']);
  update pipeline.elr_central_fetches set on_demand_id = v_id where status = 'queued' and on_demand_id is null;
  insert into pipeline.elr_central_fetch_state (on_demand_id, estimate) values (v_id, v_est || jsonb_build_object('credit_left_before', security.on_demand_credit_left_v1()));
  raise notice 's907: % pages of % universities queued under on-demand request %; estimate %; credit left %', v_n, cardinality(v_ids), v_id, v_est, security.on_demand_credit_left_v1();
end $od$;

update pipeline.automation_catalogue
   set description = description || ' s904 to s907 (21 Nov 2026): reads central pages with elr-central-v1.2, keeps each named English band''s values, matches a course to the band its own page names (elr-band-v1.0), and runs the one-off bounded fetch of known central English pages under its on-demand request.'
 where jobname = 'elr-det-sweep' and description not like '%elr-band-v1.0%';

do $c$
declare v_api jsonb; t0 timestamptz; v_ms numeric; v_cold numeric; v_n int; v_q int;
begin
  -- the first call warms the cache (the job calls it every five minutes); the second is the one timed
  t0 := clock_timestamp(); perform count(*) from security.elr_central_claim_v1(15); v_cold := extract(epoch from clock_timestamp() - t0) * 1000;
  t0 := clock_timestamp(); select count(*) into v_n from security.elr_central_claim_v1(15); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_n = 0 then raise exception 'post-check: the v1.2 claim found no page'; end if;
  if v_ms > 300 then raise exception 'post-check: the central claim took % ms (limit 300 ms)', round(v_ms); end if;
  t0 := clock_timestamp(); perform count(*) from security.elr_band_claim_v1(40); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 300 then raise exception 'post-check: the band claim took % ms (limit 300 ms)', round(v_ms); end if;
  t0 := clock_timestamp(); select count(*) into v_q from security.elr_central_fetch_claim_v1(10); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 300 then raise exception 'post-check: the fetch claim took % ms (limit 300 ms)', round(v_ms); end if;
  if (select count(*) from pipeline.elr_central_fetches) > 100 then raise exception 'post-check: more than 100 pages queued'; end if;
  if v_q = 0 and exists (select 1 from pipeline.elr_central_fetches where status = 'queued') then raise exception 'post-check: queued pages have no open on-demand request'; end if;
  if (security.elr_band_record_v1('[]'::jsonb, 'post-check')->>'pages')::int <> 0 then raise exception 'post-check: the band writer answered an empty call wrongly'; end if;
  if security.elr_band_defs_record_v1('[]'::jsonb, 'elr-central-v1.2') <> 0 then raise exception 'post-check: the band definitions writer answered an empty call wrongly'; end if;
  if (select count(*) from cron.job where active) <> (select n from s904_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s904_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's904-s909: central claim % pages (% ms cold, % ms warm); fetch claim % pages; status %', v_n, round(v_cold), round(v_ms), v_q, security.elr_band_status_v1();
end $c$;
