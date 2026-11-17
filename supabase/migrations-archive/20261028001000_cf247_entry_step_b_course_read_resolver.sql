-- CF-247 Track C Step B, bounded RMIT slice (Platform Admin mandate 28 Oct 2026 20:36; decisions 28 Oct: no ATAR-to-band mapping, honest
-- step-5 fallback; B4 developer pack only). Record: admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md, under
-- docs/platform/ENTRY-REQUIREMENTS-IMPLEMENTATION.md 2.3–2.5. Platform part only (B1, resolver, B5). The consumer API (B2/B3) is a separate,
-- paste-reviewed change; nothing here touches it.
--
-- 1. B1 on the existing Enrich fields lane: field entry_requirements (NOT in the field registry security.enrich_fields_v1, so no automatic
--    plan, standing gap queue or Read with AI asks for it). Stored course page only (AU field source rule {ai_stored}); AU strong identity
--    proofs only. The worker reads it with the pinned entry model; security.enrich_entry_record_v1 admits rows as 'proposed' under the B1
--    rules and opens one Layer 4 item course_entry_first_read; a person admits or quarantines them (security.course_entry_review_apply_v1).
-- 2. security.entry_resolve_v1(course, country): the five-rule resolution order over active rows (pure lookup; no eligibility arithmetic).
-- 3. public.admin_entry_requirements(action, args): bounded admin reads for the Provider drawer and Course blade sections, the resolver,
--    and the Platform Admin's "read from the stored page" request (one course a request).
-- 4. The decided slice read: one count-guarded entry_requirements item for RMIT Bachelor of Engineering (Honours) BH126.
-- Replaces: nothing (the course-level table was empty and unwritten; the matrix reader is unchanged)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched. No new job: the existing Enrich fields lane runs the read.

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

-- ---------------------------------------------------------------- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.course_read_countries', 'Course entry requirements: countries read', 'Countries whose course pages may be read for academic entry requirements (one course a request, from the stored page).', 'list', '["AU"]'::jsonb, null, null, 'countries', 910, 'Entry requirements', 'public.admin_entry_requirements (read)', 'CF-247 Track C Step B (28 Oct 2026)'),
 ('pipeline', 'entry.max_rows_per_course', 'Course entry requirements: rows a course', 'At most this many requirement rows are proposed from one course page (B1).', 'number', '6'::jsonb, 1, 10, 'rows', 911, 'Entry requirements', 'security.enrich_entry_record_v1', 'CF-247 Track C Step B (28 Oct 2026)'),
 ('pipeline', 'entry.min_confidence', 'Course entry requirements: minimum confidence', 'A course requirement row the model gives a lower confidence than this is not proposed (dropped as low_confidence).', 'number', '0.8'::jsonb, 0.5, 1, 'confidence', 912, 'Entry requirements', 'security.enrich_entry_record_v1', 'CF-247 Track C Step B (28 Oct 2026)'),
 ('pipeline', 'entry.course_page_chars', 'Course entry requirements: page text read', 'How much of the stored course page text the model reads for entry requirements.', 'number', '100000'::jsonb, 10000, 150000, 'characters', 913, 'Entry requirements', 'public.svc_enrich_ai_next, worker enrich_ai (entry_requirements)', 'CF-247 Track C Step B (28 Oct 2026)'),
 ('pipeline', 'entry.level_equivalents', 'Entry resolution: level equivalents', 'Course level = provider matrix level pairs the resolver treats as the same level (BH=BA: an honours bachelor uses the provider''s "Bachelor degrees" rows). Clear to match levels exactly.', 'list', '["BH=BA"]'::jsonb, null, null, 'level pairs', 914, 'Entry requirements', 'security.entry_resolve_v1', 'CF-247 Track C Step B (28 Oct 2026)')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- B1 source rule and identity (AU only)
insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_at)
values ('AU', 'entry_requirements', array['ai_stored'], 'CF-247 Track C Step B (28 Oct 2026): academic entry requirements from the stored course page only', now())
on conflict do nothing;
update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('entry_requirements', jsonb_build_array('cricos_code', 'adapter_code', 'manual'))
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'AU' and not (a.identities ? 'entry_requirements');

