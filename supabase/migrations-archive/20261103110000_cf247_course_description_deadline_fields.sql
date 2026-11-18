-- CF-247 Workstream C: course description and application deadline are read by the platform (Platform Admin direction 3 Nov 2026 09:32,
-- platform-led enrichment; acceptance report 2026-11-03-platform-enrichment-control-autonomy-acceptance-report.md item 1).
-- Why (live, read-only, 3 Nov 2026 10:10-10:40 AEDT): pipeline.field_register has reader 'none' for description and deadline; neither is in
--   security.enrich_fields_v1, so no Enrich fields task, no standing gap-queue item, no enrichment-plan step and no worker mode reads them.
--   163 of about 35,700 active courses hold a description (catalogue.courses.description, read by public.website_v2_course); no
--   catalogue.course_intakes.application_deadline was ever filled from a course page.
-- What (the existing Enrich fields engine; no new engine, job or screen):
--   1 security.enrich_fields_v1 (md5-guarded edit): fields description ('Course description') and deadline ('Application deadline'), sources
--     ai_stored and scraper allowed; the starting rule (pipeline.field_source_rules, ALL) is ai_stored only: the stored course page, no new
--     read. Enrich fields (preview, start, rules), Stalled fields Fill now, the standing gap queue and the enrichment plan's "Fill missing
--     fields" step all take the field list from this function.
--   2 Items: public.admin_enrich_fields (md5-guarded edit of the v2.15.419 definition: its in-flight, published-provider, retry, export and
--     estimate rules kept) counts and creates them (description: none held; deadline: the course has active
--     intakes and none has a deadline); security.field_gap_queue_tick_v1 (md5-guarded edit) adds them through
--     security.enrich_course_text_gaps_v1: only courses with a stored page, at most enrich.course_text_items_per_day new standing items a
--     day for each field, with the queue's own rules (locks, holds, unpublished providers, recheck days, items in progress).
--   3 The worker (coverage-sweep v0.59.4, mode enrich_ai, course-text.ts) reads both from the stored course page leased with the item (the
--     slice's existing rule: the bound page with an identity proof), in one call per course with the central model, every quote checked
--     against the page. public.svc_enrich_ai_record (md5-guarded edit) passes them to security.enrich_course_text_record_v1.
--   4 Course description admission (security.course_description_check_v1, the provider description rules): the course's own bound page
--     only (the item's stored copy is the page bound to the course; the country's page proofs for 'description'); 1 to N complete sentences
--     about this course, each quoted from the page, no marketing word or claim that is not in its quote, each sentence supported by its
--     quote, the length within the settings (held, never cut, when too long, too short or a fragment), not the same text as another course
--     of the provider (boilerplate). A provider's first descriptions go to Layer 4 (field_code course_description_first_read, shown with the
--     description review: approved as read or rejected); once enrich.course_description_review_first of the provider's latest decisions are
--     all approvals, its descriptions that pass every check are admitted without a person, and those held while waiting are admitted then.
--     At most enrich.course_description_pending_max wait in Layer 4 per provider; the rest are held with their reading kept (no AI spent again).
--     Admission writes catalogue.courses.description only when none is held and the course is not locked by hand.
--   5 Application deadline admission: an explicit date only (kind date, YYYY-MM-DD, the day, month and year printed in the quote, the quote on
--     the page), tied to the intake the page names (matched to the course's active intakes by month or period words and year) or, when the
--     page gives one deadline, to the course's only active intake; not after the intake's start and not more than
--     intake_dates.deadline_max_days_before before it; never over a deadline held; never inferred. Rolling and not stated are kept on the item.
--     Admission writes catalogue.course_intakes.application_deadline (read by the search projection and the Website API v2 course item).
--   6 Layer 4: security.layer4_review_decide_impl (md5-guarded edit) applies an approval through security.layer4_course_description_apply_v1;
--     security.layer4_inbox_items_v1 (md5-guarded edit) lists the items with the description kind; trigger
--     layer4_review_items_course_description settles the Enrich fields item.
--   7 Coverage: field_register reader 'enrich' for both; security.enrich_coverage_snapshot_v1 and security.field_stalled_v1 (md5-guarded edits)
--     count them and offer Fill now. The country page proofs for description and deadline are those already approved for intakes.
-- Spend: no Firecrawl or AI budget is raised. Reads use the stored page (the scraper source is not in the starting rule); AI calls go through
--   the existing enrich_fields lane and its guard (openrouter guard_enrich_fields).
-- Consumer API (G3): unchanged. Values are written only into existing columns the API already reads (catalogue.courses.description by
--   public.website_v2_course; catalogue.course_intakes.application_deadline through the search projection). No consumer object changes.
--   Rolling deadlines have no consumer field and are not published.
-- Replaces: security.enrich_fields_v1, public.svc_enrich_ai_record, public.admin_enrich_fields, security.field_gap_queue_tick_v1, security.field_stalled_v1, security.enrich_coverage_snapshot_v1, security.layer4_review_decide_impl, security.layer4_inbox_items_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. No job is added. The fields ship enabled (register reader enrich); the standing queue's daily item cap is a setting.

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

-- 0. the definitions the new code calls are the ones it was written against (not changed here) ------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.pdesc_has_term_v1(text,text)', 'b2b8d6499c2ad619b68842258ca7e2e3'), ('security.pdesc_support_v1(text,text)', 'adedab4f5da6e6fec8a0d840fea15bde'),
                                 ('security.pdesc_similarity_v1(text,text)', '357a9ebfde1c68a286ad4f685445cf9b'), ('security.coverage_identity_allowed(uuid,text,text)', '8a46ead4d1582d57010a6e3854d99b94'),
                                 ('security.enrich_item_held_v1(uuid,text)', '688da7aedbb7ee3f09f629b497c25579'), ('security.layer4_adapter_field_v1(text)', '9fba6997bbe20728fe3c6017d9ff6c77')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_text_items_per_day', 'Course description and deadline: standing items a day',
  'Most new course description items, and most new application deadline items, the standing gap queue adds in a day (each field). Enrich fields tasks a person starts are sized by their own scope and preview.',
  'number', to_jsonb(500), 0, 20000, 'items', 1101, 'Course description and deadline',
  'security.enrich_course_text_gaps_v1 (job field-gap-queue)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_min_sentences', 'Course description: fewest sentences',
  'A course description with fewer sentences is held (not admitted).', 'number', to_jsonb(1), 1, 5, 'sentences', 1102, 'Course description and deadline',
  'security.course_description_check_v1; worker coverage-sweep enrich_ai (stated to the model)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_max_sentences', 'Course description: most sentences',
  'A course description with more sentences is held whole, never cut.', 'number', to_jsonb(4), 1, 12, 'sentences', 1103, 'Course description and deadline',
  'security.course_description_check_v1; worker coverage-sweep enrich_ai (stated to the model)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_min_chars', 'Course description: shortest',
  'A course description shorter than this (the sentences, not the quotes) is held.', 'number', to_jsonb(80), 20, 1000, 'characters', 1104, 'Course description and deadline',
  'security.course_description_check_v1', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_max_chars', 'Course description: longest',
  'A course description longer than this (the sentences, not the quotes) is held whole, never cut.', 'number', to_jsonb(700), 200, 4000, 'characters', 1105, 'Course description and deadline',
  'security.course_description_check_v1; worker coverage-sweep enrich_ai (stated to the model)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_min_quote_chars', 'Course description: shortest quote',
  'Fewest letters and digits a sentence''s quote has for it to count as found on the page.', 'number', to_jsonb(20), 8, 200, 'characters', 1106, 'Course description and deadline',
  'worker coverage-sweep enrich_ai (course-text.ts)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'enrich.course_description_review_first', 'Course description: decided by a person first',
  'A provider''s course descriptions go to Layer 4 until this many of its latest decided ones are all approvals; then a description that passes every check is admitted without a person. A rejection sends the provider''s descriptions back to Layer 4. A very large number keeps every description in Layer 4.',
  'number', to_jsonb(5), 1, 100000, 'descriptions', 1107, 'Course description and deadline',
  'security.course_description_trusted_v1, security.enrich_course_text_record_v1', 'CF-247 Workstream C (3 Nov 2026): Layer 4 on first admission'),
 ('pipeline', 'enrich.course_description_pending_max', 'Course description: waiting in Layer 4 per provider',
  'Most course descriptions of one provider waiting in Layer 4 at once; the rest are held with their reading kept and admitted once the provider''s first ones are approved.',
  'number', to_jsonb(10), 1, 200, 'items', 1108, 'Course description and deadline',
  'security.enrich_course_text_record_v1', 'CF-247 Workstream C (3 Nov 2026): Layer 4 on first admission'),
 ('pipeline', 'enrich.course_description_duplicate_window', 'Course description: descriptions compared',
  'How many of the provider''s latest course descriptions (held or waiting) a new one is compared with; one with the same words (pdesc.duplicate_share) is boilerplate and is held.',
  'number', to_jsonb(500), 50, 5000, 'descriptions', 1109, 'Course description and deadline',
  'security.course_description_check_v1', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers'),
 ('pipeline', 'reading.answer_tokens.course_text', 'AI answer length: course description and deadline',
  'Most tokens of one answer of the course description and deadline read; a cut answer is held, never parsed.', 'number', to_jsonb(1500), 500, 8000, 'tokens', 942, 'AI answer limits',
  'worker coverage-sweep enrich_ai (course-text.ts)', 'CF-247 Workstream C (3 Nov 2026): course description and deadline readers')
on conflict (toolset_key, key) do nothing;
-- the provider description rules are reused: their settings name the new user too
update pipeline.platform_toolset_settings set used_by = used_by || '; security.course_description_check_v1 (course descriptions)', updated_at = now()
 where toolset_key = 'pipeline' and key in ('pdesc.superlatives', 'pdesc.claim_words', 'pdesc.support_min_share', 'pdesc.duplicate_share')
   and coalesce(used_by, '') not like '%course_description_check_v1%';
update pipeline.platform_toolset_settings set used_by = used_by || '; security.enrich_course_text_record_v1 (course page deadlines)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'intake_dates.deadline_max_days_before' and coalesce(used_by, '') not like '%enrich_course_text_record_v1%';

-- 2. register, sources and page proofs -----------------------------------------------------------------------------------------------------
update pipeline.field_register set reader = 'enrich', updated_at = now(),
       fills = case field when 'description' then 'AI reads the stored course page (Enrich fields); Layer 4 for a provider''s first descriptions'
                          else 'AI reads the stored course page (Enrich fields): explicit dates tied to an intake' end,
       reason = 'CF-247 Workstream C (3 Nov 2026, Platform Admin 09:32): reader added'
 where field in ('description', 'deadline') and reader = 'none';
insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_at) values
 ('ALL', 'description', array['ai_stored'], 'CF-247 Workstream C (3 Nov 2026): the AI reads the description from the stored course page', now()),
 ('ALL', 'deadline', array['ai_stored'], 'CF-247 Workstream C (3 Nov 2026): the AI reads the application deadline from the stored course page', now())
