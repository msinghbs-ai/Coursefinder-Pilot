-- CF-247 AER D-R2 and D-R3, and the E13 extension (Platform Admin direction 2 Nov 2026 23:24, admin
-- docs/platform/nz-enrichment-brief/2026-11-02-overnight-continuous-delivery-direction-2324.md §1 "AER D-R2" and "AER D-R3"; evidence:
-- 2026-11-02-aer-layer4-readiness-assessment.md §3 G1/G2/G3/G4 and §8 R15/R16; design record 2026-11-03-aer-dr2-dr3-design.md).
-- Why:
--   * D-R3: provider entry-matrix first runs had no whole-read completeness rule outside entry.completeness_providers (RMIT only). All 40
--     pending runs record completeness "not_applicable"; approving UWA would admit 177 rows with every China row dropped.
--   * E13 extension: the course gate held only rows cut by the row limit, rows about another programme and shared pages. 170 pending reads
--     passed it while the reader had dropped printed minimums (score_without_basis, quote_not_on_page, low_confidence) that no kept row covers,
--     and reads made only of non-requirement text (course description, progression, credit, pointer or English rows) or with domestic routes
--     stored for every applicant could be approved.
--   * D-R2: while a course read waits in Layer 4 the reader refuses any new read of the course, and nothing supersedes a waiting course read,
--     so a corrected read could land only after the waiting one was rejected to clear the way.
-- What:
--   1. security.course_entry_read_check_v1(rows, dropped): the read-level checks shared by the gate and by D-R2 (uncovered dropped minimums,
--      non-requirement rows, domestic routes stored for everyone). security.course_entry_shared_page_v1(course): the shared-page part of E13,
--      factored out unchanged so D-R2 uses the same rule.
--   2. security.course_entry_gate_v1 (whole definition replaced, md5-guarded): E13 as before, plus the checks of 1. Row-level problems are
--      released by leaving the rows out (Approve except); uncovered dropped minimums are not (the read is incomplete).
--   3. security.entry_matrix_gate_v1(run, exclude): D-R3 whole-read completeness of a matrix run: current stored copy, the reader's own
--      verdict, dropped published rows not covered by an admitted row (countries left with no row are named), rows changed since the read,
--      qualification named by a column label, the provider's rank stored as the qualification's minimum, a band holding label text, a value
--      not printed in its quote or without a scale, a quote too short to prove anything, rows sharing one identity, and rows of another
--      provider, source or stored copy. A zero-row "no table" run with dropped rows is not a page without a table.
--   4. security.entry_matrix_review_apply_v1 (md5-guarded edit): a person's Approve (and Approve except) is refused, with nothing changed,
--      while the D-R3 gate finds the run incomplete; this runs before the Step C "no matrix published here" path. Reject is unchanged; the
--      automatic recording path (no Layer 4 item) is unchanged.
--   5. D-R2: pipeline.aer_read_supersessions (one row per requested correction, history kept: only requested -> superseded | refused, never
--      deleted); security.course_entry_correction_v1(item, actor, reason) asks for a corrected read of a waiting course read from the same
--      bound page (same course, same URL; refused for a decided, claimed or manually locked item, or one already being corrected), using the
--      existing stored-page read (security.course_entry_read_enqueue_v1); security.enrich_entry_record_v1 (md5-guarded edits) then lets that one
--      read replace the waiting item only when the corrected read is complete (security.course_entry_correction_check_v1): in one transaction
--      the old item becomes 'superseded' (existing status; its waiting rows are quarantined by the existing trigger) and the new item opens
--      'pending' with proposed_value.supersedes = the reviewer's diff (rows added, removed, unchanged; dropped counts before and after; old and
--      new stored copy). An incomplete correction changes nothing and is recorded as refused. Nothing is approved automatically.
--      A unique index keeps at most one waiting read per course.
--   6. security.aer_review_read_v1 (md5-guarded edit): the review screen gets the D-R3 gate for matrix items, the supersession diff, and for a
--      superseded item the item that replaced it.
-- Settings (G2; Settings > Pipeline settings, section Entry requirements): entry.gate_hold_reasons, entry.gate_cover_chars,
--   entry.gate_cover_min_chars, entry.nonrequirement_patterns, entry.domestic_audience_words, entry.matrix_gate, entry.matrix_gate_ignore_reasons,
--   entry.matrix_rank_words, entry.matrix_score_words, entry.supersede_claim_minutes, entry.supersede_lock_fields.
-- Measured on live data, read only, 2-3 Nov 2026 (logic replicated in a SELECT, no function created): the course gate holds 381 of 499 pending reads
--   (203 today; 178 newly: 151 dropped minimums no row covers, 29 with non-requirement rows, 5 with domestic rows stored for everyone, overlapping);
--   the matrix gate holds 38 of 40 pending runs (16 with lost rows, 25 with rows that cannot be admitted as read, 18 with shared identities); the two
--   it passes are ANU Advanced Placement (a column omission needs a column manifest, R14) and Newcastle (0 rows, 0 drops: a person confirms).
-- Not changed: entry.max_rows_per_course (6); no course or source is read; no AI, page fetch or Layer 4 decision; nothing approved, withdrawn
--   or re-opened. Pending items are not changed; the gates are checked when a person decides. A passing test switches nothing on.
-- Before (live, 2 Nov 2026 23:46 AEDT): security.course_entry_gate_v1 c1e99d43c6081f9a98c0eb698d943f32; security.entry_matrix_review_apply_v1
--   db3fde7584baf7e2960625d728603b99; security.aer_review_read_v1 50c31fc4df16b7bbbb39dab03aa9f9b2; security.enrich_entry_record_v1
--   9757abeeb3700c5cd2e02385def05869. After: course_entry_gate_v1 4fc06c081e451f2d0fb0a504a4fbe10f; entry_matrix_review_apply_v1 80c97f180f6d2ba54aad1abf2d058a24;
--   aer_review_read_v1 9b4aed8b80471beaac513cdf0aa55e3d; enrich_entry_record_v1 7faf2de4c2afe0a671f8f54c4a140fe4 (computed on the isolated fixtures rebuilt from this repository, whose
--   before values equal live; each helper raises, rolling the migration back, on any difference).
-- Rollback: re-apply the four before definitions; the new functions, table and settings are then unused and go by a paste file after
--   hygiene.retire_after_days.
-- Replaces: security.course_entry_gate_v1 (same name, whole definition), security.entry_matrix_review_apply_v1, security.aer_review_read_v1 and
--   security.enrich_entry_record_v1 (same names; md5-guarded edits)
-- Retires: nothing (no table, function, job or edge function is left unused)
-- Nothing dropped or deleted. New: one table (pipeline.aer_read_supersessions), one unique index, eight functions, eleven settings. No job.
--   The consumer API is not touched (G3, Decision 266): no website_*, zoho_*, api.* object or edge function changes; active rows are not changed.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
declare v_md5 text := md5(pg_get_functiondef(p_sig::regprocedure));
begin
  if v_md5 = p_after then return p_sig || ': already applied'; end if;
  if v_md5 <> p_before then raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, v_md5; end if;
  execute replace(p_def, chr(13), '');
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the change has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ---------------------------------------------------------------- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.gate_hold_reasons', 'Course entry requirements: dropped rows that hold a read',
  'A course read the reader dropped a row from for one of these reasons is incomplete, unless a waiting row covers the dropped quote. Approval is held until a corrected read replaces it.',
  'list', '["score_without_basis", "quote_not_on_page", "low_confidence"]'::jsonb, null, null, 'reasons', 932, 'Entry requirements',
  'security.course_entry_read_check_v1, security.course_entry_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): extend E13 to the incomplete course reads that bypassed it'),
 ('pipeline', 'entry.gate_cover_chars', 'Entry requirements: characters of a dropped quote a kept row must contain',
  'A dropped row counts as covered (not lost) when a kept row''s quote contains the first this-many letters and digits of the dropped quote.',
  'number', '40'::jsonb, 12, 120, 'characters', 933, 'Entry requirements',
  'security.course_entry_read_check_v1, security.entry_matrix_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): a dropped duplicate of a kept row is not a lost requirement'),
 ('pipeline', 'entry.gate_cover_min_chars', 'Entry requirements: shortest dropped quote that can be covered',
  'A dropped quote with fewer letters and digits than this cannot be shown to be covered by a kept row, so it holds the read.',
  'number', '12'::jsonb, 4, 60, 'characters', 934, 'Entry requirements',
  'security.course_entry_read_check_v1, security.entry_matrix_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24)'),
 ('pipeline', 'entry.nonrequirement_patterns', 'Course entry requirements: text that is not an entry requirement',
  'Case-insensitive patterns. A waiting row whose quote matches one (course description, progression, credit, a pointer to another page, an English proficiency note) holds approval until it is left out with Approve except.',
  'list', '["^this is an? [a-z ]*(program|programme|course|degree)", "\\mis (structured|suitable|designed) (to|for)\\M", "will (also )?introduce you", "\\mequips (registered|you|students|graduates)\\M", "National Literacy and Numeracy Test", "\\mLANTITE\\M", "^to progress from stage", "^to enrol in the research units", "^students admitted to the course, who have a recognised", "^part [a-z]\\. ", "^degree certificates", "^do you have a", "^experience is central", "^if you have qualifications from another country", "(proficiency|competen[a-z]*) in (the )?english", "^entry requirements may be waived"]'::jsonb,
  null, null, 'patterns', 935, 'Entry requirements',
  'security.course_entry_read_check_v1, security.course_entry_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): readiness assessment G3, G5 (real pending item shapes)'),
 ('pipeline', 'entry.domestic_audience_words', 'Course entry requirements: words of a domestic route',
  'Case-insensitive patterns. A waiting row whose quote names one but is stored for everyone or for international applicants holds approval until it is left out with Approve except.',
  'list', '["\\mdomestic\\M", "\\mATAR\\M", "\\mVCE\\M", "\\mVTAC\\M", "selection rank"]'::jsonb, null, null, 'patterns', 936, 'Entry requirements',
  'security.course_entry_read_check_v1, security.course_entry_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): readiness assessment G4; E12 keeps domestic ATAR rules apart'),
 ('pipeline', 'entry.matrix_gate', 'Entry matrices: whole-read completeness gate on',
  'A provider entry-matrix run is approved only when the whole read is accounted for (D-R3). Off only with a recorded reason.',
  'number', '1'::jsonb, 0, 1, 'on/off', 937, 'Entry requirements',
  'security.entry_matrix_gate_v1, security.entry_matrix_review_apply_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24)'),
 ('pipeline', 'entry.matrix_gate_ignore_reasons', 'Entry matrices: dropped rows that do not hold a run',
  'Reasons a matrix reader drops a row that are correct exclusions, not lost minimums (an English test row; a row that publishes no minimum).',
  'list', '["english_test_row", "no_minimum_published"]'::jsonb, null, null, 'reasons', 938, 'Entry requirements',
  'security.entry_matrix_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24)'),
 ('pipeline', 'entry.matrix_rank_words', 'Entry matrices: words of the provider''s own rank',
  'Case-insensitive patterns for a provider''s entrance or selection rank. Such a value is the band a qualification''s minimum maps to, never the qualification''s name or minimum.',
  'list', '["entrance rank", "selection rank", "\\mATAR\\M"]'::jsonb, null, null, 'patterns', 939, 'Entry requirements',
  'security.entry_matrix_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): ANU ladders (rank and score columns swapped)'),
 ('pipeline', 'entry.matrix_score_words', 'Entry matrices: words of the qualification''s own score',
  'Case-insensitive patterns for the column that prints the qualification''s minimum on a ladder table (for example "Indicative score required").',
  'list', '["indicative score", "score required"]'::jsonb, null, null, 'patterns', 940, 'Entry requirements',
  'security.entry_matrix_gate_v1', 'CF-247 D-R3 (Platform Admin 2 Nov 2026 23:24): ANU ladders (rank and score columns swapped)'),
 ('pipeline', 'entry.supersede_claim_minutes', 'Entry requirements: a reviewer''s claim protects a waiting read for',
  'A waiting read a reviewer claimed less than this long ago is not replaced by a corrected read.',
  'number', '60'::jsonb, 5, 1440, 'minutes', 941, 'Entry requirements',
  'security.course_entry_correction_check_v1', 'CF-247 D-R2 (Platform Admin 2 Nov 2026 23:24): manual decisions protected'),
 ('pipeline', 'entry.supersede_lock_fields', 'Entry requirements: course locks that stop a corrected read',
  'A course with a manual lock on one of these fields keeps its waiting read; no corrected read replaces it.',
  'list', '["entry_requirements", "course_url", "official_url"]'::jsonb, null, null, 'fields', 942, 'Entry requirements',
  'security.course_entry_correction_check_v1', 'CF-247 D-R2 (Platform Admin 2 Nov 2026 23:24): locks protected')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- D-R2 history
