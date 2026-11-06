-- CF-247 Course descriptions, the complete capability (Platform Admin 6 Nov 2026 09:44 §2, §4, §5; plan docs/platform/work-packages/2026-11-06-course-descriptions-implementation-plan.md).
-- Migration family 20261106500000-20261106549999 (reserved for course descriptions).
--
-- What this adds (the reader, the checks, the Layer 4 admission and the screens already exist: v2.15.422 and later):
--   1. D2: a course-description claim-word list (enrich.course_description_claim_words) and D5: a course-description marketing-word list
--      (enrich.course_description_marketing_words), each seeded from today's pdesc.claim_words / pdesc.superlatives, so the effective policy on the
--      day of release is identical. "students" stays in the list: it is evaluated with production-matched examples (course_description_claim_eval_v1)
--      before any decision removes it, and every rule is run again after every correction.
--   2. D3: the 700-character and four-sentence limits are unchanged (existing settings).
--   3. D4: enrich.course_description_reask_max (ships 0 = off). The worker re-asks once for a length or sentence-count breach when it is set to 1.
--   4. D1: no admission path changes. Every description still waits in Layer 4 (enrich.course_description_review_first is untouched); nothing is
--      admitted by this migration and AI text is never counted as admitted or published.
--   5. Read-only reconciliation of the pending Layer 4 descriptions, a reviewer queue in the shape the Layer 4 Inbox already renders, the held
--      reasons, the claim-word evaluation and the stratified trust-policy sample (30 AU / 15 NZ / 5 CA, subject to availability). All of it is
--      measurement; none of it can admit, decide or change a setting.
--
-- Replaces: security.course_description_check_v1 (the same rules, now a wrapper of security.course_description_check_with_v1, which reads the course lists)
-- Retires: nothing (the course-description use of pdesc.claim_words and pdesc.superlatives is replaced by the new course lists; the provider settings stay)
-- Consumer API: untouched (G3). catalogue.courses.description is not written here; no website_v2_*, api.* or edge function is read or changed.
-- Guards: the live md5 of security.course_description_check_v1 read from production 6 Nov 2026 14:01 AEDT: ff3d6dd7b0f88c85b1fdff6c8a8cd86b.

do $guard$
declare v_md5 text := md5(pg_get_functiondef('security.course_description_check_v1(uuid,jsonb)'::regprocedure));
begin
  if v_md5 <> 'ff3d6dd7b0f88c85b1fdff6c8a8cd86b'
     and pg_get_functiondef('security.course_description_check_v1(uuid,jsonb)'::regprocedure) not like '%course_description_check_with_v1%' then
    raise exception 'security.course_description_check_v1 is % and not the guarded definition ff3d6dd7b0f88c85b1fdff6c8a8cd86b (nor already replaced); re-read it and re-plan', v_md5;
  end if;
end $guard$;

-- 1. settings (G2): every value has a label, a range, a unit and a used_by line ------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
select 'pipeline', 'enrich.course_description_claim_words', 'Course description: claim words',
       'Words that make a ranking, outcome, facility or accreditation claim; a course description sentence may use one only when the same word is inside the sentence''s quote. Seeded from the provider list (pdesc.claim_words) so today''s policy is unchanged; it is edited here, with a reason, without touching provider descriptions. "students" is evaluated (Enrich fields, Course descriptions, Claim words) before it is removed.',
       'list', s.value, null, null, 'words', 1118, 'Course description and deadline', 'security.course_description_check_with_v1 (security.course_description_check_v1)',
       'CF-247 Platform Admin 6 Nov 2026 D2: a separate course-description claim-word list, initially identical to the provider list'
  from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'pdesc.claim_words'
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
select 'pipeline', 'enrich.course_description_marketing_words', 'Course description: marketing words',
       'Words and phrases that may appear in a course description sentence only inside the sentence''s quote. Seeded from the provider list (pdesc.superlatives) so today''s policy is unchanged.',
       'list', s.value, null, null, 'words', 1119, 'Course description and deadline', 'security.course_description_check_with_v1 (security.course_description_check_v1)',
       'CF-247 Platform Admin 6 Nov 2026 D5: course-description marketing words separate from the provider rules, effective policy unchanged at release'
  from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'pdesc.superlatives'
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'enrich.course_description_reask_max', 'Course description: re-asks for a length breach',
 'When the AI answer has too many sentences or is too long, the worker asks once more on the same stored page (same pinned model, same answer limit) for a version within the limits. The second answer goes through every check again; nothing is ever cut. 0 = off (ships off; the Controller switches it to 1 as a recorded setting change after the feature is verified, within the existing AI spend limits).',
 'number', '0'::jsonb, 0, 1, 're-asks', 1110, 'Course description and deadline', 'worker coverage-sweep enrich_ai (course-text.ts)',
 'CF-247 Platform Admin 6 Nov 2026 D4: one AI re-ask for length or sentence-count breaches, shipped off'),
