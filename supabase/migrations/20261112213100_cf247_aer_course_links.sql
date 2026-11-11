-- CF-247 F-AER.08 step 3: course links for course-by-qualification entry tables (Platform Admin 11 Nov 2026, decision 2 "Code, title, then AI match, with
-- verification": "1. Exact CRICOS code and verified provider. 2. Exact normalised course title, verified provider and study level, with a unique match. 3. AI-assisted
-- candidate matching for unresolved rows. 4. Human Layer 4 review where identity remains ambiguous. AI must only suggest candidates. Do not automatically admit
-- AI-proposed course associations without independently verified evidence. Persist confirmed course mappings and reuse them"; decision 1: "Every extracted minimum
-- must map to exactly one course and one qualification ... Reject ambiguous or conflicting mappings").
-- Guards: G1 (no job), G2 (the switch and the candidate limits are settings), G3 (no consumer API object: catalogue.provider_qualification_requirements and the new table
--   are read by no consumer function; two columns are added beside, nothing is altered), Decision 260, Layer 4 authority unchanged (a link only names the course of a
--   proposed row; rows are admitted only by a person's decision or rule D1, and a row whose course is not linked is flagged by the D-R3 gate and cannot be admitted).
-- Evidence (production catalogue, read only, 12 Nov 2026 08:50-09:10 AEDT; course labels from the proven grids of the stored UNSW, Sydney and UQ PDFs):
--   Sydney prints a CRICOS code on every row: 89 of 89 labels link by code. UNSW and UQ print none; by exact normalised title, provider and a level the label names:
--   UNSW 44 of 65 (4 labels name two catalogue courses, 17 have no exact title), UQ 49 of 54 (1 two courses, 4 no exact title). 182 of 208 labels (87%) link without
--   a person; the 26 others are listed for a person with the catalogue courses whose titles share most words (suggestions only, never linked by themselves).
--   No course_minimum row has a course today (14 active, 181 proposed): the resolver's rule 2 (a per-course row) has never applied.
-- What:
--   1. Settings: aer.course_link_on (1), aer.course_link_candidates (5), aer.course_link_candidate_min_overlap (0.5).
--   2. catalogue.entry_course_links: one link per provider and printed course label (its normalised key): confirmed (cricos, title or person), unresolved (with
--      candidates) or rejected (a person found no catalogue course). A confirmed link is reused by every later read.
--   3. security.entry_course_title_key_v1 (B -> Bachelor of, M -> Master of, Hons -> Honours, / and & -> and, footnote marks and "(Level n)" removed, words only) and
--      security.entry_course_label_levels_v1 (the study levels a label names); security.entry_course_link_v1 (the four rules above, steps 1, 2 and the person's link).
--   4. catalogue.provider_qualification_requirements: course_label and course_id (additive): a per-course IB or A Level minimum keeps its course and is never
--      recorded as a provider-wide minimum.
--   5. Triggers *_0_course_link (BEFORE INSERT, before the identity trigger): a row with a course label gets its linked course.
--   6. public.svc_entry_matrix_record (md5-guarded): qualification rows keep their course label; the reader's name is kept in the row provenance and the run result
--      (it was dropped: every row said entry_ai); the Layer 4 item shows each sample row's course and the count of rows whose course is not linked.
--   7. security.entry_matrix_gate_v1 (md5-guarded): a waiting row whose course is not linked is flagged (Approve except can leave it out); a qualification row of
--      an unlinked course holds the read until its course is linked.
--   8. public.admin_entry_course_links(provider) and public.admin_entry_course_link_decide(link, course, reason) for Layer 4 (rank 3, the Layer 4 reviewer):
--      a person links a label to one of the provider's catalogue courses, or records that it has none; the waiting rows of that label take the decision.
--   9. Waiting (proposed) rows that already carry a course label are linked now; admitted (active) rows are not changed here.
-- Not here: AI candidates (decision 2 step 3) come with the worker route (step 4), with a pinned model; until then the suggestions are by shared title words.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 08:55 AEDT):
--   public.svc_entry_matrix_record(uuid,jsonb,numeric,text) 2cdbd0a839cb928be0983509e3c68670
--   security.entry_matrix_gate_v1(uuid,uuid[]) 78ca8d1f195a285c1736338768bfaa54
-- Replaces: public.svc_entry_matrix_record and security.entry_matrix_gate_v1 (same names and signatures; md5-guarded text edits).
-- Retires: nothing.
-- Reversal without code: aer.course_link_on 0 (no new link is made, the gate no longer flags unlinked rows; links already made stay as recorded).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.course_link_on', 'Entry requirements: link course rows to catalogue courses',
  '1 links each course-level entry row to one of the provider''s catalogue courses: by the CRICOS code printed on its row, else by the exact course title with a study level the label names, only when exactly one course matches; a label with no single match waits for a person in Layer 4 and its rows cannot be admitted. 0 makes no new link and stops flagging unlinked rows.',
  'number', to_jsonb(1), 0, 1, 'switch', 1530, 'Entry requirements', 'security.entry_course_link_v1, security.entry_matrix_gate_v1',
  'Platform Admin 11 Nov 2026 decision 2 (code, title, then AI match, with verification)'),
 ('pipeline', 'aer.course_link_candidates', 'Entry requirements: course suggestions shown for an unlinked label',
  'How many of the provider''s catalogue courses are suggested to the person for a course label that has no single match (suggestions only; nothing is linked until a person chooses).',
  'number', to_jsonb(5), 1, 20, 'courses', 1531, 'Entry requirements', 'security.entry_course_link_v1', 'CF-247 F-AER.08 step 3'),
 ('pipeline', 'aer.course_link_candidate_min_overlap', 'Entry requirements: shared title words for a course suggestion',
  'A catalogue course is suggested for an unlinked label only when at least this share of the two titles'' words is common to both (0.5 is half).',
  'number', to_jsonb(0.5), 0.1, 1, 'share', 1532, 'Entry requirements', 'security.entry_course_link_v1', 'CF-247 F-AER.08 step 3')
on conflict (toolset_key, key) do nothing;

create table if not exists catalogue.entry_course_links (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  label_key text not null,
  course_label text not null,
  course_id uuid references catalogue.courses(id),
  state text not null check (state in ('confirmed', 'unresolved', 'rejected')),
  method text not null check (method in ('cricos', 'title', 'person', 'none')),
  cricos_code text,
  candidates jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  reason text,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_id, label_key),
  check (state <> 'confirmed' or course_id is not null)
);
comment on table catalogue.entry_course_links is
  'CF-247 F-AER.08 step 3 (decision 2, 11 Nov 2026): the catalogue course of each course label an entry table prints, per provider. confirmed: by the CRICOS code on the row, the exact normalised title with a level the label names (one course only), or a person in Layer 4; unresolved: no single match, waiting for a person with suggested courses; rejected: a person found no catalogue course. Confirmed links are reused by every later read.';