create table if not exists pipeline.aer_read_supersessions(
  id uuid primary key default gen_random_uuid(),
  old_item_id uuid not null,
  course_id uuid not null,
  source_url text not null,
  old_evidence_id uuid,
  enrich_item_id bigint not null unique,
  job_id uuid,
  requested_by uuid,
  reason text not null,
  state text not null default 'requested' check (state in ('requested', 'superseded', 'refused')),
  new_item_id uuid,
  outcome text,
  diff jsonb,
  requested_at timestamptz not null default now(),
  closed_at timestamptz);
comment on table pipeline.aer_read_supersessions is 'CF-247 D-R2: one row per corrected read asked for a waiting course entry read: the item, its bound page and stored copy, the read that was asked, and the outcome (superseded by the new item, with the reviewer''s diff, or refused with the reason). History: a row moves once from requested to superseded or refused and is never deleted.';
create unique index if not exists aer_read_supersessions_open_uq on pipeline.aer_read_supersessions(old_item_id) where state = 'requested';
-- at most one waiting read per course (live 2 Nov 2026 23:46: no course has two)
create unique index if not exists layer4_review_items_course_entry_pending_uq on pipeline.layer4_review_items(entity_id)
  where field_code = 'course_entry_first_read' and status = 'pending';

create or replace function security.aer_read_supersessions_guard_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'D-R2 history is kept: a supersession record is never deleted' using errcode = '42501'; end if;
  if old.state <> 'requested' or new.state not in ('superseded', 'refused')
     or (new.id, new.old_item_id, new.course_id, new.source_url, new.old_evidence_id, new.enrich_item_id, new.job_id, new.requested_by, new.reason, new.requested_at)
        is distinct from (old.id, old.old_item_id, old.course_id, old.source_url, old.old_evidence_id, old.enrich_item_id, old.job_id, old.requested_by, old.reason, old.requested_at) then
    raise exception 'D-R2 history is kept: a supersession record moves once from requested to superseded or refused' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function security.aer_read_supersessions_guard_v1() from public, anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'aer_read_supersessions_guard' and tgrelid = 'pipeline.aer_read_supersessions'::regclass) then
    create trigger aer_read_supersessions_guard before update or delete on pipeline.aer_read_supersessions
      for each row execute function security.aer_read_supersessions_guard_v1();
  end if;
