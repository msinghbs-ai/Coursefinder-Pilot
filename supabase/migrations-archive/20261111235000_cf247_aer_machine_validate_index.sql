-- CF-247 F-AER.03 machine admission validation fits its time limit (Platform Admin 11 Nov 2026 14:39 AEDT "Go": enable AER machine admission now, after validation).
-- Guards: G1 (no job), G2 (no operational value), G3 (additive index only: nothing the consumer API reads is altered, dropped, renamed or retyped), Decision 260,
--   "a passing qualification never switches anything on by itself" (this migration switches nothing; activation is a separate, recorded step).
-- Evidence (production, read only, 11 Nov 2026 14:00 AEDT): security.aer_machine_validate_v1() cannot finish inside the API statement limit (2 min; the gateway closes at
--   about 150 s): security.aer_machine_history_v1() alone takes 120 s. It looks up catalogue.course_entry_requirements by provenance->>'review_item_id' three times for each
--   of the 498 past human decisions, and no index serves that expression, so each lookup reads the whole table (4,864 rows, 5.3 MB).
-- What: one expression index on catalogue.course_entry_requirements ((provenance->>'review_item_id')). No function, setting, row or job changes.
-- Replaces: nothing. Retires: nothing.
-- Reversal: drop index catalogue.course_entry_requirements_review_item_idx (a paste file for the Platform Admin; nothing reads the index by name).

create index if not exists course_entry_requirements_review_item_idx on catalogue.course_entry_requirements ((provenance->>'review_item_id'));
comment on index catalogue.course_entry_requirements_review_item_idx is 'CF-247 F-AER.03: serves lookups of entry rows by the Layer 4 item that proposed them (security.aer_machine_history_v1, Layer 4 review); additive.';

do $post$ begin
  if to_regclass('catalogue.course_entry_requirements_review_item_idx') is null then raise exception 'post-check: index missing'; end if;
end $post$;
