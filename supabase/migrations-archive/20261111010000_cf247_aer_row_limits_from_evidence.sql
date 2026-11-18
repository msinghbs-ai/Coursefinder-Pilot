-- CF-247 AER row limits from measured evidence (Platform Admin decision 10 Nov 2026 23:4x, decision 2 of the AER recovery pack: "Yes, from evidence").
-- Guards: G1 (no job added), G2 (values live in settings, not code), G3 (no consumer API object changed). Layer 4 authority unchanged: a recovered read is a NEW waiting item.
-- Evidence (production, read only, 10 Nov 2026 23:3x AEDT, project fxcwkweaxjtknorudmwp): latest pipeline.aer_replay_checks per pending course_entry_first_read item
-- whose replay was refused only by the row limit (entry.max_rows_per_course = 6, entry.max_rows_by_provider = []):
--   RMIT 83 items need 7..19 (median 10)            -> 19   (all 83)
--   Monash 33 items need 7..52 (median 17)          -> 19   (19 of 33; 14 need 22..52 = per-country lists, left held: not raised past the setting maximum 19)
--   QUT 32 items need 16..121 (median 69)           -> not set: these are per-country admission tables read as course rows (matrix content); raising
--                                                      would be unsupported expansion. They stay held and are reported as an exception for the entry matrix route.
--   AUT 4 (7,7,8,11) -> 11; ANU 1 (11) -> 11; UNSW 1 (9) -> 9; MIT 1 (8) -> 8; Adelaide 2 (7,30) -> 7 (the 30-row read stays held); EIT, Ara, Deakin 1 each (7) -> 7
-- Expected recovery by job aer-replay with no AI read: about 113 held reads, each checked again by E13 and D-R2 (duplicates collapse to one row: 20261107130000),
-- replaced only when complete. Replay throughput is raised so that this clears in about a day (no spend; each replay replaces one waiting item with one).
-- Reversal: set entry.max_rows_by_provider back to [] and the three replay settings back to 5 / 10 / 100.
-- Replaces: nothing. Retires: nothing.

do $g$
begin
  if (select max_value::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.max_rows_per_course') < 19 then
    raise exception 'entry.max_rows_per_course maximum is below 19; a provider value above it would be ignored';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider') <> '[]'::jsonb then
    raise exception 'entry.max_rows_by_provider is not empty: reconcile with the live value before applying';
  end if;
end $g$;

update pipeline.platform_toolset_settings
   set value = '["8e1adb6c-e069-43db-9584-bd054255e702=19", "543b87b8-f0dd-4bc7-80d6-76252cfaabec=19", "39301fa8-bff2-4389-bbcd-32d8415fae04=11", "e47a940d-186f-4a17-bb22-2b794b73248c=11", "22657140-1cb0-4fa7-91df-90518ea8b35b=9", "becd7287-5ede-4a62-800e-b2cd15d62c33=8", "de2201a1-69ee-40ff-b6aa-0e54e535e6c0=7", "ea5a3fa6-31f4-4553-9cfd-6bff49c36a6b=7", "87576ec2-c4b0-4a00-ab94-64422c77d545=7", "c5c5d225-3d4c-4e41-8275-78eddd261073=7"]'::jsonb,
       reason = 'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 2: from evidence): per-university limits from measured replay needs (RMIT 19, Monash 19, AUT 11, ANU 11, UNSW 9, MIT 8, Adelaide/EIT/Ara/Deakin 7); QUT left at 6 (country tables belong to the matrix route)',
       updated_at = now()
 where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';

update pipeline.platform_toolset_settings set value = to_jsonb(20), reason = 'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 2): clear the evidence-recovered held reads in about a day; no spend', updated_at = now()
 where toolset_key = 'pipeline' and key = 'batch.aer_replay';
update pipeline.platform_toolset_settings set value = to_jsonb(10), reason = 'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 2): RMIT holds 83 recoverable reads; no spend', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.replay_per_provider';
update pipeline.platform_toolset_settings set value = to_jsonb(200), reason = 'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 2): about 113 recoverable reads; no spend', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.replay_daily_max';

do $p$
begin
  if security.course_entry_max_rows_v1('8e1adb6c-e069-43db-9584-bd054255e702') <> 19 then raise exception 'post-check: RMIT limit not read as 19'; end if;
  if security.course_entry_max_rows_v1('2c4f515c-c146-4e90-ba8a-294130aa1f40') <> 6 then raise exception 'post-check: QUT must stay at the global 6'; end if;
end $p$;
