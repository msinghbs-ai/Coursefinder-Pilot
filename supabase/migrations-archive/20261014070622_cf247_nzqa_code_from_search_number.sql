-- CF-247 v2.15.276 (14 Oct 2026) Decision 258: the NZQA provider search number is the NZQA organisation number followed by a
-- five-digit site number (checked: 415 of 415 search numbers in the stored register evidence give a registered NZQA number).
-- layer1-provider-facts v1.3.0 reads code_from_id from the source and matches every row by the organisation number. The name
-- match added earlier today remains only for a number that matches nothing. Nothing is dropped or deleted.
update pipeline.sources
   set metadata = metadata || jsonb_build_object('code_from_id', '^([0-9]+)[0-9]{5}$'), updated_at = now()
 where metadata->>'source_system' = 'PROVIDER_FACTS' and label = 'NZQA provider search: organisation type'
   and not (metadata ? 'code_from_id');
