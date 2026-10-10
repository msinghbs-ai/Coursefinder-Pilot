-- CF-247 (Decision 235, 2 Oct 2026). Platform Admin, 22:55, by multiple choice: "Yes, test then switch on". Canadian course
-- pages matched by field + award (identity v0.5.9) are accepted for the official course page, English and intakes,
-- after a hand check found no wrong pairings (record in the change-control entry of this time). Tuition is unchanged
-- (course code only). Values entered by hand are never overwritten. Hand check: 37 matches under v0.5.9, 36 right and 1
-- the right programme on an archived 2015 calendar page; rule v0.5.10 (worker v0.11.2) no longer uses field + award
-- matches on calendar pages more than a year old, and the matches are checked again under v0.5.10 first.
do $g$
begin
  if (select a.identities from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'CA')
     is distinct from '{"english": ["exact_title"], "intakes": ["exact_title"], "tuition": ["cricos_code"], "official_url": ["exact_title"]}'::jsonb then
    raise exception 'Canadian identities changed; not switching on';
  end if;
end $g$;

update pipeline.coverage_course_pages
   set status = 'mismatch', read_status = 'identity_mismatch', identity_basis = null
 where identity_basis = 'field_award' and coalesce(basis, '') <> 'manual';

update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('english', '["exact_title", "field_award"]'::jsonb,
                                                       'intakes', '["exact_title", "field_award"]'::jsonb,
                                                       'official_url', '["exact_title", "field_award"]'::jsonb),
       approved_ref = a.approved_ref || '; Decision 235 (field + award for Canadian course pages; Platform Admin 2 Oct 2026 22:55, switched on after a hand check)',
       updated_at = now()
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'CA';
