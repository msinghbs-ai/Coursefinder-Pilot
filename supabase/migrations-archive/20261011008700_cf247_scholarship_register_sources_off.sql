-- CF-247 (11 Oct 2026, Platform Admin: no Study Australia or other national register): the three scholarship register sources
-- (Study Australia, Australia Awards, Manaaki) are taken off Layer 1. Their runs have no reader any more (layer1-operations
-- workers) and the feed worker scholarships-au-etl is retired. The rows are kept, marked retired. Nothing is dropped or deleted.
update pipeline.sources
   set metadata = metadata || jsonb_build_object('layer1_register', false, 'retired_at', '2026-10-11',
                                                 'retired_reason', 'Platform Admin 11 Oct 2026: scholarships come only from providers'' own pages; national registers retired')
 where metadata->>'source_system' = 'SCHOLARSHIP_REGISTER';
