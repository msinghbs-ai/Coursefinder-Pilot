-- CF-247 F-AER.03 (country and qualification variants): read again the stored entry pages whose earlier reads dropped international-qualification rows, now that the reader
-- keeps them (Platform Admin 11 Nov 2026 decisions, item 2; worker coverage-sweep v0.70.0 and migration 20261112060000, released and verified 11 Nov 2026 ~19:30 AEDT).
-- Guards: G1 (no job), G2 (nothing in code), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged: each new read goes to a person on its entry-matrix item;
--   active rows stay active until that person approves the new read.
-- Evidence (production, read only, 11 Nov 2026 ~19:40 AEDT): the newest done read of 23 sources (22 providers) dropped 92 rows as unknown_country whose heading is an
--   every-country word or a recognised international qualification. 15 of those providers already have an entry-matrix item waiting for a person; reading their sources again
--   now would put a second item beside the waiting one, so they are left for after that decision. The other 8 sources (28 rows) are read again here.
-- What: public.admin_entry_matrix_reread for those 8 sources (the governed re-read: the newest stored copy's run is queued again with its earlier result kept; no Firecrawl;
--   one AI read each by the pinned entry model). Nothing else changes.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v jsonb;
begin
  v := public.admin_entry_matrix_reread(array['1b84f485-110a-4974-83d9-3398023c3f9c', '2a80f0b5-4d0c-4458-b184-8c139a57deef', '386d077c-420f-426c-bbfd-31f3feaff4e3',
                                              '7b4b9c3c-181b-4574-8d54-f35f61075052', '9528d774-3de3-4860-b7c3-bc3e8fd99e18', 'b02ee786-4338-4ce8-8827-e0c4d31d2a6a',
                                              'c73047ab-dcb1-4bac-bc77-8320152645de', 'f9a2c98b-e0f2-4c92-94ea-5d91799eb70b']::uuid[],
        'F-AER.03 qualification-first (worker v0.70.0): earlier read dropped international-qualification rows as unknown_country; Platform Admin decision 11 Nov 2026 item 2');
  raise notice 'reread: %', v;
  if coalesce((v->>'runs')::int, 0) = 0 then raise exception 'post-check: no source was queued again (%)', v; end if;
end $r$;
