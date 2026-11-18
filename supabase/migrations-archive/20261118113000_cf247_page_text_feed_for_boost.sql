-- CF-247 S2-Build (Platform Admin 18 Nov 2026 10:12: "Ensure the coverage-sweep page-fetch lanes are actively fetching and storing course pages for
-- the ~21,600 active courses that still lack course_description / study_load / intakes ... so S2 - BOOST has a continuous stream of stored pages").
-- Measured (read only, 18 Nov 2026 10:15 AEDT): of 32,259 active AU, NZ and CA courses with no study load, 31,130 have no stored course-page TEXT
-- (evidence provider_course_page_text, the only kind public.svc_boost_extract_claim / security.boost_extract_claim_v1 reads), yet 20,210 of them have
-- a bound course page already read and stored as HTML (evidence source_snapshot, written by mode read). The text kind was written only by the tuition
-- handoff (2,505 files, none in 10 days), so Boost drained its 2,144 claimable pages and had nothing new. The read lane (coverage-read, coverage-read-2)
-- is idle-paused by flag-recheck because no bound page is due (its re-read cycle has 20,840 bound pages due in more than 30 days): fetching again is
-- not what is missing, and would spend Firecrawl credit on pages already held.
-- Change: a deterministic text conversion of the stored copies, no Firecrawl and no AI:
--   job page-text (catalogued, every 2 minutes) calls coverage-sweep mode page_text (worker v1.0.15), which takes the next stored HTML copies from
--   public.svc_page_text_next_v1 (bound page, read, stored; active course still lacking a study load or a description; provider shown; countries and
--   order by the Boost priority matrix, security.boost_country_category_matrix_v1, intakes and course basics; then course priority), turns each into
--   plain text with the readers' own htmlToText, stores it at coverage-text/<course>/<hash>.txt and records it with public.svc_page_text_record_v1
--   as evidence provider_course_page_text (derived_from_evidence_id = the copy), which Boost's existing claim then reads. Each copy is converted once
--   (pipeline.page_text_conversions); a text shorter than page_text.min_chars is recorded too_short and not offered again; a failure is offered again
--   after a day. Sizes are settings (batch.page_text, page_text.min_chars). The job is idle-paused by flag-recheck when nothing is left, like every
--   coverage-sweep job. No catalogue value is written here: Boost's own claim, verification and admission rules are unchanged. G3 untouched.
-- Replaces: nothing (the tuition handoff keeps its own text files and its Layer 3 hand-off).
-- Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.page_text', 'Page text for Boost: copies a run',
  'How many stored course-page copies one run of the page-text job turns into plain text for Boost (no Firecrawl, no AI).',
  'number', to_jsonb(40), 1, 200, 'pages', 1240, 'S2-Build, 18 Nov 2026 (feed stored pages to Boost)', 'Batch sizes', 'job page-text (coverage-sweep mode page_text)'),
 ('pipeline', 'page_text.min_chars', 'Page text for Boost: shortest text kept',
  'A stored course page whose plain text is shorter than this is recorded as too short and is not offered to Boost.',
  'number', to_jsonb(200), 50, 5000, 'characters', 1241, 'S2-Build, 18 Nov 2026 (feed stored pages to Boost)', 'Coverage sweep', 'coverage-sweep mode page_text')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.page_text_conversions (
  source_evidence_id uuid primary key references pipeline.evidence_artifacts(id),
  course_id uuid not null references catalogue.courses(id),
  outcome text not null check (outcome in ('claimed', 'done', 'too_short', 'failed')),
  text_evidence_id uuid references pipeline.evidence_artifacts(id),
  bytes integer,
  error text,
  claimed_at timestamptz not null default now(),
  done_at timestamptz
);
comment on table pipeline.page_text_conversions is 'CF-247 S2-Build (18 Nov 2026): one row per stored course-page copy (evidence source_snapshot) the page-text job turned, or tried to turn, into the plain-text page Boost reads (evidence provider_course_page_text). claimed while a run holds it, done with the text evidence, too_short (not offered again) or failed (offered again after a day).';
create index if not exists page_text_conversions_course_idx on pipeline.page_text_conversions(course_id);
alter table pipeline.page_text_conversions enable row level security;
revoke all on pipeline.page_text_conversions from anon, authenticated;

