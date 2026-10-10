-- CF-247 (Decision 228 switched on, 3 Oct 2026; Platform Admin "yes calendars", "Try again now"). Part B of
-- 20261003000500: approving a parsed calendar reports how many reviews it will answer; the job answers them every
-- 10 minutes; the job is listed on Automations.
-- 7. approving a parsed calendar reports how many reviews it will answer
do $p$
declare s text; d text;
  o1 text := $o$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;$o$;
  n1 text := $n$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;
  if p_action = 'approve' and x.kind = 'intake_calendar' then
    v := jsonb_build_object('to_answer', (select count(*) from security.semester_intake_plan_v1(x.provider_id) r where r.outcome = 'answer'));
  end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from 'ed78f0a0bd0534430e194c543846edc5' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

select cron.schedule('provider-calendar-intakes', '7-59/10 * * * *', $$select security.semester_intake_apply_v1(null)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-calendar-intakes', 'Admission', 63, 'Answer semester-only intakes from calendars',
        'Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Trimester 2") from the university''s approved calendar, where every period named has one start month. The course page stays the evidence; courses with intakes already, or set by hand, are left alone.', 5, false)
on conflict (jobname) do nothing;
