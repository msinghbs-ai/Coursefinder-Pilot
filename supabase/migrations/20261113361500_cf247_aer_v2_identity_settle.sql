-- CF-247 AER v2 stored-page identity, step 1 (S1-AER Platform Admin decision 2, 13 Nov 2026; admin AER v2 design §10.2, F-AER.08): settle the stored official
--   pages that already carry the course's own identity proof but were left 'ambiguous'.
-- Matching order (decision 2): 1. the course's own published code (CRICOS, NZQA) on a verified provider page; 2. a unique exact normalised title and level;
--   3. AI candidate ranking for what is still unresolved (next step, not in this change); 4. independent verification (E16, security.course_page_check_v1,
--   and the binding trigger on pipeline.coverage_course_pages); 5. a person in Layer 4 only for genuinely ambiguous cases. This change is 1, 2 and 4.
-- Evidence (13 Nov 2026 17:10 AEDT): 1,019 courses of AER-eligible providers have a stored official page that the reader proved (identity_basis set: 638 by the
--   course's CRICOS code printed on the page, the rest by the exact title and level rules) but whose binding stayed 'ambiguous' because the site-map binder
--   once scored two pages equally. Only 'bound' pages are read for entry requirements, fees and intakes, so these courses get nothing. The reader's own promotion
--   (ambiguous -> bound on a CRICOS proof) was added after most of them were read (all 638 were read 29 Sep to 26 Oct), and title proofs never promote.
-- Rule (security.aer_v2_identity_settle_check_v1, writes nothing): bind only when every one holds:
--   the page is stored and read with an identity proof allowed for the country (security.coverage_identity_allowed); not a manual binding; no earlier rejection
--   or block of this page for this course (prior rejection memory); the course is not held; no course-link item for the course is pending in Layer 4 or was
--   decided by a person; the E16 check passes on the same page, title and proof; and one catalogue course: the course's own code proves it (E16 rule own_code),
--   or no other active course of the provider has the same normalised title and no other course holds the page. Anything else stays as it is, with its reason.
--   The fixture added four checks before E16 (security.aer_v2_title_names_course_v1 and the host, package and code checks): the page is on the provider's own
--   host; its main heading, or the first part of its title, is exactly the course title (a heading that adds a stream, major or campus, a title with a middle
--   part, or a broken bracket is not); no "package" or "pathway" page; no other course's CRICOS code in the heading. Without them the first version bound 4
--   pages the review labelled another course (pathway packages, a sibling college's page) and 6 it could not confirm (streams, a campus abroad, a showcase).
--   Release result (dry run against live, 13 Nov 2026 18:05 AEDT): 42 of the 200 cases bound, all 42 gold-labelled this course; 0 incorrect; 158 held.
-- Precision (decision 2 "200 stratified stored-page cases ... zero incorrect automated bindings"): pipeline.aer_v2_identity_fixture holds 200 cases across nine
--   strata (own code; unique title proof; same-title or shared page; E16 refused; person-rejected; person-approved; generic pages; close titles; identity
--   refused), each with a gold label: Layer 4 decisions by a person, otherwise an independent blind review (page title, heading and address, the official page
--   opened where needed, no Firecrawl). The post-check below fails this change if any case the rule binds is not gold-labelled this course.
-- What:
--   1. pipeline.aer_v2_identity_settlements: one row per page decided (bound, held with its reason, or refused_by_guard), with the page, evidence id and content
--      hash, identity proof, prior status, E16 verdict, rule version and actor (machine).
--   2. security.aer_v2_identity_settle_check_v1(course) and security.aer_v2_identity_settle_v1(): the job step; it sets status 'bound' only through the
--      existing binding trigger (E16 and the CRICOS identity guard run again on the update; a refusal there is recorded as refused_by_guard).
--   3. pipeline.aer_v2_identity_fixture and security.aer_v2_identity_fixture_report_v1(): the 200 cases, their gold labels and the rule's decision at release.
--   4. Settings aer.v2_identity_settle_on (1) and batch.aer_v2_identity_settle (1000); job aer-v2-identity-settle at :22 and :52, catalogued.
-- Guards: G1 (one new job, catalogued before it is scheduled), G2 (switch and batch are settings; the job command has no number; the 45-second run guard is a
--   fire guard, marked fixed), G3 (no consumer API object read or changed), G4 (spec cf-247-aer-v2-identity-settle-contract), Decision 260 (Replaces/Retires,
--   table purposes, register rows), AER v1 frozen (no v1 reader, rule or table changed; shared binding functions and the trigger are used, not edited),
--   nothing deleted. Switched on by Platform Admin decision 2 (13 Nov 2026) once the fixture shows zero incorrect bindings, which the post-check enforces.
-- Replaces: nothing (the reader's own ambiguous -> bound promotion stays). Retires: nothing.

-- 0. what this change reads must exist -----------------------------------------------------------------------------------------------------------------
do $g$
declare v_sig text;
begin
  foreach v_sig in array array['security.course_page_check_v1(uuid,text,text,text)', 'security.coverage_identity_allowed(uuid,text,text)', 'security.course_held_v1(uuid)',
                               'security.no_page_hold_v1(uuid)', 'security.aer_eligible_v1()', 'security.pipeline_num_v1(text,numeric)'] loop
    if to_regprocedure(v_sig) is null then raise exception 'this change reads %, which does not exist', v_sig; end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.coverage_course_pages'::regclass and tgname = 'coverage_page_refused_host') then
    raise exception 'this change relies on the binding trigger coverage_page_refused_host (E16) on pipeline.coverage_course_pages';
  end if;
end $g$;

-- 1. settlement record -----------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_v2_identity_settlements (
  id bigserial primary key,
  course_id uuid not null,
  provider_id uuid,
  url text not null,
  evidence_id uuid,
  content_hash text,
  identity_basis text,
  prior_status text not null,
  decision text not null check (decision in ('bound', 'held', 'refused_by_guard')),
  reason text not null,
  e16 jsonb,
  rule_version text not null,
  actor text not null default 'machine',
  mode text not null check (mode in ('apply', 'dry_run')),
  decided_at timestamptz not null default now()
);
comment on table pipeline.aer_v2_identity_settlements is 'AER v2 stored-page identity (S1-AER decision 2, 13 Nov 2026; AER v2 design §10.2): one row per stored official page the identity settle step decided for a course: bound (the page''s own proof, uniqueness and the E16 check security.course_page_check_v1 passed), held (with the first failing reason) or refused_by_guard (the binding trigger refused it). Keeps the page, evidence id and content hash, the identity proof, the prior status, the E16 verdict, the rule version and the actor.';
create index if not exists aer_v2_identity_settlements_course on pipeline.aer_v2_identity_settlements(course_id, decided_at desc);

-- 2. the check (no write) --------------------------------------------------------------------------------------------------------------------------------
-- 2a. the page's own heading names exactly this course (fixture finding, 13 Nov 2026: a CRICOS code or a title found anywhere in the page text also matched
--     package and pathway pages, a stream of the qualification, a sibling course of another college and a campus abroad; the page's title or main heading
--     must itself be the course title). Only a leading national or provider code and the trailing site name are set aside; "(Level N)" may be left off.
create or replace function security.aer_v2_title_names_course_v1(p_page_title text, p_h1 text, p_course_title text) returns boolean
language plpgsql immutable set search_path to '' as $f$
declare v_t text; v_nl text; v_h1 text; v_ti text; v_parts text[]; v_head text;
begin
  v_t := btrim(regexp_replace(lower(replace(coalesce(p_course_title, ''), '&', ' and ')), '[^a-z0-9]+', ' ', 'g'));
  if v_t = '' then return false; end if;
  v_nl := btrim(regexp_replace(v_t, '\s*level \d{1,2}$', ''));
  -- entities decoded, a leading national or provider code set aside, then normalised
  v_h1 := regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p_h1, ''), '&(#8211|#8212|ndash|mdash);', '-', 'gi'), '&(#39|#8217|rsquo|lsquo);', '''', 'gi'), '&amp;', '&', 'gi'), '&nbsp;', ' ', 'gi');
  v_ti := regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p_page_title, ''), '&(#8211|#8212|ndash|mdash);', '-', 'gi'), '&(#39|#8217|rsquo|lsquo);', '''', 'gi'), '&amp;', '&', 'gi'), '&nbsp;', ' ', 'gi');
  -- a heading that repeats the site name after "|" (some sites print the page title as the heading) is read up to the "|"
  v_h1 := btrim(regexp_replace(lower(replace(regexp_replace(btrim(split_part(v_h1, '|', 1)), '^(?:[A-Z]{2,6}[0-9]{3,6}[A-Z]?|[0-9]{5}NAT)\s*[-–—:|]?\s+', ''), '&', ' and ')), '[^a-z0-9]+', ' ', 'g'));
  -- 1. the main heading is the course title
  if v_h1 <> '' and (v_h1 = v_t or v_h1 = v_nl) then return true; end if;
  -- 2. a heading that is the course title plus more words names a stream, major or campus of it: not this course
  if v_h1 <> '' and (v_h1 like v_t || ' %' or v_h1 like v_nl || ' %') then return false; end if;
  -- 3. the page title: its first part before "|", which may carry the site name after one dash; brackets must be whole and nothing may stand between
  v_head := btrim(split_part(v_ti, '|', 1));
  v_parts := regexp_split_to_array(v_head, '\s+[–—-]\s+');
  if cardinality(v_parts) > 2 then return false; end if;
  v_head := btrim(v_parts[1]);
  if length(v_head) - length(replace(v_head, '(', '')) <> length(v_head) - length(replace(v_head, ')', '')) then return false; end if;
  v_head := btrim(regexp_replace(lower(replace(regexp_replace(v_head, '^(?:[A-Z]{2,6}[0-9]{3,6}[A-Z]?|[0-9]{5}NAT)\s*[-–—:|]?\s+', ''), '&', ' and ')), '[^a-z0-9]+', ' ', 'g'));
  return v_head <> '' and (v_head = v_t or v_head = v_nl);