on conflict (country_code, field) do nothing;
-- the page proofs a country already approved for intakes (a course page read for the course) admit its description and deadline
update pipeline.coverage_admission_countries a set identities = a.identities || jsonb_build_object('description', a.identities->'intakes'), updated_at = now()
 where a.identities ? 'intakes' and not (a.identities ? 'description');
update pipeline.coverage_admission_countries a set identities = a.identities || jsonb_build_object('deadline', a.identities->'intakes'), updated_at = now()
 where a.identities ? 'intakes' and not (a.identities ? 'deadline');

-- 3. helpers --------------------------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_deadline_missing_v1(p_course uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from catalogue.course_intakes x where x.course_id = p_course and x.status = 'active')
     and not exists (select 1 from catalogue.course_intakes x where x.course_id = p_course and x.status = 'active' and x.application_deadline is not null)
$$;
comment on function security.enrich_deadline_missing_v1(uuid) is 'CF-247 Workstream C (3 Nov 2026): a course''s application deadline is missing when it has active intakes and none has a deadline (the coverage rule).';
revoke all on function security.enrich_deadline_missing_v1(uuid) from public, anon, authenticated;

-- the standing gap queue's course description and deadline items: courses with a stored page, the queue's rules, a daily cap per field
create or replace function security.enrich_course_text_gaps_v1(p_fields text[])
returns table(provider_id uuid, course_id uuid, field text, pri int) language plpgsql security definer set search_path = '' as $$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int;
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc)
      select m.pid, m.cid, f, case when l.state is null then 1
                                    when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end
        from miss m left join last l on l.cid = m.cid
       where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => v_days)
              or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
         and not security.enrich_item_held_v1(m.cid, f)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
       order by 4, m.cid
       limit v_room;
  end loop;
