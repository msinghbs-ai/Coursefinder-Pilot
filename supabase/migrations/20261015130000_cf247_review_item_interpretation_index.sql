-- CF-247 (15 Oct 2026): usage audit D7. The paste file that purges unused Layer 3 interpretations timed out in its dry run: removing an
-- interpretation checks that no Layer 4 review item still points at it, and the only index on layer4_review_items.layer3_interpretation_id
-- covers pending items only, so every check read the whole table (64,395 checks x 20,000 rows). A plain index makes each check a lookup.
-- Replaces: nothing (the pending-only unique index stays; it enforces one pending review per interpretation)
-- Retires: nothing
-- 1 Index  Nothing dropped or deleted.

create index if not exists layer4_review_items_layer3_interpretation on pipeline.layer4_review_items (layer3_interpretation_id) where layer3_interpretation_id is not null;

do $post$
begin
  if not exists (select 1 from pg_indexes where schemaname = 'pipeline' and indexname = 'layer4_review_items_layer3_interpretation') then
    raise exception 'review item interpretation index post-check: index missing';
  end if;
end $post$;