-- ---------------------------------------------------------------- B1 admission
create or replace function security.enrich_entry_record_v1(p_item bigint, p_r jsonb) returns text
language plpgsql security definer set search_path to '' as $$
declare i pipeline.field_enrich_items%rowtype; g record; x jsonb; v_in int := 0; v_drop jsonb := coalesce(p_r->'value'->'dropped', '[]'::jsonb);
        v_notes jsonb := '[]'::jsonb; v_max int := security.pipeline_num_v1('entry.max_rows_per_course', 6)::int;
        v_conf numeric := security.pipeline_num_v1('entry.min_confidence', 0.8); v_kind text; v_q text; v_d text; v_score numeric; v_basis text;
        v_band text; v_aud text; v_c numeric; v_review uuid; v_ids uuid[] := '{}'; v_id uuid;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.course_id is null then return 'nothing'; end if;
  select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at into g
    from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
  if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'entry_requirements') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit entry requirements for this country', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  if jsonb_array_length(coalesce(p_r->'value'->'rows', '[]'::jsonb)) = 0 then
    update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(p_r->>'reason', ''), 'the page does not state it'), value = jsonb_build_object('dropped', v_drop), updated_at = now() where id = i.id;
    return 'not_stated';
  end if;
  -- an earlier read of this course still waits for a person: nothing is proposed twice
  if exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = i.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'an earlier read of this course waits in Layer 4', updated_at = now() where id = i.id;
    return 'already';
  end if;
  for x in select * from jsonb_array_elements(p_r->'value'->'rows') loop
    v_kind := x->>'kind'; v_q := left(btrim(coalesce(x->>'quote', '')), 300); v_d := left(btrim(coalesce(x->>'description', '')), 500);
    v_c := case when x->>'confidence' ~ '^[0-9.]+$' then (x->>'confidence')::numeric end;
    v_score := case when x->>'min_entry_score' ~ '^[0-9]+(\.[0-9]+)?$' then (x->>'min_entry_score')::numeric end;
    v_basis := nullif(btrim(coalesce(x->>'min_entry_score_basis', '')), '');
    v_band := nullif(btrim(coalesce(x->>'benchmark_band', '')), '');
    if v_kind is null or v_kind not in ('prior_qualification', 'minimum_grade', 'subject_prerequisite', 'portfolio_interview', 'work_experience', 'override', 'general_note') then
      v_drop := v_drop || jsonb_build_object('reason', 'kind_unknown', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    if length(v_q) < 4 then v_drop := v_drop || jsonb_build_object('reason', 'no_quote', 'kind', v_kind); continue; end if;
    if coalesce(v_c, 0) < v_conf then v_drop := v_drop || jsonb_build_object('reason', 'low_confidence', 'kind', v_kind, 'quote', v_q); continue; end if;
    -- the English requirement is its own field: a row about an English test or English proficiency is never stored here (B1 rule)
    if (v_q || ' ' || v_d) ~* '(\mielts\M|\mtoefl\M|\mpte\M|\mduolingo\M|cambridge english|\moet\M|english language (requirement|proficiency|test)|english proficiency)' then
      v_drop := v_drop || jsonb_build_object('reason', 'english_duplicate', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    -- no numeric score without its basis: both the number and the basis words are printed in the quote (B1 rule)
    if v_score is not null and (v_basis is null or strpos(lower(regexp_replace(v_q, '\s+', ' ', 'g')), lower(regexp_replace(v_basis, '\s+', ' ', 'g'))) = 0
                                or not exists (select 1 from regexp_matches(v_q, '([0-9]+(\.[0-9]+)?)', 'g') m where m[1]::numeric = v_score)) then
      v_drop := v_drop || jsonb_build_object('reason', 'score_without_basis', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    if v_score is null then v_basis := null; end if;
    -- a band only when the quote prints it exactly; never derived (Platform Admin 28 Oct 2026: no ATAR-to-band mapping)
    if v_band is not null and strpos(lower(v_q), lower(v_band)) = 0 then
      v_notes := v_notes || jsonb_build_object('note', 'band_not_printed', 'band', v_band, 'quote', v_q); v_band := null;
    end if;
    -- audience from the quote's own words; international applicability is never inferred
    v_aud := case when v_q ~* '\m(international|overseas)\M' then 'international'
                  when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic' else 'all' end;
    if v_in >= v_max then v_drop := v_drop || jsonb_build_object('reason', 'over_row_limit', 'kind', v_kind, 'quote', v_q); continue; end if;
    insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_grade, min_entry_score, min_entry_score_basis, benchmark_band,
                                                    quote, source_url, evidence_id, confidence, as_at, status, provenance)
    values (i.course_id, v_kind, v_aud, coalesce(nullif(v_d, ''), v_q), nullif(btrim(coalesce(x->>'min_grade', '')), ''), v_score, v_basis, v_band,
            v_q, g.url, coalesce(i.evidence_id, g.evidence_id), v_c, coalesce(g.captured_at::date, current_date), 'proposed',
            jsonb_build_object('reader', 'enrich_ai', 'field', 'entry_requirements', 'item_id', i.id, 'job_id', i.job_id, 'model', p_r->>'model',
                               'worker', p_r->>'worker', 'prompt', p_r->>'prompt_version'))
    returning id into v_id;
    v_ids := v_ids || v_id; v_in := v_in + 1;
  end loop;
  if v_in = 0 then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'no row met the admission rules', value = jsonb_build_object('dropped', v_drop, 'notes', v_notes), updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                           status, escalation_reason, change_control_ref)
  values ('course', i.course_id, 'course_entry_first_read', coalesce(i.evidence_id, g.evidence_id),
          jsonb_build_object('active_rows', (select count(*) from catalogue.course_entry_requirements r where r.course_id = i.course_id and r.status = 'active')),
          jsonb_build_object('item_id', i.id, 'url', g.url, 'rows', v_in, 'dropped', v_drop, 'notes', v_notes,
            'sample', (select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'audience', r.audience, 'description', r.description, 'min_entry_score', r.min_entry_score,
                                         'min_entry_score_basis', r.min_entry_score_basis, 'benchmark_band', r.benchmark_band, 'quote', r.quote) order by r.kind)
                         from catalogue.course_entry_requirements r where r.id = any (v_ids))),
          jsonb_build_object('source', 'course entry reader', 'page', g.url, 'identity_basis', g.identity_basis),
          jsonb_build_object('item_id', i.id, 'model', p_r->>'model'),
          'pending', 'Course entry requirements first read: a person admits the rows before any is active (Track C Step B)', 'CF-CHG-20260915-247')
  returning id into v_review;
  update catalogue.course_entry_requirements set provenance = provenance || jsonb_build_object('review_item_id', v_review) where id = any (v_ids);
  update pipeline.field_enrich_items set state = 'review', reason = null, quote = left((select r.quote from catalogue.course_entry_requirements r where r.id = v_ids[1]), 300),
         value = jsonb_build_object('rows', v_in, 'review_item_id', v_review, 'dropped', v_drop, 'notes', v_notes), updated_at = now() where id = i.id;
  return 'review';