('pipeline', 'enrich.course_description_held_days', 'Course description: held reasons window',
 'How many days back the held-reasons report on Enrich fields looks.',
 'number', '7'::jsonb, 1, 30, 'days', 1111, 'Course description and deadline', 'security.course_description_held_reasons_v1 (Enrich fields, Course descriptions)',
 'CF-247 course descriptions 6 Nov 2026: operator visibility of held reasons'),
('pipeline', 'enrich.course_description_report_max', 'Course description: readings re-checked in one report',
 'Most readings one report (reconciliation, held reasons, claim words) runs the full checks again in a single call; the rest are counted without a re-check.',
 'number', '500'::jsonb, 50, 5000, 'readings', 1112, 'Course description and deadline', 'security.course_description_summary_v1, security.course_description_claim_eval_v1',
 'CF-247 course descriptions 6 Nov 2026: bounded read-only reports'),
('pipeline', 'enrich.course_description_examples', 'Course description: examples shown per word',
 'How many example readings the claim-word evaluation shows for each word and kind (suggested harmless, suggested a real claim).',
 'number', '3'::jsonb, 1, 10, 'examples', 1113, 'Course description and deadline', 'security.course_description_claim_eval_v1',
 'CF-247 Platform Admin 6 Nov 2026 D2: production-matched positive and negative examples'),
('pipeline', 'enrich.course_description_sample_countries', 'Course description: trust-policy sample countries',
 'The countries of the stratified trust-policy sample, in order. Each country''s size is enrich.course_description_sample_<code>.',
 'list', '["AU","NZ","CA"]'::jsonb, null, null, 'countries', 1114, 'Course description and deadline', 'security.course_description_sample_ids_v1',
 'CF-247 Platform Admin 6 Nov 2026 §2: stratified sample of 50 (30 Australian, 15 New Zealand, 5 Canadian)'),
('pipeline', 'enrich.course_description_sample_au', 'Course description: sample size, Australia',
 'Descriptions of Australian providers in the trust-policy sample (subject to eligible availability). A measurement only: it never admits anything and never bypasses Layer 4.',
 'number', '30'::jsonb, 0, 200, 'descriptions', 1115, 'Course description and deadline', 'security.course_description_sample_ids_v1',
 'CF-247 Platform Admin 6 Nov 2026 §2: 30 Australian'),
('pipeline', 'enrich.course_description_sample_nz', 'Course description: sample size, New Zealand',
 'Descriptions of New Zealand providers in the trust-policy sample (subject to eligible availability).',
 'number', '15'::jsonb, 0, 200, 'descriptions', 1116, 'Course description and deadline', 'security.course_description_sample_ids_v1',
 'CF-247 Platform Admin 6 Nov 2026 §2: 15 New Zealand'),
('pipeline', 'enrich.course_description_sample_ca', 'Course description: sample size, Canada',
 'Descriptions of Canadian providers in the trust-policy sample (subject to eligible availability).',
 'number', '5'::jsonb, 0, 200, 'descriptions', 1117, 'Course description and deadline', 'security.course_description_sample_ids_v1',
 'CF-247 Platform Admin 6 Nov 2026 §2: 5 Canadian')
on conflict (toolset_key, key) do nothing;
-- the provider lists no longer say they drive course descriptions (metadata only; the values are untouched)
update pipeline.platform_toolset_settings set used_by = replace(used_by, 'security.course_description_check_v1 (course descriptions)', 'course descriptions have their own list: enrich.course_description_claim_words'),
       reason = 'CF-247 Platform Admin 6 Nov 2026 D2: used_by corrected (metadata only)'
 where toolset_key = 'pipeline' and key = 'pdesc.claim_words' and used_by like '%security.course_description_check_v1 (course descriptions)%';
update pipeline.platform_toolset_settings set used_by = replace(used_by, 'security.course_description_check_v1 (course descriptions)', 'course descriptions have their own list: enrich.course_description_marketing_words'),
       reason = 'CF-247 Platform Admin 6 Nov 2026 D5: used_by corrected (metadata only)'
 where toolset_key = 'pipeline' and key = 'pdesc.superlatives' and used_by like '%security.course_description_check_v1 (course descriptions)%';