end $$;
revoke all on pipeline.aer_read_supersessions from public, anon, authenticated;

create or replace function security.aer_read_supersession_close_v1(p_id uuid, p_state text, p_why text, p_new_item uuid, p_diff jsonb) returns void
language sql security definer set search_path to '' as $$
  update pipeline.aer_read_supersessions set state = p_state, outcome = left(p_why, 500), new_item_id = p_new_item, diff = p_diff, closed_at = now()
   where id = p_id and state = 'requested'
$$;
revoke all on function security.aer_read_supersession_close_v1(uuid, text, text, uuid, jsonb) from public, anon, authenticated;
comment on function security.aer_read_supersession_close_v1(uuid, text, text, uuid, jsonb) is 'CF-247 D-R2: closes one requested correction as superseded (with the new item and diff) or refused (with the reason).';

-- ---------------------------------------------------------------- the read-level checks of a course read (E13 extension, D-R2)
-- p_rows: the rows that would be admitted ({id?, kind, audience, quote}); p_dropped: the reader's dropped rows ({reason, kind, quote}).
create or replace function security.course_entry_read_check_v1(p_rows jsonb, p_dropped jsonb) returns jsonb
language sql stable security definer set search_path to '' as $$
  with s as (select coalesce(security.toolset_setting('pipeline', 'entry.gate_hold_reasons'), '[]'::jsonb) hold,
                    coalesce(security.toolset_setting('pipeline', 'entry.nonrequirement_patterns'), '[]'::jsonb) pat,
                    coalesce(security.toolset_setting('pipeline', 'entry.domestic_audience_words'), '[]'::jsonb) dom,
                    security.pipeline_num_v1('entry.gate_cover_chars', 40)::int n, security.pipeline_num_v1('entry.gate_cover_min_chars', 12)::int m),
  r as (select x, lower(regexp_replace(coalesce(x->>'quote', ''), '[^[:alnum:]]', '', 'g')) fq from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x),
  d as (select y, lower(regexp_replace(coalesce(y->>'quote', ''), '[^[:alnum:]]', '', 'g')) fq
          from jsonb_array_elements(coalesce(p_dropped, '[]'::jsonb)) y, s where s.hold ? coalesce(y->>'reason', '')),
  dc as (select d.y, exists (select 1 from r, s where length(d.fq) >= s.m and strpos(r.fq, left(d.fq, s.n)) > 0) cov from d)
  select jsonb_build_object(
    'drops_uncovered', (select coalesce(jsonb_agg(jsonb_build_object('reason', y->>'reason', 'kind', y->>'kind', 'quote', left(y->>'quote', 160))), '[]'::jsonb) from dc where not cov),
    'drops_covered', (select count(*) from dc where cov),
    'not_requirement', (select coalesce(jsonb_agg(jsonb_build_object('id', r.x->>'id', 'quote', left(r.x->>'quote', 160))), '[]'::jsonb) from r, s
                         where exists (select 1 from jsonb_array_elements_text(s.pat) p where btrim(p) <> '' and coalesce(r.x->>'quote', '') ~* p)),
    'audience', (select coalesce(jsonb_agg(jsonb_build_object('id', r.x->>'id', 'audience', r.x->>'audience', 'quote', left(r.x->>'quote', 160))), '[]'::jsonb) from r, s
                  where coalesce(r.x->>'audience', 'all') <> 'domestic'
                    and exists (select 1 from jsonb_array_elements_text(s.dom) w where btrim(w) <> '' and coalesce(r.x->>'quote', '') ~* w)))