end $$;
revoke all on function security.enrich_entry_record_v1(bigint, jsonb) from public, anon, authenticated;
comment on function security.enrich_entry_record_v1(bigint, jsonb) is 'CF-247 Track C Step B (B1): admits a course page''s entry-requirement rows as proposed under the B1 rules (quote, basis, band printed, no English duplicate, audience from the quote) and opens Layer 4 course_entry_first_read.';

select pg_temp.edit_n('public.svc_enrich_ai_record(jsonb)', 'c3685d7aa7306365fa33f6f09834ea90', array[
  array[$o$
    elsif i.field = 'campus_list' then$o$,
        $n$
    elsif i.field = 'entry_requirements' then
      -- CF-247 Track C Step B (28 Oct 2026): course academic entry requirements, proposed for a person (B1)
      v_k := security.enrich_entry_record_v1(i.id, r);
    elsif i.field = 'campus_list' then$n$]], array[1]);

select pg_temp.edit_n('public.svc_enrich_ai_next(integer)', '0ad1ad53db595992ecb4b892c07ec184', array[
  array[$o$    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code)$o$,
        $n$    'entry', jsonb_build_object('model', coalesce(security.toolset_setting('pipeline', 'entry.matrix_model') #>> '{}', 'openai/gpt-4.1-mini'),
                                'page_chars', security.pipeline_num_v1('entry.course_page_chars', 100000)::int),  -- CF-247 Track C Step B: the pinned entry model
    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code)$n$]], array[1]);