-- 2. the checks: the same rules in the same order; the two word lists are read from the course settings (D2, D5) ---------------------------------
-- security.course_description_check_with_v1 holds the whole check. Optional word lists let the claim-word evaluation run EVERY rule again with a
-- candidate list; null reads the settings (course list, then the provider list if the course list is missing).
CREATE OR REPLACE FUNCTION security.course_description_check_with_v1(p_course uuid, p_result jsonb, p_claim_words jsonb, p_marketing_words jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text; v_sup numeric; v_other record; v_pid uuid;
        v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6); v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_checks jsonb; v_words text[];
        v_claim jsonb := coalesce(p_claim_words, security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_mkt jsonb := coalesce(p_marketing_words, security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb);
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
    if exists (select 1 from jsonb_array_elements_text(v_mkt) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_claim) w
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
  -- CF-247 IQ-00053 residual: the new text is split into words once, and each other text inline, by the rule of security.pdesc_words_v1 and
  -- security.pdesc_similarity_v1 (distinct lower-case words of 3 or more letters or digits; shared words over all words of both)
  v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_other from (
    select x.course_id, case when cardinality(v_words) = 0 or cardinality(x.wb) = 0 then 0
                             else round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) end sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb from (
      select c.id course_id, c.description d, c.updated_at at from catalogue.courses c
       where c.provider_id = v_pid and c.id <> p_course and nullif(btrim(c.description), '') is not null
      union all
      select r.entity_id, r.proposed_value->>'description', r.created_at from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
       where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid and r.entity_id <> p_course
      order by 3 desc limit security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int) x0) x
      cross join lateral (select count(*) n from unnest(v_words) w where w = any (x.wb)) k) z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.course_id is not null then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_other_course', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.course_id, 'similarity', v_other.sim),
      'reason', 'the same words as another course''s description (' || v_other.sim || '): text that is not about this course');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'ok', 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$
;
revoke all on function security.course_description_check_with_v1(uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.course_description_check_v1(p_course uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 course descriptions (6 Nov 2026): the check is security.course_description_check_with_v1 with the course word lists from settings
  select security.course_description_check_with_v1(p_course, p_result, null, null)
$function$;

-- 3. reconciliation of the pending Layer 4 course descriptions (read only) -----------------------------------------------------------------
-- Every pending course_description_first_read item is placed in exactly one class, in this order: course_inactive, already_filled (the course has
-- a description, so approving would be refused as "changed since proposed"), locked (a hand lock on the description), page_changed (the stored
-- page the reading was made from is no longer the course's bound page), no_reading (the stored AI reading cannot be found), fails_now (the stored
-- reading no longer passes every check; the rule is named) and ready (a person can decide it as read). The classes add up to the pending total.
create or replace function security.course_description_reconcile_v1(p_provider uuid default null, p_recheck boolean default false, p_cap integer default null)
returns table(item_id uuid, provider_id uuid, country text, course_id uuid, course_title text, created_at timestamptz, class text, why text, enrich_item bigint,
              rule text, checks jsonb, reask jsonb, rechecked boolean, evidence_id uuid)
language sql stable security definer set search_path to '' as $function$
  with p as (
    select r.id, r.entity_id, r.evidence_id, r.created_at,
           case when coalesce(r.proposed_value->>'item_id', '') ~ '^\d+$' then (r.proposed_value->>'item_id')::bigint end eid
      from pipeline.layer4_review_items r
     where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'course_description_first_read'),
  j as (
    select p.*, c.provider_id pid, c.lifecycle_status, nullif(btrim(c.description), '') now_desc, coalesce(nullif(c.display_title, ''), c.canonical_title) title,
           k.iso_alpha2::text country, g.evidence_id bound, e.value ev, e.id enrich_id,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('description', 'course_description', 'all')) locked,
           row_number() over (order by p.created_at, p.id) rn
      from p join catalogue.courses c on c.id = p.entity_id
      left join catalogue.providers pv on pv.id = c.provider_id
      left join ref.countries k on k.id = pv.country_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.field_enrich_items e on e.id = p.eid
     where p_provider is null or c.provider_id = p_provider),
  s as (
    select j.*, case when j.lifecycle_status is distinct from 'active' then 'course_inactive'
                     when j.now_desc is not null then 'already_filled'
                     when j.locked then 'locked'
                     when j.bound is distinct from j.evidence_id then 'page_changed'
                     when j.ev is null or jsonb_typeof(j.ev->'sentences') is distinct from 'array' or jsonb_array_length(j.ev->'sentences') = 0 then 'no_reading'
                end static_class,
           coalesce(p_recheck, false) and (p_cap is null or j.rn <= p_cap) do_check
      from j)
  select s.id, s.pid, s.country, s.entity_id, s.title, s.created_at,
         case when s.static_class is not null then s.static_class
              when z.chk is not null and not coalesce((z.chk->>'ok')::boolean, false) then 'fails_now' else 'ready' end,
         case s.static_class when 'course_inactive' then 'The course is no longer active.'
                             when 'already_filled' then 'The course already has a description, so this proposal cannot be approved as read.'
                             when 'locked' then 'The description is locked by hand.'
                             when 'page_changed' then 'The stored page this was read from is no longer the course''s bound page; it is read again with the new copy.'
                             when 'no_reading' then 'The AI reading behind this proposal is not stored, so its checks cannot be shown.'
                             else case when z.chk is not null and not coalesce((z.chk->>'ok')::boolean, false) then 'No longer passes the checks: ' || (z.chk->>'rule') || ': ' || coalesce(z.chk->>'reason', '')
                                       else 'A person can decide this as read.' end end,
         s.enrich_id, z.chk->>'rule', z.chk->'checks', s.ev->'reask', z.chk is not null, s.evidence_id
    from s left join lateral (select security.course_description_check_v1(s.entity_id, s.ev) chk where s.static_class is null and s.do_check) z on true
$function$;
revoke all on function security.course_description_reconcile_v1(uuid, boolean, integer) from public, anon, authenticated;

-- 4. the trust-policy sample (read only): a stable, stratified pick; never an authority to bypass Layer 4 ----------------------------------------
create or replace function security.course_description_sample_pool_v1() returns table(item_id uuid, country text)
language sql stable security definer set search_path to '' as $function$
  -- every course description item a person has decided or can decide now (not superseded, not stale), with its provider's country
  select r.id, k.iso_alpha2::text
    from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
    join catalogue.providers pv on pv.id = c.provider_id join ref.countries k on k.id = pv.country_id
   where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status <> 'superseded'
     and (r.status <> 'pending' or r.id in (select q.item_id from security.course_description_reconcile_v1(null, true, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int) q where q.class = 'ready'))
$function$;
revoke all on function security.course_description_sample_pool_v1() from public, anon, authenticated;

create or replace function security.course_description_sample_ids_v1() returns table(item_id uuid, country text, pick integer)
language sql stable security definer set search_path to '' as $function$
  with strata as (select upper(x) code from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) x),
  ranked as (select el.item_id, el.country, row_number() over (partition by el.country order by md5(el.item_id::text)) rn
               from security.course_description_sample_pool_v1() el where el.country in (select code from strata))
  select ranked.item_id, ranked.country, ranked.rn::int from ranked
   where ranked.rn <= security.pipeline_num_v1('enrich.course_description_sample_' || lower(ranked.country), 0)