alter table catalogue.entry_course_links enable row level security;

alter table catalogue.provider_qualification_requirements add column if not exists course_label text;
alter table catalogue.provider_qualification_requirements add column if not exists course_id uuid references catalogue.courses(id);
comment on column catalogue.provider_qualification_requirements.course_label is 'F-AER.08: the course the table prints this minimum for (null: the minimum is the provider''s, for every course)';
comment on column catalogue.provider_qualification_requirements.course_id is 'F-AER.08: the catalogue course of course_label (catalogue.entry_course_links); a row with a label and no course cannot be admitted';
create index if not exists provider_qualification_requirements_course_idx on catalogue.provider_qualification_requirements (course_id) where course_id is not null;

create or replace function security.entry_course_title_key_v1(p text) returns text language sql immutable set search_path to '' as $f$
  select nullif(btrim(regexp_replace(regexp_replace(lower(
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
             '[\^*#†‡]+', ' ', 'g'),
             '\(level [0-9]+\)', ' ', 'gi'),
             '\mB\M\.?(\s)', 'Bachelor of\1', 'g'),
             '\mM\M\.?(\s)', 'Master of\1', 'g'),
             '\mHons\M', 'Honours', 'g'),
             '[/&]', ' and ', 'g'),
             '\mof\s+of\M', 'of', 'gi')),
           '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')), '')
