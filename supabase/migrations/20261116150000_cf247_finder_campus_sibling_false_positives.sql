-- CF-247 course page check (official-URL finder): two false-positive rules found in the Layer 4 official URL resolution (Pilot #1177 / #1180;
-- coursefinder-admin docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md §7; paste file PASTE-20261116-l4-lift-false-link-refusals.sql).
-- Platform Admin 16 Nov 2026 20:14: ship the targeted fix.
-- Replaces: security.course_page_check_v1 (same name; md5-guarded text edit of the campus and sibling rules, resulting md5 checked).
-- Retires: nothing.
--
-- (a) Campus rule (refuse 'campus', "the page is for another campus (X)"): an active campus of the provider that the course is not offered at
--     counted as "another campus" when its name appeared in the page address tail or title. A campus named like the provider itself
--     (Durham College, University of Calgary, University of New England) is in almost every page title as the provider's name. All 26
--     campus refusals on record were this. Now a campus whose name is contained in the provider's canonical, display or short name is not
--     evidence of another campus.
-- (b) Sibling rule (refuse 'sibling', "the page address is another course's at this provider (X)"): the course's own name counted as the
--     address only when its key, hyphenated, was an exact prefix of the last address segment. An apostrophe (Dean's Scholar), a missing
--     separator or dropped words in a double degree (ACU bachelor-of-artsbachelor-of-laws, Newcastle ...-honours-mathematics, Wollongong
--     ...---bachelor-of-int-studies) broke that, so the shorter single degree won. Now the sibling is not proven when the rest of the address
--     after the sibling's name carries at least one word of this course's title that the sibling's title does not have, and no other word
--     longer than binding.sibling_tail_abbrev_max_chars (faculty codes and abbreviations such as smah, int). A page whose remaining words
--     belong to neither (dental-assisting-levels-i-and-ii for a course titled Dental Assisting) is still refused.
-- No consumer API object is read or changed (G3). No job or table. One setting.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'binding.sibling_tail_abbrev_max_chars', 'Course page check: abbreviation length after a sibling course''s name',
  'When an address starts with another course''s name, the rest of the address must name this course for the page to be this course''s: at least one word of this course''s title that the other course lacks, and no other word longer than this many letters (shorter words are taken as faculty codes or abbreviations, such as smah or int).',
  'number', '4'::jsonb, 0, 10, 'letters', 3245, 'Course pages', 'security.course_page_check_v1',
  'Finder false positives (Platform Admin 16 Nov 2026 20:14): double degrees and Dean''s Scholar addresses read as the single degree''s')
on conflict do nothing;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', '38c776ca90378d866167390f7d40d42b', 'c0183b440fa7feb8dee1d624b1ff2224',
  array[
    $o1$           security.pipeline_num_v1('binding.handbook_max_age_years', 2) max_age),$o1$,
    $o2$               and length(security.course_title_key(o.canonical_title)) > case when t.slug like replace(t.tk, ' ', '-') || '%' then length(t.tk) else 0 end
             order by length(o.canonical_title) desc limit 1) other_title),$o2$,
    $o3$               and position(security.course_title_key(k2.name) in t.tk) = 0$o3$
  ],
  array[
    $n1$           security.pipeline_num_v1('binding.handbook_max_age_years', 2) max_age,
           security.pipeline_num_v1('binding.sibling_tail_abbrev_max_chars', 4)::int abbrev_max),$n1$,
    $n2$               and length(security.course_title_key(o.canonical_title)) > case when t.slug like replace(t.tk, ' ', '-') || '%' then length(t.tk) else 0 end
               -- 16 Nov 2026 (finder false positives): not a sibling when the rest of the address names this course (a word of this course's
               -- title the sibling lacks, and no other word longer than binding.sibling_tail_abbrev_max_chars): double degrees, Dean's Scholar
               and not (exists (select 1 from regexp_split_to_table(substr(t.slug, length(replace(security.course_title_key(o.canonical_title), ' ', '-')) + 1), '[^a-z0-9]+') w
                                 where w <> '' and w = any (regexp_split_to_array(security.course_title_key(replace(t.ctitle, '''', '')), ' '))
                                   and not w = any (regexp_split_to_array(security.course_title_key(replace(o.canonical_title, '''', '')), ' ')))
                        and not exists (select 1 from regexp_split_to_table(substr(t.slug, length(replace(security.course_title_key(o.canonical_title), ' ', '-')) + 1), '[^a-z0-9]+') w
                                 where length(w) > (select s.abbrev_max from s)
                                   and not w = any (regexp_split_to_array(security.course_title_key(replace(t.ctitle, '''', '')), ' '))))
             order by length(o.canonical_title) desc limit 1) other_title),$n2$,
    $n3$               and position(security.course_title_key(k2.name) in t.tk) = 0
               -- 16 Nov 2026 (finder false positives): a campus named like the provider is the provider's own name in page titles, not another campus
               and not exists (select 1 from catalogue.providers p2, unnest(array[p2.canonical_name, p2.display_name, p2.short_name]) pn(nm)
                                where p2.id = t.provider_id and btrim(coalesce(pn.nm, '')) <> ''
                                  and position(' ' || security.course_title_key(k2.name) || ' ' in ' ' || security.course_title_key(pn.nm) || ' ') > 0)$n3$
  ]);

do $post$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_page_check_v1(uuid,text,text,text)'::regprocedure)) <> 'c0183b440fa7feb8dee1d624b1ff2224' then
    raise exception 'post-check: security.course_page_check_v1 does not have the recorded body'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'binding.sibling_tail_abbrev_max_chars') then
    raise exception 'post-check: binding.sibling_tail_abbrev_max_chars is missing'; end if;
end $post$;
