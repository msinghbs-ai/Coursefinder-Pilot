-- CF-247 Website API v3, build brief WP-1.5 (O20, REQ-28: the printed words and official page of each entry requirement) and WP-1.6 (O22,
-- REQ-28: academic entry in search). Decision 277: v3 only; v2 and everything it reads are only read.
--   O20  provider entry_matrix[] items gain quote and source_url (catalogue.provider_entry_matrix: the printed words and the official page).
--        course entry.resolution.rows[] gain source_url (rows already carry quote); a course-page row takes its own page, a matrix row the
--        matrix page. Every v2 key and value of the row is unchanged. Null means not held.
--   O22  search items gain has_academic_entry: true when an admitted academic entry requirement is held for the course (an active course-page
--        requirement for international or all applicants) or for its provider (an active entry matrix row for the course, or one not tied
--        to a course). It says a requirement is published, not that the applicant meets it; the course action's entry.resolution gives the
--        rows. search takes two more filters: has_academic_entry (true keeps only those courses, as has_english does) and edu_country
--        (ISO alpha-2, the country of previous education): with it, has_academic_entry counts only requirements for that country (a
--        course-page requirement naming no country counts for every country). An unknown edu_country is refused (INVALID_INPUT).
-- How: the v3 forms of three v2 bodies are made from the live v2 definitions by named edits, so they can never drift from v2 on a v2 key:
--   security.entry_matrix_payload_v3 and security.entry_resolve_v3 (the v1 bodies plus the source keys) and
--   public.website_v3_course_search_core (website_v2_course_search plus the two filters). Each source definition is md5-guarded.
-- Replaces: public.website_v3_course_search(jsonb,integer,integer,text), public.website_v3_course(text,text), public.website_v3_provider(text),
--   public.website_v3_provider(text,text) (same names and signatures, by named edits, md5-guarded against the WP-0, WP-1.1 and WP-1.7
--   definitions). public.website_v3_provider_item, public.website_v3_course_search_item(jsonb) and the scholarship functions are not touched.
-- Retires: nothing.
-- Reversal: supabase/held/website_api_v3_entry_source_forward_recovery.sql (reverse edits; the new functions are then removed by paste file).

