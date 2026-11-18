-- CF-247 S2 - BOOST: corrections to the deterministic Scholarship course links rule of 20261118153000 (Platform Admin 18 Nov 2026 13:06,
-- read back live the same hour). Three of the 57 decisions were wrong:
--   - "International Four-Year Doctoral Partial Tuition Award" and "University of Otago Law Alumni Scholarship" were set to No courses because
--     their descriptions mention "PhD transfer students" and "accommodation" in passing: the not-course-specific wording is now read in the
--     scholarship's NAME only (every page it is meant for names it: transfer-student notices, accommodation awards, Huayu, "after you graduate");
--   - "UC Business School International School Leavers Scholarship" was set to No courses because its name says Business and the course is
--     the Bachelor of Commerce: when the name's subjects keep no course, the description's subject words are added.
--   The suggestion now counts every live candidate (not superseded), as security.scholarship_scope_apply_v1 reads them, so it can be worked
--   out again for a scholarship already decided.
-- Every scholarship decided by the rule (decided_by the automated rule authority, reason "Auto-applied deterministic title/description scope
-- rule: ...") is worked out again; where the decision or scope changes it is applied again with a new audit row. Decisions made by a person
-- are never touched.
-- G1: no new job. G2: no new value. G3: no consumer API object's shape is changed.
-- Replaces: security.scholarship_scope_suggest_v1 and security.scholarship_scope_auto_decide_v1 of migration 20261118153000 (same signatures)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text;
begin
  v := md5(pg_get_functiondef('security.scholarship_scope_suggest_v1(uuid)'::regprocedure));
  if v <> '6b7cfe351986dd6e4de734911b5ffaf1' then raise exception 'security.scholarship_scope_suggest_v1 is not the definition this migration replaces (md5 %)', v; end if;
  v := md5(pg_get_functiondef('security.scholarship_scope_auto_decide_v1(uuid,boolean)'::regprocedure));
  if v <> '504c9a61683423b1eb095402e3027fd6' then raise exception 'security.scholarship_scope_auto_decide_v1 is not the definition this migration replaces (md5 %)', v; end if;
  v := md5(pg_get_functiondef('security.scholarship_scope_apply_v1(uuid,uuid)'::regprocedure));
  if v <> '55d2012984ee2c1779e6d83e0231ee57' then raise exception 'security.scholarship_scope_apply_v1 is not the definition this migration relies on (md5 %)', v; end if;
end $pre$;

create or replace function security.scholarship_scope_suggest_v1(p_scholarship_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare s record; v_name text; v_text text; v_levels text[] := '{}'; v_subj text[] := '{}'; v_titles text[] := '{}'; v_ids jsonb;
        v_filter jsonb := '{}'::jsonb; v_cand int; v_match int := 0; w text; a text; v_phrase text; v_tok text; v_words text; v_pat text;
        v_name_code boolean := false; v_from_phrase boolean := false; v_dsubj text[] := '{}';
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
  select count(*) into v_cand from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id join scholarship.scholarships sc on sc.id = c.scholarship_id
   where c.scholarship_id = p_scholarship_id and c.status <> 'superseded' and co.provider_id = sc.provider_id;
  if v_filter <> '{}'::jsonb then
    select count(*) into v_match from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id join scholarship.scholarships sc on sc.id = c.scholarship_id
     where c.scholarship_id = p_scholarship_id and c.status <> 'superseded' and co.provider_id = sc.provider_id and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
  end if;
  -- a name phrase no course title holds whole ("Engineering Science") falls back to its first word ("Engineering")
  if v_match = 0 and v_from_phrase and exists (select 1 from unnest(v_subj) z where z ~ '\s') then
    select coalesce(array_agg(distinct case when x = any (v_subj) then split_part(x, ' ', 1) else x end), '{}') into v_titles from unnest(v_titles) x;
    v_filter := (v_filter - 'title') || jsonb_build_object('title', array_to_string(v_titles, ', '));
    select count(*) into v_match from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id join scholarship.scholarships sc on sc.id = c.scholarship_id
     where c.scholarship_id = p_scholarship_id and c.status <> 'superseded' and co.provider_id = sc.provider_id and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
  end if;
  -- name subjects that keep no course: the description's subject words are added ("Business School" award for the Bachelor of Commerce)
  if v_match = 0 and cardinality(v_subj) > 0 and not v_name_code then
    for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_subjects'), '[]'::jsonb)) loop
      if s.description ~* ('\m' || regexp_replace(w, v_esc, '\\\1', 'g') || '\M') and not (w = any (v_titles)) then v_dsubj := v_dsubj || w; end if;
    end loop;
    if cardinality(v_dsubj) > 0 then
      select coalesce(array_agg(distinct x), '{}') into v_titles from unnest(v_titles || v_dsubj) x;
      v_filter := (v_filter - 'title') || jsonb_build_object('title', array_to_string(v_titles, ', '));
      select count(*) into v_match from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id join scholarship.scholarships sc on sc.id = c.scholarship_id
     where c.scholarship_id = p_scholarship_id and c.status <> 'superseded' and co.provider_id = sc.provider_id and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
    end if;
  end if;
  insert into pipeline.scholarship_scope_suggestions (scholarship_id, filter, levels_found, subjects_found, basis, candidate_courses, matched_courses, computed_at)
  values (p_scholarship_id, v_filter, v_levels, v_titles, left(v_text, 600), v_cand, v_match, now())
  on conflict (scholarship_id) do update set filter = excluded.filter, levels_found = excluded.levels_found, subjects_found = excluded.subjects_found, basis = excluded.basis,
         candidate_courses = excluded.candidate_courses, matched_courses = excluded.matched_courses, computed_at = now();
  return jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_filter, 'levels', to_jsonb(v_levels), 'subjects', to_jsonb(v_titles), 'candidates', v_cand, 'matched', v_match);
end $function$;
revoke all on function security.scholarship_scope_suggest_v1(uuid) from public, anon, authenticated;
comment on function security.scholarship_scope_suggest_v1(uuid) is 'CF-247 (Platform Admin 18 Nov 2026 11:57 and 13:06): works out the rule-based course scope suggested for a waiting scholarship from its own name (its "in ..." phrase, subject words, degree codes), then its description (also when the name''s subjects keep no course), and how many of its proposed courses that scope keeps.';

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
   where position(lower(p) in lower(s.name)) > 0 limit 1;
  if v_hit is not null then
    v_decision := 'none'; v_rule := 'not course-specific wording "' || v_hit || '" in its name';
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
comment on function security.scholarship_scope_auto_decide_v1(uuid, boolean) is 'CF-247 (Platform Admin 18 Nov 2026 13:06): the deterministic course scope decision for a waiting scholarship (not course-specific wording in its name: none; a scope from its own words that keeps a course: that scope; explicit university-wide wording with no restriction: all; otherwise none) and, with p_apply, applying it as the Course links decision does, under the automated rule authority, with its audit rows.';

-- Work out again every scholarship decided by the rule; apply again where the decision or scope changes
create temp table cf_redo on commit drop as
  select d.scholarship_id, d.decision old_decision, d.filter old_filter, security.scholarship_scope_auto_decide_v1(d.scholarship_id, false) r
    from pipeline.scholarship_scope_decisions d
   where d.decided_by = security.system_actor_id() and d.reason like 'Auto-applied deterministic title/description scope rule:%';
create temp table cf_redone on commit drop as
  select x.scholarship_id, x.old_decision, security.scholarship_scope_auto_decide_v1(x.scholarship_id, true) r
    from cf_redo x where x.r->>'decision' <> x.old_decision or (x.r->'filter') <> x.old_filter;

do $c$
declare v_n int; v_names jsonb;
begin
  select count(*) into v_n from cf_redone;
  if (select count(*) from security.scholarship_links_waiting_v1()) > 0 then raise exception 'post-check: a scholarship waits for a course scope'; end if;
  if exists (select 1 from cf_redo x join scholarship.scholarships s on s.id = x.scholarship_id
              where s.name in ('International Four-Year Doctoral Partial Tuition Award', 'University of Otago Law Alumni Scholarship', 'UC Business School International School Leavers Scholarship')
                and not exists (select 1 from pipeline.scholarship_scope_decisions d where d.scholarship_id = x.scholarship_id and d.decision = 'filter' and d.accepted > 0)) then
    raise exception 'post-check: a corrected scholarship still keeps no course';
  end if;
  if exists (select 1 from cf_redone z where not exists (select 1 from pipeline.layer4_mass_operations m where m.target_kind = 'scholarship_course_scope'
              and (m.group_key->>'scholarship_id')::uuid = z.scholarship_id and m.created_at >= now() - interval '1 hour' and m.reason like 'Auto-applied deterministic%')) then  -- fixed: this migration's own audit window
    raise exception 'post-check: a re-applied decision has no audit row';
  end if;
  select jsonb_agg(jsonb_build_object('n', r->>'name', 'from', old_decision, 'to', r->>'decision', 'acc', r->'result'->>'accepted') order by r->>'name') into v_names from cf_redone;
  raise notice 'Scholarship course links re-decided by the corrected rule: % (%)', v_n, v_names;
end $c$;