$function$;
revoke all on function security.course_description_sample_ids_v1() from public, anon, authenticated;

-- 5. the summary: proposed, held, admitted and published are different measures -----------------------------------------------------------------
create or replace function security.course_description_summary_v1(p_provider uuid default null, p_recheck boolean default false) returns jsonb
language sql stable security definer set search_path to '' as $function$
  with r as (select * from security.course_description_reconcile_v1(p_provider, p_recheck, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int)),
  cls as (select r.class, count(*) n from r group by 1),
  cty as (select coalesce(r.country, '?') country, count(*) n, count(*) filter (where r.class = 'ready') ready from r group by 1),
  l4 as (
    select i.id, i.status, c.id course_id, i.proposed_value->>'description' d, nullif(btrim(c.description), '') cur
      from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
     where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and (p_provider is null or c.provider_id = p_provider)),
  fe as (select f.* from pipeline.field_enrich_items f where f.field = 'description' and (p_provider is null or f.provider_id = p_provider))
  select jsonb_build_object(
    'provider_id', p_provider,
    'pending', (select count(*) from r),
    'by_class', coalesce((select jsonb_object_agg(cls.class, cls.n) from cls), '{}'::jsonb),
    'by_country', coalesce((select jsonb_object_agg(cty.country, jsonb_build_object('pending', cty.n, 'ready', cty.ready)) from cty), '{}'::jsonb),
    'rechecked', (select count(*) from r where r.rechecked),
    'oldest', (select min(r.created_at) from r),
    -- the four measures, never mixed: an AI reading waiting in Layer 4 is neither admitted nor published
    'proposed_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
    'waiting_behind_provider_cap', (select count(*) from fe where fe.state = 'skipped' and fe.reason like 'held\_first\_admission:%'),
    'admitted_by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved') and l4.cur is not distinct from nullif(btrim(l4.d), '')),
    'admitted_without_a_person', (select count(*) from fe where fe.state = 'filled' and coalesce(fe.value->>'admitted', '') <> ''),
    'published_to_the_website', (select count(distinct l4.course_id) from l4 join search.course_documents sd on sd.course_id = l4.course_id
                                   where l4.status in ('approved', 'edited_approved') and l4.cur is not distinct from nullif(btrim(l4.d), '') and nullif(btrim(sd.description), '') = l4.cur
                                     and sd.publication_status = 'published'
                                     and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = l4.course_id)),
    'decided', (select jsonb_object_agg(z.status, z.n) from (select l4.status, count(*) n from l4 group by 1) z),
    'limits', jsonb_build_object('min_sentences', security.pipeline_num_v1('enrich.course_description_min_sentences', 1), 'max_sentences', security.pipeline_num_v1('enrich.course_description_max_sentences', 4),
                                 'min_chars', security.pipeline_num_v1('enrich.course_description_min_chars', 80), 'max_chars', security.pipeline_num_v1('enrich.course_description_max_chars', 700)),
    'reask_max', security.pipeline_num_v1('enrich.course_description_reask_max', 0),
    'review_first', security.pipeline_num_v1('enrich.course_description_review_first', 100000),
    'note', 'Measurement only. A person admits every description in Layer 4; nothing here admits, decides or changes a setting.')
