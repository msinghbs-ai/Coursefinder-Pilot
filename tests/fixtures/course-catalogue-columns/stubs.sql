-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: reference rows and the two legacy sort paths the fixture does not rebuild.
-- Reference rows copied from production (no user data): the pipeline toolset, the six roles and their ranks, the field absence classes.
insert into pipeline.platform_toolsets(key, label, kind) values ('pipeline', 'Pipeline (job sizes, re-reads and retries)', 'platform') on conflict do nothing;
insert into security.roles(code, name, rank) values ('viewer', 'Viewer', 1), ('counsellor', 'Counsellor', 2), ('curator', 'Curator', 3),
  ('pipeline_operator', 'Pipeline Operator', 4), ('pim_admin', 'PIM Admin', 5), ('platform_admin', 'Platform Admin', 6) on conflict do nothing;
insert into pipeline.field_absence_classes(code, label, meaning, verified_negative, coverage_state, reeval_trigger, sort) values
 ('not_on_this_page', 'Not on this page', 'fixture', true, 'not_on_page', 'page_change', 1),
 ('on_other_stored_page', 'Found on another stored page', 'fixture', false, 'candidate', 'new_page', 2),
 ('needs_source_discovery', 'Needs source discovery', 'fixture', false, null, 'new_page', 3),
 ('evidence_pending', 'Evidence pending', 'fixture', false, 'in_queue', 'page_change', 4),
 ('explicitly_not_stated', 'Explicitly not stated', 'fixture', true, 'not_on_page', 'page_change', 5),
 ('not_applicable', 'Not applicable', 'fixture', false, 'not_on_page', 'none', 6),
 ('identity_unresolved', 'Source identity unresolved', 'fixture', false, 'page_found', 'identity_change', 7)
on conflict do nothing;
-- The fee and completeness sorts go to the legacy decision page (unchanged by this change, not rebuilt here): a stand-in that returns the
-- requested page in title order with the same item shape, so the extras merge is exercised on that path too.
create or replace function public.ui_courses_decision_page(p_limit integer, p_offset integer, p_query text, p_country text, p_subdivision text, p_provider uuid,
  p_level text, p_field text, p_delivery text, p_lifecycle text, p_publication text, p_has_fee boolean, p_has_intake boolean, p_has_english boolean,
  p_has_scholarship boolean, p_min numeric, p_freshness text, p_sort text, p_dir text, p_has_state boolean, p_has_link boolean, p_group text)
returns jsonb language sql stable as $f$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'canonical_title', c.canonical_title) order by lower(c.canonical_title), c.id), '[]'::jsonb),
    'total', (select count(*) from catalogue.courses), 'sort', p_sort, 'direction', p_dir)
  from (select * from catalogue.courses order by lower(canonical_title), id limit p_limit offset p_offset) c
$f$;
create or replace function security.admin_course_page_search_state(p jsonb) returns jsonb language sql stable as $f$ select p $f$;