end $f$;
comment on function security.aer_v2_title_names_course_v1(text, text, text) is 'AER v2 stored-page identity: true when the main heading is exactly the course title, or (with no heading that adds a stream, major or campus to it) the first part of the page title is, with at most the site name after one dash and whole brackets; a leading national or provider code is set aside and a trailing "(Level N)" may be left off.';

create or replace function security.aer_v2_identity_settle_check_v1(p_course uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare g record; v_chk jsonb; v_twin boolean; v_shared boolean; v_nt text; v_heads text; v_host text; v_own_code boolean;
begin
  select p.course_id, p.provider_id, p.url, p.status, p.read_status, p.identity_basis, p.basis, p.evidence_id,
         p.candidates->>'page_title' page_title, p.candidates->>'h1' h1, a.storage_path, a.content_hash, co.canonical_title, co.course_code, co.lifecycle_status
    into g
    from pipeline.coverage_course_pages p join catalogue.courses co on co.id = p.course_id
    left join pipeline.evidence_artifacts a on a.id = p.evidence_id
   where p.course_id = p_course;
  if g.course_id is null then return jsonb_build_object('decision', 'held', 'reason', 'no_page'); end if;
  if g.status <> 'ambiguous' then return jsonb_build_object('decision', 'held', 'reason', 'not_ambiguous'); end if;
  if g.lifecycle_status <> 'active' then return jsonb_build_object('decision', 'held', 'reason', 'course_not_active'); end if;
  if coalesce(g.basis, '') = 'manual' then return jsonb_build_object('decision', 'held', 'reason', 'manual_binding'); end if;
  if g.read_status is distinct from 'read' or g.identity_basis is null then return jsonb_build_object('decision', 'held', 'reason', 'no_identity_proof'); end if;
  if g.storage_path is null then return jsonb_build_object('decision', 'held', 'reason', 'not_stored'); end if;
  if not security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'official_url') then return jsonb_build_object('decision', 'held', 'reason', 'proof_not_allowed'); end if;
  -- prior decisions: any rejection or block of this page for this course, a hold, and any course link a person decided or is to decide
  if exists (select 1 from pipeline.page_rejections x where x.course_id = g.course_id and x.url = g.url)
     or exists (select 1 from pipeline.course_page_blocks k where k.course_id = g.course_id and k.url = g.url) then
    return jsonb_build_object('decision', 'held', 'reason', 'page_rejected_before');
  end if;
  if security.course_held_v1(g.course_id) or security.no_page_hold_v1(g.course_id) then return jsonb_build_object('decision', 'held', 'reason', 'course_held'); end if;
  if exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = g.course_id and i.field_code = 'official_course_url'
              and (i.status = 'pending' or exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = i.id and d.actor_id is not null))) then
    return jsonb_build_object('decision', 'held', 'reason', 'person_course_link');
  end if;
  -- the page is on the provider's own host (its website, an approved alias or extra domain), not another sub-site
  v_host := regexp_replace(coalesce(security.reference_host_of(g.url), ''), '^www\.', '');
  if not (v_host = any (security.provider_hosts_v1(g.provider_id))) then return jsonb_build_object('decision', 'held', 'reason', 'host_not_provider_site'); end if;
  -- the page's own heading names exactly this course; no package or pathway page; no other course's CRICOS code in the heading
  v_heads := coalesce(g.page_title, '') || ' ' || coalesce(g.h1, '');
  if v_heads ~* '\m(package|pathway)\M' then return jsonb_build_object('decision', 'held', 'reason', 'package_or_pathway_page'); end if;
  if exists (select 1 from regexp_matches(upper(v_heads), '\m([0-9]{6}[A-Z])\M', 'g') m where m[1] <> upper(coalesce(g.course_code, ''))) then
    return jsonb_build_object('decision', 'held', 'reason', 'other_code_in_heading');
  end if;
  if not security.aer_v2_title_names_course_v1(g.page_title, g.h1, g.canonical_title) then return jsonb_build_object('decision', 'held', 'reason', 'heading_not_course_title'); end if;
  -- the independent binding check (E16) on the same page, title and proof
  v_chk := security.course_page_check_v1(g.course_id, g.url, g.page_title, g.identity_basis);
  if coalesce(v_chk->>'verdict', '') <> 'pass' then
    return jsonb_build_object('decision', 'held', 'reason', 'e16_' || coalesce(v_chk->>'rule', v_chk->>'verdict', 'unknown'), 'e16', v_chk);
  end if;
  -- one catalogue course: the course's own code in the page heading or address tells same-title courses apart; otherwise no other active course of the
  -- provider has the same title and no other course holds the page
  v_own_code := length(coalesce(g.course_code, '')) >= 4 and (upper(v_heads || ' ' || g.url) ~ ('\m' || upper(g.course_code) || '\M'));
  v_nt := regexp_replace(lower(replace(g.canonical_title, '&', ' and ')), '[^a-z0-9]+', ' ', 'g');
  v_twin := exists (select 1 from catalogue.courses c2 where c2.provider_id = g.provider_id and c2.id <> g.course_id and c2.lifecycle_status = 'active'
                     and regexp_replace(lower(replace(c2.canonical_title, '&', ' and ')), '[^a-z0-9]+', ' ', 'g') = v_nt);
  v_shared := exists (select 1 from pipeline.coverage_course_pages g2 where g2.url = g.url and g2.course_id <> g.course_id);
  if not v_own_code and (v_twin or v_shared) then
    return jsonb_build_object('decision', 'held', 'reason', case when v_twin then 'same_title_course' else 'page_shared' end, 'e16', v_chk);
  end if;
  return jsonb_build_object('decision', 'bound', 'reason', case when v_own_code then 'own_code_in_heading' else 'unique_title_' || g.identity_basis end,
                            'e16', v_chk, 'url', g.url, 'evidence_id', g.evidence_id, 'content_hash', g.content_hash, 'identity_basis', g.identity_basis);
end $f$;
comment on function security.aer_v2_identity_settle_check_v1(uuid) is 'AER v2 stored-page identity (design §10.2): whether an ambiguous stored page may be bound to its course: the page''s own identity proof (allowed for the country); no earlier rejection, hold or person course-link decision; the provider''s own host; the page title or heading is exactly the course title, with no package, pathway or other course code; the E16 check passes; and one catalogue course (own code in the heading or address, or no same-title course and no other course on the page). Writes nothing.';
revoke all on function security.aer_v2_identity_settle_check_v1(uuid) from public, anon, authenticated;

-- 3. the job step --------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_v2_identity_settle_v1(p_apply boolean default true) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_on boolean := security.pipeline_num_v1('aer.v2_identity_settle_on', 0) >= 1;
        v_batch int := security.pipeline_num_v1('batch.aer_v2_identity_settle', 1000)::int;
        v_t0 timestamptz := clock_timestamp(); r record; v jsonb; v_after text; v_dec text; v_out jsonb := '{}'::jsonb; v_n int := 0;
        v_mode text := case when p_apply then 'apply' else 'dry_run' end;