$$;
revoke all on function security.course_entry_read_check_v1(jsonb, jsonb) from public, anon, authenticated;
comment on function security.course_entry_read_check_v1(jsonb, jsonb) is 'CF-247 D-R3/E13 extension: the read-level checks of a course entry read: dropped minimums (entry.gate_hold_reasons) no kept row covers, rows that are not entry requirements (entry.nonrequirement_patterns), and domestic routes stored for everyone (entry.domestic_audience_words).';

-- the E13 shared-page rule, unchanged, for one course (used by the gate and by D-R2)
create or replace function security.course_entry_shared_page_v1(p_course uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(distinct c2.canonical_title), '[]'::jsonb)
    from pipeline.coverage_course_pages g1
    join catalogue.courses c1 on c1.id = g1.course_id
    join pipeline.coverage_course_pages g2 on g2.url = g1.url and g2.course_id <> g1.course_id
    join catalogue.courses c2 on c2.id = g2.course_id
   where g1.course_id = p_course
     and lower(regexp_replace(regexp_replace(c2.canonical_title, '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g'))
         <> lower(regexp_replace(regexp_replace(c1.canonical_title, '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g'))
     and security.pipeline_num_v1('entry.shared_page_hold', 1) >= 1 and security.pipeline_num_v1('entry.variant_check', 1) >= 1
     and not (coalesce(security.toolset_setting('pipeline', 'entry.variant_check_off_providers'), '[]'::jsonb) ? c1.provider_id::text)
$$;
revoke all on function security.course_entry_shared_page_v1(uuid) from public, anon, authenticated;
comment on function security.course_entry_shared_page_v1(uuid) is 'CF-247 E13 (factored out by D-R2): the differently named programmes whose stored page is also this course''s page (entry.shared_page_hold).';

-- ---------------------------------------------------------------- 2. the course gate: E13 plus the read-level checks
select pg_temp.replace_once('security.course_entry_gate_v1(uuid,uuid[])', 'c1e99d43c6081f9a98c0eb698d943f32', '4fc06c081e451f2d0fb0a504a4fbe10f', $def$
create or replace function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}') returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare r pipeline.layer4_review_items%rowtype; v_drop jsonb; v_cut int; v_joined jsonb; v_other jsonb; v_shared jsonb; v_why text[] := '{}'; v_chk jsonb; v_n int;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code <> 'course_entry_first_read' then return null; end if;
  v_drop := coalesce(r.proposed_value->'dropped',
                     (select f.value->'dropped' from pipeline.field_enrich_items f where f.id = nullif(r.proposed_value->>'item_id', '')::bigint), '[]'::jsonb);
  select count(*) into v_cut from jsonb_array_elements(v_drop) d where d->>'reason' = 'over_row_limit';
  select coalesce(jsonb_agg(jsonb_build_object('kind', d->>'kind', 'quote', d->>'quote')), '[]'::jsonb) into v_joined
    from jsonb_array_elements(v_drop) d where d->>'reason' = 'over_row_limit' and security.course_entry_joined_v1(d->>'quote', d->>'kind');
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'names', n.v, 'quote', x.quote) order by x.kind, x.id), '[]'::jsonb) into v_other
    from catalogue.course_entry_requirements x cross join lateral (select security.course_entry_variant_v1(x.course_id, x.quote) v) n
   where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and not (x.id = any (coalesce(p_exclude, '{}'::uuid[]))) and n.v is not null;
  v_shared := security.course_entry_shared_page_v1(r.entity_id);
  -- D-R3 (Platform Admin 2 Nov 2026 23:24): the read-level checks on the rows that would be admitted
  v_chk := security.course_entry_read_check_v1(
    (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'audience', x.audience, 'quote', x.quote)), '[]'::jsonb)
       from catalogue.course_entry_requirements x
      where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and not (x.id = any (coalesce(p_exclude, '{}'::uuid[])))), v_drop);
  if v_cut > 0 then
    v_why := v_why || format('the reader cut %s requirement(s) on this page at its row limit, so the read is incomplete: reject it', v_cut);
  end if;
  if jsonb_array_length(v_joined) > 0 then
    v_why := v_why || format('%s of the cut requirement(s) belong to a requirement that was kept (for example "%s")', jsonb_array_length(v_joined), left(v_joined->0->>'quote', 80));
  end if;
  if jsonb_array_length(v_other) > 0 then
    v_why := v_why || format('%s waiting row(s) are about another programme (%s): leave them out with Approve except, or reject the read',
                             jsonb_array_length(v_other), (select string_agg(distinct o->>'names', ', ') from jsonb_array_elements(v_other) o));
  end if;
  if jsonb_array_length(v_shared) > 0 then
    v_why := v_why || format('the stored page is also the page of %s other programme(s) (%s), so its rows cannot be told apart by programme: reject the read',
                             jsonb_array_length(v_shared), (select string_agg(t, ', ') from (select jsonb_array_elements_text(v_shared) t limit 3) z)
                             || case when jsonb_array_length(v_shared) > 3 then ', …' else '' end);
  end if;
  v_n := jsonb_array_length(v_chk->'drops_uncovered');
  if v_n > 0 then
    v_why := v_why || format('the reader dropped %s printed requirement(s) that no waiting row covers (%s), so the read is incomplete: replace it with a corrected read, or reject it',
                             v_n, (select string_agg(k || ' ' || c, ', ') from (select d->>'reason' k, count(*) c from jsonb_array_elements(v_chk->'drops_uncovered') d group by 1 order by 1) z));
  end if;
  if jsonb_array_length(v_chk->'not_requirement') > 0 then
    v_why := v_why || format('%s waiting row(s) are not entry requirements (course description, progression, credit, a pointer or an English note): leave them out with Approve except',
                             jsonb_array_length(v_chk->'not_requirement'));
  end if;
  if jsonb_array_length(v_chk->'audience') > 0 then
    v_why := v_why || format('%s waiting row(s) name a domestic route but are stored for %s: leave them out with Approve except',
                             jsonb_array_length(v_chk->'audience'), (select string_agg(distinct a->>'audience', ' or ') from jsonb_array_elements(v_chk->'audience') a));
  end if;
  return jsonb_build_object('rule', 'E13', 'complete', cardinality(v_why) = 0, 'rows_cut', v_cut, 'joined', v_joined, 'other_programme', v_other,
                            'shared_page', v_shared, 'drops_uncovered', v_chk->'drops_uncovered', 'drops_covered', v_chk->'drops_covered',
                            'not_requirement', v_chk->'not_requirement', 'audience', v_chk->'audience', 'reasons', to_jsonb(v_why));
