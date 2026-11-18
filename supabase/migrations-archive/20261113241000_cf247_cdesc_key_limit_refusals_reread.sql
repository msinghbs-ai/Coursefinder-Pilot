-- CF-247 F-CDESC: description reads the AI service refused on 12 Nov 2026 are put back in line to be read.
-- Platform Admin 12 Nov 2026 22:05 ("dont limit on data admittance make exceptions for it") and 22:11 ("proceed with best solution to conclude").
-- What happened (live, 12 Nov 2026 from 22:41 AEDT): OpenRouter refused every call with "HTTP 403 Key limit exceeded (weekly limit)", the
--   spending limit set on the API key (credit was left). The worker records a refused call as a failed reading of the course, and
--   security.enrich_course_text_gaps_v1 reads a failed course again only after gaps.recheck_days (60) or a new page read. About 3,900
--   courses were recorded failed this way without ever being read.
-- What: those items (field description, failed, reason "HTTP 403 ... Key limit exceeded", course still active and without a description)
--   become skipped with the mark "reread:", which the gap function already reads again (migration 20261112190000). They are read when the
--   daily cap (enrich.course_text_items_per_day, set to 0 on 12 Nov 23:05 as a protective stop, control event 36188) is put back after the
--   key limit is raised. No function, setting, check or admission rule is changed; nothing is admitted by this change.
-- Not in this change (follow-up): the worker and the gap function should treat a refusal by the AI service itself (key limit, credit) as
--   "stop reading", not as a failed reading of each course.
-- Guards: G2 (no operational value; the stop bound is marked fixed), G3 (no consumer API object), housekeeping s42.
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal: none needed (the mark only asks for a reading; the usual checks and machine admission decide what is admitted).

do $rl$
declare v_n int;
begin
  update pipeline.field_enrich_items e
     set state = 'skipped', reason = left('reread: the AI service refused the call (key limit), the course was not read: ' || e.reason, 300), updated_at = now()
   where e.field = 'description' and e.state = 'failed' and e.reason like 'HTTP 403:%Key limit exceeded%'
     and exists (select 1 from catalogue.courses c where c.id = e.course_id and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null);
  get diagnostics v_n = row_count;
  -- fixed: the bound is the 4,000 reads queued when the refusals began, with room; a larger number means something else is being marked
  if v_n > 6000 then raise exception 'repair would mark % readings, far more than the about 3,900 measured: stopped, nothing applied', v_n; end if;
  raise notice 'reread: % refused description reads marked to be read again', v_n;
end $rl$;
