-- CF-247 R22 (17 Oct 2026): fewer full-load calls for the website. Platform Admin 16 Oct 2026 23:44 and 17 Oct 2026 00:29 ("Proceed with next
-- steps"): developer requests numbered R18-R22, R22 first. Raghav measured a full load of 257 calls in 2 min 53 s, largest page 628 KB.
-- Measured 17 Oct 2026: a sync page is built from stored items in 60-75 ms; the rest of each call (about 0.6 s) is the round trip, so fewer,
-- larger pages make the full load faster. The gateway already compresses replies for a caller that sends Accept-Encoding: gzip (a 476 KB page
-- went out as 69 KB), which the developer guide now asks for.
-- website.sync_page_max 200 -> 600 (its range up to 1000): a full page is about 1.4 MB of JSON, about 0.2 MB compressed; about 90 calls.
-- A caller can still ask for smaller pages with page_size.
-- O8 (provider detail slow) is closed: items are served from the stored copy; building one provider detail takes about 0.13 s.
-- Replaces: nothing (setting value only)
-- Retires: nothing
-- Nothing dropped or deleted.

update pipeline.platform_toolset_settings
   set max_value = 1000, value = to_jsonb(600), updated_at = now(),
       reason = 'CF-247 R22, 17 Oct 2026: full load in about 90 calls (was about 257); a page is built in under 0.1 s, so the round trip decides the time',
       help = 'The most size units one sync reply carries (a unit is website.sync_item_unit_bytes of stored JSON; at least one item a page). 600 is about 1.4 MB, about 0.2 MB when the caller accepts gzip.'
 where toolset_key = 'pipeline' and key = 'website.sync_page_max' and value = to_jsonb(200);

do $post$
begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'website.sync_page_max') <> to_jsonb(600) then
    raise exception 'R22 post-check: website.sync_page_max is not 600';
  end if;
end $post$;
