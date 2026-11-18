-- CF-247 Lean AI Input Phase 1b step 1, recall matcher fix (Platform Admin 14 Nov 2026 13:25, option A): worker coverage-sweep v0.91.0 mode
-- lean_sections_eval matches each labelled value against the blocks' words without their "[B<n> @<offset>]" labels (lean-sections.ts blockPlain),
-- so a quote that runs across adjacent blocks is found. Run phase1b-step1-2026-11-14 (worker v0.89.0) under-counted converted-page and selection
-- recall for such quotes; its done cases are kept as recorded (their page, current-reader and first-cut figures are exact), its unread cases are
-- closed as superseded, and the same 2,800 labelled cases are seeded again as run phase1b-step1b-2026-11-14 (same seed, same fixed hash order).
-- The new cases are held for 10 minutes so that only the v0.91.0 worker (deployed in the same release) reads them. No AI, no Firecrawl; nothing
-- admitted; no reader request, prompt, model, admission, budget or consumer API change. Nothing is dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

update pipeline.lean_section_eval_cases
   set state = 'failed', leased_until = null, done_at = now(),
       error = 'superseded: recall matcher fixed in worker v0.91.0; the case is read again in run phase1b-step1b-2026-11-14'
 where run_label = 'phase1b-step1-2026-11-14' and state = 'pending';

select security.lean_sections_eval_seed_v1('phase1b-step1b-2026-11-14');

update pipeline.lean_section_eval_cases set leased_until = now() + interval '10 minutes'  -- fixed: the release window, so the v0.89.0 worker reads none of the new run
 where run_label = 'phase1b-step1b-2026-11-14' and state = 'pending';

do $c$
begin
  if (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1b-2026-11-14') <> (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1-2026-11-14') then
    raise exception 'post-check: run b holds the same cases as run a';
  end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1-2026-11-14' and state = 'pending') then raise exception 'post-check: run a has no unread case left'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1b-2026-11-14' and (state <> 'pending' or leased_until is null)) then raise exception 'post-check: run b is pending and held'; end if;
end $c$;