$function$;
revoke all on function security.course_description_summary_v1(uuid, boolean) from public, anon, authenticated;

-- 6. the reviewer queue: items in the shape the Layer 4 Inbox already renders, decided through the Inbox's own decide action ---------------------
create or replace function security.course_description_items_v1(p_provider uuid default null, p_offset integer default 0, p_sample boolean default false) returns jsonb
language sql stable security definer set search_path to '' as $function$
  with r as (
    select q.* from security.course_description_reconcile_v1(p_provider, p_provider is not null, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int) q
     where q.class = 'ready' and (not coalesce(p_sample, false) or q.item_id in (select s.item_id from security.course_description_sample_ids_v1() s))),
  pg as (select r.* from r order by r.created_at, r.item_id limit security.pipeline_num_v1('layer4.inbox_page_size', 25)::int offset greatest(coalesce(p_offset, 0), 0))
  select jsonb_build_object(
    'total', (select count(*) from r),
    'offset', greatest(coalesce(p_offset, 0), 0), 'limit', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'provider_description', 'ref', pg.item_id::text, 'provider_id', pg.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name), 'subject', pg.course_title,
        'why', coalesce(nullif(i.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'ready', true,
        'detail', jsonb_strip_nulls(jsonb_build_object('field_code', i.field_code, 'course_id', pg.course_id, 'course_code', c.course_code,
                    'code_label', case when pg.country = 'AU' then 'CRICOS' else 'Course code' end,
                    'before', i.before_value, 'proposed', i.proposed_value, 'evidence_id', i.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                    'reask', pg.reask, 'in_sample', pg.item_id in (select s.item_id from security.course_description_sample_ids_v1() s),
                    -- the stored reading checked again now, so a card says when its rules have moved since it was proposed
                    'rules_now', case when pg.rechecked then jsonb_build_object('ok', true) else
                                  (select jsonb_build_object('ok', coalesce((z.v->>'ok')::boolean, false), 'rule', z.v->>'rule', 'reason', z.v->>'reason')
                                     from (select security.course_description_check_v1(pg.course_id, e.value) v) z) end)))
        order by pg.created_at, pg.item_id)
      from pg join pipeline.layer4_review_items i on i.id = pg.item_id
      join catalogue.courses c on c.id = pg.course_id
      left join catalogue.providers pv on pv.id = pg.provider_id
      left join pipeline.field_enrich_items e on e.id = pg.enrich_item
      left join pipeline.evidence_artifacts ev on ev.id = i.evidence_id), '[]'::jsonb))
$function$;
revoke all on function security.course_description_items_v1(uuid, integer, boolean) from public, anon, authenticated;