create or replace function public.svc_page_text_next_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb; v_lim int := least(greatest(coalesce(p_limit, 1), 1), 200);  -- fixed: bound on one call; the size is the setting batch.page_text
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247:page_text_next'));
  with mx as (
    select m.country_code, max(m.weight) weight from security.boost_country_category_matrix_v1() m
     where m.enrichment_category in ('intakes_deadlines', 'course_basics') and m.weight > 0 group by 1),
  al as (select split_part(x, '=', 1) src, split_part(x, '=', 2) dst from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x),
  cand as (
    select cp.course_id, e.id evidence_id, e.storage_path, cp.url, k.iso_alpha2::text country, mx.weight, coalesce(pr.sort, 1000000) csort
      from pipeline.coverage_course_pages cp
      join pipeline.evidence_artifacts e on e.id = cp.evidence_id and e.evidence_type = 'source_snapshot' and e.storage_path is not null
      join catalogue.courses c on c.id = cp.course_id and c.lifecycle_status = 'active'
      join catalogue.providers p on p.id = c.provider_id
      join ref.countries k on k.id = p.country_id
      join mx on mx.country_code = coalesce((select al.dst from al where al.src = k.iso_alpha2::text limit 1), k.iso_alpha2::text)
      left join pipeline.course_priority pr on pr.course_id = cp.course_id
     where cp.status = 'bound' and cp.read_status = 'read'
       and (c.study_load is null or nullif(btrim(c.description), '') is null)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from pipeline.page_text_conversions x where x.source_evidence_id = e.id
                        and (x.outcome in ('done', 'too_short')
                             or (x.outcome = 'claimed' and x.claimed_at > now() - interval '10 minutes')  -- fixed: claim lease
                             or (x.outcome = 'failed' and x.claimed_at > now() - interval '1 day')))  -- fixed: retry interval for a failed copy
       and not exists (select 1 from pipeline.evidence_artifacts t where t.entity_id = cp.course_id and t.evidence_type = 'provider_course_page_text'
                        and t.metadata->>'derived_from_evidence_id' = e.id::text)
     order by mx.weight desc, csort, cp.course_id
     limit v_lim),
  ins as (
    insert into pipeline.page_text_conversions as t (source_evidence_id, course_id, outcome, claimed_at)
    select evidence_id, course_id, 'claimed', now() from cand
    on conflict (source_evidence_id) do update set outcome = 'claimed', claimed_at = now(), error = null
    returning t.source_evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path, 'url', c.url, 'country', c.country)
                  order by c.weight desc, c.csort), '[]'::jsonb)
    into v from cand c join ins i on i.source_evidence_id = c.evidence_id;
  return jsonb_build_object('items', v, 'min_chars', security.pipeline_num_v1('page_text.min_chars', 200)::int);
end $function$;
comment on function public.svc_page_text_next_v1(integer) is 'CF-247 S2-Build (18 Nov 2026): the next stored course-page copies (bound, read, source_snapshot) of active courses still lacking a study load or a description, in Boost priority-matrix order, claimed for the page-text job. Service role only.';
revoke all on function public.svc_page_text_next_v1(integer) from public, anon, authenticated;
grant execute on function public.svc_page_text_next_v1(integer) to service_role;

create or replace function public.svc_page_text_record_v1(p_source_evidence_id uuid, p_outcome text, p_storage_path text, p_content_hash text, p_bytes integer, p_error text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare x pipeline.page_text_conversions; e pipeline.evidence_artifacts; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  if p_outcome not in ('done', 'too_short', 'failed') then raise exception 'outcome is done, too_short or failed' using errcode = '22023'; end if;
  select * into x from pipeline.page_text_conversions where source_evidence_id = p_source_evidence_id for update;
  if x.source_evidence_id is null then raise exception 'copy not claimed' using errcode = '22023'; end if;
  if p_outcome = 'done' then
    if coalesce(p_storage_path, '') !~ '^coverage-text/[0-9a-f-]{36}/[0-9a-f]{32}\.txt$' or coalesce(p_content_hash, '') = '' then raise exception 'a done copy needs its text path and hash' using errcode = '22023'; end if;
    select * into e from pipeline.evidence_artifacts where id = p_source_evidence_id;
    select t.id into v_ev from pipeline.evidence_artifacts t where t.entity_id = x.course_id and t.evidence_type = 'provider_course_page_text'
       and t.metadata->>'derived_from_evidence_id' = p_source_evidence_id::text limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id, source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
      values (x.course_id, e.source_id, 'provider_course_page_text', e.source_url, p_storage_path, p_content_hash, 'text/plain',
              jsonb_build_object('derived_from_evidence_id', p_source_evidence_id, 'bytes', p_bytes, 'capture', 'coverage-sweep-page-text-v1', 'made_for', 'boost'),
              1, 'coverage:' || x.course_id)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.page_text_conversions set outcome = p_outcome, text_evidence_id = v_ev, bytes = p_bytes, error = left(p_error, 500), done_at = now()
   where source_evidence_id = p_source_evidence_id;
  return jsonb_build_object('ok', true, 'outcome', p_outcome, 'text_evidence_id', v_ev);
end $function$;
comment on function public.svc_page_text_record_v1(uuid, text, text, text, integer, text) is 'CF-247 S2-Build (18 Nov 2026): records the outcome of one page-text conversion; a done copy is kept as evidence provider_course_page_text (derived_from_evidence_id = the stored copy), which Boost reads. Service role only.';
revoke all on function public.svc_page_text_record_v1(uuid, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.svc_page_text_record_v1(uuid, text, text, text, integer, text) to service_role;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('page-text', 'Coverage sweep', 395, 'Page text for Boost',
  'Turns stored course-page copies (already fetched by the read lane) into the plain-text pages Boost reads, for active courses still lacking a study load or a description, in Boost priority order. No Firecrawl, no AI. Pauses itself when nothing is left.',
  5, true)
on conflict (jobname) do nothing;

select cron.schedule('page-text', '*/2 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''page_text'', ''limit'', security.pipeline_num_v1(''batch.page_text'', 40)::int))');

do $$
begin
  if (select count(*) from cron.job where jobname = 'page-text' and active) <> 1 then raise exception 'post-check: job page-text'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'page-text') then raise exception 'post-check: catalogue'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('batch.page_text', 'page_text.min_chars')) <> 2 then raise exception 'post-check: settings'; end if;
end $$;