end $$
$def$);

-- ---------------------------------------------------------------- 3. D-R3: the whole-read completeness gate of a matrix run
create or replace function security.entry_matrix_gate_v1(p_run uuid, p_exclude uuid[] default '{}') returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare r pipeline.entry_matrix_runs%rowtype; s pipeline.entry_matrix_sources%rowtype; v_ex uuid[] := coalesce(p_exclude, '{}'::uuid[]);
        v_why text[] := '{}'; v_fix boolean := true; v_rows int; v_wait int; v_lost jsonb; v_cov int; v_missing jsonb; v_flag jsonb; v_dup jsonb;
        v_n int := security.pipeline_num_v1('entry.gate_cover_chars', 40)::int; v_m int := security.pipeline_num_v1('entry.gate_cover_min_chars', 12)::int;
        v_ignore jsonb := coalesce(security.toolset_setting('pipeline', 'entry.matrix_gate_ignore_reasons'), '[]'::jsonb);
        v_rank text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_rank_words'), '[]'::jsonb)) w where btrim(w) <> '');
        v_score text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_score_words'), '[]'::jsonb)) w where btrim(w) <> '');
begin
  select * into r from pipeline.entry_matrix_runs where id = p_run;
  if r.id is null then return null; end if;
  if security.pipeline_num_v1('entry.matrix_gate', 1) < 1 then
    return jsonb_build_object('rule', 'D-R3', 'complete', true, 'off', true, 'reasons', '[]'::jsonb);
  end if;
  select * into s from pipeline.entry_matrix_sources where id = r.source_id;
  -- the read is of the source's current stored copy and finished
  if r.state is distinct from 'done' then v_why := v_why || format('the read has not finished (%s)', coalesce(r.state, 'no state')); v_fix := false; end if;
  if s.id is null or r.content_hash is distinct from s.content_hash then
    v_why := v_why || 'the read is not of the source''s current stored copy: read the current copy before deciding'::text; v_fix := false;
  end if;
  -- the reader's own verdict, where it made one
  if coalesce(r.result->'completeness'->>'status', 'not_applicable') not in ('not_applicable', 'complete') then
    v_why := v_why || format('the reader''s completeness check did not pass (%s)', r.result->'completeness'->>'status'); v_fix := false;
  end if;
  -- rows changed since the read: every row the read proposed still waits (admitted or left out by the reviewer)
  select count(*) filter (where m.status = 'proposed'), count(*) filter (where m.status = 'proposed' and not (m.id = any (v_ex))) into v_wait, v_rows
    from catalogue.provider_entry_matrix m where m.run_id = r.id;
  if v_wait is distinct from coalesce(r.rows_admitted, 0) then
    v_why := v_why || format('%s row(s) wait but the read proposed %s: rows changed since the read', v_wait, coalesce(r.rows_admitted, 0)); v_fix := false;
  end if;
  -- dropped published rows that no admitted row covers (left out rows do not cover anything)
  with a as (select lower(regexp_replace(coalesce(m.quote, ''), '[^[:alnum:]]', '', 'g')) fq, m.country_code
               from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex))),
       d as (select x, lower(regexp_replace(coalesce(x->>'quote', ''), '[^[:alnum:]]', '', 'g')) fq
               from jsonb_array_elements(coalesce(r.result->'dropped', '[]'::jsonb)) x where not (v_ignore ? coalesce(x->>'reason', ''))),
       dc as (select d.x, exists (select 1 from a where length(d.fq) >= v_m and strpos(a.fq, left(d.fq, v_n)) > 0) cov from d)
  select coalesce(jsonb_agg(jsonb_build_object('reason', x->>'reason', 'country', x->>'country', 'quote', left(x->>'quote', 120))) filter (where not cov), '[]'::jsonb),
         count(*) filter (where cov),
         coalesce((select jsonb_agg(distinct dc2.x->>'country') from dc dc2 where not dc2.cov and coalesce(dc2.x->>'country', '') <> ''
                     and not exists (select 1 from a where a.country_code = upper(dc2.x->>'country'))), '[]'::jsonb)
    into v_lost, v_cov, v_missing from dc;
  if jsonb_array_length(v_lost) > 0 then
    v_why := v_why || format('the reader dropped %s published row(s) that no admitted row covers (%s)%s, so the read is incomplete: replace it with a corrected read, or reject it',
                             jsonb_array_length(v_lost),
                             (select string_agg(k || ' ' || c, ', ') from (select l->>'reason' k, count(*) c from jsonb_array_elements(v_lost) l group by 1 order by 1) z),
                             case when jsonb_array_length(v_missing) > 0 then '; left with no row at all: ' || (select string_agg(c, ', ' order by c) from jsonb_array_elements_text(v_missing) c) else '' end);
    v_fix := false;
  end if;
  -- row-level problems (each can be left out with Approve except)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'why', w.why) order by m.id), '[]'::jsonb) into v_flag
    from catalogue.provider_entry_matrix m
    cross join lateral (select array(select (regexp_matches(coalesce(m.quote, ''), '[0-9]+(?:\.[0-9]+)?', 'g'))[1]) nums) n
    cross join lateral (select case
        when m.provider_id is distinct from r.provider_id or m.source_id is distinct from r.source_id or m.content_hash is distinct from r.content_hash
          then 'another provider, source or stored copy'
        when btrim(coalesce(m.qualification_name, '')) = '' or (v_rank is not null and m.qualification_name ~* v_rank) or (v_score is not null and m.qualification_name ~* v_score)
          then 'qualification named by a column label'
        when m.grade_scale = 'rank' and v_score is not null and coalesce(m.quote, '') ~* v_score
          then 'the provider''s rank is stored as the qualification''s minimum'
        when v_rank is not null and v_score is not null and coalesce(m.min_grade, '') ~* v_rank and coalesce(m.quote, '') ~* v_score
          then 'the provider''s rank is stored as the qualification''s minimum'
        -- a ladder quote printing the rank and the score: the minimum is the score's own cell (the second number when the rank is printed first)
        when v_rank is not null and v_score is not null and m.min_value is not null and coalesce(m.quote, '') ~* v_rank and coalesce(m.quote, '') ~* v_score
             and cardinality(n.nums) = 2
             and m.min_value <> (case when strpos(lower(m.quote), lower(substring(m.quote from '(?i)(' || v_rank || ')')))
                                         < strpos(lower(m.quote), lower(substring(m.quote from '(?i)(' || v_score || ')'))) then n.nums[2] else n.nums[1] end)::numeric
          then 'the provider''s rank is stored as the qualification''s minimum'
        when coalesce(m.benchmark_band, '') <> '' and ((v_rank is not null and m.benchmark_band ~* v_rank) or (v_score is not null and m.benchmark_band ~* v_score))
          then 'the band holds label text, not a band'
        when m.min_value is not null and (coalesce(m.grade_scale, 'none') = 'none' or strpos(coalesce(m.quote, ''), trim_scale(m.min_value)::text) = 0)
          then 'the value has no scale or is not printed in its quote'
        when length(regexp_replace(coalesce(m.quote, ''), '[^[:alnum:]]', '', 'g')) < v_m / 2
          then 'the quote is too short to prove the row'
        end why) w
   where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex)) and w.why is not null;
  if jsonb_array_length(v_flag) > 0 then
    v_why := v_why || format('%s waiting row(s) cannot be admitted as read (%s): leave them out with Approve except, or replace the read with a corrected one',
                             jsonb_array_length(v_flag), (select string_agg(k || ' ' || c, '; ') from (select f->>'why' k, count(*) c from jsonb_array_elements(v_flag) f group by 1 order by 1) z));
  end if;
  select coalesce(jsonb_agg(g.ids), '[]'::jsonb) into v_dup
    from (select jsonb_agg(m.id order by m.id) ids from catalogue.provider_entry_matrix m
           where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex)) group by m.row_hash having count(*) > 1) g;
  if jsonb_array_length(v_dup) > 0 then
    v_why := v_why || format('%s group(s) of waiting rows share one identity (%s rows): leave out all but one of each, or replace the read with a corrected one',
                             jsonb_array_length(v_dup), (select sum(jsonb_array_length(g)) from jsonb_array_elements(v_dup) g));
  end if;
  return jsonb_build_object('rule', 'D-R3', 'complete', cardinality(v_why) = 0, 'rows', v_rows, 'waiting', v_wait, 'read_rows', r.rows_admitted,
                            'dropped_lost', v_lost, 'dropped_covered', v_cov, 'countries_missing', v_missing, 'flagged', v_flag, 'same_identity', v_dup,
                            'except_fixable', v_fix, 'no_table', coalesce(r.result->>'outcome', '') = 'no_requirements_table',
                            'reasons', to_jsonb(v_why));
