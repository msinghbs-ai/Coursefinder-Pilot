-- PASTE (Platform Admin): CF-247 s1125, P0 AER preprocessing (Platform Admin 25 Nov 2026 08:16 AEDT, Admin #1063).
-- Project fxcwkweaxjtknorudmwp only. Run after Pilot migration 20261126190000 (s1125) is live. One transaction.
-- What it does:
--   1. widens two CHECK constraints of the existing Lean AI Input harness tables, so they take the course entry requirements cohort:
--      pipeline.lean_section_eval_cases.gold_source also accepts 'ai_earlier' (an earlier paid AI answer, checked against the page, not ground
--      truth) and 'cohort_size' (a cohort page measured for size only); pipeline.lean_qualify_cases.field also accepts 'entry_requirements'.
--      Every value the old constraints accepted is still accepted. A migration never drops a constraint, so this is a paste file.
--   2. calls security.lean_entry_qualify_start_v1() (from the migration): seeds 152 earlier rows and 225 cohort pages for the recall check (no AI),
--      and 332 qualification pages (53 earlier-answer pages and 30 Layer 4 accepted pages on deepseek-v4-flash, qwen3-30b, mistral-small-3.2 and
--      mimo-v2.6-flash); opens the on-demand request (estimate US$0.60; the existing ceiling reading.lean_qualify_ceiling_usd, US$2.00, stops it);
--      sets reading.lean_qualify_on 1 and batch.lean_qualify 3; resumes the catalogued jobs lean-qualify and lean-sections-eval.
--   Nothing is admitted, proposed or sent to Layer 4; the course_entry_requirements route stays off; no qualification is recorded.
-- Guarded: stops unless the two constraints are exactly the definitions read on 25 Nov 2026 and the start function exists.
begin;
do $p$
begin
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'lean_section_eval_cases_gold_source_check') <> 'CHECK ((gold_source = ANY (ARRAY[''aer_accepted''::text, ''adapter''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'lean_qualify_cases_field_check') <> 'CHECK ((field = ANY (ARRAY[''fees''::text, ''intakes''::text])))' then
    raise exception 'stop: a harness CHECK constraint is not the definition read on 25 Nov 2026';
  end if;
  if to_regprocedure('security.lean_entry_qualify_start_v1()') is null then raise exception 'stop: Pilot migration 20261126190000 (s1125) is not live'; end if;
end $p$;
alter table pipeline.lean_section_eval_cases drop constraint lean_section_eval_cases_gold_source_check,
  add constraint lean_section_eval_cases_gold_source_check check (gold_source in ('aer_accepted', 'adapter', 'ai_earlier', 'cohort_size'));
alter table pipeline.lean_qualify_cases drop constraint lean_qualify_cases_field_check,
  add constraint lean_qualify_cases_field_check check (field in ('fees', 'intakes', 'entry_requirements'));
select security.lean_entry_qualify_start_v1() as started;
commit;
