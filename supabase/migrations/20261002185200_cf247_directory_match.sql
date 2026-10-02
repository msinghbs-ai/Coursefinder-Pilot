-- CF-247 (2 Oct 2026). Hotcourses capture, step 2. The captured listing pages name 154 Canadian and 54 New Zealand
-- institutions. Their profile pages do not show the institution's own website (only tracking links), so Hotcourses gives
-- the institution list and a course count for comparison, not website hints. This function:
--   - matches each listed institution to our provider in the same country by exact normalised name (case, punctuation,
--     a leading "The" and bracketed parts ignored); no fuzzy matching;
--   - reads the course count ("129 courses") from the institution's captured profile page, when it has been captured.
-- Hints only: nothing here changes a provider or a course.
create or replace function security.directory_match_v1(p_site text default 'hotcourses')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline' as $f$
declare v_matched int; v_counts int;
begin
  with p as (
    select p.id, k.iso_alpha2 cc,
           array[trim(regexp_replace(regexp_replace(lower(regexp_replace(coalesce(p.display_name, p.canonical_name), '\s*\([^)]*\)', '', 'g')), '[^a-z0-9]+', ' ', 'g'), '^the ', '')),
                 trim(regexp_replace(regexp_replace(lower(regexp_replace(p.canonical_name, '\s*\([^)]*\)', '', 'g')), '[^a-z0-9]+', ' ', 'g'), '^the ', ''))] names
      from catalogue.providers p join ref.countries k on k.id = p.country_id where p.lifecycle_status = 'active'),
  m as (
    select d.site, d.country_code, d.directory_id, (array_agg(p.id order by p.id))[1] provider_id, count(distinct p.id) n
      from pipeline.directory_institutions d
      join p on p.cc = d.country_code and trim(regexp_replace(regexp_replace(lower(d.name), '[^a-z0-9]+', ' ', 'g'), '^the ', '')) = any(p.names)
     where d.site = p_site group by 1, 2, 3)
  update pipeline.directory_institutions d set provider_id = m.provider_id, matched_by = 'exact_name', updated_at = now()
    from m where m.n = 1 and d.site = m.site and d.country_code = m.country_code and d.directory_id = m.directory_id
     and d.provider_id is distinct from m.provider_id;
  get diagnostics v_matched = row_count;
  update pipeline.directory_institutions d set course_count_hint = x.n, updated_at = now()
    from (select distinct on (di.directory_id, di.country_code) di.directory_id, di.country_code,
                 nullif(regexp_replace(substring(dp.page_text from '(?i)(\d[\d,]{0,6})\s+courses?\M'), ',', '', 'g'), '')::int n
            from pipeline.directory_institutions di join pipeline.directory_pages dp on split_part(dp.url, '#', 1) = di.profile_url
           where di.site = p_site order by di.directory_id, di.country_code, dp.captured_at desc) x
   where d.site = p_site and d.directory_id = x.directory_id and d.country_code = x.country_code and x.n is not null and d.course_count_hint is distinct from x.n;
  get diagnostics v_counts = row_count;
  return jsonb_build_object('matched', v_matched, 'course_counts', v_counts);
end $f$;
revoke all on function security.directory_match_v1(text) from public, anon, authenticated;
select security.directory_match_v1('hotcourses');