end $$;
revoke all on function security.entry_matrix_gate_v1(uuid, uuid[]) from public, anon, authenticated;
comment on function security.entry_matrix_gate_v1(uuid, uuid[]) is 'CF-247 D-R3: whole-read completeness of a provider entry-matrix run (current copy, reader verdict, rows changed, dropped rows no admitted row covers and the countries left with none, column-label qualifications, rank stored as minimum, label bands, values without scale or not printed, short quotes, shared identities, foreign rows). complete=false holds approval (entry.matrix_gate).';

-- ---------------------------------------------------------------- 4. approval of a matrix run: an incomplete run never reaches approval
select pg_temp.edit_once('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'db3fde7584baf7e2960625d728603b99', '80c97f180f6d2ba54aad1abf2d058a24', array[
 array[$o$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0;$o$,
       $n$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;$n$],
 array[$o$  -- Step C (29 Oct 2026): a rendered page with no requirements table; approval confirms "no matrix published here" and changes no row
$o$,
       $n$  -- D-R3 (Platform Admin 2 Nov 2026 23:24): a person's approval (Approve, Approve except, or confirming "no matrix published here") is refused,
  -- with nothing changed, while the whole read cannot be shown complete (security.entry_matrix_gate_v1); Reject and the automatic path are unchanged
  if p_action = 'approve' and p_item is not null then
    v_gate := security.entry_matrix_gate_v1(r.id, coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}'));
    if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
      raise exception 'Held (D-R3, incomplete read): %. Nothing was changed',
        (select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w) using errcode = '55000';
    end if;
  end if;
  -- Step C (29 Oct 2026): a rendered page with no requirements table; approval confirms "no matrix published here" and changes no row
$n$]],
 array[1, 1]);