$f$;
comment on function security.entry_course_title_key_v1(text) is 'F-AER.08: a course title in one comparable form (B/M abbreviations, Hons, / and &, footnote marks, "(Level n)"); used only for an exact comparison';

create or replace function security.entry_course_label_levels_v1(p text) returns text[] language sql immutable set search_path to '' as $f$
  select array(select distinct l from (
    select unnest(case when k ~ '\mbachelor\M' then array['BA', 'BH'] end) l
    union all select unnest(case when k ~ '\mmaster\M' then array['MA', 'MC', 'MR', 'ME'] end)
    union all select unnest(case when k ~ '\mdoctor\M' then array['DR', 'PD'] end)
    union all select unnest(case when k ~ '\mgraduate diploma\M' then array['GD'] end)
    union all select unnest(case when k ~ '\mgraduate certificate\M' then array['GC'] end)) z where l is not null)
  from (select security.entry_course_title_key_v1(p) k) x
$f$;
comment on function security.entry_course_label_levels_v1(text) is 'F-AER.08: the study levels (ref.study_levels.short_code) a printed course label names (Bachelor: BA, BH; Master: MA, MC, MR, ME; Doctor: DR, PD; Graduate diploma, certificate)';

create or replace function security.entry_course_link_v1(p_provider uuid, p_label text, p_cricos text default null, p_source uuid default null, p_quote text default null)
returns uuid language plpgsql security definer set search_path to '' as $f$
declare v_key text := security.entry_course_title_key_v1(p_label); l catalogue.entry_course_links%rowtype; v_ids uuid[]; v_code text := upper(btrim(coalesce(p_cricos, '')));
        v_levels text[] := security.entry_course_label_levels_v1(p_label); v_cand jsonb; v_method text;
        v_n int := security.pipeline_num_v1('aer.course_link_candidates', 5)::int; v_min numeric := security.pipeline_num_v1('aer.course_link_candidate_min_overlap', 0.5);
