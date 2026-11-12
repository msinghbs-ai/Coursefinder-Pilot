-- CF-247 F-AER.08 production verification: UNSW's grid read is recorded within the statement time (Platform Admin mandate 12 Nov 2026 09:23: "If production
-- verification fails ... correct the root cause and continue autonomously").
-- Guards: G1 (no job), G2 (no new value), G3 (catalogue.courses is read by the consumer API: two indexes are added beside it; no column, function or row of it is
--   altered, dropped, renamed or retyped), Decision 260, Layer 4 authority unchanged.
-- Evidence (production, 12 Nov 2026 10:24-10:45 AEDT): UNSW's grid read (2,257 rows) failed three times, the last as "svc_entry_matrix_record: canceling statement due to
--   statement timeout" (the first try was also stopped by the worker call's CPU limit, fixed in v0.74.1). Sydney (2,047 rows, linked by CRICOS code) and UQ (1,430
--   rows, 383 courses) were recorded. UNSW links by title: each new printed course compares its key with every one of its 667 courses' canonical and display
--   titles, computing the key each time (65 labels x 1,334 keys), inside the one statement that records the read.
-- What:
--   1. Expression indexes on catalogue.courses (provider_id, security.entry_course_title_key_v1(canonical_title | display_title)): the title rule of
--      security.entry_course_link_v1 becomes an index lookup (the function is immutable; the query is unchanged).
--   2. security.entry_course_link_v1 looks the stored link up first and reads its settings and level rules only for a label not yet decided; a label with no single
--      match is recorded without suggestions, and the suggestions are made when a person opens the label in Layer 4 (security.entry_course_link_suggest_v1, called by
--      public.admin_entry_course_links, now volatile). Measured on live (rolled back): 1,950 rows recorded in 12.6 s (6 ms a row), against 1.0 s for rows with no
--      course; one link call of an already-linked label cost 1.1 ms (three settings and the level rules read before the lookup); recording is one statement under the
--      8 s API limit.
--   3. UNSW's stored PDF is read again (no model, no Firecrawl), unless a person has taken its item.
-- Live definitions this change replaces (md5 of pg_get_functiondef, read 12 Nov 2026 15:50 AEDT): security.entry_course_link_v1 6b78fe97a66288f86d587db399e05567,
--   public.admin_entry_course_links c8a14456f2549ea0f81b80cc4f3c4a2f (both from #1050).
-- Replaces: security.entry_course_link_v1 and public.admin_entry_course_links (same signatures). Retires: nothing.

create index if not exists courses_title_key_ix on catalogue.courses (provider_id, security.entry_course_title_key_v1(canonical_title));
create index if not exists courses_display_title_key_ix on catalogue.courses (provider_id, security.entry_course_title_key_v1(display_title));

do $g$
begin
  if md5(pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure)) <> '6b78fe97a66288f86d587db399e05567'
     or md5(pg_get_functiondef('public.admin_entry_course_links(uuid,text)'::regprocedure)) <> 'c8a14456f2549ea0f81b80cc4f3c4a2f' then
    raise exception 'live course-link functions differ from the definitions this change replaces';
  end if;
end $g$;