-- ---------------------------------------------------------------- 5. D-R2: the checks of a corrected read, and asking for one
-- p_rows null: the checks before a read is asked (item, decision, claim, lock, page); with rows: also the completeness of the corrected read
-- and the reviewer's diff against the waiting read.
create or replace function security.course_entry_correction_check_v1(p_item uuid, p_course uuid, p_url text, p_rows jsonb default null, p_dropped jsonb default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare o pipeline.layer4_review_items%rowtype; v_why text[] := '{}'; v_chk jsonb; v_shared jsonb; v_diff jsonb;
begin
  select * into o from pipeline.layer4_review_items where id = p_item;
  if o.id is null or o.field_code <> 'course_entry_first_read' then return jsonb_build_object('ok', false, 'why', 'not a course entry read'); end if;
  if o.status <> 'pending' then v_why := v_why || format('the read no longer waits (%s)', o.status); end if;
  if o.entity_id is distinct from p_course then v_why := v_why || 'another course'::text; end if;
  if exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = o.id) then v_why := v_why || 'a person has decided it'::text; end if;
  if o.claimed_at is not null and o.claimed_at > now() - make_interval(mins => security.pipeline_num_v1('entry.supersede_claim_minutes', 60)::int) then
    v_why := v_why || 'a reviewer claimed it'::text;
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p_course
               and l.field in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.supersede_lock_fields'), '[]'::jsonb)))) then
    v_why := v_why || 'the course has a manual lock'::text;
  end if;
  if p_url is null or p_url is distinct from o.proposed_value->>'url' then
    v_why := v_why || format('the course''s bound page (%s) is not the page of the waiting read (%s): a new first read, not a correction', coalesce(p_url, 'none'), coalesce(o.proposed_value->>'url', 'none'));
  end if;
  if p_rows is not null then
    v_chk := security.course_entry_read_check_v1(p_rows, p_dropped);
    v_shared := security.course_entry_shared_page_v1(p_course);
    if jsonb_array_length(p_rows) = 0 then v_why := v_why || 'the corrected read has no row'::text; end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_dropped, '[]'::jsonb)) d where d->>'reason' in ('over_row_limit', 'other_programme')) then
      v_why := v_why || 'the corrected read cut or set aside rows'::text;
    end if;
    if jsonb_array_length(v_chk->'drops_uncovered') > 0 then v_why := v_why || format('the corrected read still drops %s printed requirement(s)', jsonb_array_length(v_chk->'drops_uncovered')); end if;
    if jsonb_array_length(v_chk->'not_requirement') > 0 then v_why := v_why || format('%s row(s) are not entry requirements', jsonb_array_length(v_chk->'not_requirement')); end if;
    if jsonb_array_length(v_chk->'audience') > 0 then v_why := v_why || format('%s domestic row(s) stored for everyone', jsonb_array_length(v_chk->'audience')); end if;
    if jsonb_array_length(v_shared) > 0 then v_why := v_why || 'the page is shared with another programme'::text; end if;
    -- the reviewer's diff: a row is the same when kind, audience, quote (letters and digits), score and basis are the same
    with oldr as (select x.kind, x.audience, x.quote, x.min_entry_score sc, x.min_entry_score_basis b,
                         x.kind || '|' || x.audience || '|' || lower(regexp_replace(coalesce(x.quote, ''), '[^[:alnum:]]', '', 'g')) || '|' || coalesce(x.min_entry_score::text, '') || '|' || lower(coalesce(x.min_entry_score_basis, '')) k
                    from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = o.id::text),
         newr as (select y->>'kind' kind, y->>'audience' audience, y->>'quote' quote, y->>'min_entry_score' sc, y->>'min_entry_score_basis' b,
                         (y->>'kind') || '|' || (y->>'audience') || '|' || lower(regexp_replace(coalesce(y->>'quote', ''), '[^[:alnum:]]', '', 'g')) || '|' || coalesce((y->>'min_entry_score')::numeric::text, '') || '|' || lower(coalesce(y->>'min_entry_score_basis', '')) k
                    from jsonb_array_elements(p_rows) y)
    select jsonb_build_object(
      'added', (select coalesce(jsonb_agg(jsonb_build_object('kind', n.kind, 'audience', n.audience, 'score', n.sc, 'basis', n.b, 'quote', left(n.quote, 200))), '[]'::jsonb) from newr n where not exists (select 1 from oldr x where x.k = n.k)),
      'removed', (select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'audience', x.audience, 'score', x.sc, 'basis', x.b, 'quote', left(x.quote, 200))), '[]'::jsonb) from oldr x where not exists (select 1 from newr n where n.k = x.k)),
      'unchanged', (select count(*) from newr n where exists (select 1 from oldr x where x.k = n.k)),
      'dropped_before', (select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) from (select d->>'reason' k, count(*) c from jsonb_array_elements(coalesce(o.proposed_value->'dropped', '[]'::jsonb)) d group by 1) z),
      'dropped_after', (select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) from (select d->>'reason' k, count(*) c from jsonb_array_elements(coalesce(p_dropped, '[]'::jsonb)) d group by 1) z),
      'old_evidence_id', o.evidence_id)
      into v_diff;
  end if;
  return jsonb_build_object('ok', cardinality(v_why) = 0, 'why', array_to_string(v_why, '; '), 'reasons', to_jsonb(v_why), 'check', v_chk, 'diff', v_diff);
end $$;
revoke all on function security.course_entry_correction_check_v1(uuid, uuid, text, jsonb, jsonb) from public, anon, authenticated;
comment on function security.course_entry_correction_check_v1(uuid, uuid, text, jsonb, jsonb) is 'CF-247 D-R2: may a corrected read replace this waiting course entry read? Same course and bound page, still waiting, no decision, no recent claim, no manual lock (entry.supersede_lock_fields); with the corrected rows, also complete (security.course_entry_read_check_v1, no cut, no shared page) and the reviewer''s diff.';

