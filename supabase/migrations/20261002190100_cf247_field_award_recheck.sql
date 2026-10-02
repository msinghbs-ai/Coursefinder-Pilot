-- CF-247 (Decision 235, 2 Oct 2026 23:25 AEST). The hand check of the first 25 Canadian field + award matches (identity
-- v0.5.8) found 23 right and 2 to tighten: "Mathematics Honours" taken for plain Mathematics, and a UBC Okanagan course
-- matched to a page that does not say Okanagan. Rule v0.5.9 (worker v0.11.1) keeps "honours" as part of the field and
-- needs "Okanagan" in the heading or title for UBC Okanagan courses. Pages matched under v0.5.8 are set back to mismatch so
-- the stored-page check runs them again under v0.5.9. None of them was admitted: Canadian admission does not yet accept
-- field + award (switched on separately after a second hand check).
update pipeline.coverage_course_pages
   set status = 'mismatch', read_status = 'identity_mismatch', identity_basis = null
 where identity_basis = 'field_award' and coalesce(basis, '') <> 'manual';
