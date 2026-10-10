-- CF-247 (Decision 227 flag step, 2 Oct 2026 22:40 AEST). The flag rule of migration 20261002183710 without any approval.
-- 20261002183700 and 20261002183710 were not applied: both database approval prompts were cancelled (19:21 and again
-- 22:37), so nothing is approved here. The Platform Admin approves each policy in Coverage › Attributes › English policies.
--  * Flagged: where a policy gives a university standard but says some courses need more without listing them (or does
--    not say which levels, or has exceptions it does not name), a course given the standard is marked: its note says to
--    check the course page and its confidence is 0.6 instead of 1. UNE and Canberra are marked as such policies.
--  * Courses open to international students are written first.
--  * As before, only courses with no English requirement and none set by hand are written; differences are left as they are.
-- Patch behind an md5 guard on security.provider_english_apply_v1 (migration 20261002183100).

update pipeline.provider_policy_proposals
   set proposal = proposal || jsonb_build_object('flag_standard', true), updated_at = now()
 where id in ('0f2e1883-7d56-474e-b92e-9b9a2a9ed8b0', 'ce6c0e15-b7af-4b1b-a1fa-8228d145767d');

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
