-- MEASURE (read only). Run after migration 20261107150000 is applied; nothing is written, fetched or paid for.
-- What the stored-link step would do for every AER-eligible provider that has no entry-requirements page today, with the step still off:
-- outcomes (attached / host_shared / no_entry_candidate / no_link_material), and the pages it would attach per provider (would_attach).
-- Limit 1500 is the largest value of setting batch.aer_source_stored_find.
select security.entry_source_stored_find_v1(1500, false);