end $$;
comment on function security.enrich_course_text_gaps_v1(text[]) is 'CF-247 Workstream C (3 Nov 2026): course description and application deadline gaps for the standing gap queue: active courses with a stored page, the queue''s rules (locks, holds, unpublished providers, recheck days, in progress), at most enrich.course_text_items_per_day new standing items a day for each field.';
revoke all on function security.enrich_course_text_gaps_v1(text[]) from public, anon, authenticated;

-- a provider whose latest enrich.course_description_review_first decided course descriptions are all approvals
create or replace function security.course_description_trusted_v1(p_provider uuid) returns boolean language sql stable security definer set search_path = '' as $$
  with n as (select greatest(1, security.pipeline_num_v1('enrich.course_description_review_first', 5)::int) k),
  d as (select r.status from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and c.provider_id = p_provider
           and r.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
         order by r.decided_at desc nulls last limit (select k from n))
  select count(*) = (select k from n) and bool_and(d.status in ('approved', 'edited_approved')) from d
$$;
comment on function security.course_description_trusted_v1(uuid) is 'CF-247 Workstream C (3 Nov 2026): Layer 4 on first admission. True when the provider''s latest enrich.course_description_review_first decided course descriptions are all approvals.';
revoke all on function security.course_description_trusted_v1(uuid) from public, anon, authenticated;

-- the provider description rules applied to a course description (security.provider_description_validate_v1, without its About-page rules)
create or replace function security.course_description_check_v1(p_course uuid, p_result jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text; v_sup numeric; v_other record; v_pid uuid;
        v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6); v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_checks jsonb;