-- ---------------------------------------------------------------- B1 human admission (Layer 4)
create or replace function security.course_entry_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare r pipeline.layer4_review_items%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_enrich bigint;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code <> 'course_entry_first_read' then raise exception 'not a course entry review item'; end if;
  v_enrich := nullif(r.proposed_value->>'item_id', '')::bigint;
  if p_action = 'approve' then
    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    update catalogue.course_entry_requirements x set status = 'superseded', status_reason = 'replaced by Layer 4 item ' || p_item, updated_at = now()
     where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai';
    get diagnostics v_sup = row_count;
    update catalogue.course_entry_requirements x set status = 'inactive', status_reason = 'excluded by the reviewer: ' || coalesce(p_reason, ''), updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and x.id = any (v_ex);
    get diagnostics v_off = row_count;
    update catalogue.course_entry_requirements x set status = 'active', status_reason = null, updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed';
    get diagnostics v_on = row_count;
    update pipeline.field_enrich_items set state = 'filled', updated_at = now() where id = v_enrich and state = 'review';
  else
    update catalogue.course_entry_requirements x set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed';
    get diagnostics v_off = row_count;
    update pipeline.field_enrich_items set state = 'skipped', reason = 'Layer 4 ' || p_action || ' (not admitted)', updated_at = now() where id = v_enrich and state = 'review';
  end if;
  return jsonb_build_object('course_entry_review', p_item, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup);
end $$;
revoke all on function security.course_entry_review_apply_v1(uuid, text, jsonb, text) from public, anon, authenticated;
comment on function security.course_entry_review_apply_v1(uuid, text, jsonb, text) is 'CF-247 Track C Step B (B1): a Layer 4 decision on course_entry_first_read admits the read''s rows (approve; edit-and-approve may exclude rows) or makes them inactive.';

create or replace function security.course_entry_review_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.course_entry_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $$;
revoke all on function security.course_entry_review_trg_v1() from public, anon, authenticated;
create trigger layer4_review_items_course_entry after update of status on pipeline.layer4_review_items
  for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code = 'course_entry_first_read')
  execute function security.course_entry_review_trg_v1();

select pg_temp.edit_n('security.layer4_review_decide_impl(uuid,text,text,jsonb)', 'a438f594dea0fc905323b640ea909b30', array[
  array[$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$o$,
        $n$    elsif v_item.entity_type='course' and v_item.field_code='course_entry_first_read' then
      -- CF-247 Track C Step B: approving a course entry read admits its rows (edit-and-approve may exclude rows); reject etc. by trigger
      v_scalar:=security.course_entry_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$n$]], array[1]);

