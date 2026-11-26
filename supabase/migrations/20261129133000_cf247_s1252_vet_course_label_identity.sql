-- s1252 F-AER.08 shared course-label identity: VET labels (Diploma, Advanced Diploma) and printed national training package codes.
-- Guards: Operating Model G3 (no consumer API change); F-AER.08 course identity requires one provider, one exact title and one study level;
--          protected manual decisions (confirmed and rejected links) are read first and never changed; confidence thresholds and Layer 4 authority unchanged.
-- Replaces: security.entry_course_link_v1(uuid,text,text,uuid,text) (same signature, md5 guarded; adds one step after the existing ones).
-- Retires: nothing. Does not change any admission mode, setting, reader or model.
-- Rollback: restore the previous function body (s1041 text); the links created here stay reviewable in catalogue.entry_course_links (method 'title').
-- Why: security.entry_course_label_levels_v1 names only degree-level words, so a label such as "RII60520 Advanced Diploma of Civil Construction Design"
--      never reached the exact-title step, and the printed training package code (RII60520) is not part of the catalogue title. George Brown (NSW) and
--      one other provider could never link such labels. The level now comes from the existing mapper security.entry_label_levels_v1 only when the established
--      helper names no level, so every label that linked before links the same way.
do $s1252$
declare
  v_def text := pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure);
  v_old text;
  v_new text;
  v_confirmed_before text;
  v_confirmed_after text;
  v_decided uuid[];
  r record;
  v_linked int := 0;
begin
  if md5(v_def) <> 'f6ef02c506ddc1d842fa0437abfea4c6' then
    raise exception 's1252: entry_course_link_v1 definition changed (md5 %); rebase required', md5(v_def);
  end if;

  v_old := 'v_nz_key text;';
  v_new := 'v_nz_key text; v_code_key text; v_vet_levels text[];';
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1252: declaration anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '  if v_method is not null then';
  v_new := $vet$
  -- s1252 VET and training package codes: used only when the established level helper names no level, so every label that linked before links the same way.
  -- The level comes from the existing mapper (security.entry_label_levels_v1); a printed national training package code (three letters, five digits, an optional
  -- letter) is not part of a catalogue title. The match still needs this provider, an active course, the level the label names and exactly one exact title.
  if v_method is null and cardinality(v_levels) = 0 and p_label !~* '(conjoint|/)' then
    v_vet_levels := array(select s.short_code from ref.study_levels s where s.id = any (security.entry_label_levels_v1(p_label)));
    v_code_key := security.entry_course_title_key_v1(regexp_replace(btrim(p_label), '^[A-Za-z]{3}[0-9]{5}[A-Za-z]?[[:space:]]+', ''));
    if cardinality(v_vet_levels) > 0 and v_code_key is not null then
      v_ids := array(
        select distinct c.id
        from catalogue.courses c join ref.study_levels s on s.id = c.study_level_id
        where c.provider_id = p_provider and c.lifecycle_status = 'active'
          and s.short_code = any (v_vet_levels)
          and (security.entry_course_title_key_v1(c.canonical_title) = v_code_key
            or security.entry_course_title_key_v1(c.display_title) = v_code_key));
      if cardinality(v_ids) = 1 then v_method := 'title'; end if;
    end if;
  end if;
  if v_method is not null then$vet$;
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1252: matching anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);

  -- a cached "unresolved" label is looked at again only when its code differs or the catalogue changed; this fix must reach labels cached before it
  v_old := 'if l.state = ''unresolved'' and p_provider not in';
  v_new := 'if l.state = ''unresolved'' and (p_label ~* ''(conjoint|/)'' or cardinality(security.entry_course_label_levels_v1(p_label)) > 0) and p_provider not in';
  -- (the cache stays for labels that name a level, conjoint labels and slashed labels; labels naming no level are evaluated again)
  if (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old) <> 1 then
    raise exception 's1252: cache anchor count differs';
  end if;
  v_def := replace(v_def,v_old,v_new);

  execute v_def;
  if md5(pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure)) = 'f6ef02c506ddc1d842fa0437abfea4c6' then
    raise exception 's1252: no change applied';
  end if;

  select array_agg(id order by id), md5(string_agg(id::text || coalesce(course_id::text,'') || state, ',' order by id)) into v_decided, v_confirmed_before
    from catalogue.entry_course_links where state in ('confirmed','rejected');

  -- re-evaluate the unresolved labels that name no level to the established helper; the deterministic steps decide, nothing is forced
  for r in
    select l.provider_id, l.course_label, l.cricos_code,
           nullif(l.evidence->>'source_id','')::uuid src, l.evidence->>'quote' quote
    from catalogue.entry_course_links l
    where l.state = 'unresolved' and l.course_label !~* '(conjoint|/)'
      and coalesce(array_length(security.entry_course_label_levels_v1(l.course_label), 1), 0) = 0
  loop
    if security.entry_course_link_v1(r.provider_id, r.course_label, r.cricos_code, r.src, r.quote) is not null then
      v_linked := v_linked + 1;
    end if;
  end loop;

  select md5(string_agg(id::text || coalesce(course_id::text,'') || state, ',' order by id)) into v_confirmed_after
    from catalogue.entry_course_links where id = any (v_decided);
  if v_confirmed_after is distinct from v_confirmed_before then
    raise exception 's1252: a confirmed or rejected decision changed';
  end if;
  raise notice 's1252: % unresolved labels linked by exact provider, level and title', v_linked;
end $s1252$;

comment on function security.entry_course_link_v1(uuid,text,text,uuid,text) is
 'F-AER.08 s1252: existing confirmed/rejected decisions first; unique exact title/level, with Auckland/VUW award-abbreviation normalisation and, for labels the level helper cannot read, the existing level mapper and printed training package code; unresolved remains Layer 4';