begin
  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course;
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if coalesce((p_result->>'about_course')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not state it');
  end if;
  if v_n < security.pipeline_num_v1('enrich.course_description_min_sentences', 1) or v_n > security.pipeline_num_v1('enrich.course_description_max_sentences', 4) then
    return jsonb_build_object('ok', false, 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s words are not on the course page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- a sentence that does not end as a sentence is a fragment: held, never cut or completed (Platform Admin 2 Nov 2026 23:24)
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'rule', 'incomplete_sentence', 'checks', v_checks, 'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('enrich.course_description_min_chars', 80) or length(v_text) > security.pipeline_num_v1('enrich.course_description_max_chars', 700) then
    return jsonb_build_object('ok', false, 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range (held whole, never cut)');
  end if;
  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  select z.course_id, z.sim into v_other from (
    select x.course_id, security.pdesc_similarity_v1(v_text, x.d) sim from (
      select c.id course_id, c.description d, c.updated_at at from catalogue.courses c
       where c.provider_id = v_pid and c.id <> p_course and nullif(btrim(c.description), '') is not null
      union all
      select r.entity_id, r.proposed_value->>'description', r.created_at from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
       where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid and r.entity_id <> p_course
      order by 3 desc limit security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int) x) z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.course_id is not null then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_other_course', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.course_id, 'similarity', v_other.sim),
      'reason', 'the same words as another course''s description (' || v_other.sim || '): text that is not about this course');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'ok', 'text', v_text, 'checks', v_checks, 'reason', null);
end $$;
comment on function security.course_description_check_v1(uuid, jsonb) is 'CF-247 Workstream C (3 Nov 2026): the course description checks (the provider description rules): sentence count, every quote on the page, no unquoted marketing word or claim, complete sentences, each sentence supported by its quote, length within the settings (held, never cut), not another course''s words.';
revoke all on function security.course_description_check_v1(uuid, jsonb) from public, anon, authenticated;

-- does the page's intake wording name this intake (month or period words; a year in the wording must be the intake's)
create or replace function security.course_deadline_intake_match_v1(p_label text, p_year int, p_text text) returns boolean language sql immutable set search_path = '' as $$
  with n as (select lower(btrim(coalesce(p_label, ''))) l,
                    regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_text, '')), '\mone\M', '1', 'g'), '\mtwo\M', '2', 'g'), '\mthree\M', '3', 'g'), '\s+', ' ', 'g') t)
  select n.l <> '' and n.t <> ''
     and case when n.l ~ '^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*$' then n.t ~ ('\m' || left(n.l, 3))
              else n.t ~ ('\m' || regexp_replace(n.l, '([^a-z0-9 ])', '\\\1', 'g') || '\M') end
     and (p_year is null or n.t !~ '\m(19|20)\d\d\M' or n.t ~ ('\m' || p_year || '\M'))
    from n
$$;
comment on function security.course_deadline_intake_match_v1(text, integer, text) is 'CF-247 Workstream C (3 Nov 2026): whether the page''s intake wording names an intake (its month, or its period words such as Semester 1; a year in the wording must be the intake''s year).';

-- is the date printed in the quote (its year, its day, and its month by name or in a numeric date)
create or replace function security.course_deadline_in_quote_v1(p_date date, p_quote text) returns boolean language sql immutable set search_path = '' as $$
  with q as (select lower(coalesce(p_quote, '')) t, extract(year from p_date)::int y, extract(month from p_date)::int m, extract(day from p_date)::int d,
                    lower(left(to_char(p_date, 'FMMonth'), 3)) mn)
  select p_date is not null and q.t ~ ('\m' || q.y || '\M') and q.t ~ ('\m0?' || q.d || '(st|nd|rd|th)?\M')
     and (q.t ~ ('\m' || q.mn) or q.t ~ ('\m0?' || q.d || '[/.-]0?' || q.m || '[/.-]' || q.y || '\M') or q.t ~ ('\m' || q.y || '-0?' || q.m || '-0?' || q.d || '\M'))
    from q
$$;
comment on function security.course_deadline_in_quote_v1(date, text) is 'CF-247 Workstream C (3 Nov 2026): a deadline is admitted only when the quote prints its year, its day and its month (never inferred).';