-- 7. held reasons (read only): why readings are held, over the set number of days ------------------------------------------------------------
create or replace function security.course_description_held_reasons_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  with span as (select make_interval(days => security.pipeline_num_v1('enrich.course_description_held_days', 7)::int) s),
  words as (select w from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w),
  f as (select x.* from pipeline.field_enrich_items x, span where x.field = 'description' and x.updated_at >= now() - span.s),
  held as (select f.id, f.value, f.value->'check'->>'rule' rule, nullif(f.value->'check'->'checks'->>'chars', '')::int chars, nullif(f.value->'check'->'checks'->>'sentences', '')::int sentences
             from f where f.state = 'skipped' and f.reason like 'held: %'),
  passed as (select f.* from f where f.state in ('review', 'filled') or (f.state = 'skipped' and f.reason like 'held\_first\_admission:%')),
  claim as (
    select words.w word, h.id from held h cross join lateral jsonb_array_elements(coalesce(h.value->'sentences', '[]'::jsonb)) s cross join words
     where h.rule = 'unsupported_claim' and security.pdesc_has_term_v1(s->>'text', words.w) and not security.pdesc_has_term_v1(s->>'quote', words.w)
     group by words.w, h.id)
  select jsonb_build_object(
    'days', (select extract(day from span.s) from span),
    'readings', (select count(*) from passed) + (select count(*) from held),
    'passed_every_check', (select count(*) from passed),
    'held_by_a_check', (select count(*) from held),
    'by_rule', coalesce((select jsonb_object_agg(z.rule, z.n) from (select coalesce(held.rule, 'unknown') rule, count(*) n from held group by 1) z), '{}'::jsonb),
    'too_long_chars', (select jsonb_build_object('held', count(*), 'median', percentile_cont(0.5) within group (order by held.chars), 'p90', percentile_cont(0.9) within group (order by held.chars), 'max', max(held.chars))
                         from held where held.rule = 'length'),
    'too_many_sentences', coalesce((select jsonb_object_agg(z.sentences::text, z.n) from (select held.sentences, count(*) n from held where held.rule = 'sentence_count' group by 1) z), '{}'::jsonb),
    'claim_words', coalesce((select jsonb_object_agg(z.word, z.n) from (select claim.word, count(*) n from claim group by 1) z), '{}'::jsonb),
    'failed', coalesce((select jsonb_object_agg(z.why, z.n) from (select left(coalesce(f.reason, 'no reason recorded'), 80) why, count(*) n from f where f.state = 'failed' group by 1) z), '{}'::jsonb),
    'ai_cost_usd', (select round(coalesce(sum(f.cost_usd), 0)::numeric, 4) from f),
    'ai_cost_per_passing_reading_usd', (select round((coalesce(sum(f.cost_usd), 0) / nullif((select count(*) from passed), 0))::numeric, 5) from f),
    'reask', jsonb_build_object('attempted', (select count(*) from f where f.value ? 'reask'),
                                'now_within_limits', (select count(*) from passed where passed.value ? 'reask'),
                                'still_held', (select count(*) from held h where h.value ? 'reask')),
    'reask_max', security.pipeline_num_v1('enrich.course_description_reask_max', 0))
$function$;
revoke all on function security.course_description_held_reasons_v1() from public, anon, authenticated;