-- ---------------------------------------------------------------- the five-rule resolver
create or replace function security.entry_resolve_v1(p_course uuid, p_country text) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare c record; v_cc text := upper(btrim(coalesce(p_country, ''))); v_levels uuid[]; v_band text; v_rows jsonb; v_note text;
begin
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries k where k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode = '22023';
  end if;
  select x.id, x.provider_id, x.study_level_id, l.short_code into c from catalogue.courses x left join ref.study_levels l on l.id = x.study_level_id where x.id = p_course;
  if c.id is null then raise exception 'INVALID_INPUT: course not found' using errcode = '22023'; end if;
  -- the course's level and the matrix levels the setting treats as the same (entry.level_equivalents, "BH=BA")
  v_levels := array_remove(array[c.study_level_id] || array(
                select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) p
                  join ref.study_levels l2 on l2.short_code = split_part(p, '=', 2)
                 where split_part(p, '=', 1) = c.short_code), null);
  -- 1 a course override (audience international or all; this country or none)
  select jsonb_agg(jsonb_build_object('text', r.description, 'min_grade', r.min_grade, 'min_score', r.min_entry_score, 'min_score_basis', r.min_entry_score_basis,
                                      'quote', r.quote, 'as_at', r.as_at, 'case_by_case', r.min_grade is null and r.min_entry_score is null) order by r.created_at)
    into v_rows from catalogue.course_entry_requirements r left join ref.countries k on k.id = r.country_id
   where r.course_id = c.id and r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.country_id is null or k.iso_alpha2 = v_cc);
  if v_rows is not null then
    return jsonb_build_object('country', v_cc, 'step', 1, 'rule', 'course_override', 'rows', v_rows,
      'outcome', case when exists (select 1 from jsonb_array_elements(v_rows) z where not (z->>'case_by_case')::boolean) then 'minimum_published' else 'case_by_case' end);
  end if;
  -- 2 a per-course matrix row for the country; 3 the band ladder; 4 the provider minimum (active rows only, never proposed or quarantined)
  for i in 2 .. 4 loop
    if i = 3 then
      select r.benchmark_band into v_band from catalogue.course_entry_requirements r
       where r.course_id = c.id and r.status = 'active' and r.benchmark_band is not null and r.audience in ('international', 'all') order by r.updated_at desc limit 1;
      if v_band is null then continue; end if;
    end if;
    select jsonb_agg(jsonb_build_object('qualification', m.qualification_name, 'study_level', m.level_label, 'min_grade', m.min_grade, 'scale', m.grade_scale,
                                        'band', m.benchmark_band, 'conditions', m.conditions, 'quote', m.quote, 'as_at', m.as_at, 'edition', m.edition,
                                        'case_by_case', m.min_grade is null or m.grade_scale = 'none') order by m.qualification_name, m.level_label)
      into v_rows from catalogue.provider_entry_matrix m
     where m.provider_id = c.provider_id and m.status = 'active' and m.country_code = v_cc
       and case i when 2 then m.course_id = c.id
                  when 3 then m.course_id is null and m.matrix_kind = 'band_ladder' and m.benchmark_band = v_band and m.study_level_id = any (v_levels)
                  else m.course_id is null and m.matrix_kind = 'provider_minimum' and m.study_level_id = any (v_levels) end;
    if v_rows is not null then
      return jsonb_build_object('country', v_cc, 'step', i, 'rule', case i when 2 then 'course_country_row' when 3 then 'band_ladder' else 'provider_minimum' end,
        'band', case when i = 3 then v_band end, 'rows', v_rows,
        'outcome', case when exists (select 1 from jsonb_array_elements(v_rows) z where not (z->>'case_by_case')::boolean) then 'minimum_published' else 'case_by_case' end);
    end if;
  end loop;
  -- 5 nothing published applies: contact the provider (never invented). Say why a band table could not be used.
  v_note := case
    when v_band is null and exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id and m.status = 'active' and m.country_code = v_cc
                                       and m.matrix_kind = 'band_ladder' and m.study_level_id = any (v_levels))
      then 'The provider publishes a band table for this country, but the course page prints no band to enter it with.'
    when v_band is not null then 'The course band ' || v_band || ' has no published row for this country and level.'
    when exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id and m.status = 'active' and m.country_code = v_cc)
      then 'The provider publishes rows for this country, none for this course''s level.'
    else 'No published requirement for this country.' end;
  return jsonb_build_object('country', v_cc, 'step', 5, 'rule', 'contact_provider', 'outcome', 'contact_provider', 'rows', '[]'::jsonb, 'note', v_note,
    'contact', (select p.website from catalogue.providers p where p.id = c.provider_id));