begin
  if p_provider is null or v_key is null or security.pipeline_num_v1('aer.course_link_on', 1) < 1 then return null; end if;
  select * into l from catalogue.entry_course_links where provider_id = p_provider and label_key = v_key;
  -- a confirmed link is reused; a person's "no catalogue course" stands; an unresolved label is looked at again only when the provider's catalogue changed since
  if l.state = 'confirmed' then return l.course_id; end if;
  if l.state = 'rejected' then return null; end if;
  if l.state = 'unresolved' and v_code = coalesce(l.cricos_code, '')
     and not exists (select 1 from catalogue.courses c where c.provider_id = p_provider and c.updated_at > l.updated_at) then return null; end if;
  -- 1 the CRICOS code printed on the row, at this provider, one active course
  if v_code ~ '^[0-9]{6}[0-9A-Z]$' then
    v_ids := array(select c.id from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active' and upper(btrim(c.course_code)) = v_code);
    if cardinality(v_ids) = 1 then v_method := 'cricos'; end if;
  end if;
  -- 2 the exact title (canonical or display) at this provider, at a level the label names, one active course
  if v_method is null and cardinality(v_levels) > 0 then
    v_ids := array(select c.id from catalogue.courses c join ref.study_levels s on s.id = c.study_level_id
                    where c.provider_id = p_provider and c.lifecycle_status = 'active' and s.short_code = any (v_levels)
                      and (security.entry_course_title_key_v1(c.canonical_title) = v_key or security.entry_course_title_key_v1(c.display_title) = v_key));
    if cardinality(v_ids) = 1 then v_method := 'title'; end if;
  end if;
  if v_method is not null then
    insert into catalogue.entry_course_links as x (provider_id, label_key, course_label, course_id, state, method, cricos_code, evidence)
    values (p_provider, v_key, left(p_label, 300), v_ids[1], 'confirmed', v_method, nullif(v_code, ''), jsonb_build_object('source_id', p_source, 'quote', left(p_quote, 300)))
    on conflict (provider_id, label_key) do update set course_id = excluded.course_id, state = 'confirmed', method = excluded.method, cricos_code = excluded.cricos_code,
       evidence = excluded.evidence, candidates = '[]'::jsonb, updated_at = now();
    return v_ids[1];
  end if;
  -- 3 no single match: suggestions for a person (the courses whose titles share most words), never a link
  select coalesce(jsonb_agg(jsonb_build_object('course_id', z.id, 'title', z.canonical_title, 'code', z.course_code, 'level', z.short_code, 'overlap', round(z.o, 2),
                                               'why', case when z.k = v_key then 'same title, another course' else 'shares title words' end) order by z.o desc, z.canonical_title), '[]'::jsonb)
    into v_cand
    from (select c.id, c.canonical_title, c.course_code, s.short_code, k.k,
                 (select count(*) from (select unnest(string_to_array(k.k, ' ')) intersect select unnest(string_to_array(v_key, ' '))) i)::numeric
                 / greatest((select count(*) from (select unnest(string_to_array(k.k, ' ')) union select unnest(string_to_array(v_key, ' '))) u), 1) o
            from catalogue.courses c left join ref.study_levels s on s.id = c.study_level_id
            cross join lateral (select security.entry_course_title_key_v1(c.canonical_title) k) k
           where c.provider_id = p_provider and c.lifecycle_status = 'active'
           order by 6 desc limit v_n) z
   where z.o >= v_min or z.k = v_key;
  insert into catalogue.entry_course_links as x (provider_id, label_key, course_label, state, method, cricos_code, candidates, evidence)
  values (p_provider, v_key, left(p_label, 300), 'unresolved', 'none', nullif(v_code, ''), v_cand, jsonb_build_object('source_id', p_source, 'quote', left(p_quote, 300)))
  on conflict (provider_id, label_key) do update set state = 'unresolved', cricos_code = excluded.cricos_code, candidates = excluded.candidates, evidence = excluded.evidence, updated_at = now();
  return null;
end $f$;
comment on function security.entry_course_link_v1(uuid, text, text, uuid, text) is 'F-AER.08 decision 2: the catalogue course of a printed course label (CRICOS code, else exact title and level, one course only; a person''s link is reused); null when unresolved';

create or replace function security.entry_course_link_tg() returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if new.course_id is null and nullif(btrim(new.course_label), '') is not null then
    new.course_id := security.entry_course_link_v1(new.provider_id, new.course_label, new.conditions->>'cricos_code', new.source_id, new.quote);
  end if;
  return new;
end $f$;
-- named to fire before provider_entry_matrix_a_route and provider_entry_matrix_identity (triggers fire in name order), so the identity includes the course
drop trigger if exists provider_entry_matrix_0_course_link on catalogue.provider_entry_matrix;
create trigger provider_entry_matrix_0_course_link before insert on catalogue.provider_entry_matrix for each row execute function security.entry_course_link_tg();
drop trigger if exists provider_qualification_requirements_0_course_link on catalogue.provider_qualification_requirements;
create trigger provider_qualification_requirements_0_course_link before insert on catalogue.provider_qualification_requirements for each row execute function security.entry_course_link_tg();

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

select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', '2cdbd0a839cb928be0983509e3c68670', array[
  array[$o$insert into catalogue.provider_qualification_requirements(provider_id, qualification_code,$o$,
        $n$insert into catalogue.provider_qualification_requirements(provider_id, course_label, qualification_code,$n$],
  array[$o$values (r.provider_id, v_qcode, left(coalesce($o$,
        $n$values (r.provider_id, nullif(trim(v_qx->>'course_name'), ''), v_qcode, left(coalesce($n$],
  array[$o$jsonb_build_object('reader', 'entry_ai', 'model'$o$,
        $n$jsonb_build_object('reader', coalesce(nullif(p_result->>'reader', ''), 'entry_ai'), 'model'$n$],
  array[$o$'completeness', p_result->'completeness', 'qualification_rows', v_qin)$o$,
        $n$'completeness', p_result->'completeness', 'qualification_rows', v_qin, 'reader', p_result->'reader', 'cell_reader', p_result->'cell_reader')$n$],
  array[$o$                'qualification_rows', v_qin,
$o$,
        $n$                'qualification_rows', v_qin,
                -- F-AER.08 (12 Nov 2026): course rows and those whose course is not linked to a catalogue course (Layer 4 course links)
                'course_rows', (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.course_label is not null)
                             + (select count(*) from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.course_label is not null),
                'course_rows_unlinked', (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.course_label is not null and m.course_id is null)
                             + (select count(*) from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.course_label is not null and q.course_id is null),
$n$],
  array[$o$'sample', (select jsonb_agg(jsonb_build_object('id', m.id, 'country', m.country_code,$o$,
        $n$'sample', (select jsonb_agg(jsonb_build_object('id', m.id, 'country', m.country_code, 'course', m.course_label, 'course_linked', m.course_id is not null,$n$]
], array[1, 1, 2, 1, 1, 1]);

select pg_temp.edit_n('security.entry_matrix_gate_v1(uuid,uuid[])', '78ca8d1f195a285c1736338768bfaa54', array[
  array[$o$          then 'another provider, source or stored copy'
$o$,
        $n$          then 'another provider, source or stored copy'
        -- F-AER.08 (12 Nov 2026, decision 1): every course minimum belongs to exactly one catalogue course
        when m.course_label is not null and m.course_id is null and security.pipeline_num_v1('aer.course_link_on', 1) >= 1
          then 'the course is not linked to a catalogue course (Layer 4 course links)'
$n$],
  array[$o$v_flag jsonb; v_dup jsonb;$o$, $n$v_flag jsonb; v_dup jsonb; v_qc int;$n$],
  array[$o$  select coalesce(jsonb_agg(g.ids), '[]'::jsonb) into v_dup$o$,
        $n$  -- F-AER.08 (12 Nov 2026): a qualification minimum printed for one course waits until that course is linked (it is never admitted as the provider's)
  if security.pipeline_num_v1('aer.course_link_on', 1) >= 1 then
    select count(*) into v_qc from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed' and q.course_label is not null and q.course_id is null;
    if v_qc > 0 then
      v_why := v_why || format('%s qualification row(s) belong to a course not linked to a catalogue course: link the course in Layer 4 course links, then decide', v_qc); v_fix := false;
    end if;
  end if;
  select coalesce(jsonb_agg(g.ids), '[]'::jsonb) into v_dup$n$]
], array[1, 1, 1]);

create or replace function public.admin_entry_course_links(p_provider uuid, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Layer 4 reviewer required' using errcode = '42501'; end if;
  return jsonb_build_object('provider_id', p_provider,
    'counts', (select jsonb_object_agg(state, n) from (select state, count(*) n from catalogue.entry_course_links where provider_id = p_provider group by 1) z),
    'links', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'label', l.course_label, 'state', l.state, 'method', l.method, 'cricos', l.cricos_code,
                         'course_id', l.course_id, 'course', c.canonical_title, 'course_code', c.course_code, 'candidates', l.candidates, 'evidence', l.evidence,
                         'reason', l.reason, 'decided_at', l.decided_at,
                         'waiting_rows', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = l.provider_id and m.status = 'proposed'
                                            and security.entry_course_title_key_v1(m.course_label) = l.label_key)
                                       + (select count(*) from catalogue.provider_qualification_requirements q where q.provider_id = l.provider_id and q.status = 'proposed'
                                            and security.entry_course_title_key_v1(q.course_label) = l.label_key))
                       order by case l.state when 'unresolved' then 0 when 'rejected' then 1 else 2 end, l.course_label)
                       from catalogue.entry_course_links l left join catalogue.courses c on c.id = l.course_id
                      where l.provider_id = p_provider and (p_state is null or l.state = p_state)), '[]'::jsonb));
end $f$;
comment on function public.admin_entry_course_links(uuid, text) is 'F-AER.08 Layer 4 course links: each printed course label of a provider''s entry tables, its catalogue course or suggestions, and its waiting rows';

create or replace function public.admin_entry_course_link_decide(p_link uuid, p_course uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare l catalogue.entry_course_links%rowtype; v_reason text := btrim(coalesce(p_reason, '')); v_m int := 0; v_q int := 0;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Layer 4 reviewer required' using errcode = '42501'; end if;
  if length(v_reason) < 5 then raise exception 'reason required'; end if;
  select * into l from catalogue.entry_course_links where id = p_link for update;
  if l.id is null then raise exception 'course link not found'; end if;
  if p_course is not null and not exists (select 1 from catalogue.courses c where c.id = p_course and c.provider_id = l.provider_id) then
    raise exception 'the course is not one of this provider''s catalogue courses' using errcode = '22023';
  end if;
  update catalogue.entry_course_links set course_id = p_course, state = case when p_course is null then 'rejected' else 'confirmed' end, method = 'person',
         reason = v_reason, decided_by = auth.uid(), decided_at = now(), updated_at = now()
   where id = l.id;
  -- the label's waiting rows take the decision (admitted rows are changed only by a later read and its decision)
  update catalogue.provider_entry_matrix m set course_id = p_course, updated_at = now()
   where m.provider_id = l.provider_id and m.status = 'proposed' and security.entry_course_title_key_v1(m.course_label) = l.label_key
     and m.course_id is distinct from p_course;
  get diagnostics v_m = row_count;
  update catalogue.provider_qualification_requirements q set course_id = p_course, updated_at = now()
   where q.provider_id = l.provider_id and q.status = 'proposed' and security.entry_course_title_key_v1(q.course_label) = l.label_key
     and q.course_id is distinct from p_course;
  get diagnostics v_q = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', case when p_course is null then 'course_link_none' else 'course_link' end, 'catalogue.entry_course_links',
          jsonb_build_object('link', l.id, 'provider', l.provider_id, 'label', l.course_label, 'course', p_course, 'previous', l.course_id, 'previous_state', l.state,
                             'rows', v_m, 'qualification_rows', v_q, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'state', case when p_course is null then 'rejected' else 'confirmed' end, 'rows', v_m, 'qualification_rows', v_q);
end $f$;
comment on function public.admin_entry_course_link_decide(uuid, uuid, text) is 'F-AER.08 Layer 4: a person links a printed course label to one of the provider''s catalogue courses (or records none); the label''s waiting rows take it';
revoke all on function public.admin_entry_course_links(uuid, text) from public, anon;
revoke all on function public.admin_entry_course_link_decide(uuid, uuid, text) from public, anon;
grant execute on function public.admin_entry_course_links(uuid, text) to authenticated;
grant execute on function public.admin_entry_course_link_decide(uuid, uuid, text) to authenticated;

-- 9 waiting rows that already carry a course label are linked now (one link per label; the identity trigger recomputes each row's identity)
update catalogue.provider_entry_matrix m set course_id = security.entry_course_link_v1(m.provider_id, m.course_label, m.conditions->>'cricos_code', m.source_id, m.quote), updated_at = now()
 where m.status = 'proposed' and m.course_id is null and nullif(btrim(m.course_label), '') is not null;

do $c$
declare v jsonb;
begin
  select jsonb_build_object('links', (select jsonb_object_agg(state, n) from (select state, count(*) n from catalogue.entry_course_links group by 1) z),
                            'linked_waiting_rows', (select count(*) from catalogue.provider_entry_matrix where status = 'proposed' and course_id is not null)) into v;
  raise notice 'F-AER.08 course links: %', v;
  -- post-checks: the key and the level rules give what the measurements above rest on
  if security.entry_course_title_key_v1('B Arts/B Education (Secondary)^') <> 'bachelor of arts and bachelor of education secondary' then raise exception 'post-check: title key'; end if;
  if security.entry_course_title_key_v1('Bachelor of Arts (Level 7)') <> 'bachelor of arts' then raise exception 'post-check: title key (level)'; end if;
  if not (security.entry_course_label_levels_v1('B Engineering (Hons)/M Engineering') @> array['BA', 'BH', 'MA', 'MC', 'MR', 'ME']) then raise exception 'post-check: label levels'; end if;
  if (select tgname from pg_trigger where tgrelid = 'catalogue.provider_entry_matrix'::regclass and not tgisinternal order by tgname limit 1) <> 'provider_entry_matrix_0_course_link'
    then raise exception 'post-check: the course link must fire before the identity trigger'; end if;
end $c$;