create or replace function security.course_entry_correction_v1(p_item uuid, p_actor uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare o pipeline.layer4_review_items%rowtype; g record; v_chk jsonb; v_job uuid; v_enrich bigint; v_id uuid;
begin
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'give a reason (kept in the record)'; end if;
  select * into o from pipeline.layer4_review_items where id = p_item for update;
  if o.id is null then raise exception 'no such Layer 4 item'; end if;
  select pg.url, pg.evidence_id into g from pipeline.coverage_course_pages pg where pg.course_id = o.entity_id;
  v_chk := security.course_entry_correction_check_v1(p_item, o.entity_id, g.url);
  if not (v_chk->>'ok')::boolean then raise exception 'No corrected read (D-R2): %. Nothing was changed', v_chk->>'why' using errcode = '55000'; end if;
  if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then
    raise exception 'No corrected read (D-R2): a corrected read of this item is already asked for. Nothing was changed' using errcode = '55000';
  end if;
  if exists (select 1 from pipeline.field_enrich_items f where f.course_id = o.entity_id and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'No corrected read (D-R2): a read of this course is already in progress. Nothing was changed' using errcode = '55000';
  end if;
  v_job := security.course_entry_read_enqueue_v1(o.entity_id, p_actor, 'Corrected read (D-R2) of Layer 4 item ' || p_item || ': ' || btrim(p_reason));
  select f.id into v_enrich from pipeline.field_enrich_items f where f.job_id = v_job and f.course_id = o.entity_id and f.field = 'entry_requirements';
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason)
  values (p_item, o.entity_id, g.url, o.evidence_id, v_enrich, v_job, p_actor, btrim(p_reason)) returning id into v_id;
  return jsonb_build_object('request_id', v_id, 'job_id', v_job, 'enrich_item_id', v_enrich, 'review_item_id', p_item);
end $$;
revoke all on function security.course_entry_correction_v1(uuid, uuid, text) from public, anon, authenticated;
comment on function security.course_entry_correction_v1(uuid, uuid, text) is 'CF-247 D-R2: asks for a corrected read of a waiting course entry read from the same bound page (stored page, security.course_entry_read_enqueue_v1); the read replaces the waiting item only when complete. Owner only (a governed migration or paste); nothing is approved.';

-- ---------------------------------------------------------------- 5b. the reader: a requested corrected read replaces the waiting one, whole or not at all
select pg_temp.edit_once('security.enrich_entry_record_v1(bigint,jsonb)', '9757abeeb3700c5cd2e02385def05869', '7faf2de4c2afe0a671f8f54c4a140fe4', array[
 array[$o$        v_keep jsonb := '[]'::jsonb; v_n int; v_joined int;
$o$,
       $n$        v_keep jsonb := '[]'::jsonb; v_n int; v_joined int; v_sup pipeline.aer_read_supersessions%rowtype; v_old pipeline.layer4_review_items%rowtype; v_chk jsonb;
$n$],
 array[$o$  if i.id is null or i.course_id is null then return 'nothing'; end if;
$o$,
       $n$  if i.id is null or i.course_id is null then return 'nothing'; end if;
  -- D-R2: a corrected read asked for a waiting item (security.course_entry_correction_v1)
  select * into v_sup from pipeline.aer_read_supersessions s where s.enrich_item_id = i.id and s.state = 'requested' for update;
$n$],
 array[$o$    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit entry requirements for this country', updated_at = now() where id = i.id;
$o$,
       $n$    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit entry requirements for this country', updated_at = now() where id = i.id;
    if v_sup.id is not null then perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', 'the page''s proof does not admit entry requirements', null, null); end if;
$n$],
 array[$o$    return 'not_stated';
$o$,
       $n$    if v_sup.id is not null then perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', 'the corrected read states no requirement', null, null); end if;
    return 'not_stated';
$n$],
 array[$o$  if exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = i.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'an earlier read of this course waits in Layer 4', updated_at = now() where id = i.id;
$o$,
       $n$  -- D-R2: only the read asked to correct it may pass the waiting read (and only when complete, checked below before any row is written)
  if exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = i.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending'
               and (v_sup.id is null or r.id <> v_sup.old_item_id)) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'an earlier read of this course waits in Layer 4', updated_at = now() where id = i.id;
    if v_sup.id is not null then perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', 'another read of this course waits in Layer 4', null, null); end if;
$n$],
 array[$o$    return 'held_partial';
$o$,
       $n$    if v_sup.id is not null then perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', 'the corrected read was cut at the row limit (E13)', null, null); end if;
    return 'held_partial';
$n$],
 array[$o$  for x in select * from jsonb_array_elements(v_keep) loop
    insert into catalogue.course_entry_requirements$o$,
       $n$  -- D-R2 (Platform Admin 2 Nov 2026 23:24): the corrected read replaces the waiting one only when it is complete and the waiting one is still
  -- undecided, unclaimed and unlocked; then, in this transaction, the waiting item becomes 'superseded' (its rows are quarantined by the trigger)
  if v_sup.id is not null then
    select * into v_old from pipeline.layer4_review_items where id = v_sup.old_item_id for update;
    v_chk := security.course_entry_correction_check_v1(v_sup.old_item_id, i.course_id, g.url, v_keep, v_drop);
    if not coalesce((v_chk->>'ok')::boolean, false) then
      update pipeline.field_enrich_items set state = 'skipped', reason = left('corrected read refused (D-R2): ' || (v_chk->>'why'), 300),
             value = jsonb_build_object('rows_read', v_keep, 'dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage', 'supersession', v_sup.id), updated_at = now()
       where id = i.id;
      perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', v_chk->>'why', null, v_chk->'diff');
      return 'not_admitted';
    end if;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where id = v_old.id and status = 'pending';
  end if;
  for x in select * from jsonb_array_elements(v_keep) loop
    insert into catalogue.course_entry_requirements$n$],
 array[$o$    update pipeline.field_enrich_items set state = 'skipped', reason = 'no row met the admission rules', value = jsonb_build_object('dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at = now() where id = i.id;
$o$,
       $n$    update pipeline.field_enrich_items set state = 'skipped', reason = 'no row met the admission rules', value = jsonb_build_object('dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at = now() where id = i.id;
    if v_sup.id is not null then perform security.aer_read_supersession_close_v1(v_sup.id, 'refused', 'no row of the corrected read met the admission rules', null, null); end if;
$n$],
 array[$o$  returning id into v_review;
$o$,
       $n$  returning id into v_review;
  if v_sup.id is not null then
    -- D-R2: the new item carries the reviewer's diff and names the read it replaced; nothing is approved
    update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('supersedes', coalesce(v_chk->'diff', '{}'::jsonb)
             || jsonb_build_object('review_item_id', v_sup.old_item_id, 'request_id', v_sup.id, 'reason', v_sup.reason, 'requested_by', v_sup.requested_by,
                                   'new_evidence_id', coalesce(i.evidence_id, g.evidence_id)))
     where id = v_review;
    perform security.aer_read_supersession_close_v1(v_sup.id, 'superseded', null, v_review, v_chk->'diff');
  end if;
$n$]],
 array[1, 1, 1, 1, 1, 1, 1, 1, 1]);

-- ---------------------------------------------------------------- 6. the review screen: matrix gate, supersession
select pg_temp.edit_once('security.aer_review_read_v1(uuid)', '50c31fc4df16b7bbbb39dab03aa9f9b2', '9b4aed8b80471beaac513cdf0aa55e3d', array[
 array[$o$    'completeness_gate', case when i.field_code = 'course_entry_first_read' then security.course_entry_gate_v1(i.id) end,$o$,
       $n$    'completeness_gate', case when i.field_code = 'course_entry_first_read' then security.course_entry_gate_v1(i.id)
                              -- D-R3: a matrix run's whole-read completeness; approval is held while incomplete
                              else security.entry_matrix_gate_v1((select x.id from pipeline.entry_matrix_runs x where x.review_item_id = i.id)) end,
    -- D-R2: the read this item replaced (with the reviewer's diff), and for a replaced item the item that replaced it
    'supersedes', i.proposed_value->'supersedes',
    'superseded_by', (select jsonb_build_object('review_item_id', s.new_item_id, 'at', s.closed_at, 'reason', s.reason) from pipeline.aer_read_supersessions s
                       where s.old_item_id = i.id and s.state = 'superseded' order by s.closed_at desc limit 1),$n$]],
 array[1]);