-- 4. admission of a reading (from public.svc_enrich_ai_record) --------------------------------------------------------------------------
create or replace function security.enrich_course_text_record_v1(p_item bigint, p_r jsonb) returns text language plpgsql security definer set search_path = '' as $$
declare i pipeline.field_enrich_items%rowtype; g record; v_chk jsonb; v_text text; v_review uuid; v_pid uuid; v_n int := 0; x jsonb; it record;
        v_date date; v_kept jsonb := '[]'::jsonb; v_dl jsonb := '[]'::jsonb; v_why text; v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
        v_targets uuid[]; v_one uuid; v_kinds text[];
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.course_id is null or i.field not in ('description', 'deadline') then return 'nothing'; end if;
  select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at into g
    from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
  if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, i.field) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit ' || i.field || ' for this country',
           value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  -- only the course's own page: the stored copy read is the copy bound to the course now
  if i.evidence_id is distinct from g.evidence_id then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the copy read is no longer the course''s bound page (it is read again with the new copy)', value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.course_id
               and l.field in (i.field, case i.field when 'deadline' then 'intake' else 'course_description' end, 'all')) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', value = p_r->'value', updated_at = now() where id = i.id;
    return 'locked';
  end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = i.course_id;

  if i.field = 'description' then
    if exists (select 1 from catalogue.courses c where c.id = i.course_id and nullif(btrim(c.description), '') is not null) then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'already filled', value = p_r->'value', updated_at = now() where id = i.id; return 'already';
    end if;
    v_chk := security.course_description_check_v1(i.course_id, p_r->'value');
    if not coalesce((v_chk->>'ok')::boolean, false) then
      update pipeline.field_enrich_items set state = 'skipped', value = coalesce(p_r->'value', '{}'::jsonb) || jsonb_build_object('check', v_chk),
             reason = left(case when v_chk->>'rule' = 'not_stated' then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                                else 'held: ' || (v_chk->>'rule') || ': ' || (v_chk->>'reason') end, 300), updated_at = now()
       where id = i.id;
      return case when v_chk->>'rule' = 'not_stated' then 'not_stated' else 'held' end;
    end if;
    v_text := v_chk->>'text';
    if security.course_description_trusted_v1(v_pid) then
      update catalogue.courses set description = v_text, updated_at = now() where id = i.course_id and nullif(btrim(description), '') is null;
      get diagnostics v_n = row_count;
      update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end, reason = case when v_n > 0 then null else 'already filled' end,
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'admitted', 'checks (provider''s first descriptions approved in Layer 4)'),
             quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
       where v_n > 0 and not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
      return case when v_n > 0 then 'filled' else 'already' end;
    end if;
    -- Layer 4 on first admission: at most enrich.course_description_pending_max of the provider's wait at once; the rest keep their reading
    if (select count(*) from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid)
       >= security.pipeline_num_v1('enrich.course_description_pending_max', 10) then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved',
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk), quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      return 'held_first_admission';
    end if;
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', i.course_id, 'course_description_first_read', g.evidence_id, jsonb_build_object('description', null),
            jsonb_build_object('description', v_text, 'item_id', i.id, 'source_url', g.url, 'checks', v_chk->'checks',
                               'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(p_r->'value'->'sentences') with ordinality e(s, o))),
            jsonb_build_object('source', 'course description reader', 'page', g.url, 'identity_basis', g.identity_basis),
            jsonb_build_object('item_id', i.id, 'model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker'),
            'pending', 'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.',
            'CF-CHG-20260915-247')
    returning id into v_review;
    update pipeline.field_enrich_items set state = 'review', reason = null, value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'review_item_id', v_review),
           quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
    return 'review';
  end if;

  -- deadline: explicit dates only, tied to an intake the page names (or the course's only active intake)
  if not exists (select 1 from catalogue.course_intakes x where x.course_id = i.course_id and x.status = 'active') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'no active intake to hold a deadline', value = p_r->'value', updated_at = now() where id = i.id; return 'not_admitted';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_r->'value'->'deadlines', '[]'::jsonb)) loop
    v_why := null; v_targets := '{}'; v_date := null;
    if x->>'kind' <> 'date' then v_why := coalesce(x->>'kind', 'not_stated');
    elsif not coalesce((x->>'on_page')::boolean, false) then v_why := 'quote_not_on_page';
    elsif coalesce(x->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then v_why := 'no_full_date';
    else
      begin v_date := (x->>'date')::date; exception when others then v_date := null; end;
      if v_date is null then v_why := 'no_full_date';
      elsif not security.course_deadline_in_quote_v1(v_date, x->>'quote') then v_why := 'date_not_in_quote';
      end if;
    end if;
    if v_why is null then
      if nullif(btrim(x->>'intake'), '') is null then
        select array_agg(ci.id) into v_targets from catalogue.course_intakes ci where ci.course_id = i.course_id and ci.status = 'active';
        if cardinality(v_targets) <> 1 then v_why := 'not_tied_to_one_intake'; v_targets := '{}'; end if;
      else
        select coalesce(array_agg(ci.id), '{}') into v_targets from catalogue.course_intakes ci
         where ci.course_id = i.course_id and ci.status = 'active' and security.course_deadline_intake_match_v1(ci.intake_label, ci.intake_year, x->>'intake');
        if cardinality(v_targets) = 0 then v_why := 'intake_not_matched'; end if;
      end if;
    end if;
    v_dl := v_dl || (x || jsonb_build_object('outcome', coalesce(v_why, 'kept'), 'intake_ids', to_jsonb(v_targets)));
    if v_why is null then
      foreach v_one in array v_targets loop v_kept := v_kept || jsonb_build_object('intake_id', v_one, 'date', v_date, 'quote', x->>'quote'); end loop;
    end if;
  end loop;
  -- per intake: one date only (two different dates for one intake are held), within the intake's window, never over a deadline held
  for it in select ci.id, ci.start_date, ci.intake_year, ci.application_deadline, array_agg(distinct (k->>'date')::date) dates, min(k->>'quote') quote
              from jsonb_array_elements(v_kept) k join catalogue.course_intakes ci on ci.id = (k->>'intake_id')::uuid group by 1, 2, 3, 4 loop
    if cardinality(it.dates) > 1 then v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'conflicting_dates'); continue; end if;
    v_date := it.dates[1];
    if it.application_deadline is not null then continue; end if;
    if (it.start_date is not null and (v_date > it.start_date or v_date < it.start_date - v_max_before))
       or (it.start_date is null and it.intake_year is not null and (v_date < make_date(it.intake_year - 1, 1, 1) or v_date > make_date(it.intake_year, 12, 31))) then
      v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'outside_intake_window', 'date', v_date); continue;
    end if;
    update catalogue.course_intakes set application_deadline = v_date where id = it.id and application_deadline is null;
    if found then v_n := v_n + 1; end if;
  end loop;
  v_kinds := array(select distinct d->>'outcome' from jsonb_array_elements(v_dl) d);
  update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end,
         value = jsonb_build_object('deadlines', v_dl, 'applied', v_n),
         quote = left(coalesce((select k->>'quote' from jsonb_array_elements(v_kept) k limit 1), p_r->>'quote', i.quote), 300),
         reason = case when v_n > 0 then null
                       when cardinality(v_kinds) = 0 or v_kinds <@ array['not_stated'] then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                       when v_kinds <@ array['rolling', 'not_stated'] then 'the page says applications are rolling (no date to hold)'
                       when 'kept' = any (v_kinds) then 'already filled or outside the intake''s dates'
                       else left('held: ' || array_to_string(v_kinds, ', '), 300) end,
         updated_at = now()
   where id = i.id;
  if v_n > 0 then
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return case when v_n > 0 then 'filled' else 'not_admitted' end;
end $$;
comment on function security.enrich_course_text_record_v1(bigint, jsonb) is 'CF-247 Workstream C (3 Nov 2026): admits an Enrich fields reading of a course description (checks, then Layer 4 for a provider''s first descriptions) or of application deadlines (explicit dates in the quote, tied to an intake, within its dates). Only into catalogue.courses.description and catalogue.course_intakes.application_deadline when empty; never over a lock.';
revoke all on function security.enrich_course_text_record_v1(bigint, jsonb) from public, anon, authenticated;

