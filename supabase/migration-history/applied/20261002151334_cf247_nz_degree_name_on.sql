-- CF-247 (Decision 236, 3 Oct 2026). Platform Admin, 00:57: "yes NZ". New Zealand university pages that name a degree
-- without its NZQA level are accepted for the official course page, English and intakes (identity v0.5.12, worker
-- v0.12.1): the heading is exactly the degree name, optionally followed by its abbreviation, the page names no other
-- level of it, and the degree is not conjoint, double or a broad degree taught in many subjects. Hand check: 45 matches
-- under v0.5.11, 44 right and 1 a generic "Master of Arts" matched to a subject page, which led to the broad-degree
-- exclusion; the matches are checked again under v0.5.12 first. Tuition is unchanged. Values entered by hand are never
-- overwritten.
do $g$
begin
  if (select a.identities from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ')
     is distinct from '{"english": ["cricos_code", "nzqa_code", "exact_title", "title_level"], "intakes": ["cricos_code", "nzqa_code", "exact_title", "title_level"], "tuition": ["cricos_code", "nzqa_code"], "official_url": ["cricos_code", "nzqa_code", "exact_title", "title_level"]}'::jsonb then
    raise exception 'New Zealand identities changed; not switching on';
  end if;
end $g$;

update pipeline.coverage_course_pages
   set status = 'mismatch', read_status = 'identity_mismatch', identity_basis = null
 where identity_basis = 'degree_name' and coalesce(basis, '') <> 'manual';

update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('english', '["cricos_code", "nzqa_code", "exact_title", "title_level", "degree_name"]'::jsonb,
                                                       'intakes', '["cricos_code", "nzqa_code", "exact_title", "title_level", "degree_name"]'::jsonb,
                                                       'official_url', '["cricos_code", "nzqa_code", "exact_title", "title_level", "degree_name"]'::jsonb),
       approved_ref = a.approved_ref || '; Decision 236 (New Zealand degree name for university pages; Platform Admin 3 Oct 2026 00:57, switched on after a hand check)',
       updated_at = now()
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'NZ';
