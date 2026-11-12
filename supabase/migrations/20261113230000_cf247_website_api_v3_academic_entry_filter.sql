-- CF-247 Website API v3, build brief WP-1.6 (O22, REQ-28): search filter has_academic_entry, optionally narrowed by edu_country.
-- Decision 277: v3 only; v2 is only read. v2 search takes neither (has_english exists, academic entry does not).
--   has_academic_entry true   courses with a published academic entry requirement: the provider's admitted entry table (any country, or
--                             the edu_country given) or, with no edu_country, an admitted minimum score on the course itself
--   has_academic_entry false  the other courses
--   edu_country               ISO alpha-2; narrows has_academic_entry to that country of previous education (provider tables only, because a
--                             course-level score names no country). Given without has_academic_entry it is not applied and listed in
--                             filters_not_applied, as v2 does for any filter it does not apply.
-- Live 12 Nov 2026: 16 providers hold an entry table (4,153 searchable courses); 321 more courses hold a course-level minimum score.
--
-- How: public.website_v3_course_search_core is made from the live public.website_v2_course_search definition (md5-guarded) with three
-- edits: its name; the two filters added to its list of known filters; one more condition beside the provider filter, plus input checks.
-- Paging, totals, sorting and items are therefore exactly v2's. public.website_v3_course_search (WP-1.7) calls it in place of v2.
-- Replaces: public.website_v3_course_search(jsonb, integer, integer, text) (same name and signature; md5-guarded). Retires: nothing.

create or replace function pg_temp.copy_with_edits(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change copies (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> 1 then raise exception '%: copy edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

do $guard$
begin
  if md5(pg_get_functiondef('public.website_v3_course_search(jsonb,integer,integer,text)'::regprocedure)) <> '263f5ac682ed8ae297b8586581abebda' then
    raise exception 'live public.website_v3_course_search differs from the WP-1.7 definition (md5 %)', md5(pg_get_functiondef('public.website_v3_course_search(jsonb,integer,integer,text)'::regprocedure));
  end if;
end $guard$;

select pg_temp.copy_with_edits('public.website_v2_course_search(jsonb,integer,integer,text)', 'dcefed12a1e879aa1cc0f69e72d91428', array[
  -- 1. its own name (v2 stays as it is)
  array[$o$public.website_v2_course_search($o$, $n$public.website_v3_course_search_core($n$],
  -- 2. the two filters are known (edu_country only when has_academic_entry is given)
  array[$o$'changed_since','institution_types'];$o$,
        $n$'changed_since','institution_types','has_academic_entry']
                          || case when nullif(f->>'has_academic_entry','') is not null then array['edu_country'] else array[]::text[] end;$n$],
  -- 3. input checks
  array[$o$if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;$o$,
        $n$if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  -- 20261113230000 (Website API v3 O22): has_academic_entry and edu_country
  if nullif(f->>'has_academic_entry','') is not null and lower(f->>'has_academic_entry') not in ('true','false') then raise exception 'INVALID_INPUT: has_academic_entry must be true or false' using errcode='22023'; end if;
  if nullif(f->>'has_academic_entry','') is not null and nullif(f->>'edu_country','') is not null
     and not exists (select 1 from ref.countries k where k.iso_alpha2 = upper(btrim(f->>'edu_country'))) then
    raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode='22023';
  end if;$n$],
  -- 4. the condition, beside the provider filter
  array[$o$and (v_providers is null or d.provider_stable_key = any(v_providers))$o$,
        $n$and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (nullif(f->>'has_academic_entry','') is null
           or (exists (select 1 from catalogue.provider_entry_matrix em where em.provider_id = d.provider_id and em.status = 'active'
                        and (nullif(f->>'edu_country','') is null or em.country_code = upper(btrim(f->>'edu_country'))))
               or (nullif(f->>'edu_country','') is null
                   and exists (select 1 from catalogue.course_entry_requirements er where er.course_id = d.course_id and er.status = 'active' and er.min_entry_score is not null)))
              = lower(f->>'has_academic_entry')::boolean)$n$]
]);
comment on function public.website_v3_course_search_core(jsonb, integer, integer, text) is
  'Website API v3 O22 (build brief WP-1.6): public.website_v2_course_search as of 12 Nov 2026 (md5 dcefed12) with filters has_academic_entry and edu_country.';
revoke all on function public.website_v3_course_search_core(jsonb, integer, integer, text) from public, anon, authenticated;
grant execute on function public.website_v3_course_search_core(jsonb, integer, integer, text) to service_role;

create or replace function public.website_v3_course_search(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v3_course_search_core(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_course_search_item(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;
comment on function public.website_v3_course_search(jsonb, integer, integer, text) is
  'Website API v3 (Decision 277): course search with has_academic_entry and edu_country (O22), intakes[].start_date_status (R28) and description_excerpt (O26).';

do $post$ begin
  if (public.website_v3_course_search_core('{"country_codes":["AU"]}'::jsonb, 1, 5, null) - 'items') <> (public.website_v2_course_search('{"country_codes":["AU"]}'::jsonb, 1, 5, null) - 'items')
  then raise exception 'post-check: without the new filters the v3 search must answer as v2'; end if;
end $post$;