-- 8. claim-word evaluation (read only), D2: positive and negative examples with the whole check run again -------------------------------------
create or replace function security.course_description_claim_eval_v1(p_words jsonb default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_list jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_cap int := security.pipeline_num_v1('enrich.course_description_report_max', 500)::int; v_ex int := security.pipeline_num_v1('enrich.course_description_examples', 3)::int;
        v_days int := security.pipeline_num_v1('enrich.course_description_held_days', 7)::int; v_out jsonb := '[]'::jsonb; w text; v_rest jsonb; v_one jsonb;
begin
  -- the window of this evaluation is the held-reasons window; the word list is the course list; every other rule runs again on each reading
  for w in select x from jsonb_array_elements_text(coalesce(p_words, v_list)) x loop
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_rest from jsonb_array_elements_text(v_list) x where x <> w;
    with items as (
      select f.id, f.course_id, f.value from pipeline.field_enrich_items f
       where f.field = 'description' and f.state = 'skipped' and f.reason like 'held: unsupported\_claim%' and f.updated_at >= now() - make_interval(days => v_days)
       order by f.updated_at desc limit v_cap),
    hit as (
      select i.id, i.course_id, i.value,
             (select s->>'text' from jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', w) and not security.pdesc_has_term_v1(s->>'quote', w) limit 1) txt,
             (select s->>'quote' from jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', w) and not security.pdesc_has_term_v1(s->>'quote', w) limit 1) qt,
             (select count(distinct x) from jsonb_array_elements_text(v_list) x, jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s
               where security.pdesc_has_term_v1(s->>'text', x) and not security.pdesc_has_term_v1(s->>'quote', x)) n_words
        from items i),
    h2 as (select hit.* from hit where hit.txt is not null),
    r as (select h2.*, security.course_description_check_with_v1(h2.course_id, h2.value, v_rest, null) chk, coalesce(h2.qt ~* '\m(you|your)\M', false) reader from h2)
    select jsonb_build_object('word', w, 'held', count(*), 'only_this_word', count(*) filter (where r.n_words = 1),
             'passes_every_other_rule_without_it', count(*) filter (where (r.chk->>'ok')::boolean),
             'next_rule', coalesce((select jsonb_object_agg(z.rule, z.n) from (select r2.chk->>'rule' rule, count(*) n from r r2 where not (r2.chk->>'ok')::boolean group by 1) z), '{}'::jsonb),
             'quote_addresses_the_reader', count(*) filter (where r.reader),
             -- suggestions for a person to judge, not a ruling: the page says "you" where the sentence says the word (suggested harmless) or it does not (suggested a real claim)
             'suggested_harmless', coalesce((select jsonb_agg(jsonb_build_object('text', e.txt, 'quote', e.qt)) from (select r3.txt, r3.qt from r r3 where r3.reader order by r3.id limit v_ex) e), '[]'::jsonb),
             'suggested_claim', coalesce((select jsonb_agg(jsonb_build_object('text', e.txt, 'quote', e.qt)) from (select r3.txt, r3.qt from r r3 where not r3.reader order by r3.id limit v_ex) e), '[]'::jsonb))
      into v_one from r;
    if coalesce((v_one->>'held')::int, 0) > 0 then v_out := v_out || jsonb_build_array(v_one); end if;
  end loop;
  return jsonb_build_object('window_days', v_days, 'evaluated_up_to', v_cap, 'words', v_out,
    'note', 'Evaluation only. Removing a word is a Platform Admin decision made as a recorded setting change; every other rule still applies after it.');
end $function$;
revoke all on function security.course_description_claim_eval_v1(jsonb) from public, anon, authenticated;

-- 9. the trust-policy sample report (read only) ---------------------------------------------------------------------------------------------
-- Measures factual accuracy (the share a person approved), course identity (rejections tagged [identity]), claim support (the lowest sentence
-- support and the claim words present) and reviewer disagreement (a reading that passed every check but a person rejected it, or one a person
-- approved that the rules no longer pass). It is never an authority to bypass Layer 4: enrich.course_description_review_first is not touched.
create or replace function security.course_description_sample_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  with ids as (select * from security.course_description_sample_ids_v1()),
  pool as (select p.country, count(*) n from security.course_description_sample_pool_v1() p group by 1),
  strata as (select upper(x) code, o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) with ordinality t(x, o)),
  claim as (select w from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w),
  dcn as (select distinct on (d.review_item_id) d.review_item_id, d.action, d.reason from pipeline.layer4_decisions d order by d.review_item_id, d.created_at desc),
  rws as (
    select ids.item_id, ids.country, ids.pick, i.status, dcn.action, dcn.reason,
           case when i.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
                then coalesce(substring(dcn.reason from '^\s*\[(identity|support|marketing|fragment|other)\]'), 'unclassified') end reason_class,
           coalesce(pv.display_name, pv.canonical_name) provider, coalesce(nullif(c.display_title, ''), c.canonical_title) course, g.identity_basis, g.url page_url,
           i.proposed_value->>'description' description,
           (select min(security.pdesc_support_v1(s->>'text', s->>'quote')) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s) min_support,
           (select coalesce(jsonb_agg(distinct claim.w), '[]'::jsonb) from claim, jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', claim.w)) claims,
           case when e.value is null then null else security.course_description_check_v1(c.id, e.value) end rules_now
      from ids join pipeline.layer4_review_items i on i.id = ids.item_id
      join catalogue.courses c on c.id = i.entity_id left join catalogue.providers pv on pv.id = c.provider_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.field_enrich_items e on e.id = case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end
      left join dcn on dcn.review_item_id = i.id)
  select jsonb_build_object(
    'strata', coalesce((select jsonb_agg(jsonb_build_object('country', strata.code, 'wanted', security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0),
                          'eligible', coalesce(pool.n, 0), 'selected', (select count(*) from rws where rws.country = strata.code),
                          'shortfall', greatest(0, security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0) - (select count(*) from rws where rws.country = strata.code))) order by strata.o)
                          from strata left join pool on pool.country = strata.code), '[]'::jsonb),
    'selected', (select count(*) from rws),
    'pending', (select count(*) from rws where rws.status = 'pending'),
    'approved', (select count(*) from rws where rws.status in ('approved', 'edited_approved')),
    'rejected', (select count(*) from rws where rws.reason_class is not null),
    'approval_share_of_decided', (select round((count(*) filter (where rws.status in ('approved', 'edited_approved')))::numeric / nullif(count(*) filter (where rws.status <> 'pending'), 0), 3) from rws),
    'rejected_by_class', coalesce((select jsonb_object_agg(z.reason_class, z.n) from (select rws.reason_class, count(*) n from rws where rws.reason_class is not null group by 1) z), '{}'::jsonb),
    'reviewer_disagreement', jsonb_build_object(
        'passed_every_check_but_rejected', (select count(*) from rws where rws.reason_class is not null),
        'approved_but_rules_now_fail', (select count(*) from rws where rws.status in ('approved', 'edited_approved') and rws.rules_now is not null and not coalesce((rws.rules_now->>'ok')::boolean, false))),
    'claim_support', jsonb_build_object('with_claim_words_in_quote', (select count(*) from rws where jsonb_array_length(rws.claims) > 0), 'lowest_sentence_support', (select min(rws.min_support) from rws)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('ref', rws.item_id, 'country', rws.country, 'provider', rws.provider, 'course', rws.course, 'status', rws.status,
                        'reason_class', rws.reason_class, 'reason', rws.reason, 'min_support', rws.min_support, 'claims', rws.claims, 'identity_basis', rws.identity_basis,
                        'page_url', rws.page_url, 'description', rws.description, 'rules_now', rws.rules_now) order by rws.country, rws.pick) from rws), '[]'::jsonb),
    'note', 'A measurement of what the checks let through, decided by a person in Layer 4. It is not an authority to bypass Layer 4 and does not change enrich.course_description_review_first.')