create or replace function pg_temp.v3_edit(p_sig text, p_md5 text, p_olds text[], p_news text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(d) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(d); end if;
  for i in 1 .. cardinality(p_olds) loop
    if (length(d) - length(replace(d, p_olds[i], ''))) <> length(p_olds[i]) then raise exception '%: edit % must match exactly once', p_sig, i; end if;
    d := replace(d, p_olds[i], p_news[i]);
  end loop;
  execute d;
end $$;

-- O20: the matrix payload with the printed words and the official page of each row
select pg_temp.v3_edit('security.entry_matrix_payload_v1(uuid,text)', '5f7eb75596fd2758871b1df71b859109',
  array['FUNCTION security.entry_matrix_payload_v1(', $o$'as_at', m.as_at, /* CF-247 D5$o$],
  array['FUNCTION security.entry_matrix_payload_v3(', $n$'as_at', m.as_at, 'quote', m.quote, 'source_url', m.source_url, /* CF-247 D5$n$]);
comment on function security.entry_matrix_payload_v3(uuid, text) is
  'Website API v3 O20 (build brief WP-1.5): security.entry_matrix_payload_v1 with quote and source_url on each row; read by Website API v3 only.';

-- O20: the entry resolution with the official page of each row
select pg_temp.v3_edit('security.entry_resolve_v1(uuid,text)', '69bbc05f650191954a22af09c0c85c74',
  array['FUNCTION security.entry_resolve_v1(', $o$'quote', r.quote, 'as_at', r.as_at, 'case_by_case'$o$, $o$'quote', m.quote, 'as_at', m.as_at, 'edition'$o$],
  array['FUNCTION security.entry_resolve_v3(', $n$'quote', r.quote, 'source_url', r.source_url, 'as_at', r.as_at, 'case_by_case'$n$,
        $n$'quote', m.quote, 'source_url', m.source_url, 'as_at', m.as_at, 'edition'$n$]);
comment on function security.entry_resolve_v3(uuid, text) is
  'Website API v3 O20 (build brief WP-1.5): security.entry_resolve_v1 with source_url on each row; read by Website API v3 only.';

-- O22: is an admitted academic entry requirement held for this course or its provider (for one country of previous education, when given)
create or replace function security.course_has_academic_entry_v3(p_course uuid, p_provider uuid, p_country text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from catalogue.course_entry_requirements r left join ref.countries k on k.id = r.country_id
                  where r.course_id = p_course and r.status = 'active' and r.audience in ('international', 'all')
                    and (p_country is null or r.country_id is null or k.iso_alpha2 = p_country))
      or exists (select 1 from catalogue.provider_entry_matrix m
                  where m.provider_id = p_provider and m.status = 'active' and (m.course_id is null or m.course_id = p_course)
                    and (p_country is null or m.country_code = p_country))
$$;
comment on function security.course_has_academic_entry_v3(uuid, uuid, text) is
  'Website API v3 O22 (build brief WP-1.6): true when an active academic entry requirement is held for the course or its provider (for one country when given); read only.';

-- O22: the v2 search with the two filters
select pg_temp.v3_edit('public.website_v2_course_search(jsonb,integer,integer,text)', 'dcefed12a1e879aa1cc0f69e72d91428',
  array['FUNCTION public.website_v2_course_search(',
        $o$'changed_since','institution_types'];$o$,
        $o$  v_need_fee boolean;$o$,
        $o$  if v_kw is not null then v_q := websearch_to_tsquery('english', v_kw); end if;$o$,
        $o$      and (not coalesce((f->>'has_scholarship')::boolean,false) or d.has_scholarship)$o$],
  array['FUNCTION public.website_v3_course_search_core(',
        $n$'changed_since','institution_types','has_academic_entry','edu_country'];$n$,
        $n$  v_need_fee boolean;
  v_edu text := nullif(upper(btrim(coalesce(f->>'edu_country',''))),'');$n$,
        $n$  if v_edu is not null and (v_edu !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries ek where ek.iso_alpha2 = v_edu)) then raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode='22023'; end if;
  if v_kw is not null then v_q := websearch_to_tsquery('english', v_kw); end if;$n$,
        $n$      and (not coalesce((f->>'has_scholarship')::boolean,false) or d.has_scholarship)
      and (not coalesce((f->>'has_academic_entry')::boolean,false) or security.course_has_academic_entry_v3(d.course_id, d.provider_id, v_edu))$n$]);
comment on function public.website_v3_course_search_core(jsonb, integer, integer, text) is
  'Website API v3 O22 (build brief WP-1.6): public.website_v2_course_search with the filters has_academic_entry and edu_country; items are v2 items.';

-- O22: a v3 search item with has_academic_entry
create or replace function public.website_v3_course_search_item(p_item jsonb, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v3_course_search_item(p_item); v_course uuid; v_provider uuid;
begin
  if v is null or jsonb_typeof(v) <> 'object' then return v; end if;
  select d.course_id, d.provider_id into v_course, v_provider from search.course_documents d
   where lower(d.course_stable_key) = lower(v->>'course_id') and d.course_stable_key is not null limit 1;
  return v || jsonb_build_object('has_academic_entry', security.course_has_academic_entry_v3(v_course, v_provider, p_edu_country));
end $$;
comment on function public.website_v3_course_search_item(jsonb, text) is
  'Website API v3: a v3 search item (R28, O26) with has_academic_entry (O22), for one country of previous education when given.';

-- the v3 actions, by named edits of the live definitions
select pg_temp.v3_edit('public.website_v3_course_search(jsonb,integer,integer,text)', '263f5ac682ed8ae297b8586581abebda',
  array['public.website_v2_course_search(p_filters, p_page, p_page_size, p_sort)', 'public.website_v3_course_search_item(x)'],
  array['public.website_v3_course_search_core(p_filters, p_page, p_page_size, p_sort)',
        $n$public.website_v3_course_search_item(x, nullif(upper(btrim(coalesce(p_filters->>'edu_country', ''))), ''))$n$]);
select pg_temp.v3_edit('public.website_v3_course(text,text)', '7f56ec0e8fc16b05f8ff5fb15a2998dc',
  array[$o$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;$o$],
  array[$n$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  -- O20: the same resolution with source_url on each row (the course is the one the v2 answer names)
  if jsonb_typeof(v #> '{item,entry,resolution}') = 'object' then
    v := jsonb_set(v, '{item,entry,resolution}', security.entry_resolve_v3(
           (select d.course_id from search.course_documents d
             where lower(d.course_stable_key) = lower(v #>> '{item,course_id}') and d.course_stable_key is not null limit 1), p_edu_country));
  end if;$n$]);
select pg_temp.v3_edit('public.website_v3_provider(text)', '87f7de23346bdd960fefc0ce5af92d9c',
  array[$o$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;$o$],
  array[$n$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  -- O20: the same matrix with quote and source_url on each row
  if jsonb_typeof(v #> '{item,entry_matrix}') = 'array' then
    v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(
           (select p.id from catalogue.providers p where p.stable_key = v #>> '{item,provider_id}'), null));
  end if;$n$]);
select pg_temp.v3_edit('public.website_v3_provider(text,text)', 'daf3b4a4b89edc5d864fd2d4a5269b7e',
  array[$o$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;$o$],
  array[$n$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  -- O20: the same matrix (for the country asked) with quote and source_url on each row
  if jsonb_typeof(v #> '{item,entry_matrix}') = 'array' then
    v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(
           (select p.id from catalogue.providers p where p.stable_key = v #>> '{item,provider_id}'), upper(btrim(p_edu_country))));
  end if;$n$]);

comment on function public.website_v3_course_search(jsonb, integer, integer, text) is
  'Website API v3 (Decision 277): the v2 search with the filters has_academic_entry and edu_country (O22); items carry R28, description_excerpt (O26) and has_academic_entry (O22).';
comment on function public.website_v3_course(text, text) is
  'Website API v3 (Decision 277): website_v2_course with intakes[].start_date_status (R28) and source_url on entry.resolution.rows[] (O20).';
comment on function public.website_v3_provider(text) is
  'Website API v3 (Decision 277): website_v2_provider with campuses[] one per campus (R23), R31 and quote, source_url on entry_matrix[] (O20).';
comment on function public.website_v3_provider(text, text) is
  'Website API v3 (Decision 277): website_v2_provider with campuses[] one per campus (R23), R31 and quote, source_url on entry_matrix[] (O20).';

revoke all on function security.entry_matrix_payload_v3(uuid, text) from public, anon, authenticated;
revoke all on function security.entry_resolve_v3(uuid, text) from public, anon, authenticated;
revoke all on function security.course_has_academic_entry_v3(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.website_v3_course_search_core(jsonb, integer, integer, text) from public, anon, authenticated;
revoke all on function public.website_v3_course_search_item(jsonb, text) from public, anon, authenticated;
grant execute on function public.website_v3_course_search_core(jsonb, integer, integer, text) to service_role;
grant execute on function public.website_v3_course_search_item(jsonb, text) to service_role;

do $post$ begin
  if security.course_has_academic_entry_v3(null, null, null) is distinct from false then raise exception 'post-check: no course, no requirement'; end if;
  if security.entry_matrix_payload_v3('00000000-0000-0000-0000-000000000000', null) <> '[]'::jsonb then raise exception 'post-check: an unknown provider has no matrix rows'; end if;
  if not (public.website_v3_course_search_item('{"course_id":"none","intakes":[]}'::jsonb, null) ? 'has_academic_entry') then raise exception 'post-check: search items carry has_academic_entry'; end if;
end $post$;