-- 5. Layer 4: approval writes the description; the decision settles the item; held readings follow once the provider is trusted -----------
create or replace function security.course_description_release_held_v1(p_provider uuid) returns integer language plpgsql security definer set search_path = '' as $$
declare r record; v_n int := 0; v_k int;
begin
  if p_provider is null or not security.course_description_trusted_v1(p_provider) then return 0; end if;
  for r in select e.id, e.course_id, e.value->>'text' txt from pipeline.field_enrich_items e join pipeline.coverage_course_pages g on g.course_id = e.course_id
            where e.provider_id = p_provider and e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'
              and nullif(btrim(e.value->>'text'), '') is not null and e.evidence_id is not distinct from g.evidence_id
            for update of e skip locked loop
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('description', 'course_description', 'all')) then continue; end if;
    -- the checks are run again (another course may have taken the same words since)
    if not coalesce((security.course_description_check_v1(r.course_id, (select e.value from pipeline.field_enrich_items e where e.id = r.id))->>'ok')::boolean, false) then continue; end if;
    update catalogue.courses set description = r.txt, updated_at = now() where id = r.course_id and nullif(btrim(description), '') is null;
    get diagnostics v_k = row_count;
    update pipeline.field_enrich_items set state = case when v_k > 0 then 'filled' else 'skipped' end, reason = case when v_k > 0 then null else 'already filled' end,
           value = value || jsonb_build_object('admitted', 'held, admitted once the provider''s first descriptions were approved'), updated_at = now() where id = r.id;
    v_n := v_n + v_k;
  end loop;
  if v_n > 0 then
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return v_n;
end $$;
comment on function security.course_description_release_held_v1(uuid) is 'CF-247 Workstream C (3 Nov 2026): once a provider''s first course descriptions are approved in Layer 4, its descriptions held while they waited (same bound page, checks passed again) are admitted.';
revoke all on function security.course_description_release_held_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_course_description_apply_v1(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_shown text;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then raise exception 'not a course description item' using errcode = '22023'; end if;
  -- approved as read: an edited description has no quote for its new words (reject it; the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('description', 'course_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(c.description), '') into v_now from catalogue.courses c where c.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.courses set description = v_text, updated_at = now() where id = i.entity_id;
  select c.description into v_shown from catalogue.courses c where c.id = i.entity_id;  -- the column public.website_v2_course reads
  return jsonb_build_object('course_id', i.entity_id, 'description_chars', length(v_text), 'held', v_shown = v_text, 'evidence_id', i.evidence_id, 'actor', p_actor);
end $$;
comment on function security.layer4_course_description_apply_v1(uuid, uuid, jsonb, text) is 'CF-247 Workstream C (3 Nov 2026): a Layer 4 approval of a course description, as read (never edited), writes catalogue.courses.description when it is unchanged since the proposal and not locked.';
revoke all on function security.layer4_course_description_apply_v1(uuid, uuid, jsonb, text) from public, anon, authenticated;

create or replace function security.course_description_review_trg_v1() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_item bigint := case when coalesce(new.proposed_value->>'item_id', '') ~ '^\d+$' then (new.proposed_value->>'item_id')::bigint end; v_pid uuid;
begin
  if v_item is not null then
    update pipeline.field_enrich_items set state = case when new.status in ('approved', 'edited_approved') then 'filled' else 'skipped' end,
           reason = case when new.status in ('approved', 'edited_approved') then null else 'not admitted in Layer 4 (' || new.status || ')' end, updated_at = now()
     where id = v_item and state = 'review';
  end if;
  if new.status in ('approved', 'edited_approved') then
    select c.provider_id into v_pid from catalogue.courses c where c.id = new.entity_id;
    perform security.course_description_release_held_v1(v_pid);
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return null;
end $$;
comment on function security.course_description_review_trg_v1() is 'CF-247 Workstream C (3 Nov 2026): trigger layer4_review_items_course_description: a decided course description settles its Enrich fields item (filled, or skipped with the decision); an approval admits the provider''s held descriptions once it is trusted.';
revoke all on function security.course_description_review_trg_v1() from public, anon, authenticated;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.layer4_review_items'::regclass and tgname = 'layer4_review_items_course_description') then
    create trigger layer4_review_items_course_description after update of status on pipeline.layer4_review_items for each row
      when (old.status = 'pending' and new.status <> 'pending' and new.field_code = 'course_description_first_read') execute function security.course_description_review_trg_v1();
  end if;
end $t$;

-- 6. md5-guarded edits of the existing engine --------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_fields_v1()', '0efc2f55d0f1e285225be7a10a28f4c1', '80ee183b324c196b4c9559cec6e3360f', array[[
$o$    ('campus_region', 'Campus region (state)', 'provider', array['ai_city'], 10)) v(field, label, level, sources, sort)$o$,
$n$    ('campus_region', 'Campus region (state)', 'provider', array['ai_city'], 10),
    -- 3 Nov 2026 (CF-247 Workstream C, Platform Admin 09:32): course description and application deadline from the course page
    ('description', 'Course description', 'course', array['ai_stored', 'scraper'], 11),
    ('deadline', 'Application deadline', 'course', array['ai_stored', 'scraper'], 12)) v(field, label, level, sources, sort)$n$]], array[1]);

