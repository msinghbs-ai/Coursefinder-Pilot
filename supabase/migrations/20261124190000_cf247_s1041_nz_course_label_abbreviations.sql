-- s1041 F-AER.08 NZ/CA delegated lane: Auckland/VUW course-label identity, deterministic evidence only.
-- Guards: Operating Model G3 (no consumer API changes); protected manual decisions immutable;
--          F-AER.08 course identity requires one provider/title/study-level candidate;
--          incomplete headings, conjoint variants and multiple candidates stay Layer 4.
-- Replaces: security.entry_course_link_v1(uuid,text,text,uuid,text) (same signature, md5 guarded).
-- Retires: nothing. Does not change any admission mode or reader/model settings.
-- Rollback: restore the previous function body; confirmed link records remain reviewable.
do $s1041$
declare
  v_def text := pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure);
  v_old text;
  v_new text;
begin
  if md5(v_def) <> '38c42eb11b956f932ab3b78a53e06c07' then
    raise exception 's1041: entry_course_link_v1 definition changed (md5 %); rebase required', md5(v_def);
  end if;

  -- Add an explicitly scoped normalised title: retain the original label key as
  -- the human-decision identity, so a rejected label is never overridden.
  v_old := 'v_levels text[]; v_method text;';
  v_new := 'v_levels text[]; v_method text; v_nz_key text;';
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1041: declaration anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);

  -- A pre-existing unresolved cache must be rechecked after this reader fix,
  -- but only for these two NZ providers; every other provider keeps its cache.
  v_old := 'if l.state = ''unresolved'' and v_code = coalesce(l.cricos_code, '''')';
  v_new := 'if l.state = ''unresolved'' and p_provider not in (''e096aba7-e1eb-4903-9a63-2bfb71e9a8b8''::uuid, ''34616965-b2b7-42a7-8da7-50ffbf120958''::uuid) and v_code = coalesce(l.cricos_code, '''')';
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1041: cache anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '  if v_method is not null then';
  v_new := $nz$
  -- s1041 Auckland/VUW: source footnote glyphs and a trailing printed award
  -- abbreviation are not part of a catalogue title. Do not strip genuine
  -- (Honours), (Teaching), subject streams, conjoint degrees or internal brackets.
  -- Every match still requires the level named by the printed label and exactly
  -- one ACTIVE course for this provider; ambiguous names stay unresolved.
  if v_method is null and p_provider in ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid, '34616965-b2b7-42a7-8da7-50ffbf120958'::uuid)
     and cardinality(v_levels) > 0
     and p_label !~* '(conjoint|specialisation|specialization|^other majors|^cell and molecular|/|\bmajors\b)' then
    v_nz_key := security.entry_course_title_key_v1(
       regexp_replace(translate(p_label, '*∆□◊', '    '),
         '[[:space:]]+[(]B[A-Za-z]{1,16}([(][A-Za-z]+[)])?[)][[:space:]]*$', '', 'g'));
    if v_nz_key is not null and v_nz_key <> v_key then
      v_ids := array(
        select distinct c.id
        from catalogue.courses c join ref.study_levels s on s.id = c.study_level_id
        where c.provider_id = p_provider and c.lifecycle_status = 'active'
          and s.short_code = any(v_levels)
          and (security.entry_course_title_key_v1(c.canonical_title) = v_nz_key
            or security.entry_course_title_key_v1(c.display_title) = v_nz_key));
      if cardinality(v_ids) = 1 then v_method := 'title'; end if;
    end if;
  end if;
  if v_method is not null then$nz$;
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1041: matching anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
  if md5(pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure)) =
     '38c42eb11b956f932ab3b78a53e06c07' then raise exception 's1041: no change applied'; end if;
end $s1041$;

-- No automatic review approval, mass supersession or course publication.
-- Existing proposed rows are linked only by the already-governed re-read or Layer 4 path.
comment on function security.entry_course_link_v1(uuid,text,text,uuid,text) is
 'F-AER.08 s1041: existing confirmed/rejected decisions first; unique exact title/level, with Auckland/VUW award-abbreviation and printed-footnote normalisation; unresolved remains Layer 4';
