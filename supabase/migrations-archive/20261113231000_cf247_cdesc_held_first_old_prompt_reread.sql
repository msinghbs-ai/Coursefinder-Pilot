-- CF-247 F-CDESC: first readings held behind the provider's places that an earlier prompt made and that no longer pass the checks are read again.
-- Platform Admin 12 Nov 2026 22:05 ("dont limit on data admittance make exceptions for it") and 22:11 ("proceed with best solution to conclude").
-- Measured live 12 Nov 2026 22:35: 734 description readings wait as held_first_admission (28 providers). 721 were made by the earlier prompt
--   course-text-v2 and 13 record no prompt; 732 fail today's checks (mostly a sentence copied from the page). Two rules together left them
--   with no way forward:
--   security.course_description_promote_held_v1 passes a held reading to the admission check only when it passes the checks, and
--   security.enrich_course_text_gaps_v1 reads a held_first_admission reading again only when its reader was never recorded. So the courses
--   were neither admitted nor read again.
-- What: those readings (earlier prompt, failing today's checks, course still without a description) are marked "reread:", the mark the gap
--   function already reads again whatever prompt made the reading (migration 20261112190000). The released prompt then reads them within the
--   daily cap, and the usual checks and machine admission decide. No function, setting, check or admission rule is changed; nothing is
--   admitted by this change. A held reading made by the released prompt, or one that still passes the checks, is left as it is.
-- Guards: G2 (no operational value; the stop bound is marked fixed), G3 (no consumer API object), housekeeping s42.
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal: none needed (a reading marked "reread:" that is read again and passes is admitted by the usual rule; the mark only asks for a reading).

do $rl$
declare v_n int;
begin
  update pipeline.field_enrich_items e
     set reason = left('reread: held first reading from an earlier prompt no longer passes the checks: ' || e.reason, 300), updated_at = now()
   where e.field = 'description' and e.state = 'skipped' and e.reason like 'held\_first\_admission:%'
     and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()
     and exists (select 1 from catalogue.courses c where c.id = e.course_id and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null)
     and not coalesce((security.course_description_check_v1(e.course_id, e.value)->>'ok')::boolean, false);
  get diagnostics v_n = row_count;
  -- fixed: the bound is the measured 732 with room for the time between measuring and applying
  if v_n > 2000 then raise exception 'relabel would mark % readings, far more than the 732 measured: stopped, nothing applied', v_n; end if;
  raise notice 'reread: % held first readings marked to be read again', v_n;
end $rl$;