select pg_temp.edit_once('public.svc_enrich_ai_record(jsonb)', '264ab812e37f4c1877bdafbdb43147b1', 'ae1ced1c1f1fd092afe885cfc37be0b4', array[[
$o$    elsif i.field = 'campus_list' then
$o$,
$n$    elsif i.field in ('description', 'deadline') then
      -- CF-247 Workstream C (3 Nov 2026): course description and application deadline from the stored course page
      v_k := security.enrich_course_text_record_v1(i.id, r);
    elsif i.field = 'campus_list' then
$n$]], array[1]);

select pg_temp.edit_once('security.field_gap_queue_tick_v1()', 'd909e54d6b6de0f8d2893fbb2d8553bd', '387f8edbe3363ea52317e024d96f2369', array[[
$o$   limit v_cap;
$o$,
$n$   limit v_cap;
  -- CF-247 Workstream C (3 Nov 2026): course description and application deadline, at most enrich.course_text_items_per_day a day each
  insert into _gap select t.provider_id, t.course_id, t.field, t.pri from security.enrich_course_text_gaps_v1(v_fields) t;
$n$]], array[1]);

select pg_temp.edit_once('public.admin_enrich_fields(text,jsonb)', '349584fc0e9b605e1067cbbd488e435a', '476062fa6437a4266ab6716fad0021c4', array[
 [$o$                                        when 'provider_address' then (select count(*) from catalogue.providers p where p.id in (select provider_id from scope) and nullif(btrim(p.address_line1), '') is null) end,$o$,
  $n$                                        when 'provider_address' then (select count(*) from catalogue.providers p where p.id in (select provider_id from scope) and nullif(btrim(p.address_line1), '') is null)
                                        -- CF-247 Workstream C (3 Nov 2026): course description; application deadline (active intakes, none dated)
                                        when 'description' then (select count(*) from scope s join catalogue.courses c on c.id = s.id where nullif(btrim(c.description), '') is null)
                                        when 'deadline' then (select count(*) from scope s where security.enrich_deadline_missing_v1(s.id)) end,$n$],
 [$o$                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') else false end$o$,
  $n$                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active')
                    when 'description' then nullif(btrim(c.description), '') is null when 'deadline' then security.enrich_deadline_missing_v1(c.id) else false end$n$]], array[1, 1]);

