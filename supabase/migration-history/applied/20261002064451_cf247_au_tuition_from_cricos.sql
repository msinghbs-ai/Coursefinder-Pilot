-- CF-247 (Decision 225, 2 Oct 2026). Platform Admin, 16:42: "Th tuition fees were already listed in cricos for au region
-- why are we investing in refinding those? It should only be done where regulatory are not advertising it and only for
-- international students. We should concentrate on intakes and English requirements."
-- Australian courses carry the international course cost CRICOS publishes (registered tuition, 26,912 courses). The
-- search for a tuition fee on provider pages is therefore stopped for any country whose regulator publishes it:
--  1. a country rule with no tuition identities means "tuition comes from the regulator": Australia's tuition list is
--     emptied (New Zealand and Canada keep theirs). The course-page tuition hand-off to the AI check follows the rule.
--  2. the institution reader stops searching for and reading fee schedules for those countries
--     (security.tuition_chase_enabled); it still finds English policies and academic calendars.
--  3. Australian tuition work waiting for the AI check is parked, and Australian tuition reviews waiting in Layer 4 are
--     closed as superseded with the reason kept.
-- Fees already recorded are not changed. Function patches are behind md5 guards.

update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('tuition', '[]'::jsonb),
       approved_ref = a.approved_ref || '; Decision 225 (tuition comes from CRICOS, the regulator; provider-page fees are not chased; Platform Admin 2 Oct 2026 16:42)',
       updated_at = now()
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'AU';

create or replace function security.tuition_chase_enabled(p_provider_id uuid)
returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((select jsonb_array_length(coalesce(a.identities->'tuition', '[]'::jsonb)) > 0
                     from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
                    where p.id = p_provider_id), false)
$f$;
revoke all on function security.tuition_chase_enabled(uuid) from public, anon, authenticated;

do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('public','svc_provider_facts_search_next','8877b60844b77f8d465a81dc3859134a',
      array[$o$     where s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3)$o$],
      array[$n$     where (s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3))
       and (s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))$n$]),
    ('public','svc_provider_facts_read_next','a028891bb3f7ecf2ad7fed585eeac76a',
      array[$o$     where f.kind = 'fee_schedule'$o$],
      array[$n$     where f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id)$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;

update pipeline.layer3_work_items w
   set status = 'parked', updated_at = now(),
       last_error = left('parked: tuition for this country comes from the regulator (CRICOS); Decision 225', 500)
  from catalogue.courses c
 where c.id = w.entity_id and w.task_class = 'provider_current_tuition_validation' and w.status = 'pending'
   and not security.tuition_chase_enabled(c.provider_id);

update pipeline.layer4_review_items r
   set status = 'superseded', decided_at = now(),
       layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
         'reason', 'Tuition for this course comes from CRICOS, the regulator; a fee on the provider''s page is not chased (Decision 225).',
         'at', now(), 'ref', 'Decision 225'))
  from catalogue.courses c
 where c.id = r.entity_id and r.status = 'pending' and r.field_code = 'provider_current_tuition_validation'
   and not security.tuition_chase_enabled(c.provider_id);
