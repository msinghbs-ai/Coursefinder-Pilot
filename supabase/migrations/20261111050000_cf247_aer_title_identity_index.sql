-- CF-247 F-AER.01 follow-up to 20261111040000 (Integration Controller, 11 Nov 2026 00:0x AEDT): the own-site title rule looks up other bound pages at the same address
-- (cross-provider page, page bound to another course). pipeline.coverage_course_pages (35,717 rows, 71 MB) has no index on url for bound pages, so the rule scanned the table per
-- course and the AER population (and every function built on it: the scheduled reader, aer_no_source_route_v1, Data delivery) hit the statement timeout in the first live check.
-- Adds one partial index (built in well under a second at this size). No function, setting or data changes.
-- Replaces: nothing.
-- Retires: nothing.
create index if not exists coverage_course_pages_bound_url_idx on pipeline.coverage_course_pages (url) where status = 'bound';
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.coverage_course_pages_bound_url_idx', 'Layer 2', 'Index: bound course pages by address (own-site title identity for entry requirements)', 'active', '{}', '20261111050000')
on conflict do nothing;
