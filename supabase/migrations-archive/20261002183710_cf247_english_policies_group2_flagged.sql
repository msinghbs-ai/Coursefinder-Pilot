-- CF-247 (Decision 227, 2 Oct 2026), flag step. Platform Admin, 19:21 and by multiple choice: approve Victoria University, USQ,
-- Sydney, UNE and Canberra too ("Apply all and leave and flag which aren't listed and courses meant for international
-- students are priorities").
--  * Approved: Victoria University's requirements PDF (it names 19 courses that need more, which are held back or given
--    their own score); its two web-page versions are rejected because they do not name those courses. USQ, Sydney, UNE
--    and Canberra are approved as they are.
--  * Flagged: where the policy gives a university standard but says some courses need more without listing them (or does
--    not say which levels, or has exceptions it does not name), a course given the standard is marked: its note says to
--    check the course page and its confidence is 0.6 instead of 1. UNE (higher requirements kept in a separate policy)
--    and Canberra (no single score stated) are flagged by this decision. Values already written for flagged policies are
--    marked the same way. A course's own score from a page that names it is never flagged.
--  * Courses open to international students are written first.
--  * As before, only courses with no English requirement and none set by hand are written; differences are left as they are.
-- Patch behind an md5 guard on security.provider_english_apply_v1 (migration 20261002183100).

update pipeline.provider_policy_proposals
   set proposal = proposal || jsonb_build_object('flag_standard', true), updated_at = now()
 where id in ('0f2e1883-7d56-474e-b92e-9b9a2a9ed8b0', 'ce6c0e15-b7af-4b1b-a1fa-8228d145767d');

update pipeline.provider_policy_proposals
   set status = 'approved', decided_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', decided_at = now(), updated_at = now(),
       decision_note = 'Approved by the Platform Admin, 2 Oct 2026 19:21 (group 2): apply to courses with no English requirement and none set by hand; flag courses given the university standard where the policy does not list the courses that need more; international courses first.'
 where kind = 'english_policy' and status = 'proposed'
   and id in ('147f94d7-da11-4857-baa4-7ea5352cddfe', '0f2e1883-7d56-474e-b92e-9b9a2a9ed8b0', 'ce6c0e15-b7af-4b1b-a1fa-8228d145767d');

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('policies', 'approve', 'English policies, group 2 flagged: Sydney, UNE, Canberra (courses needing more are not listed)',
        jsonb_build_object('decision', 'Decision 227', 'approved_in', 'chat 2 Oct 2026 19:21'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

-- the flag rule, one place
create or replace function security.provider_english_flagged(p_proposal jsonb)
returns boolean language sql immutable as $f$
  select coalesce((p_proposal->>'flag_standard')::boolean, false)
      or coalesce(p_proposal->'caveats', '[]'::jsonb) ?| array['higher_unlisted', 'exceptions_unlisted', 'level_not_stated']
$f$;

do $p$
declare s text; d text;
  o1 text := $o$declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;$o$;
  n1 text := $n$declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;
  v_flag boolean; v_flagged int := 0;$n$;
  o2 text := $o$  for r in select * from security.provider_english_plan_v1(p_proposal_id) where outcome = 'write' loop$o$;
  n2 text := $n$  v_flag := security.provider_english_flagged(x.proposal);
  -- courses open to international students first
  for r in select pl.* from security.provider_english_plan_v1(p_proposal_id) pl join catalogue.courses co on co.id = pl.course_id
            where pl.outcome = 'write' order by co.open_to_international desc nulls last, pl.title loop$n$;
  o3 text := $o$                               || ' courses in ' || v_name || '''s English language policy (approved by a Platform Admin, Decision 227)' end))$o$;
  n3 text := $n$                               || ' courses in ' || v_name || '''s English language policy (approved by a Platform Admin, Decision 227)'
                               || case when v_flag then '. Flagged: this is the university standard; the policy says some courses need more and does not list them, so check the course page' else '' end end))$n$;
  o4 text := $o$      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;$o$;
  n4 text := $n$      if v_flag and r.plan <> 'named' then
        update catalogue.course_english_requirements set confidence = 0.6
         where course_id = r.course_id and source_requirement_key like 'policy:' || x.id || ':%';
        v_flagged := v_flagged + 1;
      end if;
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;$n$;
  o5 text := $o$           'refused', v_err, 'last_error', v_last, 'last_applied_at', now()), updated_at = now()$o$;
  n5 text := $n$           'refused', v_err, 'last_error', v_last, 'last_applied_at', now(),
           'flagged', coalesce((apply_summary->>'flagged')::int, 0) + v_flagged), updated_at = now()$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'provider_english_apply_v1';
  if md5(s) is distinct from '625279c0f125b18eb9c07c71740f057c' then raise exception 'provider_english_apply_v1 changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece 1 not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'piece 2 not found once'; end if;
  if (length(d) - length(replace(d, o3, ''))) / length(o3) <> 1 then raise exception 'piece 3 not found once'; end if;
  if (length(d) - length(replace(d, o4, ''))) / length(o4) <> 1 then raise exception 'piece 4 not found once'; end if;
  if (length(d) - length(replace(d, o5, ''))) / length(o5) <> 1 then raise exception 'piece 5 not found once'; end if;
  execute replace(replace(replace(replace(replace(d, o1, n1), o2, n2), o3, n3), o4, n4), o5, n5);
end $p$;

-- values already written for a flagged policy (default rows only) are marked the same way
update catalogue.course_english_requirements r
   set confidence = 0.6,
       notes = r.notes || '. Flagged: this is the university standard; the policy says some courses need more and does not list them, so check the course page'
  from pipeline.provider_policy_proposals x
 where r.source_requirement_key like 'policy:' || x.id || ':%' and x.kind = 'english_policy' and x.status = 'approved'
   and security.provider_english_flagged(x.proposal) and r.notes like 'Default for %' and r.notes not like '%Flagged:%';