begin
  if p_apply and not v_on then return jsonb_build_object('on', false); end if;
  for r in
    select p.course_id, p.provider_id, p.url, p.evidence_id, p.identity_basis
      from pipeline.coverage_course_pages p join catalogue.courses co on co.id = p.course_id
     where p.status = 'ambiguous' and p.read_status = 'read' and p.identity_basis is not null and coalesce(p.basis, '') <> 'manual' and co.lifecycle_status = 'active'
       -- a page decided in the last day with the same evidence is not looked at again until it changes
       and not exists (select 1 from pipeline.aer_v2_identity_settlements s where s.course_id = p.course_id and s.url = p.url and s.mode = 'apply'
                         and s.evidence_id is not distinct from p.evidence_id and s.decided_at > now() - interval '1 day')  -- fixed: a held page is looked at again daily
     order by (p.provider_id in (select e.provider_id from security.aer_eligible_v1() e)) desc, p.course_id
     limit v_batch
  loop
    exit when clock_timestamp() - v_t0 > interval '45 seconds';  -- fixed: a run stays inside the job's time
    v := security.aer_v2_identity_settle_check_v1(r.course_id);
    v_dec := v->>'decision';
    if v_dec = 'bound' and p_apply then
      update pipeline.coverage_course_pages set status = 'bound', leased_until = null where course_id = r.course_id and url = r.url and status = 'ambiguous';
      select status into v_after from pipeline.coverage_course_pages where course_id = r.course_id;
      if v_after is distinct from 'bound' then v_dec := 'refused_by_guard'; end if;
    end if;
    insert into pipeline.aer_v2_identity_settlements(course_id, provider_id, url, evidence_id, content_hash, identity_basis, prior_status, decision, reason, e16, rule_version, mode)
    values (r.course_id, r.provider_id, r.url, r.evidence_id, v->>'content_hash', r.identity_basis, 'ambiguous',
            case when v_dec = 'bound' and not p_apply then 'held' else v_dec end,
            case when v_dec = 'bound' and not p_apply then 'dry_run_would_bind:' || (v->>'reason') else v->>'reason' end,
            v->'e16', 'aer-v2-identity-settle-v1', v_mode);
    v_n := v_n + 1;
    v_out := jsonb_set(v_out, array[v_dec], to_jsonb(coalesce((v_out->>v_dec)::int, 0) + 1));
  end loop;
  return jsonb_build_object('on', v_on, 'mode', v_mode, 'checked', v_n, 'outcomes', v_out, 'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;
comment on function security.aer_v2_identity_settle_v1(boolean) is 'AER v2 stored-page identity (design §10.2), job aer-v2-identity-settle: binds ambiguous stored pages that pass security.aer_v2_identity_settle_check_v1, through the binding trigger (E16 again), and records every decision in pipeline.aer_v2_identity_settlements. Off (aer.v2_identity_settle_on 0) it does nothing; p_apply false records what it would do.';
revoke all on function security.aer_v2_identity_settle_v1(boolean) from public, anon, authenticated;

-- 4. the 200-case precision fixture -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_v2_identity_fixture (
  case_id text primary key,
  stratum text not null,
  course_id uuid not null,
  url text not null,
  gold_label text not null check (gold_label in ('this_course', 'other_course', 'generic', 'unsure')),
  gold_source text not null check (gold_source in ('person_layer4', 'independent_review')),
  rule_decision text not null check (rule_decision in ('bound', 'held')),
  rule_reason text not null,
  recorded_at timestamptz not null default now()
);
comment on table pipeline.aer_v2_identity_fixture is 'AER v2 stored-page identity precision fixture (S1-AER decision 2, 13 Nov 2026): 200 stratified stored-page cases with a gold label (a person''s Layer 4 course-link decision, otherwise an independent blind review) and the settle rule''s decision when the rule was released. Zero cases bound without the gold label this_course is the release condition.';

create or replace function security.aer_v2_identity_fixture_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'cases', count(*),
    'bound', count(*) filter (where rule_decision = 'bound'),
    'bound_correct', count(*) filter (where rule_decision = 'bound' and gold_label = 'this_course'),
    'incorrect_bindings', count(*) filter (where rule_decision = 'bound' and gold_label <> 'this_course'),
    'held_this_course', count(*) filter (where rule_decision = 'held' and gold_label = 'this_course'),
    'held_not_this_course', count(*) filter (where rule_decision = 'held' and gold_label <> 'this_course'),
    'by_stratum', (select jsonb_object_agg(stratum, x) from (select stratum, jsonb_build_object('cases', count(*), 'bound', count(*) filter (where rule_decision = 'bound'),
                     'gold_this_course', count(*) filter (where gold_label = 'this_course')) x from pipeline.aer_v2_identity_fixture group by stratum) s),
    'held_reasons', (select jsonb_object_agg(rule_reason, n) from (select rule_reason, count(*) n from pipeline.aer_v2_identity_fixture where rule_decision = 'held' group by 1) h))
  from pipeline.aer_v2_identity_fixture
$f$;
comment on function security.aer_v2_identity_fixture_report_v1() is 'AER v2 stored-page identity: precision of the settle rule on its 200-case fixture (incorrect_bindings must be 0), recall on the gold this_course cases, by stratum and held reason.';


