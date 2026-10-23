-- CF-247 (24 Oct 2026). Platform Admin 07:43, zero-yield page re-acquisition (bug report and build mandate; admin repo
-- docs/platform/nz-enrichment-brief/2026-10-24-zero-yield-reacquisition.md holds the numbers, the predicate and every decision).
-- A bound course page whose stored copy gave no value and no statement after every reader ran is ZERO-YIELD. Zero-yield alone never
-- resets a page (Otago's real course pages are zero-yield because Otago prints fees elsewhere); a page is VERIFIED WRONG when, on top
-- of that, it looks like a listing or search page, its title does not overlap the course title, or it says "not found"; or, whether
-- zero-yield or not, it sits off the provider's dominant course-page pattern while an on-pattern candidate with a strong title match
-- exists in the provider's known pages (the University of Auckland catalogue-regulations case).
-- The flow: DETECT (nightly job, per-provider snapshot, a provider above the flag rate is systematic) → VERIFY (the signals above; the
-- stored copy is also re-verified by the existing reidentify lane once reset) → RESET (existing statuses mismatch / identity_mismatch;
-- a pipeline.page_rejections row, the minimal negative-evidence list the full S1 absorbs; item-5 links retract through guard 3) →
-- RE-ACQUIRE through the existing lanes (the provider's known pages from the Firecrawl map, refreshed through the source finder when
-- stale; the AI page match, which now skips rejected pages and gets one more attempt after a rejection) → REPLAY (the standing enrich
-- and fee lanes read the new page's stored copy; the official link fills the same night).
-- Everything tunable is a setting; manual bindings are never touched; a reset is count-limited per provider and per run; automatic
-- resets are OFF until the Platform Admin switches zero_yield.auto_reset on after the UoA pilot (a passing check never switches
-- anything on by itself).
-- Replaces: nothing (svc_coverage_reidentify_next and coverage_ai_match_prepare_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 negative evidence (the S1 partial) and the detect snapshots ------------------------------------------------------------------
create table if not exists pipeline.page_rejections (
  course_id uuid not null references catalogue.courses(id),
  url text not null,
  provider_id uuid not null,
  evidence_id uuid,
  source text not null default 'zero_yield',
  reason text not null,
  signals jsonb not null default '{}'::jsonb,
  rejected_at timestamptz not null default now(),
  rejected_by uuid,
  primary key (course_id, url)
);
comment on table pipeline.page_rejections is 'pages proven wrong for a course (negative evidence): the AI page match and the reidentify lane never offer or re-bind a rejected page; written by the zero-yield flow (source zero_yield) and, later, by the full S1 which absorbs this list; never deleted';
create index if not exists page_rejections_provider_idx on pipeline.page_rejections (provider_id, rejected_at desc);
alter table pipeline.page_rejections enable row level security;

create table if not exists pipeline.zero_yield_snapshots (
  at timestamptz not null,
  provider_id uuid not null,
  country text not null,
  bound integer not null,
  zero_yield integer not null,
  verified_wrong integer not null,
  rate_pct numeric,
  flagged boolean not null default false,
  reset integer not null default 0,
  detail jsonb not null default '{}'::jsonb,
  primary key (at, provider_id)
);
comment on table pipeline.zero_yield_snapshots is 'per-provider zero-yield figures written by the nightly zero-yield-detect job: bound pages with a stored copy, zero-yield pages, verified-wrong pages, the rate, whether the provider is flagged as systematic, and how many pages were reset; the before/after record of the re-acquisition flow; 90-day retention';
create index if not exists zero_yield_snapshots_provider_idx on pipeline.zero_yield_snapshots (provider_id, at desc);
alter table pipeline.zero_yield_snapshots enable row level security;

-- 2 settings ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'zero_yield.min_bound', 'Zero-yield: smallest provider measured', 'A provider with fewer bound pages than this is listed but never flagged as systematic.', 'number', '10'::jsonb, '1', '500', 'pages', 701, 'Zero-yield pages', 'job zero-yield-detect', 'zero-yield mandate (Platform Admin 24 Oct 2026 07:43)'),
 ('pipeline', 'zero_yield.flag_rate_pct', 'Zero-yield: rate that flags a provider', 'Share of a provider''s bound pages that are zero-yield above which its binding pattern counts as systematic and the provider goes to batch mode.', 'number', '25'::jsonb, '1', '100', '%', 702, 'Zero-yield pages', 'job zero-yield-detect', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.title_overlap_min', 'Verify: least title overlap', 'Share of the course title''s words found in the page title below which a zero-yield page is verified wrong.', 'number', '0.5'::jsonb, '0.1', '1', 'share', 703, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.off_pattern_share_max', 'Verify: off-pattern share', 'A bound page whose address pattern (host and first path folders) is used by fewer than this share of the provider''s bound pages is off-pattern; it is verified wrong when an on-pattern candidate with a strong title match exists.', 'number', '0.35'::jsonb, '0.05', '0.9', 'share', 704, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.candidate_overlap_min', 'Verify: least candidate title overlap', 'Share of the course title''s words an on-pattern candidate page must carry for an off-pattern page to be verified wrong.', 'number', '0.6'::jsonb, '0.1', '1', 'share', 705, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.listing_url_pattern', 'Verify: listing or search address', 'Regular expression (case ignored): a page address matching it is a listing or search page, never a course page.', 'text', '"/(search|category|categories|courses|programmes|programs|study-options|subjects|browse|listing|a-z|all-courses)/?(\\?|$)|[?&](q|query|search|keyword)="'::jsonb, null, null, 'pattern', 706, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.not_found_pattern', 'Verify: not-found page title', 'Regular expression (case ignored) for a page title that says the page does not exist.', 'text', '"not found|page unavailable|no longer available|404"'::jsonb, null, null, 'pattern', 707, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.reset_per_provider', 'Reset: pages a provider a run', 'Verified-wrong pages reset for one provider in one run.', 'number', '50'::jsonb, '1', '500', 'pages', 708, 'Zero-yield pages', 'security.zero_yield_reset_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.providers_per_run', 'Reset: providers a run', 'Flagged providers the nightly job resets in one run when automatic resets are on.', 'number', '5'::jsonb, '1', '100', 'providers', 709, 'Zero-yield pages', 'job zero-yield-detect', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.auto_reset', 'Reset: automatic', '1 lets the nightly job reset verified-wrong pages of flagged providers by itself; 0 only detects and reports (a person runs the reset). Off until the University of Auckland pilot is reviewed.', 'number', '0'::jsonb, '0', '1', 'on/off', 710, 'Zero-yield pages', 'job zero-yield-detect', 'zero-yield mandate: activation is a separate step'),
 ('pipeline', 'zero_yield.urls_max_age_days', 'Re-acquire: refresh the provider''s pages after', 'When the provider''s known pages (Firecrawl map, site maps) are older than this, a reset also asks the source finder to look again.', 'number', '14'::jsonb, '1', '180', 'days', 711, 'Zero-yield pages', 'security.zero_yield_reset_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.level_words', 'Verify: level words', 'Words that name a study level; an on-pattern candidate page whose address names a level the course title does not is never taken as the course''s page.', 'list', '["certificate","diploma","graduate","postgraduate","bachelor","bachelors","master","masters","doctor","doctorate","phd","honours","foundation","associate","apprenticeship","micro"]'::jsonb, null, null, 'words', 714, 'Zero-yield pages', 'security.zero_yield_pages_v1', 'zero-yield mandate'),
 ('pipeline', 'zero_yield.detect_providers_per_run', 'Detect: providers measured a run', 'Providers the hourly detect job measures in one run, those not measured in the last day first; the day covers every provider.', 'number', '150'::jsonb, '10', '2000', 'providers', 713, 'Zero-yield pages', 'job zero-yield-detect', 'zero-yield mandate'),
 ('pipeline', 'retention.zero_yield_snapshots_days', 'Zero-yield snapshots kept', 'Snapshots older than this are removed by retention-worker.', 'number', '90'::jsonb, '30', '365', 'days', 712, 'Retention', 'job retention-worker', 'zero-yield mandate')
on conflict (toolset_key, key) do nothing;

-- 3 the predicate and the signals -------------------------------------------------------------------------------------------------
create or replace function security.zero_yield_pages_v1(p_provider uuid default null)
returns table (course_id uuid, provider_id uuid, country text, url text, evidence_id uuid, identity_basis text, basis text, canonical_title text, page_title text,
               zero boolean, listing boolean, not_found boolean, title_overlap numeric, pattern_share numeric, candidate_url text, candidate_overlap numeric, verified_wrong boolean)
language sql stable security definer set search_path = '' as $$
with s as (
  select security.pipeline_num_v1('zero_yield.title_overlap_min', 0.5) t_min,
         security.pipeline_num_v1('zero_yield.off_pattern_share_max', 0.35) off_max,
         security.pipeline_num_v1('zero_yield.candidate_overlap_min', 0.6) c_min,
         coalesce((select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zero_yield.listing_url_pattern'), '^$') listing_rx,
         coalesce((select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zero_yield.not_found_pattern'), '^$') nf_rx,
         coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zero_yield.level_words'), '{}'::text[]) level_words),
b as materialized (
  select p.course_id, p.provider_id, k.iso_alpha2::text country, p.url, p.evidence_id, p.identity_basis, p.basis, c.canonical_title, p.candidates->>'page_title' page_title,
         regexp_replace(p.url, '^(https?://[^/]+/(?:[^/]+/){0,3}).*$', '\1') pattern,
         security.coverage_text_tokens(regexp_replace(c.canonical_title, '\(\s*level\s+\d+\s*\)', '', 'i')) ttok,
         security.coverage_text_tokens(coalesce(p.candidates->>'page_title', '')) ptok,
         (exists (select 1 from catalogue.course_fees f where f.course_id = p.course_id and f.evidence_id = p.evidence_id)
          or exists (select 1 from catalogue.course_english_requirements e where e.course_id = p.course_id and e.evidence_id = p.evidence_id)
          or exists (select 1 from catalogue.course_intakes i where i.course_id = p.course_id and i.evidence_id = p.evidence_id)) admitted,
         (exists (select 1 from pipeline.field_enrich_items i where i.course_id = p.course_id and i.evidence_id = p.evidence_id and i.state in ('filled', 'review'))) enrich_stated,
         (exists (select 1 from pipeline.field_enrich_items i where i.course_id = p.course_id and i.evidence_id = p.evidence_id)) enrich_tried,
         (exists (select 1 from pipeline.fee_reader_queue q where q.course_id = p.course_id and q.evidence_id = p.evidence_id and q.state = 'done' and coalesce(q.rows_found, 0) > 0)) fee_stated,
         (nullif(p.candidates->'fee'->>'value', '') is not null or jsonb_array_length(coalesce(p.candidates->'fee'->'candidates', '[]'::jsonb)) > 0
          or (p.candidates->'english' is not null and p.candidates->'english' <> '{}'::jsonb) or jsonb_array_length(coalesce(p.candidates->'intakes', '[]'::jsonb)) > 0) extract_stated
    from pipeline.coverage_course_pages p
    join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
    join catalogue.providers pr on pr.id = p.provider_id
    join ref.countries k on k.id = pr.country_id
    join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null
   where p.status = 'bound' and p.read_status = 'read' and (p_provider is null or p.provider_id = p_provider)),
share as materialized (select provider_id, pattern, count(*)::numeric / sum(count(*)) over (partition by provider_id) sh from b group by 1, 2),
z as materialized (
  select b.*, sh.sh pattern_share,
         (b.enrich_tried and not b.admitted and not b.enrich_stated and not b.fee_stated and not b.extract_stated) zero,
         (b.url ~* s.listing_rx) listing,
         (coalesce(b.page_title, '') ~* s.nf_rx) not_found,
         (select coalesce(count(*) filter (where t = any (b.ptok)), 0)::numeric / greatest(1, cardinality(b.ttok)) from unnest(b.ttok) t) title_overlap
    from b join share sh on sh.provider_id = b.provider_id and sh.pattern = b.pattern cross join s),
purl as materialized (
  -- the provider's known pages that sit on an accepted (on-pattern) address pattern, computed once
  select u.provider_id, u.url, u.tokens, u.title_tokens
    from pipeline.coverage_provider_urls u
    join share sh on sh.provider_id = u.provider_id and sh.pattern = regexp_replace(u.url, '^(https?://[^/]+/(?:[^/]+/){0,3}).*$', '\1')
    cross join s
   where sh.sh >= s.off_max and u.url !~* s.listing_rx
     and exists (select 1 from z where z.provider_id = u.provider_id and z.pattern_share < s.off_max)),
cand as materialized (
  select z.course_id, c.url, c.ov
    from z cross join s
    join lateral (
      select u.url, (select count(*) filter (where t = any (u.tokens))::numeric / greatest(1, cardinality(z.ttok)) from unnest(z.ttok) t) ov
        from purl u
       where u.provider_id = z.provider_id and u.url <> z.url and u.tokens && z.ttok
         -- a candidate naming a level the course does not (graduate diploma for a diploma, master for a bachelor) is not the course's page
         and not exists (select 1 from unnest(u.tokens) w where w = any (s.level_words) and not (w = any (z.ttok)))
         and not exists (select 1 from pipeline.page_rejections r where r.course_id = z.course_id and r.url = u.url)
       order by ov desc, length(u.url) limit 1) c on true
   where z.pattern_share < s.off_max)
select z.course_id, z.provider_id, z.country, z.url, z.evidence_id, z.identity_basis, z.basis, z.canonical_title, z.page_title,
       z.zero, z.listing, z.not_found, round(z.title_overlap, 2), round(z.pattern_share, 3), cand.url, round(cand.ov, 2),
       (coalesce(z.basis, '') <> 'manual' and ((z.zero and (z.listing or z.not_found or z.title_overlap < s.t_min)) or (z.pattern_share < s.off_max and coalesce(cand.ov, 0) >= s.c_min))) verified_wrong
  from z cross join s left join cand on cand.course_id = z.course_id
$$;
comment on function security.zero_yield_pages_v1(uuid) is 'every bound course page with a stored copy, with the zero-yield predicate (no value admitted and nothing stated by the fee, enrich and extract readers on that copy) and the verified-wrong signals (listing address, not-found title, weak title overlap, off the provider''s dominant pattern with an on-pattern candidate); zero-yield mandate 24 Oct 2026';

create or replace function security.page_rejection_bonus_v1(p_course uuid) returns integer
language sql stable security definer set search_path = '' as $$
  -- one more AI page match for a course after each rejection of a page it was bound to
  select case when exists (select 1 from pipeline.page_rejections r where r.course_id = p_course
                             and r.rejected_at > coalesce((select max(q.created_at) from pipeline.coverage_ai_match q where q.course_id = p_course), '-infinity'::timestamptz)) then 1 else 0 end
$$;
create or replace function security.page_match_bonus_v1(p_course uuid, p_provider uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select greatest(security.course_list_bonus_v1(p_course, p_provider), security.page_rejection_bonus_v1(p_course))
$$;

-- 4 reset: verified-wrong pages of one provider ---------------------------------------------------------------------------------------
create or replace function security.zero_yield_reset_v1(p_provider uuid, p_limit integer default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_lim int := greatest(1, least(coalesce(p_limit, security.pipeline_num_v1('zero_yield.reset_per_provider', 50)::int), 500));
        v_age int := greatest(1, security.pipeline_num_v1('zero_yield.urls_max_age_days', 14)::int);
        v_now timestamptz := clock_timestamp(); v_n int := 0; v_links int := 0; v_refind boolean := false; v_fill jsonb;
begin
  with sel as (
    select * from security.zero_yield_pages_v1(p_provider) z where z.verified_wrong order by z.zero desc, z.title_overlap limit v_lim)
  insert into pipeline.page_rejections(course_id, url, provider_id, evidence_id, source, reason, signals, rejected_at)
  select r.course_id, r.url, r.provider_id, r.evidence_id, 'zero_yield',
         case when r.zero and r.not_found then 'zero-yield page that says not found'
              when r.zero and r.listing then 'zero-yield listing or search page'
              when r.zero then 'zero-yield page whose title does not match the course'
              else 'page off the provider''s course-page pattern while an on-pattern page matches the course' end,
         jsonb_build_object('zero', r.zero, 'listing', r.listing, 'not_found', r.not_found, 'title_overlap', r.title_overlap, 'pattern_share', r.pattern_share, 'candidate_url', r.candidate_url, 'candidate_overlap', r.candidate_overlap, 'identity_basis', r.identity_basis, 'page_title', r.page_title), v_now
    from sel r
  on conflict (course_id, url) do update set rejected_at = v_now, reason = excluded.reason, signals = excluded.signals, evidence_id = excluded.evidence_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('provider_id', p_provider, 'reset', 0); end if;
  update pipeline.coverage_course_pages p
     set status = 'mismatch', read_status = 'identity_mismatch', leased_until = null, next_read_at = now(), read_attempts = 0
    from pipeline.page_rejections r where r.provider_id = p_provider and r.rejected_at = v_now and p.course_id = r.course_id and p.url = r.url and p.status = 'bound' and coalesce(p.basis, '') <> 'manual';
  -- the official link filled from the page is taken back by guard 3 (the fill job retracts fills whose page left bound)
  v_fill := security.course_url_fill_v1();
  v_links := coalesce((v_fill->>'retracted')::int, 0);
  -- the provider's known pages are refreshed when stale (the source finder looks again: Firecrawl map, site maps)
  if coalesce((select max(u.last_seen_at) from pipeline.coverage_provider_urls u where u.provider_id = p_provider), '-infinity'::timestamptz) < now() - make_interval(days => v_age) then
    update pipeline.source_find_runs set next_try_at = now(), step = null, leased_until = null, work = jsonb_build_object('again', true, 'reason', 'zero-yield re-acquisition') where provider_id = p_provider;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at, work) values (p_provider, 'none', now(), jsonb_build_object('again', true, 'reason', 'zero-yield re-acquisition')) on conflict (provider_id) do nothing;
    v_refind := true;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('pipeline', 'zero_yield_reset', p_provider::text,
          jsonb_build_object('reset', v_n, 'links_retracted', v_links, 'finder_asked', v_refind, 'reasons', (select jsonb_object_agg(reason, n) from (select reason, count(*) n from pipeline.page_rejections where provider_id = p_provider and rejected_at = v_now group by 1) z)), null);
  return jsonb_build_object('provider_id', p_provider, 'reset', v_n, 'links_retracted', v_links, 'finder_asked', v_refind);
end $$;
comment on function security.zero_yield_reset_v1(uuid, integer) is 'resets the verified-wrong pages of one provider: page_rejections row, page back to mismatch / identity_mismatch (the course unbinds; the AI page match and reidentify skip the rejected page), item-5 links retracted, the source finder asked again when the provider''s known pages are stale; count-limited; manual bindings never touched';

-- 5 detect: the nightly job -----------------------------------------------------------------------------------------------------------
create or replace function security.zero_yield_detect_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_at timestamptz := date_trunc('minute', now()); v_min int := security.pipeline_num_v1('zero_yield.min_bound', 10)::int;
        v_rate numeric := security.pipeline_num_v1('zero_yield.flag_rate_pct', 25); v_auto boolean := security.pipeline_num_v1('zero_yield.auto_reset', 0) = 1;
        v_per int := greatest(1, security.pipeline_num_v1('zero_yield.providers_per_run', 5)::int); v_batch int := greatest(10, least(security.pipeline_num_v1('zero_yield.detect_providers_per_run', 150)::int, 2000));
        r record; v_r jsonb; v_reset int := 0; v_prov int := 0; v_flag int := 0;
begin
  -- providers not measured in the last day first, a bounded number a run (the job runs hourly, so every provider is measured each day)
  for r in select x.provider_id from (select distinct p.provider_id from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id = p.evidence_id and e.storage_path is not null where p.status = 'bound' and p.read_status = 'read') x
            where not exists (select 1 from pipeline.zero_yield_snapshots s where s.provider_id = x.provider_id and s.at > now() - interval '23 hours')
            order by (select count(*) from pipeline.coverage_course_pages p2 where p2.provider_id = x.provider_id and p2.status = 'bound') desc
            limit v_batch loop
    insert into pipeline.zero_yield_snapshots(at, provider_id, country, bound, zero_yield, verified_wrong, rate_pct, flagged, detail)
    select v_at, z.provider_id, z.country, count(*), count(*) filter (where z.zero), count(*) filter (where z.verified_wrong),
           round(100.0 * count(*) filter (where z.zero) / count(*), 1),
           (count(*) >= v_min and 100.0 * count(*) filter (where z.zero) / count(*) >= v_rate),
           jsonb_build_object('listing', count(*) filter (where z.listing), 'not_found', count(*) filter (where z.not_found), 'off_pattern', count(*) filter (where z.pattern_share < security.pipeline_num_v1('zero_yield.off_pattern_share_max', 0.35)), 'manual', count(*) filter (where z.basis = 'manual'))
      from security.zero_yield_pages_v1(r.provider_id) z group by z.provider_id, z.country
    on conflict (at, provider_id) do nothing;
    v_prov := v_prov + 1;
  end loop;
  select count(*) into v_flag from pipeline.zero_yield_snapshots s where s.at = v_at and s.flagged;
  -- resets (when switched on) consider every flagged provider measured in the last day, most affected first
  if v_auto then
    for r in select distinct on (s.provider_id) s.provider_id, s.verified_wrong from pipeline.zero_yield_snapshots s where s.at > now() - interval '23 hours' and s.flagged and s.verified_wrong > 0
               and not exists (select 1 from pipeline.admin_control_events d where d.action = 'zero_yield_reset' and d.target = s.provider_id::text and d.created_at > now() - interval '23 hours')
             order by s.provider_id, s.at desc loop
      v_r := security.zero_yield_reset_v1(r.provider_id);
      v_reset := v_reset + coalesce((v_r->>'reset')::int, 0);
      update pipeline.zero_yield_snapshots s set reset = coalesce((v_r->>'reset')::int, 0) where s.provider_id = r.provider_id and s.at = (select max(at) from pipeline.zero_yield_snapshots where provider_id = r.provider_id);
      exit when (select count(*) from pipeline.admin_control_events d where d.action = 'zero_yield_reset' and d.created_at > now() - interval '1 hour') >= v_per;
    end loop;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('pipeline', 'zero_yield_detect', 'zero_yield_snapshots', jsonb_build_object('at', v_at, 'providers', v_prov, 'flagged', v_flag, 'auto_reset', v_auto, 'reset', v_reset), null);
  return jsonb_build_object('at', v_at, 'providers', v_prov, 'flagged', v_flag, 'auto_reset', v_auto, 'reset', v_reset);
end $$;
comment on function security.zero_yield_detect_v1() is 'hourly: writes the per-provider zero-yield snapshot, flags providers above the rate as systematic, and (only when zero_yield.auto_reset is 1) resets the verified-wrong pages of the most affected flagged providers';

-- 6 the lanes consume the rejection list ------------------------------------------------------------------------------------------------
select pg_temp.edit_n('public.svc_coverage_reidentify_next(integer,text)', 'ddd0fda00a869ce2bcfb2062502775eb', array[
  array[$o$and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)$o$,
        $n$and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)
          and not exists (select 1 from pipeline.page_rejections x where x.course_id = p.course_id and x.url = p.url) /* 24 Oct 2026: a rejected page is never re-bound */$n$]], array[1]);
select pg_temp.edit_n('security.coverage_ai_match_prepare_v1(integer,integer)', '3d6d0e1d90e210aa02eef8a962906e12', array[
  array[$o$security.course_list_bonus_v1(co.id, co.provider_id)$o$, $n$security.page_match_bonus_v1(co.id, co.provider_id)$n$],
  array[$o$union select q.course_id, q.chosen_url from pipeline.coverage_ai_match q join c using (course_id) where q.chosen_url is not null)$o$,
        $n$union select q.course_id, q.chosen_url from pipeline.coverage_ai_match q join c using (course_id) where q.chosen_url is not null
                union select x.course_id, x.url from pipeline.page_rejections x join c using (course_id) /* 24 Oct 2026: rejected pages are never candidates */)$n$]], array[4, 1]);

-- 7 the job: catalogue row before the schedule --------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('zero-yield-detect', 'Course pages', 61, 'Zero-yield pages: detect and reset',
  'Hourly at :21 (Detect: providers measured a run providers a run, every provider once a day): counts bound course pages whose stored copy gave the readers nothing (zero-yield) and those verified wrong (listing or not-found page, title that does not match, or off the provider''s course-page pattern with a better page known); a provider above Zero-yield: rate that flags a provider is flagged as systematic. With Reset: automatic on, resets the verified-wrong pages of the most affected flagged providers (Reset: providers a run, Reset: pages a provider a run): the page goes back to "does not match", its official link is taken back, the AI page match finds a new page from the provider''s known pages with the rejected one excluded, and the readers fill the course from the new page.',
  6, true, null)
on conflict (jobname) do nothing;
select cron.schedule('zero-yield-detect', '21 * * * *', $$select security.zero_yield_detect_v1()$$);

-- 8 register ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.page_rejections', 'Layer 2', 'negative evidence: pages proven wrong for a course (S1 partial, consumed by the AI page match and reidentify)', 'active', '{}', '20261024003000'),
 ('table', 'pipeline.zero_yield_snapshots', 'Layer 2', 'nightly per-provider zero-yield figures (before/after record)', 'active', '{}', '20261024003000'),
 ('function', 'security.zero_yield_pages_v1', 'Layer 2', 'zero-yield predicate and verified-wrong signals per bound page', 'active', '{}', '20261024003000'),
 ('function', 'security.zero_yield_reset_v1', 'Layer 2', 'reset of verified-wrong pages for one provider (count-limited)', 'active', '{}', '20261024003000'),
 ('function', 'security.zero_yield_detect_v1', 'Layer 2', 'nightly detect job', 'active', '{}', '20261024003000'),
 ('function', 'security.page_rejection_bonus_v1', 'Layer 2', 'one more AI page match after a rejection', 'active', '{}', '20261024003000'),
 ('function', 'security.page_match_bonus_v1', 'Layer 2', 'course-list or rejection bonus for the AI page match', 'active', '{}', '20261024003000'),
 ('job', 'zero-yield-detect', 'Layer 2', 'hourly zero-yield detect (and reset when switched on)', 'active', '{}', '20261024003000')
on conflict (kind, name) do nothing;

do $t$ declare u uuid; r jsonb; before jsonb; after jsonb; prep jsonb; t0 timestamptz := clock_timestamp(); d jsonb; begin
  select id into u from catalogue.providers where canonical_name='University of Auckland';
  select jsonb_build_object('bound', count(*), 'zero', count(*) filter (where zero), 'wrong', count(*) filter (where verified_wrong), 'off_pattern', count(*) filter (where pattern_share < 0.35), 'off_with_cand', count(*) filter (where pattern_share < 0.35 and candidate_overlap >= 0.6), 'ms', round(extract(epoch from clock_timestamp()-t0)*1000)) into before from security.zero_yield_pages_v1(u);
  update pipeline.platform_toolset_settings set value='200'::jsonb where toolset_key='pipeline' and key='zero_yield.reset_per_provider';
  update pipeline.platform_toolset_settings set value='25'::jsonb where toolset_key='pipeline' and key='zero_yield.detect_providers_per_run';
  r := security.zero_yield_reset_v1(u);
  select jsonb_build_object('mismatch_now', count(*) filter (where status='mismatch'), 'bound_now', count(*) filter (where status='bound')) into after from pipeline.coverage_course_pages where provider_id=u;
  prep := security.coverage_ai_match_prepare_v1(1, 300);
  t0 := clock_timestamp();
  d := security.zero_yield_detect_v1();
  raise exception 'DRYRUN OK %', jsonb_build_object('uoa_before', before, 'reset', r, 'uoa_after', after,
    'rejections', (select jsonb_object_agg(reason, n) from (select reason, count(*) n from pipeline.page_rejections where provider_id=u group by 1) z),
    'sample', (select jsonb_agg(jsonb_build_object('c', left(c.canonical_title,32), 'u', regexp_replace(x.url,'^https://(www\.|study\.)?auckland\.ac\.nz',''), 'cand', regexp_replace(x.signals->>'candidate_url','^https://(www\.|study\.)?auckland\.ac\.nz/en/study/study-options/find-a-study-option/',''), 'ov', x.signals->>'candidate_overlap')) from (select * from pipeline.page_rejections where provider_id=u order by random() limit 6) x join catalogue.courses c on c.id=x.course_id),
    'prepare', prep, 'ready_for_uoa', (select count(*) from pipeline.coverage_ai_match q where q.provider_id=u and q.state='ready'),
    'detect', d, 'detect_ms', round(extract(epoch from clock_timestamp()-t0)*1000)); end $t$;
