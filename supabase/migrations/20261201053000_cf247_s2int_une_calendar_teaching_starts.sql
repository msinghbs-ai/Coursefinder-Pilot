-- S2-Intakes (PC-20261128-0931-S2-Intakes, 28 Nov 2026): UNE principal dates 2027 (calendar proposal c914b027) read again by the corrected dated
-- table parser (coverage-sweep policy.ts calendarStarts), which no longer takes an orientation, intensive or assessment period, or teaching that
-- recommences after a break, as a teaching start (decision §1: only a teaching start is a commencement).
-- Found: c914b027 held 15 dated "starts", of which only 22 Feb, 21 Jun and 18 Oct 2027 are trimester starts ("Trimester N Starts"); the other
--   rows are orientation days, mid- and end-of-trimester intensive and assessment periods and "Teaching Recommences" (block starts after a break).
--   The S1-Build Batch 08 record (admin s1327) asked for a person to edit the proposal; the Admin screen edits months only, so the reading itself
--   is corrected at its source and the person's decision stays a plain Approve or Reject.
-- What: the stored copy of that one document (fact source 3dd66033-e7c5-4819-88d8-b20ea94b1012) is put back on the existing calendar re-read
--   (job calendar-reread, through the admission-rule runner; no fetch, no Firecrawl, no AI). The re-read refreshes c914b027 in place; its status
--   stays proposed. Nothing is approved here: the address was rejected by a person earlier, so only a person can approve the refreshed reading
--   (Admin › Academic calendars, UNE, Approve). No intake date is written by this change.
-- Guards: G1 (no job), G2 (no setting), G3 (no consumer API object), G4 (cf-247-s541, parser case added).
-- Replaces: nothing.
-- Retires: nothing.

update pipeline.calendar_reread_state
   set state = 'waiting', attempts = 0,
       reason = 'S2-Intakes 28 Nov 2026: the dated parser no longer takes orientation, intensive, assessment or recommencing-teaching rows as starts; read the stored UNE principal dates 2027 copy again (no fetch)'
 where fact_source_id = '3dd66033-e7c5-4819-88d8-b20ea94b1012' and state <> 'leased';
