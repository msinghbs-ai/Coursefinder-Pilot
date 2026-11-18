-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 13:06: "Autonomously resolve all 57 Scholarship course links items without user intervention":
-- auto-apply the deterministic title/description scopes, expand the keywords for the rest, All courses only for an explicitly university-wide
-- award, No courses when not course-specific; full audit entries).
-- What it does:
--   1. Sharper rule-based scope (security.scholarship_scope_suggest_v1 replaced; same signature):
--      - subject words come from the scholarship's NAME first (its "in ..." phrase, then the subject words, then a degree code such as MBChB);
--        its description is read only when the name names no subject (an accommodation award's description mentioned "education" and had
--        linked it to 27 courses; "Science" alone in a description had linked 87);
--      - a name phrase no course title holds whole ("Engineering Science", "Marine Science") falls back to its first word;
--      - a subject word inside a longer subject found is dropped ("Science" inside "Animal Science");
--      - aliases (setting scholarship.scope_suggest_aliases): degree codes matched case-sensitively (ME, MOR, MBChB, LLB, BCom, MBA, BMus, IT,
--        FMHS) and stems (Orchestral=Music, Agriculture=Agri, Horticulture=Horticultur) add course title words;
--      - degree codes and secondary-school graduates add study levels; a doctoral scope with a subject also keeps the Doctor of Philosophy.
--   2. A deterministic decision per waiting scholarship (security.scholarship_scope_auto_decide_v1), in this order:
--      (a) a pattern of setting scholarship.scope_none_patterns in its name or description (transfer-student notices, accommodation, another
--          university's exchange award): No courses;
--      (b) a scope that keeps at least one proposed course: that scope (Only matching courses);
--      (c) a pattern of setting scholarship.scope_all_patterns (General Scholarships, Vice-Chancellor, International Merit, Academic Excellence,
--          "all programmes" and the like) with no level or subject restriction found: All courses;
--      (d) otherwise: No courses (the scholarship's own text names no scope that can be proved; a person can change it on the Course links
--          screen at any time, which applies the new decision in place of this one).
--   3. Applied to all 57 waiting scholarships under the automated rule authority (security.system_actor_id()), exactly as
--      public.admin_scholarship_links_decide does it: the decision in pipeline.scholarship_scope_decisions with the reason "Auto-applied
--      deterministic title/description scope rule: ..." and the rule and words used, security.scholarship_scope_apply_v1 (unchanged), and a
--      pipeline.layer4_mass_operations row per scholarship. The 57 Layer 4 items (Scholarship course links) settle.
-- G1: no new job. G2: the word lists are settings. G3: no consumer API object's shape is changed; course links are data the API already reads.
-- Replaces: security.scholarship_scope_suggest_v1 of migration 20261118143000 (sharper rules, same output)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text;
begin
  v := md5(pg_get_functiondef('security.scholarship_scope_suggest_v1(uuid)'::regprocedure));
  if v <> '9342f166064b89beb39acea9afa94707' then raise exception 'security.scholarship_scope_suggest_v1 is not the definition this migration replaces (md5 %)', v; end if;
  v := md5(pg_get_functiondef('security.scholarship_scope_apply_v1(uuid,uuid)'::regprocedure));
  if v <> '55d2012984ee2c1779e6d83e0231ee57' then raise exception 'security.scholarship_scope_apply_v1 is not the definition this migration relies on (md5 %)', v; end if;
end $pre$;

-- 1. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.scope_suggest_aliases', 'Scholarship course links: aliases (word=course title words)',
  'Each entry is WORD=title words. A degree code in capitals (for example MBChB, ME, LLB) is matched exactly; other words are matched in any case. When found in a scholarship''s name or description, the title words on the right are added to its suggested course scope.',
  'list', '["MBChB=Medicine", "ME=Engineering", "MEng=Engineering", "MOR=Operations Research", "LLB=Law", "LLM=Law", "BCom=Commerce", "MBA=Business", "BMus=Music", "IT=Information Technology", "FMHS=Medical, Health, Medicine", "Orchestral=Music", "Agriculture=Agri", "Horticulture=Horticultur"]'::jsonb,
  0, null, 'entries', 341, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 13:06 (resolve all 57 scholarship course links)', 'Scholarships', 'security.scholarship_scope_suggest_v1'),
 ('pipeline', 'scholarship.scope_all_patterns', 'Scholarship course links: university-wide award wording (All courses)',
  'Wording that marks an award open to every programme. A scholarship whose name or description holds one, and that names no study level or subject, is linked to all courses of its provider.',
  'list', '["General Scholarships", "Vice-Chancellor", "International Merit", "Academic Excellence", "all programmes", "all programs", "any programme", "any program", "all degrees", "any degree", "open to all students"]'::jsonb,
  0, null, 'patterns', 342, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 13:06 (All courses strictly when explicitly university-wide)', 'Scholarships', 'security.scholarship_scope_auto_decide_v1'),
 ('pipeline', 'scholarship.scope_none_patterns', 'Scholarship course links: not course-specific wording (No courses)',
  'Wording that marks a page or award not tied to any course of the provider (notices for transfer students, accommodation, an exchange at another university). A scholarship whose name or description holds one is linked to no course.',
  'list', '["Transfer Student", "Notification of Award", "Eligibility & Claiming", "Renewing Award", "Accommodation", "after you graduate", "Huayu", "study abroad", "exchange programme", "exchange program"]'::jsonb,
  0, null, 'patterns', 343, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 13:06 (No courses when not course-specific)', 'Scholarships', 'security.scholarship_scope_auto_decide_v1')
on conflict (toolset_key, key) do nothing;

-- 2. The sharper suggestion
create or replace function security.scholarship_scope_suggest_v1(p_scholarship_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare s record; v_name text; v_text text; v_levels text[] := '{}'; v_subj text[] := '{}'; v_titles text[] := '{}'; v_ids jsonb;
        v_filter jsonb := '{}'::jsonb; v_cand int; v_match int := 0; w text; a text; v_phrase text; v_tok text; v_words text; v_pat text;
        v_name_code boolean := false; v_from_phrase boolean := false;
        v_esc constant text := '([.*+?^${}()|\[\]\\])';  -- fixed: characters escaped in a word used in a pattern
begin
  select x.id, x.name, coalesce(x.description, '') description into s from scholarship.scholarships x where x.id = p_scholarship_id;
  if not found then return null; end if;
  v_name := s.name; v_text := s.name || ' ' || s.description;
  -- study levels, from the scholarship's own words (degree codes matched exactly)
  if v_text ~* '\m(doctoral|doctorate|ph\.?d)\M' then v_levels := v_levels || array['doctorate']; end if;
  if v_text ~* '\m(masters?|master''s)\M' or v_text ~ '\m(ME|MEng|MOR|MBA|LLM|MSc)\M' then v_levels := v_levels || array['masters', 'masters_coursework', 'masters_extended', 'masters_research']; end if;
  if v_text ~* '\mpostgraduate\M|\mgraduate (research|study|studies|students?)\M' and not (v_text ~* '\m(masters?|master''s|doctoral|doctorate|ph\.?d)\M' or v_text ~ '\m(ME|MEng|MOR|MBA|LLM|MSc)\M') then
    v_levels := v_levels || array['graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended', 'masters_research', 'doctorate'];
  end if;
  if v_text ~* '\m(undergraduate|bachelor|first[- ]year|school leavers?|entry[- ]level|entrance)\M|secondary[- ]school graduates?|graduated? from (a )?secondary[- ]school'
     or v_text ~ '\m(MBChB|LLB|BCom|BMus|BSc|BEng)\M' then
    v_levels := v_levels || array['bachelor', 'bachelor_honours'];
  end if;
  select coalesce(array_agg(distinct l), '{}') into v_levels from unnest(v_levels) l;
  select coalesce(jsonb_agg(sl.id::text order by sl.code), '[]'::jsonb) into v_ids from ref.study_levels sl where sl.code = any (v_levels);
  -- (1) a subject phrase the name gives after "in" ("Scholarship in Accounting & Finance"), split at "&" and "and"
  v_phrase := substring(v_name from '\min (?:the )?((?:[A-Z][A-Za-z]+)(?:\s+(?:&|and)?\s*[A-Z][A-Za-z]+)*)\s*(?:\(|$)');
  if v_phrase is not null and v_phrase !~* '^(the )?(university|faculty|canada|new zealand|australia)' then
    v_subj := array(select btrim(x) from regexp_split_to_table(v_phrase, '\s+(?:&|and)\s+') x where btrim(x) <> '');
    v_from_phrase := cardinality(v_subj) > 0;
  end if;
  -- (2) subject words of the setting found in the name
  if cardinality(v_subj) = 0 then
    for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_subjects'), '[]'::jsonb)) loop
      if v_name ~* ('\m' || regexp_replace(w, v_esc, '\\\1', 'g') || '\M') then v_subj := v_subj || w; end if;
    end loop;
  end if;
  -- (3) aliases: a degree code (capitals, matched exactly) in the name decides the subject before the description is read
  for a in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_aliases'), '[]'::jsonb)) loop
    v_tok := btrim(split_part(a, '=', 1)); v_words := btrim(split_part(a, '=', 2));
    continue when v_tok = '' or v_words = '' or v_tok !~ '[A-Z]{2}';
    if v_name ~ ('\m' || regexp_replace(v_tok, v_esc, '\\\1', 'g') || '\M') then
      v_name_code := true; v_titles := v_titles || array(select btrim(x) from regexp_split_to_table(v_words, '\s*,\s*') x where btrim(x) <> '');
    end if;
  end loop;
  -- (4) the description is read only when the name gives no subject
  if cardinality(v_subj) = 0 and not v_name_code then
    for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_subjects'), '[]'::jsonb)) loop
      if s.description ~* ('\m' || regexp_replace(w, v_esc, '\\\1', 'g') || '\M') then v_subj := v_subj || w; end if;
    end loop;
  end if;
  -- a subject inside a longer subject found is dropped ("Science" inside "Animal Science")
  select coalesce(array_agg(x order by x), '{}') into v_subj from (select distinct x from unnest(v_subj) x) d
   where not exists (select 1 from unnest(v_subj) y where y <> d.x and position(lower(d.x) in lower(y)) > 0);
  v_titles := v_titles || v_subj;
  -- (5) other aliases: degree codes in the description (when the name gave none), stems for words already read
  if not v_name_code then
    for a in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_aliases'), '[]'::jsonb)) loop
      v_tok := btrim(split_part(a, '=', 1)); v_words := btrim(split_part(a, '=', 2));
      continue when v_tok = '' or v_words = '';
      v_pat := '\m' || regexp_replace(v_tok, v_esc, '\\\1', 'g') || '\M';
      if (v_tok ~ '[A-Z]{2}' and v_text ~ v_pat)
         or (v_tok !~ '[A-Z]{2}' and (exists (select 1 from unnest(v_subj) z where z ~* v_pat) or v_name ~* v_pat)) then
        v_titles := v_titles || array(select btrim(x) from regexp_split_to_table(v_words, '\s*,\s*') x where btrim(x) <> '');
      end if;
    end loop;
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_titles from unnest(v_titles) x;
  -- a doctoral scope with a subject keeps the Doctor of Philosophy (the research doctorate of every subject)
  if 'doctorate' = any (v_levels) and cardinality(v_titles) > 0 then v_titles := v_titles || array['Doctor of Philosophy']; end if;
  if jsonb_array_length(v_ids) > 0 then v_filter := v_filter || jsonb_build_object('levels', v_ids); end if;
  if cardinality(v_titles) > 0 then v_filter := v_filter || jsonb_build_object('title', array_to_string(v_titles, ', ')); end if;
  select count(*) into v_cand from scholarship.course_mapping_candidates c where c.scholarship_id = p_scholarship_id and c.status = 'needs_review';
  if v_filter <> '{}'::jsonb then
    select count(*) into v_match from scholarship.course_mapping_candidates c
     where c.scholarship_id = p_scholarship_id and c.status = 'needs_review' and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
  end if;
  -- a name phrase no course title holds whole ("Engineering Science") falls back to its first word ("Engineering")
  if v_match = 0 and v_from_phrase and exists (select 1 from unnest(v_subj) z where z ~ '\s') then
    select coalesce(array_agg(distinct case when x = any (v_subj) then split_part(x, ' ', 1) else x end), '{}') into v_titles from unnest(v_titles) x;
    v_filter := (v_filter - 'title') || jsonb_build_object('title', array_to_string(v_titles, ', '));
    select count(*) into v_match from scholarship.course_mapping_candidates c
     where c.scholarship_id = p_scholarship_id and c.status = 'needs_review' and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
  end if;
  insert into pipeline.scholarship_scope_suggestions (scholarship_id, filter, levels_found, subjects_found, basis, candidate_courses, matched_courses, computed_at)
  values (p_scholarship_id, v_filter, v_levels, v_titles, left(v_text, 600), v_cand, v_match, now())
  on conflict (scholarship_id) do update set filter = excluded.filter, levels_found = excluded.levels_found, subjects_found = excluded.subjects_found, basis = excluded.basis,
         candidate_courses = excluded.candidate_courses, matched_courses = excluded.matched_courses, computed_at = now();
  return jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_filter, 'levels', to_jsonb(v_levels), 'subjects', to_jsonb(v_titles), 'candidates', v_cand, 'matched', v_match);
end $function$;
revoke all on function security.scholarship_scope_suggest_v1(uuid) from public, anon, authenticated;
comment on function security.scholarship_scope_suggest_v1(uuid) is 'CF-247 (Platform Admin 18 Nov 2026 11:57 and 13:06): works out the rule-based course scope suggested for a waiting scholarship from its own name (its "in ..." phrase, subject words, degree codes), then its description, and how many of its proposed courses that scope keeps.';

-- 3. The deterministic decision, and applying it under the automated rule authority
create or replace function security.scholarship_scope_auto_decide_v1(p_scholarship_id uuid, p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare s record; g jsonb; v_text text; v_hit text; v_decision text; v_filter jsonb := '{}'::jsonb; v_rule text; v_reason text; v_before jsonb; v_res jsonb;
        v_actor uuid := security.system_actor_id();
begin
  select x.id, x.name, coalesce(x.description, '') description into s from scholarship.scholarships x where x.id = p_scholarship_id;
  if not found then return null; end if;
  v_text := s.name || ' ' || s.description;
  g := security.scholarship_scope_suggest_v1(p_scholarship_id);
  select p into v_hit from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_none_patterns'), '[]'::jsonb)) p
   where position(lower(p) in lower(v_text)) > 0 limit 1;
  if v_hit is not null then
    v_decision := 'none'; v_rule := 'not course-specific wording "' || v_hit || '"';
  elsif (g->>'matched')::int > 0 then
    v_decision := 'filter'; v_filter := g->'filter';
    v_rule := 'scope from its own words: levels ' || coalesce(nullif(array_to_string(array(select jsonb_array_elements_text(g->'levels')), ', '), ''), 'any') ||
              '; title words ' || coalesce(nullif(array_to_string(array(select jsonb_array_elements_text(g->'subjects')), ', '), ''), 'any') ||
              ' (keeps ' || (g->>'matched') || ' of ' || (g->>'candidates') || ')';
  else
    select p into v_hit from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_all_patterns'), '[]'::jsonb)) p
     where position(lower(p) in lower(v_text)) > 0 limit 1;
    if v_hit is not null and jsonb_array_length(g->'levels') = 0 and jsonb_array_length(g->'subjects') = 0 then
      v_decision := 'all'; v_rule := 'university-wide wording "' || v_hit || '" and no level or subject restriction';
    else
      v_decision := 'none'; v_rule := case when (g->'filter') <> '{}'::jsonb then 'its scope keeps none of the proposed courses' else 'its own text names no scope that can be proved' end;
    end if;
  end if;
  v_reason := 'Auto-applied deterministic title/description scope rule: ' || v_rule || ' (Platform Admin 18 Nov 2026 13:06)';
  if p_apply then
    select to_jsonb(d) into v_before from pipeline.scholarship_scope_decisions d where scholarship_id = p_scholarship_id;
    insert into pipeline.scholarship_scope_decisions(scholarship_id, decision, filter, reason, decided_by, decided_at)
    values (p_scholarship_id, v_decision, v_filter, v_reason, v_actor, now())
    on conflict (scholarship_id) do update set decision = excluded.decision, filter = excluded.filter, reason = excluded.reason, decided_by = excluded.decided_by, decided_at = now();
    v_res := security.scholarship_scope_apply_v1(p_scholarship_id, v_actor);
    insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
    values ('scholarship_course_scope', 'scope_decision_' || v_decision, v_actor, jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_filter, 'previous', v_before, 'rule', v_rule),
            v_reason, coalesce((v_res->>'accepted')::int, 0) + coalesce((v_res->>'rejected')::int, 0), coalesce((v_res->>'accepted')::int, 0), v_res, 'CF-CHG-20260915-247');
  end if;
  return jsonb_build_object('scholarship_id', p_scholarship_id, 'name', s.name, 'decision', v_decision, 'filter', v_filter, 'rule', v_rule, 'applied', p_apply, 'result', v_res);
end $function$;
revoke all on function security.scholarship_scope_auto_decide_v1(uuid, boolean) from public, anon, authenticated;
comment on function security.scholarship_scope_auto_decide_v1(uuid, boolean) is 'CF-247 (Platform Admin 18 Nov 2026 13:06): the deterministic course scope decision for a waiting scholarship (not course-specific wording: none; a scope from its own words that keeps a course: that scope; explicit university-wide wording with no restriction: all; otherwise none) and, with p_apply, applying it as the Course links decision does, under the automated rule authority, with its audit rows.';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.scholarship_scope_auto_decide_v1', 'Layer 4', 'Scholarships', 'Deterministic course scope decision for a waiting scholarship, applied with audit rows', 'active', '{}', '20261118153000')
on conflict do nothing;

-- 4. Apply to every waiting scholarship
create temp table cf_auto on commit drop as
  select w.scholarship_id, security.scholarship_scope_auto_decide_v1(w.scholarship_id, true) r from security.scholarship_links_waiting_v1() w;

-- 5. Post-checks
do $c$
declare v_n int; v_left int; v_ops int; v_sum jsonb;
begin
  select count(*) into v_n from cf_auto;
  select count(*) into v_left from security.scholarship_links_waiting_v1();
  if v_left > 0 then raise exception 'post-check: % scholarships still wait for a course scope', v_left; end if;
  select count(*) into v_ops from pipeline.layer4_mass_operations m join cf_auto a on (m.group_key->>'scholarship_id')::uuid = a.scholarship_id
   where m.target_kind = 'scholarship_course_scope' and m.reason like 'Auto-applied deterministic title/description scope rule:%';
  if v_ops <> v_n then raise exception 'post-check: % decisions but % audit rows', v_n, v_ops; end if;
  if exists (select 1 from cf_auto a join pipeline.scholarship_scope_decisions d on d.scholarship_id = a.scholarship_id
              where d.decided_by is distinct from security.system_actor_id() or d.reason not like 'Auto-applied deterministic title/description scope rule:%') then
    raise exception 'post-check: a decision is not recorded under the automated rule authority with its reason';
  end if;
  if exists (select 1 from cf_auto where r->>'decision' = 'all' and r->>'rule' not like 'university-wide wording%') then raise exception 'post-check: All courses without university-wide wording'; end if;
  if (security.layer4_scholarship_links_inbox_counts_v1()->>'n')::int <> 0 then raise exception 'post-check: Scholarship course links items remain in the Inbox'; end if;
  select jsonb_build_object('decided', v_n, 'by_decision', (select jsonb_object_agg(k, n) from (select r->>'decision' k, count(*) n from cf_auto group by 1) z),
           'links_accepted', (select sum(coalesce((r->'result'->>'accepted')::int, 0)) from cf_auto),
           'links_refused', (select sum(coalesce((r->'result'->>'rejected')::int, 0)) from cf_auto)) into v_sum;
  raise notice 'Scholarship course links auto-decided: %', v_sum;
  raise notice 'Decisions: %', (select jsonb_agg(jsonb_build_object('n', r->>'name', 'd', r->>'decision', 'rule', r->>'rule', 'acc', r->'result'->>'accepted') order by r->>'name') from cf_auto);
end $c$;