$function$;
revoke all on function security.course_description_sample_report_v1() from public, anon, authenticated;

-- 10. the one read entry for the Admin workspace (Pipeline Operator and above; read only) ---------------------------------------------------------
create or replace function public.admin_course_description_queue(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb);
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  if p_action is null or p_action not in ('summary', 'items', 'held_reasons', 'claim_words', 'sample') then raise exception 'unknown action %', p_action using errcode = '22023'; end if;
  return case p_action
    when 'summary' then security.course_description_summary_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'recheck')::boolean, false))
    when 'items' then security.course_description_items_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false))
    when 'held_reasons' then security.course_description_held_reasons_v1()
    when 'claim_words' then security.course_description_claim_eval_v1(case when jsonb_typeof(a->'words') = 'array' then a->'words' end)
    else security.course_description_sample_report_v1() end;
end $function$;
revoke all on function public.admin_course_description_queue(text, jsonb) from public, anon;
grant execute on function public.admin_course_description_queue(text, jsonb) to authenticated;

-- 11. housekeeping register (Decision 260): new components, nothing retired ------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_description_check_with_v1', 'Layer 3', 'Course descriptions', 'The whole course description check, with optional claim and marketing word lists (course lists from settings by default)', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_reconcile_v1', 'Layer 4', 'Course descriptions', 'Places every pending Layer 4 course description in one class (ready, fails now, stale), read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_summary_v1', 'Layer 4', 'Course descriptions', 'Proposed, held, admitted and published description counts, read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_items_v1', 'Layer 4', 'Course descriptions', 'Reviewer queue of ready course descriptions in the Inbox item shape, read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_held_reasons_v1', 'Layer 3', 'Course descriptions', 'Held reasons of description readings, read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_claim_eval_v1', 'Layer 3', 'Course descriptions', 'Claim-word evaluation with every other rule run again, read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_sample_pool_v1', 'Layer 4', 'Course descriptions', 'Descriptions eligible for the trust-policy sample, read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_sample_ids_v1', 'Layer 4', 'Course descriptions', 'Stratified trust-policy sample (30 AU, 15 NZ, 5 CA), read only', 'active', '{}', '20261106500000'),
 ('function', 'security.course_description_sample_report_v1', 'Layer 4', 'Course descriptions', 'Trust-policy sample measures (accuracy, identity, claim support, reviewer disagreement), read only', 'active', '{}', '20261106500000'),
 ('function', 'public.admin_course_description_queue', 'Layer 4', 'Course descriptions', 'The one read entry of the Enrich fields and Layer 4 course description panels', 'active', '{}', '20261106500000')
on conflict do nothing;

-- 12. post-check: the replaced check keeps its signature, the new lists equal the provider lists on the day of release, nothing was admitted -------
do $post$
begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_claim_words') is distinct from
     (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.claim_words') then
    raise exception 'post-check: the course claim-word list differs from the provider list on the day of release (D2: initially identical)';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.course_description_marketing_words') is distinct from
     (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.superlatives') then
    raise exception 'post-check: the course marketing-word list differs from the provider list on the day of release (D5: effective policy unchanged)';
  end if;
  if security.pipeline_num_v1('enrich.course_description_reask_max', 99) <> 0 then raise exception 'post-check: the re-ask must ship off (D4)'; end if;
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched (D1)'; end if;
end $post$;