create or replace function security.entry_course_link_v1(p_provider uuid, p_label text, p_cricos text default null, p_source uuid default null, p_quote text default null)
returns uuid language plpgsql security definer set search_path to '' as $f$
declare v_key text := security.entry_course_title_key_v1(p_label); l catalogue.entry_course_links%rowtype; v_ids uuid[]; v_code text; v_levels text[]; v_method text;
begin
  if p_provider is null or v_key is null then return null; end if;
  -- the stored decision first (one index lookup): a confirmed link is reused, a person's "no catalogue course" stands
  select * into l from catalogue.entry_course_links where provider_id = p_provider and label_key = v_key;
  if l.state = 'confirmed' then return l.course_id; end if;
  if l.state = 'rejected' then return null; end if;
  if security.pipeline_num_v1('aer.course_link_on', 1) < 1 then return null; end if;
  v_code := upper(btrim(coalesce(p_cricos, '')));
  -- an unresolved label is looked at again only when its code differs or the provider's catalogue changed since
  if l.state = 'unresolved' and v_code = coalesce(l.cricos_code, '')
     and not exists (select 1 from catalogue.courses c where c.provider_id = p_provider and c.updated_at > l.updated_at) then return null; end if;
  -- 1 the CRICOS code printed on the row, at this provider, one active course
  if v_code ~ '^[0-9]{6}[0-9A-Z]$' then
    v_ids := array(select c.id from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active' and upper(btrim(c.course_code)) = v_code);
    if cardinality(v_ids) = 1 then v_method := 'cricos'; end if;
  end if;
  -- 2 the exact title (canonical or display) at this provider, at a level the label names, one active course (courses_title_key_ix, courses_display_title_key_ix)
  v_levels := security.entry_course_label_levels_v1(p_label);
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
  -- 3 no single match: waits for a person; suggestions are made when the label is opened in Layer 4 (security.entry_course_link_suggest_v1)
  insert into catalogue.entry_course_links as x (provider_id, label_key, course_label, state, method, cricos_code, candidates, evidence)
  values (p_provider, v_key, left(p_label, 300), 'unresolved', 'none', nullif(v_code, ''), '[]'::jsonb, jsonb_build_object('source_id', p_source, 'quote', left(p_quote, 300)))
  on conflict (provider_id, label_key) do update set state = 'unresolved', cricos_code = excluded.cricos_code, candidates = '[]'::jsonb, evidence = excluded.evidence, updated_at = now();
  return null;
end $f$;
comment on function security.entry_course_link_v1(uuid, text, text, uuid, text) is 'F-AER.08 decision 2: the catalogue course of a printed course label (the stored decision; else CRICOS code; else exact title and level, one course only); null when unresolved. Suggestions are made in Layer 4.';

create or replace function security.entry_course_link_suggest_v1(p_link uuid) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare l catalogue.entry_course_links%rowtype; v_cand jsonb;
        v_n int := security.pipeline_num_v1('aer.course_link_candidates', 5)::int; v_min numeric := security.pipeline_num_v1('aer.course_link_candidate_min_overlap', 0.5);
begin
  select * into l from catalogue.entry_course_links where id = p_link for update;
  if l.id is null or l.state <> 'unresolved' then return coalesce(l.candidates, '[]'::jsonb); end if;
  -- the provider's courses whose titles share most words with the label: suggestions for a person, never a link
  select coalesce(jsonb_agg(jsonb_build_object('course_id', z.id, 'title', z.canonical_title, 'code', z.course_code, 'level', z.short_code, 'overlap', round(z.o, 2),
                                               'why', case when z.k = l.label_key then 'same title, another course' else 'shares title words' end) order by z.o desc, z.canonical_title), '[]'::jsonb)
    into v_cand
    from (select c.id, c.canonical_title, c.course_code, s.short_code, k.k,
                 (select count(*) from (select unnest(string_to_array(k.k, ' ')) intersect select unnest(string_to_array(l.label_key, ' '))) i)::numeric
                 / greatest((select count(*) from (select unnest(string_to_array(k.k, ' ')) union select unnest(string_to_array(l.label_key, ' '))) u), 1) o
            from catalogue.courses c left join ref.study_levels s on s.id = c.study_level_id
            cross join lateral (select security.entry_course_title_key_v1(c.canonical_title) k) k
           where c.provider_id = l.provider_id and c.lifecycle_status = 'active'
           order by 6 desc limit v_n) z
   where z.o >= v_min or z.k = l.label_key;
  update catalogue.entry_course_links set candidates = v_cand, evidence = evidence || jsonb_build_object('suggested_at', now()) where id = l.id;
  return v_cand;
end $f$;
comment on function security.entry_course_link_suggest_v1(uuid) is 'F-AER.08 decision 2 step 3: suggested catalogue courses for an unresolved course label (shared title words; suggestions only), made when a person opens it in Layer 4';

create or replace function public.admin_entry_course_links(p_provider uuid, p_state text default null) returns jsonb
language plpgsql volatile security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Layer 4 reviewer required' using errcode = '42501'; end if;
  -- suggestions for the provider's unresolved labels not yet suggested (made here, outside the read that records the rows)
  perform security.entry_course_link_suggest_v1(l.id) from catalogue.entry_course_links l
    where l.provider_id = p_provider and l.state = 'unresolved' and not (l.evidence ? 'suggested_at');
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
comment on function public.admin_entry_course_links(uuid, text) is 'F-AER.08 Layer 4 course links: each printed course label of a provider''s entry tables, its catalogue course or suggestions (made on first view), and its waiting rows';
revoke all on function security.entry_course_link_suggest_v1(uuid) from public, anon, authenticated;

do $r$
declare v jsonb; ids uuid[] := array['b1222e5d-04c2-4964-a574-3630258da766']::uuid[];
begin
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'the item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'F-AER.08 production verification: UNSW grid read again after the course-title index (statement timeout)');
  raise notice 'reread: %', v;
end $r$;