end $$;
revoke all on function security.entry_resolve_v1(uuid, text) from public, anon, authenticated;
comment on function security.entry_resolve_v1(uuid, text) is 'CF-247 Track C Step B: the five-rule entry resolution (course override → per-course country row → band ladder → provider minimum → contact the provider) over active rows; case by case kept; pure lookup.';

-- ---------------------------------------------------------------- B5 admin reads and the read request
create or replace function public.admin_entry_requirements(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_pid uuid; v_cid uuid; v_size int; v_page int; v_status text; v_cc text; v_level text;
        v_total int; v jsonb; c record; g record; v_job uuid; v_reason text;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v_size := greatest(1, least(coalesce(nullif(p_args->>'page_size', '')::int, 50), 100));  -- fixed: a page is at most 100 rows
  v_page := greatest(1, coalesce(nullif(p_args->>'page', '')::int, 1));
  if p_action = 'provider_matrix' then
    v_pid := nullif(p_args->>'provider_id', '')::uuid; if v_pid is null then raise exception 'provider_id required'; end if;
    v_status := nullif(p_args->>'status', ''); v_cc := upper(nullif(p_args->>'country', '')); v_level := nullif(p_args->>'level', '');
    if v_status is not null and v_status not in ('active', 'proposed', 'inactive', 'superseded', 'unverified') then raise exception 'unknown status'; end if;
    select count(*) into v_total from catalogue.provider_entry_matrix m
     where m.provider_id = v_pid and (v_status is null or m.status = v_status) and (v_cc is null or m.country_code = v_cc) and (v_level is null or m.level_label = v_level);
    return jsonb_build_object('total', v_total, 'page', v_page, 'page_size', v_size,
      'counts', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select m.status s, count(*) n from catalogue.provider_entry_matrix m where m.provider_id = v_pid group by 1) z),
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', z.cc, 'n', z.n) order by z.cc), '[]'::jsonb) from (select m.country_code cc, count(*) n from catalogue.provider_entry_matrix m where m.provider_id = v_pid group by 1) z),
      'levels', (select coalesce(jsonb_agg(distinct m.level_label), '[]'::jsonb) from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.level_label is not null),
      'rows', (select coalesce(jsonb_agg(z.x order by z.cc, z.lv, z.band, z.q), '[]'::jsonb) from (
        select m.country_code cc, m.level_label lv, m.benchmark_band band, m.qualification_name q,
               jsonb_build_object('id', m.id, 'country', m.country_code, 'level', m.level_label, 'kind', m.matrix_kind, 'qualification', m.qualification_name,
                 'band', m.benchmark_band, 'min_grade', m.min_grade, 'min_value', m.min_value, 'scale', m.grade_scale, 'conditions', m.conditions, 'quote', m.quote,
                 'source_url', m.source_url, 'evidence', case when e.id is null then null else jsonb_build_object('id', e.id, 'captured_at', e.captured_at, 'content_hash', e.content_hash) end,
                 'as_at', m.as_at, 'edition', m.edition, 'status', m.status, 'status_reason', m.status_reason, 'course_code', k.course_code,
                 'run', case when r.id is null then null else jsonb_build_object('id', r.id, 'state', r.state, 'attempts', r.attempts, 'error', r.error, 'done_at', r.done_at,
                   'review_item_id', r.review_item_id, 'review_status', (select li.status from pipeline.layer4_review_items li where li.id = r.review_item_id)) end) x
          from catalogue.provider_entry_matrix m left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.evidence_artifacts e on e.id = m.evidence_id
          left join catalogue.courses k on k.id = m.course_id
         where m.provider_id = v_pid and (v_status is null or m.status = v_status) and (v_cc is null or m.country_code = v_cc) and (v_level is null or m.level_label = v_level)
         order by m.country_code, m.level_label, m.benchmark_band, m.qualification_name limit v_size offset (v_page - 1) * v_size) z));
  elsif p_action = 'course' then
    v_cid := nullif(p_args->>'course_id', '')::uuid; if v_cid is null then raise exception 'course_id required'; end if;
    select x.id, x.provider_id, x.canonical_title, x.course_code, l.short_code lvl, k.iso_alpha2 cc into c
      from catalogue.courses x left join ref.study_levels l on l.id = x.study_level_id join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id where x.id = v_cid;
    if c.id is null then raise exception 'course not found'; end if;
    select pg.url, pg.status, pg.identity_basis, e.id ev, e.captured_at, e.storage_path is not null held into g
      from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = v_cid;
    return jsonb_build_object('course', jsonb_build_object('id', c.id, 'title', c.canonical_title, 'code', c.course_code, 'level', c.lvl, 'country', c.cc, 'provider_id', c.provider_id),
      'page', case when g.url is null then null else jsonb_build_object('url', g.url, 'status', g.status, 'identity_basis', g.identity_basis, 'evidence_id', g.ev, 'captured_at', g.captured_at, 'held', g.held) end,
      'rows', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'audience', r.audience, 'description', r.description, 'min_grade', r.min_grade,
                 'min_entry_score', r.min_entry_score, 'min_entry_score_basis', r.min_entry_score_basis, 'benchmark_band', r.benchmark_band, 'quote', r.quote,
                 'source_url', r.source_url, 'evidence_id', r.evidence_id, 'confidence', r.confidence, 'as_at', r.as_at, 'status', r.status, 'status_reason', r.status_reason,
                 'review_item_id', r.provenance->>'review_item_id', 'model', r.provenance->>'model') order by r.status, r.kind), '[]'::jsonb)
               from (select * from catalogue.course_entry_requirements r0 where r0.course_id = v_cid order by r0.created_at desc limit 100) r),  -- fixed: a course's rows, at most 100
      'reviews', (select coalesce(jsonb_agg(jsonb_build_object('id', li.id, 'status', li.status, 'created_at', li.created_at, 'rows', li.proposed_value->'rows') order by li.created_at desc), '[]'::jsonb)
                    from (select * from pipeline.layer4_review_items l0 where l0.entity_type = 'course' and l0.entity_id = v_cid and l0.field_code = 'course_entry_first_read' order by l0.created_at desc limit 10) li),
      'reads', (select coalesce(jsonb_agg(jsonb_build_object('item_id', fi.id, 'state', fi.state, 'reason', fi.reason, 'cost_usd', fi.cost_usd, 'created_at', fi.created_at,
                    'dropped', fi.value->'dropped', 'notes', fi.value->'notes') order by fi.created_at desc), '[]'::jsonb)
                  from (select * from pipeline.field_enrich_items f0 where f0.course_id = v_cid and f0.field = 'entry_requirements' order by f0.id desc limit 10) fi),
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k2.iso_alpha2, 'name', k2.name) order by k2.name), '[]'::jsonb) from ref.countries k2 where k2.iso_alpha2 ~ '^[A-Z]{2}$'),
      'can_read', v_rank >= 6 and g.held is true and c.cc in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '[]'::jsonb))));
  elsif p_action = 'resolve' then
    v_cid := nullif(p_args->>'course_id', '')::uuid; if v_cid is null then raise exception 'course_id required'; end if;
    return security.entry_resolve_v1(v_cid, p_args->>'country');
  elsif p_action = 'read' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    v_cid := nullif(p_args->>'course_id', '')::uuid; v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 5 then raise exception 'give a reason (kept in the log)'; end if;
    select x.id, x.provider_id, x.canonical_title, k.iso_alpha2 cc into c
      from catalogue.courses x join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id where x.id = v_cid;
    if c.id is null then raise exception 'course not found'; end if;
    if c.cc is null or c.cc not in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '[]'::jsonb))) then
      raise exception 'course entry requirements are not read for this country (entry.course_read_countries)';
    end if;
    if exists (select 1 from pipeline.field_enrich_items f where f.course_id = v_cid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased', 'review')) then
      raise exception 'a read of this course is already in progress or waits in Layer 4';
    end if;
    v_job := security.course_entry_read_enqueue_v1(v_cid, auth.uid(), v_reason);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('entry_requirements', 'course_read', v_cid::text, jsonb_build_object('reason', v_reason, 'job_id', v_job), auth.uid());
    return jsonb_build_object('job_id', v_job);
  end if;
  raise exception 'unknown action %', p_action;
end $$;
revoke all on function public.admin_entry_requirements(text, jsonb) from public, anon;
grant execute on function public.admin_entry_requirements(text, jsonb) to authenticated;
comment on function public.admin_entry_requirements(text, jsonb) is 'CF-247 Track C Step B (B5): bounded admin reads of entry requirements (provider matrix, a course''s rows, the resolver) and the Platform Admin''s one-course read request.';

-- one course's read: an Enrich fields task with one entry_requirements item, on the stored page (no re-fetch, no Firecrawl, no fee check)
create or replace function security.course_entry_read_enqueue_v1(p_course uuid, p_by uuid, p_reason text) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_job uuid; c record;
begin
  select x.id, x.provider_id, x.canonical_title into c from catalogue.courses x where x.id = p_course;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || c.canonical_title, 200),
          jsonb_build_object('read_now', true, 'entry_read', true, 'countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(c.provider_id), 'course_ids', jsonb_build_array(c.id),
                             'fields', jsonb_build_array('entry_requirements'), 'ai', true, 'scraper', false),
          jsonb_build_object('done', 0, 'total', 1), p_by, p_reason, '1 course')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_job, c.provider_id, c.id, 'entry_requirements', 'queued') on conflict do nothing;
  return v_job;
