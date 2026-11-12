-- CF-247 Website API v3, build brief WP-1.6 (O22, REQ-28: academic entry in search). Decision 277: v3 only; v2 and everything it reads
-- are only read. (WP-1.5, O20, is Pilot #1093.)
--   O22  search items gain has_academic_entry: true when some admitted academic entry requirement is held for the course (an active
--        course-page requirement for international or all applicants) or for its provider (an active entry matrix row for the course, or
--        one not tied to a course). It means "something is published", no more: it does not say the applicant meets it, and it does not
--        promise rows for this course's study level. The course action with edu_country (entry.resolution) gives the rows that apply, and
--        can still answer contact_provider for a course whose flag is true. search takes two more filters: has_academic_entry (true keeps
--        only those courses, as has_english does) and edu_country (ISO alpha-2, the country of previous education, inside filters): with
--        it, has_academic_entry counts only requirements for that country (a course-page requirement naming no country counts for every
--        country). An unknown edu_country is refused (INVALID_INPUT).
-- How: public.website_v3_course_search_core is made from the live public.website_v2_course_search by named edits (md5-guarded), so the v3
--   search can never drift from v2 on a v2 filter, sort or key. public.website_v3_course_search is edited the same way to call it.
-- Replaces: public.website_v3_course_search(jsonb,integer,integer,text) (same name and signature, by named edits, md5-guarded against the
--   WP-1.7 definition of Pilot #1092). Nothing else is replaced.
-- Retires: nothing.
-- Reversal: supabase/held/website_api_v3_academic_entry_search_forward_recovery.sql (reverse edit; the new functions are then removed by paste file).

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

-- O22: is an admitted academic entry requirement held for this course or its provider (for one country of previous education, when given)
create or replace function security.course_has_academic_entry_v3(p_course uuid, p_provider uuid, p_country text)
-- no security definer and no search_path, so the planner can inline it into the search (every name is schema-qualified; its callers are definer functions)
returns boolean language sql stable as $$
  select exists (select 1 from catalogue.course_entry_requirements r left join ref.countries k on k.id = r.country_id
                  where r.course_id = p_course and r.status = 'active' and r.audience in ('international', 'all')
                    and (p_country is null or r.country_id is null or k.iso_alpha2 = p_country))
      or exists (select 1 from catalogue.provider_entry_matrix m
                  where m.provider_id = p_provider and m.status = 'active' and (m.course_id is null or m.course_id = p_course)
                    and (p_country is null or m.country_code = p_country))
$$;
comment on function security.course_has_academic_entry_v3(uuid, uuid, text) is
  'Website API v3 O22 (build brief WP-1.6): true when some active academic entry requirement is held for the course or its provider (for one country when given). It does not promise entry.resolution rows for the course''s level. Read only.';

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
comment on function public.website_v3_course_search(jsonb, integer, integer, text) is
  'Website API v3 (Decision 277): the v2 search with the filters has_academic_entry and edu_country (O22); items carry R28, description_excerpt (O26) and has_academic_entry (O22).';
revoke all on function security.course_has_academic_entry_v3(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.website_v3_course_search_core(jsonb, integer, integer, text) from public, anon, authenticated;
revoke all on function public.website_v3_course_search_item(jsonb, text) from public, anon, authenticated;
grant execute on function public.website_v3_course_search_core(jsonb, integer, integer, text) to service_role;
grant execute on function public.website_v3_course_search_item(jsonb, text) to service_role;

do $post$ begin
  if security.course_has_academic_entry_v3(null, null, null) is distinct from false then raise exception 'post-check: no course, no requirement'; end if;
  if not (public.website_v3_course_search_item('{"course_id":"none","intakes":[]}'::jsonb, null) ? 'has_academic_entry') then raise exception 'post-check: search items carry has_academic_entry'; end if;
end $post$;