-- 4b. the 200 cases (labelled 13 Nov 2026: strata S1 own code on page, S2 unique title proof, S3 same-title course or shared page, S4 E16 refused, S5 a person
--     rejected the link, S6 a person approved the link, S7 generic pages, S8 close titles, S9 identity refused; gold from Layer 4 decisions by a person, otherwise
--     an independent blind review of page title, heading and address). The rule's decision is taken now, before anything is bound.
-- Note on S5: 23 of the 25 person rejections were not identity errors (they kept an earlier page or archived a programme no longer offered); they are kept as
--     negatives, and the rule holds all of them (person_course_link or not ambiguous).
insert into pipeline.aer_v2_identity_fixture(case_id, stratum, course_id, url, gold_label, gold_source, rule_decision, rule_reason)
select f.case_id, f.stratum, f.course_id, f.url, f.gold, f.src, coalesce(c->>'decision', 'held'), coalesce(c->>'reason', 'unknown')
  from (values
 ('F001', 'S3', '30374ab8-fea4-419b-82a4-7665119c20e2'::uuid, 'https://utait.edu.au/course/aur40216-certificate-iv-in-automotive-mechanical-diagnosis-course/', 'this_course', 'independent_review'),
 ('F002', 'S1', 'b0b2627f-dddc-4928-84f7-1ef0e6615a64'::uuid, 'https://metroinstitute.edu.au/courses/cert-iv-business/', 'this_course', 'independent_review'),
 ('F003', 'S2', '1efc84b8-c42d-42f5-a957-6d7f13be982a'::uuid, 'https://www.lincoln.ac.nz/study/study-programmes/programme-search/bachelor-of-sport-and-recreation-management', 'this_course', 'independent_review'),
 ('F004', 'S2', 'dd055ff0-4a29-4be0-adc8-f70a376b5c79'::uuid, 'https://pcti.co.nz/courses/tproduct/704846964-280486441481-new-zealand-certificate-in-apiculture-le', 'this_course', 'independent_review'),
 ('F005', 'S2', 'b93b9659-1c4d-4d52-be30-09b44353ed88'::uuid, 'https://nzios.ac.nz/course/new-zealand-diploma-in-information-technology-technical-support-level-5/', 'this_course', 'independent_review'),
 ('F006', 'S2', '42f01e71-753c-4908-9972-8837222e3048'::uuid, 'https://newzealandaviation.co.nz/learntofly/diploma-in-aviation-level-5', 'this_course', 'independent_review'),
 ('F007', 'S1', '5fe5ed24-b449-426d-aba2-fcfae888cdd1'::uuid, 'https://aittcollege.com.au/bsb60420-advanced-diploma-of-leadership-and-management', 'this_course', 'independent_review'),
 ('F008', 'S4', 'dc097559-0f46-4823-ab23-95b81a4350cd'::uuid, 'https://www.curtin.edu.au/study/international-students/curtin-english/gateway-english', 'other_course', 'independent_review'),
 ('F009', 'S1', '067735be-2710-48f7-958b-374f78e85824'::uuid, 'https://gie.edu.au/certificate-iv-in-disability-support/', 'this_course', 'independent_review'),
 ('F010', 'S1', '4b514968-4a30-4389-a8ef-e0b79b62925c'::uuid, 'https://aapoly.edu.au/courses/bachelor-of-tourism-and-hospitality-management', 'this_course', 'independent_review'),
 ('F011', 'S2', 'e1f2b043-f220-4381-8263-560496f174da'::uuid, 'https://atlas.curtin.edu.au/singapore/courses/postgraduate-courses/graduate-certificate-in-supply-chain-management/', 'other_course', 'independent_review'),
 ('F012', 'S3', '490c67c4-6386-489c-81fb-48054a6b8d37'::uuid, 'https://swanston.edu.au/certificate-iii-in-early-childhood-education-and-care-chc30121/', 'this_course', 'independent_review'),
 ('F013', 'S3', 'c06bfbb4-8512-4723-9bf1-51d37b9549de'::uuid, 'https://www.arohacollege.edu.au/chc30125-certificate-3-early-childhood-education-and-care-2/', 'this_course', 'independent_review'),
 ('F014', 'S3', 'd71b82d0-f547-4936-925c-ac7d461b9124'::uuid, 'https://auscaretraining.edu.au/chc52021-diploma-of-community-services-2/', 'this_course', 'independent_review'),
 ('F015', 'S4', '9e8b1f01-075b-4c9b-b39a-0c0f2e87abff'::uuid, 'https://www.deakin.edu.au/course/master-construction-management-research', 'other_course', 'independent_review'),
 ('F016', 'S2', 'ec1565bd-c52a-4c02-b3e2-26d333e5c0c9'::uuid, 'https://www.northwoodcollege.com.au/cpc40120-certificate-iv-in-building-and-construction/', 'this_course', 'independent_review'),
 ('F017', 'S2', 'f76377fd-7b8f-4c1d-83fe-bd8e6492319b'::uuid, 'https://www.northwoodcollege.com.au/certificate-iii-in-wall-and-ceiling-lining-cpc31220-international/', 'this_course', 'independent_review'),
 ('F018', 'S3', '090d5653-b103-4e15-9ebc-77bc1e88f145'::uuid, 'https://mars.edu.au/courses/automotive/certificate-iv-in-automotive-electrical-technology-aur40620/', 'this_course', 'independent_review'),
 ('F019', 'S2', '20264aa5-1218-4892-8329-b5601535a387'::uuid, 'https://tpc.edu.au/certificate-iii-in-individual-support-ageing-disability/', 'unsure', 'independent_review'),
 ('F020', 'S1', 'c4d54bc8-82e3-4cf9-a1a0-499d501ececf'::uuid, 'https://bic.edu.au/diploma-of-hospitality-management', 'this_course', 'independent_review'),
 ('F021', 'S3', '6cea2d9d-60b2-49b7-86e8-4979a0b42961'::uuid, 'https://glen.edu.au/diploma-of-automotive-management/', 'this_course', 'independent_review'),
 ('F022', 'S3', '719edf55-b16b-4031-957e-74339c1d588d'::uuid, 'https://www.ucol.ac.nz/programmes/creative/new-zealand-diploma-in-arts-and-design', 'this_course', 'independent_review'),
 ('F023', 'S1', '2019f8ba-a560-4880-9b50-86f10696362a'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/postgraduate-degrees/master-of-professional-psychology', 'this_course', 'independent_review'),
 ('F024', 'S1', '28293db4-6b50-4cb1-afea-72844105c47d'::uuid, 'https://www.mei.edu.au/certificate-iv-in-leadership-and-managem', 'other_course', 'independent_review'),
 ('F025', 'S3', 'b6e845ed-f4ca-401c-9331-bb3ac203d931'::uuid, 'https://bond.edu.au/program/medical-program-bachelor-of-medical-studies-doctor-of-medicine', 'other_course', 'independent_review'),
 ('F026', 'S3', 'c2d47752-cea6-41ba-9767-fb705428b58a'::uuid, 'https://www.utas.edu.au/courses/health/courses/54d-bachelor-of-pharmacy-with-honours', 'this_course', 'independent_review'),
 ('F027', 'S4', '5311c1b9-d347-4d36-b9af-41b099cbab02'::uuid, 'https://bond.edu.au/program/bachelor-of-communication-businessbachelor-of-laws', 'unsure', 'independent_review'),
 ('F028', 'S2', 'c1e84b71-059c-4dc7-95a0-382ef2f1873a'::uuid, 'https://pacific.edu.au/certificate-iii-in-painting-and-decorating-sydney/', 'this_course', 'independent_review'),
 ('F029', 'S1', 'd0c94b5d-b80c-4152-9df9-89af2253989b'::uuid, 'https://www.tafensw.edu.au/international/courses/certificate-iv-in-building-and-construction-building--CPC40120', 'unsure', 'independent_review'),
 ('F030', 'S4', 'a8edbc10-b932-495a-b91f-2f103dcdb4c4'::uuid, 'https://study.unimelb.edu.au/how-to-apply/international-exchange-and-study-abroad/fees-and-costs', 'generic', 'independent_review'),
 ('F031', 'S3', 'c3930fc0-424f-45f5-9f13-56900989471d'::uuid, 'https://www.edunex.edu.au/rt-program/certificate-iii-in-early-childhood-education-and-care/', 'this_course', 'independent_review'),
 ('F032', 'S2', '61bb2082-a879-4a6c-bea4-0ff5da727e97'::uuid, 'https://www.epoch.edu.au/diploma-of-leadership-and-management/', 'this_course', 'independent_review'),
 ('F033', 'S4', '743f7353-135a-4abe-89f6-9a6c10bb8fa1'::uuid, 'https://www.torrens.edu.au/courses/business/diploma-of-business-sport-management', 'other_course', 'independent_review'),
 ('F034', 'S3', 'fb08e143-f846-4a08-bc37-cc639b05e12e'::uuid, 'https://mite.edu.au/certificate-iii-in-early-childhood-education-and-care/', 'this_course', 'independent_review'),
 ('F035', 'S4', 'aa6671f9-56eb-476e-9e90-07d5ae5c4a7f'::uuid, 'https://www.auipt.edu.au/courses/community-services/diploma-of-community-services/', 'this_course', 'independent_review'),
 ('F036', 'S1', '74e0ad93-14db-418a-b4a5-243c2c9b98e8'::uuid, 'https://princeton.edu.au/courses/leadership-management/certificate-iv-in-leadership-and-management-bsb40520/', 'this_course', 'independent_review'),
 ('F037', 'S4', '0d98ec84-890f-44ea-9001-bf3e33eb5713'::uuid, 'https://sia.edu.au/domestic-courses/certificate-iii-in-early-childhood-education-and-care', 'this_course', 'independent_review'),
 ('F038', 'S4', 'acb85a0b-bd5f-4663-ac4d-ebf9ed94d39f'::uuid, 'https://www.collarts.edu.au/courses/film-theatre/acting/diploma', 'this_course', 'independent_review'),
 ('F039', 'S3', '0c11e098-d4fa-4cce-b805-50fc412c3145'::uuid, 'https://soliscollege.sa.edu.au/diploma-of-community-services/', 'unsure', 'independent_review'),
 ('F040', 'S4', 'e7b8fcb8-9d20-4b5d-a790-e3de22d3544e'::uuid, 'https://www.murdoch.edu.au/course/undergraduate/b1356', 'this_course', 'independent_review'),
 ('F041', 'S3', '25b12511-bf6e-44a8-98bf-e6c24df68955'::uuid, 'https://www.tafensw.edu.au/international/package/certificate-iv-in-live-production-and-technical-services-costume--1452', 'other_course', 'independent_review'),
 ('F042', 'S1', 'ad9cf1d8-3a43-422d-b640-8e80911c6c7e'::uuid, 'https://www.tafensw.edu.au/international/package/certificate-iv-in-dental-assisting--1357', 'other_course', 'independent_review'),
 ('F043', 'S3', 'dfd81a52-5fc7-471b-8f9c-d15f1c7dc3c8'::uuid, 'https://www.astutetraining.edu.au/community-health-courses/diploma-of-community-services-chc52015/', 'this_course', 'independent_review'),
 ('F044', 'S2', 'f3ba19a1-ed06-4a26-803b-464678b78c70'::uuid, 'https://sites.rmit.edu.au/artschoolgraduates/category/art/maps/', 'generic', 'independent_review'),
 ('F045', 'S1', '5da061f4-b284-45e2-9ded-34dd62106551'::uuid, 'https://omni.edu.au/courses/certificate-iii-in-painting-and-decoration/', 'this_course', 'independent_review'),
 ('F046', 'S1', '4ecb21b3-671c-4e98-a174-ac6e5d794985'::uuid, 'https://sc.edu.au/product/sit40521-certificate-iv-in-kitchen-management/', 'this_course', 'independent_review'),
 ('F047', 'S3', '3a661172-7722-4f99-b060-0bde286ae6f1'::uuid, 'https://tafeqld.edu.au/course/17/17841/diploma-of-music', 'unsure', 'independent_review'),
 ('F048', 'S3', '154a1622-7a07-440e-b752-0d57ea010ddc'::uuid, 'https://ghmc.edu.au/diploma-of-community-services-chc52025/', 'this_course', 'independent_review'),
 ('F049', 'S1', 'e3e14ec3-43d1-4c07-b755-408e3913b41a'::uuid, 'https://www.kii.edu.au/course/ict50220-diploma-of-information-technology/', 'this_course', 'independent_review'),
 ('F050', 'S1', 'b9c4c547-52b8-47e3-8a72-ec77f2899d60'::uuid, 'https://invcollege.edu.au/courses/ageing-support', 'this_course', 'independent_review'),
 ('F051', 'S1', '69b66fd2-79ff-489f-83c8-313034950f98'::uuid, 'https://handbook.flinders.edu.au/courses/2026/gdptesol', 'this_course', 'independent_review'),
 ('F052', 'S1', '98dbb418-e1f0-4c0f-b213-9874b0c06b05'::uuid, 'https://handbook.flinders.edu.au/courses/2026/hbsar', 'this_course', 'independent_review'),
 ('F053', 'S1', '85918f9d-c2bb-4a18-9c16-b9d0527c8c53'::uuid, 'https://iprogress.edu.au/ict50220-diploma-of-information-technology', 'this_course', 'independent_review'),
 ('F054', 'S3', 'd78e76c7-d5f9-4bd6-bb32-81449cecf034'::uuid, 'https://www.collarts.edu.au/courses/music-audio/music-audio-production/audio-production-bachelor-degree', 'this_course', 'independent_review'),
 ('F055', 'S1', '67621ff4-7842-48ef-9dff-e1f6cf3854ce'::uuid, 'https://www.kaa.edu.au/course/ict50220-diploma-of-information-technology/', 'this_course', 'independent_review'),
 ('F056', 'S1', '35507d50-af0e-4ca0-9bb8-e3f22b002a79'::uuid, 'https://xcelit.edu.au/advanced-diploma-of-program-management', 'this_course', 'independent_review'),
 ('F057', 'S2', '0454260b-25b8-47f9-b098-a3d4b2ce3f36'::uuid, 'https://nomicollege.com.au/diploma-of-project-management/', 'this_course', 'independent_review'),
 ('F058', 'S1', 'a0acb657-fb44-4c65-87f6-d87e6b629952'::uuid, 'https://mmc.edu.au/advanced-diploma-of-information-technology-telecom/', 'unsure', 'independent_review'),
 ('F059', 'S1', 'f1e5f47c-0858-410f-b4d3-a37f62658f1d'::uuid, 'https://protea.edu.au/chc33021-certificate-iii-in-individual-support-cricos-112631d/', 'this_course', 'independent_review'),
 ('F060', 'S1', 'b5ebeb8d-513c-4b27-a7a5-583394f992b5'::uuid, 'https://fusioncollege.edu.au/courses/rii50520-diploma-of-civil-construction-design/', 'this_course', 'independent_review'),
 ('F061', 'S1', '6a876b4b-f3cb-4d1a-b2fc-d7561a482e27'::uuid, 'https://genesis.edu.au/certificate-iii-in-carpentry/', 'this_course', 'independent_review'),
 ('F062', 'S1', 'aaa8aafa-0617-4c32-9d08-fd1b87873e16'::uuid, 'https://franklincollege.edu.au/cpc40120-certificate-iv-in-building-and-construction-building-cricos-course-code-116074g/', 'other_course', 'independent_review'),
 ('F063', 'S3', '23632c04-ac0f-4d1c-bd03-f16344adc11f'::uuid, 'https://www.collarts.edu.au/courses/fashion/fashion-marketing/branding-communication-bachelor-degree', 'this_course', 'independent_review'),
 ('F064', 'S1', '81df312c-1a52-4dd4-8d75-a94de985582a'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-social-work', 'this_course', 'independent_review'),
 ('F065', 'S2', '17019119-130c-493e-80b2-c4881c3d1a09'::uuid, 'https://sahe.nsw.edu.au/bachelor-of-business-accounting-major/', 'unsure', 'independent_review'),
 ('F066', 'S1', '888564ca-e1d7-4c0b-927a-f19f456719f7'::uuid, 'https://apsley.nsw.edu.au/diploma-of-leadership-and-management-bsb50420.php', 'this_course', 'independent_review'),
 ('F067', 'S1', 'b6dba407-4efc-41f3-b3bd-6b5b28911b7c'::uuid, 'https://smic.edu.au/courses/cert-iv-fitness/', 'generic', 'independent_review'),
 ('F068', 'S3', '37b75695-77c5-480e-87e1-82b9bba5afe9'::uuid, 'https://iitech.edu.au/chc30125-certificate-iii-in-early-childhood-education-and-care/', 'this_course', 'independent_review'),
 ('F069', 'S3', '8a210139-3aa5-4608-8f20-166f4b4212d3'::uuid, 'https://www.apeiro.edu.au/AUR40216-Certificate-IV-in-Automotive-Mechanical-Diagnosis', 'this_course', 'independent_review'),
 ('F070', 'S2', '912970bb-bfdd-4bc6-8a3a-1c5b5c66a3b3'::uuid, 'https://salfordcollege.edu.au/courses/fbp30521-certificate-iii-in-baking/', 'this_course', 'independent_review'),
 ('F071', 'S1', '50da8331-304e-417a-8bdd-70734c347d10'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-environmental-management', 'this_course', 'independent_review'),
 ('F072', 'S2', '4e925ce8-d5f3-44f7-bc28-28793edd674e'::uuid, 'https://austnursing.edu.au/chc43015-certificate-iv-in-ageing-support/', 'this_course', 'independent_review'),
 ('F073', 'S4', '5bf8e1c2-80c7-4eb8-862d-5197d263eb65'::uuid, 'https://www.mq.edu.au/study/information-for/international/study-abroad-exchange-and-study-tours/abroad', 'unsure', 'independent_review'),
 ('F074', 'S3', '4168d5f1-0cca-4100-9692-58adb1867672'::uuid, 'https://mcbt.vic.edu.au/our-courses/certificate-iv-in-automotive-mechanical-diagnosis/', 'this_course', 'independent_review'),
 ('F075', 'S2', 'e760c41b-7776-4c16-8c86-a5334d792684'::uuid, 'https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/master-of-educational-leadership-medld.html', 'this_course', 'independent_review'),
 ('F076', 'S2', '8651d213-c15b-4c5b-8018-6bcc97981f09'::uuid, 'https://www.tafesa.edu.au/xml/course/aw/aw_TP01248.aspx', 'unsure', 'independent_review'),
 ('F077', 'S2', '0ae25a1a-5ad7-4ad5-8b01-dbe78511de50'::uuid, 'https://www.whitireiaweltec.ac.nz/study-programmes/health/paramedicine/bachelor-of-health-science-paramedic', 'this_course', 'independent_review'),
 ('F078', 'S2', 'b4d18f0d-64a1-4736-88c3-7ad2ba1e3a74'::uuid, 'https://www.toiohomai.ac.nz/study/course/new-zealand-certificate-english-language-academic-level-4', 'this_course', 'independent_review'),
 ('F079', 'S2', 'cd82e118-be38-4936-a779-4f5da695fc2c'::uuid, 'https://www.ucol.ac.nz/programmes/laboratory-science/new-zealand-diploma-in-applied-science-level-5', 'this_course', 'independent_review'),
 ('F080', 'S2', 'f57423e4-3c78-4e74-aa5b-a0b0469f9fd9'::uuid, 'https://www.spcnm.ac.nz/nz-diploma-in-holistic-nutrition-level-6/', 'this_course', 'independent_review'),
 ('F081', 'S2', '20f6cfb8-c1d5-4c19-be7b-20cb731b1250'::uuid, 'https://www.nta.co.nz/courses/agriculture/new-zealand-certificate-in-agriculture-level-3-farming-systems/', 'unsure', 'independent_review'),
 ('F082', 'S1', '0a3d1bde-f115-4528-9259-eafe32accc2f'::uuid, 'https://www.tafensw.edu.au/international/courses/certificate-iii-in-apparel-fashion-and-textiles--MST31022', 'this_course', 'independent_review'),
 ('F083', 'S1', 'a51ae8dc-4668-4d25-a632-f2e7902cc30b'::uuid, 'https://www.tafensw.edu.au/international/courses/certificate-iv-in-real-estate-practice--CPP41419', 'this_course', 'independent_review'),
 ('F084', 'S1', '08e85b50-b8c5-4d33-9ac9-dac5c201abd9'::uuid, 'https://www.tafensw.edu.au/international/package/bachelor-of-information-technology-data-engineering--1473', 'other_course', 'independent_review'),
 ('F085', 'S3', '2fa0cea8-fefa-4ca5-8b3b-17297a219fce'::uuid, 'https://aim.edu.au/courses/graduate-diploma-of-music/', 'this_course', 'independent_review'),
 ('F086', 'S3', 'c24bffa2-6157-4ae1-a34f-85184aa5bfb8'::uuid, 'https://www.nztertiarycollege.ac.nz/early-childhood-education/undergraduate-qualifications/bachelor-teaching-early-childhood-education', 'this_course', 'independent_review'),
 ('F087', 'S2', 'dcbb4d90-4844-4080-ae0f-05b39ca4aa15'::uuid, 'https://www.massey.ac.nz/study/all-qualifications-and-degrees/master-of-professional-accountancy-chartered-accountant-PMPRA', 'this_course', 'independent_review'),
 ('F088', 'S1', '02fe0114-a3f7-4bfe-9c9e-75a89ff889e5'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/postgraduate-degrees/master-of-management', 'this_course', 'independent_review'),
 ('F089', 'S1', '03f271f7-18e9-4d1c-92de-3fb9e23ba4b9'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/diploma-in-social-science', 'this_course', 'independent_review'),
 ('F090', 'S1', '14d4dadd-2776-4aa6-9a83-cc85d071b13b'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-arts-bachelor-of-science', 'this_course', 'independent_review'),
 ('F091', 'S3', '71538a42-7867-4447-8a94-af94ca716595'::uuid, 'https://tpp.ac.nz/new-zealand-certificate-in-arts-and-design-level-3', 'this_course', 'independent_review'),
 ('F092', 'S1', '5c986e44-4e4e-47d5-a6bd-bcf41b76f6a1'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-business-bachelor-of-commerce-accounting', 'this_course', 'independent_review'),
 ('F093', 'S1', '72e0827c-da2f-43fe-b6f7-91e7a2a01061'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/undergraduate-certificate-in-animal-ecology', 'this_course', 'independent_review'),
 ('F094', 'S1', '8292990b-9df7-472d-a0fa-4b1549614087'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/study-abroad-full-year', 'this_course', 'independent_review'),
 ('F095', 'S1', '8d3d9387-0687-40a4-a0ce-80d8fef904d2'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-health-science', 'this_course', 'independent_review'),
 ('F096', 'S1', 'a6911f5f-185e-4c98-907f-8bde6a78ae61'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-prosthetics-and-orthotics', 'this_course', 'independent_review'),
 ('F097', 'S1', 'ddf55d1d-028d-474b-8120-e61eba95b582'::uuid, 'https://www.unisc.edu.au/study/courses-and-programs/bachelor-degrees-undergraduate-programs/bachelor-of-education-secondary-bachelor-of-science', 'this_course', 'independent_review'),
 ('F098', 'S3', '287fc99e-71f3-4918-b126-c78674a9b97c'::uuid, 'https://pihms.ac.nz/courses/postgraduate-diploma-in-hotel-management/', 'this_course', 'independent_review'),
 ('F099', 'S2', '1797e3ec-e809-4d20-944a-85d4e6dfb525'::uuid, 'https://www.toiohomai.ac.nz/study/course/new-zealand-certificate-study-and-employment-pathways-level-4', 'this_course', 'independent_review'),
 ('F100', 'S2', 'cb4b00a9-45a4-4693-88fb-ba7c13ec412c'::uuid, 'https://www.northtec.ac.nz/programmes/new-zealand-certificate-in-primary-industry-skills-level-2-horticulture', 'unsure', 'independent_review'),
 ('F101', 'S2', '2067f579-e825-41f4-b888-03b2215ba6c8'::uuid, 'https://www.whitireiaweltec.ac.nz/study-programmes/social-practice/social-work/bachelor-of-social-work', 'this_course', 'independent_review'),
 ('F102', 'S2', '4165c2d0-07ea-44f0-9e7b-2459e4101082'::uuid, 'https://www.whitireiaweltec.ac.nz/study-programmes/computing-and-it/information-technology/new-zealand-diploma-in-information-systems-level-5', 'this_course', 'independent_review'),
 ('F103', 'S2', '54bf689f-9faf-4a86-b897-5e760f525b52'::uuid, 'https://www.whitireiaweltec.ac.nz/study-programmes/health/health-and-wellbeing/new-zealand-certificate-in-health-and-wellbeing-social-and-community-services-level-4-community-health-work', 'unsure', 'independent_review'),
 ('F104', 'S2', '6d7102f1-3445-45e2-a0b6-e41f55e7331c'::uuid, 'https://www.whitireiaweltec.ac.nz/study-programmes/postgraduate/management/postgraduate-diploma-in-management', 'this_course', 'independent_review'),
 ('F105', 'S2', 'a3c52c43-eca3-421a-a2e5-4a0d30c0348b'::uuid, 'https://www.targeteducation.co.nz/our_courses/new-zealand-certificate-in-hospitality-level-2/', 'this_course', 'independent_review'),
 ('F106', 'S5', '0d3942e4-cb96-4e04-be3d-9ee32c4a995a'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-education/', 'other_course', 'person_layer4'),
 ('F107', 'S5', 'b058b082-0cf5-42f0-899e-2fd1a741a98d'::uuid, 'https://www.sydney.edu.au/courses/courses/pc/master-of-science-in-medicine-advanced-metabolic-health.html', 'other_course', 'person_layer4'),
 ('F108', 'S5', 'e8cdbe32-a530-437d-97b0-5626e38cc452'::uuid, 'https://adelaideuni.edu.au/study/degrees/graduate-diploma-in-immersive-media-technologies/', 'other_course', 'person_layer4'),
 ('F109', 'S5', '10e33f07-1f6e-4cd1-92a9-a577f31a2c69'::uuid, 'https://adelaideuni.edu.au/study/degrees/doctor-of-philosophy/', 'other_course', 'person_layer4'),
 ('F110', 'S5', 'bde15e28-37d4-4893-9732-bf73fc054acd'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-public-health/', 'other_course', 'person_layer4'),
 ('F111', 'S5', '8471e59f-4d01-4d1e-81e8-2979190a00cf'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-psychology-honours-cognitive-neuroscience/', 'other_course', 'person_layer4'),
 ('F112', 'S5', '9d12da79-97a9-4543-a5c6-d5acd49ad9b0'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-engineering-mechanical-honours/', 'other_course', 'person_layer4'),
 ('F113', 'S5', '78819394-4f7e-4380-afd4-ef9f1bd3d4dd'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-professional-engineering-energy-resources/', 'other_course', 'person_layer4'),
 ('F114', 'S5', '850532eb-766b-4ea7-bfa2-bad1781a09f1'::uuid, 'https://handbook.latrobe.edu.au/courses/2025/hd003b', 'other_course', 'person_layer4'),
 ('F115', 'S5', '88428767-cd67-46cd-af6d-d4883d363389'::uuid, 'https://adelaideuni.edu.au/study/degrees/graduate-certificate-in-counselling-and-psychotherapy/', 'other_course', 'person_layer4'),
 ('F116', 'S5', 'c0f3f18b-cc84-4da2-90e4-93404672b978'::uuid, 'https://adelaideuni.edu.au/study/degrees/graduate-diploma-in-public-health/', 'other_course', 'person_layer4'),
 ('F117', 'S5', '65968514-89ec-4756-a984-7a7155d38662'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-podiatry-honours/', 'other_course', 'person_layer4'),
 ('F118', 'S5', 'e821390f-5460-4e78-ac0c-78233d414009'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-aboriginal-studies/', 'other_course', 'person_layer4'),
 ('F119', 'S5', '760c67c4-38bc-48bb-9468-65be32c615cd'::uuid, 'https://adelaideuni.edu.au/study/degrees/diploma-in-mathematical-studies/', 'other_course', 'person_layer4'),
 ('F120', 'S5', '0cf3ba0b-fd7b-496f-ba83-04b8b60d5ad8'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-laws-honours-bachelor-of-international-relations/', 'other_course', 'person_layer4'),
 ('F121', 'S5', '1cc0cc56-a692-420e-881c-f39e13ab9e1d'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-exercise-and-sport-science/', 'other_course', 'person_layer4'),
 ('F122', 'S5', '1b27f371-1e3e-47ed-8ae5-0dbb608d31be'::uuid, 'https://handbook.latrobe.edu.au/courses/2027/HA008', 'other_course', 'person_layer4'),
 ('F123', 'S5', '6e7843b8-3493-4a33-b99b-16c9c2e99305'::uuid, 'https://adelaideuni.edu.au/study/degrees/graduate-certificate-in-wine-and-food-business/', 'other_course', 'person_layer4'),
 ('F124', 'S5', '30136bd2-94ea-43e1-8962-aac1e59d4e40'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-teaching-primary-honours/', 'other_course', 'person_layer4'),
 ('F125', 'S5', '62c9f170-6901-4fe2-96ae-0e63f98b57b7'::uuid, 'https://adelaideuni.edu.au/study/degrees/graduate-certificate-in-business-administration/', 'other_course', 'person_layer4'),
 ('F126', 'S5', 'adb0fd6b-d06f-4e2f-895e-60b92adf37d3'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-fine-arts/', 'other_course', 'person_layer4'),
 ('F127', 'S5', '15758604-590d-40ad-a25e-ad2611ebd427'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-accounting-and-finance/', 'other_course', 'person_layer4'),
 ('F128', 'S5', '1e3877c2-d6fc-4798-b4f0-5f7096db67c0'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-project-management/', 'other_course', 'person_layer4'),
 ('F129', 'S5', 'c0dc5799-d71f-4316-a482-1da5321ec8b0'::uuid, 'https://adelaideuni.edu.au/study/degrees/bachelor-of-occupational-therapy-honours/', 'other_course', 'person_layer4'),
 ('F130', 'S5', '8d38adde-0259-480a-960d-0ed833866c3e'::uuid, 'https://adelaideuni.edu.au/study/degrees/master-of-midwifery/', 'other_course', 'person_layer4'),
 ('F131', 'S6', 'd1da3e16-de85-5668-ae8a-df08c763f741'::uuid, 'http://www.sfu.ca/students/calendar/programs/physical-geography/major/bachelor-of-science.html', 'this_course', 'person_layer4'),
 ('F132', 'S6', '80c0cbd8-08c8-5964-94ee-81f827246595'::uuid, 'https://www.sfu.ca/students/calendar/programs/counselling-psychology/master-of-education.html', 'this_course', 'person_layer4'),
 ('F133', 'S6', '1491806f-cf66-49c0-96de-db50fcf1312d'::uuid, 'https://programsandcourses.anu.edu.au/program/blany', 'this_course', 'person_layer4'),
 ('F134', 'S6', '5542fe5a-a9f0-4a4e-a212-2fad7b001803'::uuid, 'https://www.uts.edu.au/courses/master-of-finance', 'this_course', 'person_layer4'),
 ('F135', 'S6', '3fbe9656-8425-5a4d-a876-e47e92ed0441'::uuid, 'https://www.sfu.ca/students/calendar/programs/biological-sciences/master-of-science.html', 'this_course', 'person_layer4'),
 ('F136', 'S6', '9a109aba-c123-4064-815c-72a57e8af0f0'::uuid, 'https://www.flinders.edu.au/online/courses/diploma-information-technology', 'this_course', 'person_layer4'),
 ('F137', 'S6', '15fe6900-bb91-430e-96b6-4591cd8eee9c'::uuid, 'https://www.canberra.edu.au/course/322JA/5', 'this_course', 'person_layer4'),
 ('F138', 'S6', '91f54d93-0cf8-4b78-b6f9-154f1455e006'::uuid, 'https://www.canberra.edu.au/course/HLM601/1', 'this_course', 'person_layer4'),
 ('F139', 'S6', '2e37f32a-5006-4188-9448-82184fadb8bc'::uuid, 'https://programsandcourses.anu.edu.au/program/8066xmphil', 'this_course', 'person_layer4'),
 ('F140', 'S6', 'c26925a7-b138-4249-8a1e-dd1cd9f90670'::uuid, 'https://programsandcourses.anu.edu.au/program/mfors', 'this_course', 'person_layer4'),
 ('F141', 'S6', 'c6d7f4d7-9785-4fc3-8469-1a77f2b5c09a'::uuid, 'https://programsandcourses.anu.edu.au/program/hppol', 'this_course', 'person_layer4'),
 ('F142', 'S6', '18297d0a-f955-5307-b98c-1a4aab81dcc5'::uuid, 'https://www.sfu.ca/students/calendar/programs/statistics/doctor-of-philosophy.html', 'this_course', 'person_layer4'),
 ('F143', 'S6', '155987c2-1ab4-5cd1-a20f-deb44172aac9'::uuid, 'http://www.sfu.ca/students/calendar/programs/urban-worlds/major/bachelor-of-arts.html', 'this_course', 'person_layer4'),
 ('F144', 'S6', 'e50542b2-6bc4-443d-838f-b08d56db9ccd'::uuid, 'https://www.canberra.edu.au/course/330JA/7', 'this_course', 'person_layer4'),
 ('F145', 'S6', '0bcba864-9ec7-4286-89bc-73103360b37b'::uuid, 'https://www.canberra.edu.au/course/HLM102/1', 'this_course', 'person_layer4'),
 ('F146', 'S6', 'd706565d-8136-5852-bdc3-b99d13caaafc'::uuid, 'http://www.sfu.ca/students/calendar/programs/education-as-a-second-bachelor-degree/bachelor-of-education.html', 'this_course', 'person_layer4'),
 ('F147', 'S6', 'b4ecafba-0058-4ad1-b645-b10ac2ac71a4'::uuid, 'https://www.canberra.edu.au/course/973AA/7', 'this_course', 'person_layer4'),
 ('F148', 'S6', '25dcb919-96c3-4aaa-8bc6-4ffa5f0b726c'::uuid, 'https://programsandcourses.anu.edu.au/program/binsy', 'this_course', 'person_layer4'),
 ('F149', 'S6', '6adbf0bd-1125-48df-9ad8-bcfe282800c6'::uuid, 'https://www.canberra.edu.au/course/ABB002/2', 'this_course', 'person_layer4'),
 ('F150', 'S6', 'a7843bb1-8452-533f-b6cd-466a5a1a8ca3'::uuid, 'http://www.sfu.ca/students/calendar/programs/health-sciences/major/bachelor-of-science.html', 'this_course', 'person_layer4'),
 ('F151', 'S6', 'a0ed9ee5-5664-4118-92da-9c4bf5b67e8a'::uuid, 'https://www.canberra.edu.au/course/EDM301/1', 'this_course', 'person_layer4'),
 ('F152', 'S6', '19dfab8d-59d3-57e8-a2ff-358141abdb0d'::uuid, 'http://www.sfu.ca/students/calendar/programs/criminology/major/bachelor-of-arts.html', 'this_course', 'person_layer4'),
 ('F153', 'S6', 'b030354b-3b14-49f0-8e46-458537bdf67e'::uuid, 'https://www.canberra.edu.au/course/HLB301/1', 'this_course', 'person_layer4'),
 ('F154', 'S6', '4a641a46-e7b5-42bf-b67c-436e84f1c735'::uuid, 'https://www.canberra.edu.au/course/373JA/4', 'this_course', 'person_layer4'),
 ('F155', 'S6', '0819f98d-d601-42f7-ab5c-d50b6887c384'::uuid, 'https://programsandcourses.anu.edu.au/program/8510xmphil', 'this_course', 'person_layer4'),
 ('F156', 'S7', 'ed8d5519-255a-4771-9ac9-ed990ed2d49e'::uuid, 'https://collegiate.tas.edu.au/our-school/history/', 'generic', 'independent_review'),
 ('F157', 'S7', 'ced3341f-9326-497a-85f6-484d05595a0b'::uuid, 'https://www.nzist.ac.nz/scholarship', 'generic', 'independent_review'),
 ('F158', 'S7', 'c72574dd-90c8-410b-bbd2-2409f691da77'::uuid, 'https://www.nzist.ac.nz/scholarship', 'generic', 'independent_review'),
 ('F159', 'S7', 'dfe0e1e6-be1d-4583-a4c4-7de2aa32678a'::uuid, 'https://www.waikato.ac.nz/study/qualifications/bachelor-of-computer-science/', 'other_course', 'independent_review'),
 ('F160', 'S7', '3b6627a1-3ebb-4ac0-a86b-28864f97997d'::uuid, 'https://handbook.unimelb.edu.au/2026/courses/364aa', 'generic', 'independent_review'),
 ('F161', 'S7', '22e40382-0954-4135-be08-c873aa6bd167'::uuid, 'https://ebe.ac.nz/contact-us/', 'generic', 'independent_review'),
 ('F162', 'S7', '6693d1e3-a2a6-4c42-a8dc-892c99d11193'::uuid, 'https://www.uts.edu.au/courses/bachelor-of-communication-journalism-bachelor-of-international-studies', 'generic', 'independent_review'),
 ('F163', 'S7', '7934b424-b1ee-4f61-8b06-7c622664c09f'::uuid, 'https://www.uts.edu.au/courses/graduate-certificate-in-vision-science-phd-thesis-science', 'generic', 'independent_review'),
 ('F164', 'S7', '67d79d9a-f8a4-4ff2-bb69-3661882ffd31'::uuid, 'https://kcbt.edu.au/student-course-variation-form/', 'generic', 'independent_review'),
 ('F165', 'S7', '217650fe-e843-5e05-a2d0-c3eabd9ec745'::uuid, 'https://arts.ucalgary.ca/art/future-students/undergraduate/programs/visual-arts-ed', 'other_course', 'independent_review'),
 ('F166', 'S7', 'fd03b118-8ee8-513e-b7d4-ff159e92756e'::uuid, 'http://www.sfu.ca/students/calendar/programs/information-systems-in-business-administration-and-computing-science/joint-major/bachelor-of-business-administration-or-bachelor-of-science.html', 'other_course', 'independent_review'),
 ('F167', 'S7', '936c89e4-f691-4d72-b050-a81a939bd70d'::uuid, 'https://www.ara.ac.nz/products/programme/nz2596-stru-new-zealand-diploma-in-information-technology-technical-support-level-5/', 'other_course', 'independent_review'),
 ('F168', 'S7', '6311ac83-f3e1-4669-bda1-a6af7085499f'::uuid, 'https://www.mediadesignschool.com/courses/undergraduate-studies/bachelor-information-technology', 'other_course', 'independent_review'),
 ('F169', 'S7', 'a5705d57-aeb1-4bb2-8fd2-0f03176546da'::uuid, 'https://www.uts.edu.au/courses/graduate-diploma-in-interaction-design-phd-thesis-science', 'generic', 'independent_review'),
 ('F170', 'S7', '1798e709-09d7-57cb-afb1-277ee0ec3136'::uuid, 'https://fccs.ok.ubc.ca/degrees-programs/undergraduate-programs/art-history-visual-culture/', 'other_course', 'independent_review'),
 ('F171', 'S7', '108fa656-89ec-40d3-a9f4-f1fd966b2a0a'::uuid, 'https://www.waikato.ac.nz/study/fees-costs/international-tuition-costs/', 'generic', 'independent_review'),
 ('F172', 'S7', '81c6e565-f239-47f1-ad74-aa71fc6f4b5c'::uuid, 'https://www.nta.co.nz/international-student-info/course-fees-and-living-costs/', 'generic', 'independent_review'),
 ('F173', 'S7', 'cac9a8f9-61d2-4805-9723-1e8efbfd9523'::uuid, 'https://get.edu.au/online-application', 'generic', 'independent_review'),
 ('F174', 'S7', 'e74ce58d-74cf-429b-a7b5-a0ad365a50ea'::uuid, 'https://hillsong.com/college/fees/', 'generic', 'independent_review'),
 ('F175', 'S7', '9d1fd904-052a-4861-a26a-63f4d2b2dd98'::uuid, 'https://www.uts.edu.au/courses/master-of-environmental-engineering-management-phd-thesis-science', 'generic', 'independent_review'),
 ('F176', 'S8', '23773808-f23e-43c2-afa3-1d29b8ae26d2'::uuid, 'https://www.oneuedu.com/courses/advanced-diploma-of-hospitality-management-091128G', 'other_course', 'independent_review'),
 ('F177', 'S8', 'd4499602-9ada-433e-936d-5d52c0c5905a'::uuid, 'https://www.oneuedu.com/courses/diploma-of-community-services-102539E', 'other_course', 'independent_review'),
 ('F178', 'S8', 'bfd17128-fe3a-4245-90f0-fc63770166b3'::uuid, 'https://handbook.flinders.edu.au/courses/2026/BSCHBD', 'this_course', 'independent_review'),
 ('F179', 'S8', '7a323961-fbf9-4ddf-b404-1c5fae971c02'::uuid, 'https://www.oneuedu.com/courses/diploma-of-business-103719D', 'other_course', 'independent_review'),
 ('F180', 'S8', '1afc288c-705d-49d4-ba57-1f5e62b74c45'::uuid, 'https://handbook.federation.edu.au/ords/r/curriculum/catalogue/program?P5_CODE=EY9.MEC&P0_CATALOGUE_YEAR=2027&P0_CATALOGUE_TERM=0900', 'this_course', 'independent_review'),
 ('F181', 'S8', '4e97513b-b5a4-460a-b38e-4b43faffba78'::uuid, 'https://www.oneuedu.com/courses/graduate-diploma-of-management-learning-103566E', 'other_course', 'independent_review'),
 ('F182', 'S8', '551f696b-e203-4f76-b51d-435c6fe18bf6'::uuid, 'https://www.acos.edu.au/course/certificate-iv-in-disability', 'this_course', 'independent_review'),
 ('F183', 'S8', '201dc7e9-b5ad-4b0d-b9f8-fe3dcd50a16c'::uuid, 'https://datum.edu.au/sit50422-diploma-of-hospitality-management/', 'this_course', 'independent_review'),
 ('F184', 'S8', '4c6f22e0-0cb5-4aca-bbb0-620b1c2e1652'::uuid, 'https://handbook.unimelb.edu.au/2026/courses/mc-dnce', 'this_course', 'independent_review'),
 ('F185', 'S8', '239f873c-00b8-48e1-853b-b0259d219f59'::uuid, 'https://findthecourses.com.au/courses/details/advanced-diploma-of-leadership-and-management', 'other_course', 'independent_review'),
 ('F186', 'S8', 'ab3d23b1-b53d-448d-be40-3b87bfba7251'::uuid, 'https://www.oneuedu.com/courses/certificate-iii-in-individual-support-0101908', 'other_course', 'independent_review'),
 ('F187', 'S8', '4934c63e-3aa9-474b-bd34-e6309e71fe87'::uuid, 'https://www.oneuedu.com/courses/diploma-of-leadership-and-management-103711A', 'other_course', 'independent_review'),
 ('F188', 'S8', 'd04e388c-854b-4ac1-a74a-8d563ea6573d'::uuid, 'https://www.oneuedu.com/courses/diploma-of-leadership-and-management-103717F', 'other_course', 'independent_review'),
 ('F189', 'S8', '2b66ab83-a153-41ab-b3c0-fce45b54ec4f'::uuid, 'https://brooksideinternationalcollege.edu.au/courses/advanced-diploma-of-leadership-and-management/', 'this_course', 'independent_review'),
 ('F190', 'S8', '4aa923b0-ea65-488e-a267-4d6e3b4d5844'::uuid, 'https://www.oneuedu.com/courses/advanced-diploma-of-accounting-098587B', 'other_course', 'independent_review'),
 ('F191', 'S9', '1dc90caa-afda-4647-aa32-70eaf6b2b31d'::uuid, 'https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/bachelor-of-education-teaching-bedtchg.html', 'other_course', 'independent_review'),
 ('F192', 'S9', '3fa7b6b2-2f40-414e-b601-7e7949ae3afa'::uuid, 'https://www.flinders.edu.au/study/courses/postgraduate-doctor-medicine', 'other_course', 'independent_review'),
 ('F193', 'S9', '996f19d8-7f4a-4f82-9f0d-4466b1f626ad'::uuid, 'https://www.federation.edu.au/units/humov9201-doctor-of-human-movement-social-science-ft/', 'other_course', 'independent_review'),
 ('F194', 'S9', 'c1d11c5f-d17e-5c0b-a9dd-db9f3814c8fe'::uuid, 'https://science.ucalgary.ca', 'generic', 'independent_review'),
 ('F195', 'S9', '34cbce75-c9a1-4a47-9626-63d9cae3bd42'::uuid, 'https://www.wananga.ac.nz/study/certificates/te-pou-hono-ki-marae-atea', 'other_course', 'independent_review'),
 ('F196', 'S9', '562a3524-be06-448f-b4bf-3bdd94c72720'::uuid, 'https://www.aut.ac.nz/courses/postgraduate-certificate-in-arts', 'unsure', 'independent_review'),
 ('F197', 'S9', '03d62e55-4a9d-48d0-877f-f57471586d65'::uuid, 'https://www.notredame.edu.au/programs/school-of-nursing/undergraduate/bachelor-of-nursing', 'this_course', 'independent_review'),
 ('F198', 'S9', '70de0a26-d3ed-414c-b5fd-e80270315662'::uuid, 'https://www.stcatherines.net.au/admissions/study-in-australia/attachment/stc_international-student-welcome-handbook-website/', 'generic', 'independent_review'),
 ('F199', 'S1', '1d7146ca-a8e1-461d-b2a8-466b1d208b27'::uuid, 'https://australianpolytechnic.edu.au/courses/general-english-elicos/', 'this_course', 'independent_review'),
 ('F200', 'S1', '66e8815a-dbf9-402d-b999-4f2fb4e9dfb4'::uuid, 'https://www.tafensw.edu.au/international/courses/certificate-iv-in-tertiary-preparation--11225NAT', 'this_course', 'independent_review')
  ) f(case_id, stratum, course_id, url, gold, src)
  cross join lateral (select security.aer_v2_identity_settle_check_v1(f.course_id) c) x
on conflict (case_id) do nothing;

-- 5. settings (G2), job (G1) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.v2_identity_settle_on', 'Entry requirements v2: settle stored pages with their own identity proof',
  '1: twice an hour, stored official course pages left ambiguous although they carry the course''s own identity proof are bound when the E16 check passes, no person decision or earlier rejection exists and exactly one catalogue course matches (security.aer_v2_identity_settle_check_v1). Every decision is kept in pipeline.aer_v2_identity_settlements. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1548, 'Entry requirements', 'security.aer_v2_identity_settle_v1 (job aer-v2-identity-settle)',
  'S1-AER Platform Admin decision 2 (13 Nov 2026): roll out once the 200-case fixture shows zero incorrect bindings (post-check of migration 20261113361500)'),
 ('pipeline', 'batch.aer_v2_identity_settle', 'Entry requirements v2: stored pages settled per run',
  'Each run of the settle step looks at most at this many ambiguous stored pages (AER-eligible providers first).',
  'number', to_jsonb(1000), 10, 2000, 'pages', 1549, 'Entry requirements', 'security.aer_v2_identity_settle_v1 (job aer-v2-identity-settle)', 'S1-AER decision 2 (13 Nov 2026)')
on conflict (toolset_key, key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-v2-identity-settle', 'Course pages', 42, 'Entry requirements v2: settle stored pages with their own identity proof',
  'At :22 and :52: while aer.v2_identity_settle_on is 1, looks at up to batch.aer_v2_identity_settle ambiguous stored official course pages that carry the course''s own identity proof and binds those that pass security.aer_v2_identity_settle_check_v1 (E16 check, no person decision or earlier rejection, one catalogue course), through the binding trigger. Every decision is recorded in pipeline.aer_v2_identity_settlements. No Firecrawl and no AI.',
  6, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'aer-v2-identity-settle') then
    perform cron.schedule('aer-v2-identity-settle', '22,52 * * * *', 'select security.aer_v2_identity_settle_v1()');
  end if;
end $j$;

-- 6. register (housekeeping) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-v2-identity-settle', 'Layer 2', 'Entry requirements', 'AER v2 stored-page identity step 1: bind ambiguous stored pages with their own proof after E16 (S1-AER decision 2)', 'active', '{}', '20261113361500'),
 ('table', 'pipeline.aer_v2_identity_settlements', 'Layer 2', 'Entry requirements', 'Every stored-page identity settle decision: page, evidence, proof, prior status, E16 verdict, rule version, actor', 'active', '{}', '20261113361500'),
 ('table', 'pipeline.aer_v2_identity_fixture', 'Layer 2', 'Entry requirements', 'The 200-case stored-page identity precision fixture with gold labels and the settle rule''s decision', 'active', '{}', '20261113361500')
on conflict do nothing;

-- 7. post-checks: 200 cases, zero incorrect bindings, switch, job and catalogue ------------------------------------------------------------------------------
do $c$
declare v jsonb := security.aer_v2_identity_fixture_report_v1();
begin
  if (v->>'cases')::int <> 200 then raise exception 'post-check: the fixture holds 200 cases (has %)', v->>'cases'; end if;
  if (v->>'incorrect_bindings')::int <> 0 then raise exception 'post-check: the settle rule binds % fixture case(s) not gold-labelled this course: %', v->>'incorrect_bindings', v; end if;
  if (v->>'bound')::int < 1 then raise exception 'post-check: the settle rule binds no fixture case: %', v; end if;
  if not exists (select 1 from cron.job where jobname = 'aer-v2-identity-settle') or not exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-v2-identity-settle') then
    raise exception 'post-check: job aer-v2-identity-settle scheduled and catalogued';
  end if;
  if security.pipeline_num_v1('batch.aer_v2_identity_settle', -1) < 10 then raise exception 'post-check: batch.aer_v2_identity_settle'; end if;
  if (security.aer_v2_identity_settle_v1(false)->>'mode') <> 'dry_run' then raise exception 'post-check: the dry run records and binds nothing'; end if;
  if exists (select 1 from pipeline.aer_v2_identity_settlements where mode = 'apply') then raise exception 'post-check: nothing was bound by this change'; end if;
end $c$;