end $$;
revoke all on function security.course_entry_read_enqueue_v1(uuid, uuid, text) from public, anon, authenticated;
comment on function security.course_entry_read_enqueue_v1(uuid, uuid, text) is 'CF-247 Track C Step B (B1): one Enrich fields task with one entry_requirements item for one course (stored page only).';

-- ---------------------------------------------------------------- the decided slice read (count-guarded; nothing if already asked)
do $$
declare v_course uuid := '09431698-3cfd-4c2b-8669-e924bc65c329';  -- RMIT Bachelor of Engineering (Honours) BH126, CRICOS 0100714 (decision record section 2)
begin
  if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') = 0
     and exists (select 1 from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id
                  where g.course_id = v_course and g.status = 'bound' and e.storage_path is not null) then
    perform security.course_entry_read_enqueue_v1(v_course, '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid,
      'Track C Step B slice read (Platform Admin mandate 28 Oct 2026 20:36; decision record ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28)');
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('entry_requirements', 'course_read', v_course::text, jsonb_build_object('reason', 'Track C Step B slice read (decided 28 Oct 2026)', 'migration', '20261028001000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  end if;
  if (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements') > 1 then
    raise exception 'slice guard: more than one entry_requirements item would exist';
  end if;
end $$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.enrich_entry_record_v1', 'Pipeline', 'Track C Step B (B1): course entry-requirement rows proposed under the B1 rules; Layer 4 course_entry_first_read', 'active', '{}', '20261028001000'),
 ('function', 'security.course_entry_review_apply_v1', 'Pipeline', 'Track C Step B (B1): Layer 4 admission of a course entry read', 'active', '{}', '20261028001000'),
 ('function', 'security.course_entry_read_enqueue_v1', 'Pipeline', 'Track C Step B (B1): one course''s entry-requirements read on the Enrich fields lane', 'active', '{}', '20261028001000'),
 ('function', 'security.entry_resolve_v1', 'Pipeline', 'Track C Step B: the five-rule entry resolution over active rows', 'active', '{}', '20261028001000'),
 ('function', 'public.admin_entry_requirements', 'Admin', 'Track C Step B (B5): admin entry-requirements reads and the one-course read request', 'active', '{}', '20261028001000')
on conflict do nothing;