select pg_temp.edit_once('security.field_stalled_v1()', '702dc1da52bd7272c913ad287b7c8b06', 'a964f1dcf244909453835b1ceda4e3b6', array[[
$o$'international', 'p_address'),$o$, $n$'international', 'p_address', 'description', 'deadline'),$n$]], array[1]);

select pg_temp.edit_once('security.enrich_coverage_snapshot_v1()', '1f94cdee31ec466dc0e83e30728c5596', '242b178c5d924ec359f2f10b796925f0', array[
 [$o$when 'english' then s.has_english when 'intakes' then s.has_intakes else false end)$o$,
  $n$when 'english' then s.has_english when 'intakes' then s.has_intakes
                                           when 'description' then s.has_description when 'deadline' then s.has_deadline else false end)$n$],
 [$o$                 exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') has_intakes
$o$,
  $n$                 exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') has_intakes,
                 nullif(btrim(c.description), '') is not null has_description,
                 exists (select 1 from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active' and x.application_deadline is not null) has_deadline
$n$]], array[1, 1]);

select pg_temp.edit_once('security.layer4_review_decide_impl(uuid,text,text,jsonb)', '073889b7c5319019b25212ce08705a37', '55353f1903c97b268255c8c1e4f5ca6f', array[[
$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then
$o$,
$n$    elsif v_item.entity_type='course' and v_item.field_code='course_description_first_read' then
      -- CF-247 Workstream C (3 Nov 2026): a course description is admitted as read, never edited; the item is settled by trigger
      v_scalar:=security.layer4_course_description_apply_v1(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then
$n$]], array[1]);

select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'c31b009df674a4a6ff531f00b99a9a45', 'a56bc3313e02ac0611deb5657da95ce0', array[[
$o$              when r.entity_type = 'provider' and r.field_code = 'provider_description' then 'provider_description'  -- CF-247 P1 (2 Nov 2026): university descriptions
$o$,
$n$              when r.entity_type = 'provider' and r.field_code = 'provider_description' then 'provider_description'  -- CF-247 P1 (2 Nov 2026): university descriptions
              when r.entity_type = 'course' and r.field_code = 'course_description_first_read' then 'provider_description'  -- CF-247 Workstream C (3 Nov 2026): course descriptions, the same review (approve as read or reject)
$n$]], array[1]);

-- 7. housekeeping: the register ------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.enrich_deadline_missing_v1', 'Enrichment', 'Workstream C: whether a course''s application deadline is missing (active intakes, none dated)', 'active', '{}', '20261103110000'),
 ('function', 'security.enrich_course_text_gaps_v1', 'Enrichment', 'Workstream C: course description and deadline gaps for the standing gap queue (daily cap per field)', 'active', '{}', '20261103110000'),
 ('function', 'security.course_description_trusted_v1', 'Enrichment', 'Workstream C: a provider whose first course descriptions were approved in Layer 4', 'active', '{}', '20261103110000'),
 ('function', 'security.course_description_check_v1', 'Enrichment', 'Workstream C: course description checks (the provider description rules)', 'active', '{}', '20261103110000'),
 ('function', 'security.course_deadline_intake_match_v1', 'Enrichment', 'Workstream C: the page''s intake wording names a course intake', 'active', '{}', '20261103110000'),
 ('function', 'security.course_deadline_in_quote_v1', 'Enrichment', 'Workstream C: a deadline''s year, day and month are printed in its quote', 'active', '{}', '20261103110000'),
 ('function', 'security.enrich_course_text_record_v1', 'Enrichment', 'Workstream C: admission of a course description or deadline reading (Enrich fields)', 'active', '{}', '20261103110000'),
 ('function', 'security.course_description_release_held_v1', 'Layer 4', 'Workstream C: admits a trusted provider''s held course descriptions', 'active', '{}', '20261103110000'),
 ('function', 'security.layer4_course_description_apply_v1', 'Layer 4', 'Workstream C: a Layer 4 approval writes the course description', 'active', '{}', '20261103110000'),
 ('function', 'security.course_description_review_trg_v1', 'Layer 4', 'Workstream C: trigger layer4_review_items_course_description (settles the Enrich fields item)', 'active', '{}', '20261103110000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '3 Nov 2026 (20261103110000): course description and deadline fields', updated_at = now()
 where kind = 'function' and name in ('security.enrich_fields_v1', 'public.svc_enrich_ai_record', 'public.admin_enrich_fields', 'security.field_gap_queue_tick_v1', 'security.field_stalled_v1',
                                      'security.enrich_coverage_snapshot_v1', 'security.layer4_review_decide_impl', 'security.layer4_inbox_items_v1')
   and coalesce(note, '') not like '%20261103110000%';

select 'CF-247 Workstream C: course description and application deadline in Enrich fields' ok;
