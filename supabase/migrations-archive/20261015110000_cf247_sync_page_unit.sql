-- CF-247 (15 Oct 2026): Wix full load. With stored items measured (a course item averages about 2.1 KB), a 2 KB unit counted most courses twice
-- (412 calls, pages up to 380 KB). A 3 KB unit gives about 252 calls with pages up to about 540 KB (simulated over all 40,617 items).
-- Replaces: the 2 KB sync page unit (setting value)
-- Retires: nothing
update pipeline.platform_toolset_settings set value = to_jsonb(3072),
       reason = 'Measured 15 Oct 2026: 3 KB unit = about 252 full-load calls, largest page about 540 KB (2 KB: 412 calls; 4 KB: 235 calls, 723 KB)'
 where toolset_key = 'pipeline' and key = 'website.sync_item_unit_bytes';
do $post$ begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'website.sync_item_unit_bytes') <> to_jsonb(3072) then raise exception 'unit post-check'; end if;
end $post$;
