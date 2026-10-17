-- CF-247 Decision 262 (17 Oct 2026): one English policy in force per university and study level. Platform Admin 17 Oct 2026 15:01, asked how
-- 32 universities came to hold more than one approved English policy (19 with differing IELTS defaults): "One policy per uni and report it as
-- well, also record it in admin repo."
-- Cause: automatic approval of AI readings (15 Oct) and earlier written-out policies left a university's older approved policies in place, so
-- the 10-minute apply job applied several policies for the same level.
-- Rule (security.english_policy_in_force_v1, run for every university with an overlap at the start of each provider-english-defaults run):
--   for each level (undergraduate, postgraduate, research) held by more than one approved policy, the one in force is the first of:
--   1 a page that is not a course page (no /course/ or /courses/ path, no English for Academic Purposes course, no overseas campus page),
--   2 every value quoted on the page, 3 the most courses already holding its values for that level, 4 the latest decision.
--   The other policies give up that level (kept in proposal.superseded_defaults with the policy in force); a policy left with no level is closed
--   (status superseded, with a note). Course rows from a policy that gave up the level are moved to the policy in force when it gives the same
--   value for that test; otherwise the row stays and a Layer 4 item asks a person to confirm (one per course, with the value held and the value
--   of the policy in force). Courses a policy names keep their rows.
-- Also: policy parser v0.2.5 (coverage-sweep worker v0.27.2) does not read a default from a section for courses with alternative English
--   requirements (UTas).
-- Replaces: the provider-english-defaults job command gains the in-force step first (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if (select md5(command) from cron.job where jobname = 'provider-english-defaults') <> 'd6054619c7beac652113e755cdaea995' then
    raise exception 'live provider-english-defaults command differs from the one this change replaces';
  end if;
end $guard$;

create or replace function security.english_level_group(p_code text)
returns text language sql immutable set search_path = '' as $function$
  select case when p_code in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
              when p_code in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
              when p_code in ('doctorate', 'masters_research') then 'research' end
$function$;

create or replace function security.english_policy_in_force_v1(p_provider_id uuid, p_apply boolean)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare r record; d record; c record; p pipeline.provider_policy_proposals%rowtype;
        v_items jsonb := '[]'::jsonb; v_stripped jsonb := '[]'::jsonb; v_moved int := 0; v_l4 int := 0; v_closed int := 0; v_l4_courses uuid[] := '{}';
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
        v_ref text := 'CF-CHG-20260915-247; Decision 262 (one English policy in force per university and level)';
begin
  for r in
    with docs as (
      select pp.id, lv, pp.decided_at,
             pp.url !~* '(/courses?/|english-for-academic|/bengaluru/)' page_ok,
             not exists (select 1 from jsonb_array_elements(pp.proposal->'defaults'->lv) e where coalesce(e->>'quote', '') = '') quoted,
             (select count(*) from catalogue.course_english_requirements cr join catalogue.courses co on co.id = cr.course_id
                left join ref.study_levels sl on sl.id = co.study_level_id
               where cr.source_requirement_key like 'policy:' || pp.id || ':%' and cr.status = 'active' and security.english_level_group(sl.code) = lv) rows_lv
        from pipeline.provider_policy_proposals pp, jsonb_object_keys(coalesce(pp.proposal->'defaults', '{}'::jsonb)) lv
       where pp.provider_id = p_provider_id and pp.kind = 'english_policy' and pp.status = 'approved'
         and lv in ('undergraduate', 'postgraduate', 'research')
         and jsonb_typeof(pp.proposal->'defaults'->lv) = 'array' and jsonb_array_length(pp.proposal->'defaults'->lv) > 0)
    select docs.lv, array_agg(docs.id order by docs.page_ok desc, docs.quoted desc, docs.rows_lv desc, docs.decided_at desc nulls last) ids
      from docs group by docs.lv having count(*) > 1
  loop
    select * into p from pipeline.provider_policy_proposals where id = r.ids[1];
    for d in select * from pipeline.provider_policy_proposals where id = any (r.ids[2:]) loop
      for c in select cr.id rid, cr.course_id, t.code test, cr.overall_score v
                 from catalogue.course_english_requirements cr join ref.english_tests t on t.id = cr.english_test_id
                 join catalogue.courses co on co.id = cr.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                where cr.source_requirement_key like 'policy:' || d.id || ':%' and cr.status = 'active'
                  and security.english_level_group(sl.code) = r.lv and cr.notes like 'Default for %' loop
        if exists (select 1 from jsonb_array_elements(p.proposal->'defaults'->r.lv) e where e->>'test_code' = c.test and (e->>'overall_score')::numeric = c.v) then
          if p_apply then
            update catalogue.course_english_requirements
               set source_requirement_key = 'policy:' || p.id || ':' || lower(c.test), evidence_id = coalesce(p.evidence_id, evidence_id), last_verified_at = now(),
                   notes = notes || format(' In force from %s: %s (one English policy per university and level).', v_day, p.url)
             where id = c.rid;
          end if;
          v_moved := v_moved + 1;
        elsif not c.course_id = any (v_l4_courses) then
          v_l4_courses := v_l4_courses || c.course_id;
          if p_apply and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c.course_id
                                                                                 and i.field_code = 'course_english' and i.status = 'pending') then
            insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                                     status, escalation_reason, change_control_ref, created_at)
            values ('course', c.course_id, 'course_english', p.evidence_id,
                    (select coalesce(jsonb_agg(jsonb_build_object('test', t2.code, 'overall', x.overall_score) order by t2.code), '[]'::jsonb)
                       from catalogue.course_english_requirements x join ref.english_tests t2 on t2.id = x.english_test_id where x.course_id = c.course_id and x.status = 'active'),
                    jsonb_build_object('english_requirements', (select jsonb_agg(jsonb_build_object('test_code', e->>'test_code', 'overall_score', (e->>'overall_score')::numeric,
                                         'component_scores', coalesce(e->'component_scores', '{}'::jsonb), 'notes', 'From the English policy in force: ' || p.url))
                                                                from jsonb_array_elements(p.proposal->'defaults'->r.lv) e)),
                    jsonb_build_object('page', p.url, 'source', 'English policy in force', 'superseded_policy', d.url),
                    '{}'::jsonb, 'pending',
                    format('This university had two approved English policies for %s courses. This course holds %s %s from %s; the policy now in force (%s) gives %s. Please confirm which is right.',
                           r.lv, c.test, c.v, d.url, p.url,
                           (select string_agg((e->>'test_code') || ' ' || (e->>'overall_score'), ', ') from jsonb_array_elements(p.proposal->'defaults'->r.lv) e)),
                    v_ref, now());
            v_l4 := v_l4 + 1;
          end if;
        end if;
      end loop;
      if p_apply then
        update pipeline.provider_policy_proposals
           set proposal = jsonb_set(proposal #- array['defaults', r.lv], '{superseded_defaults}',
                 coalesce(proposal->'superseded_defaults', '{}'::jsonb) || jsonb_build_object(r.lv, jsonb_build_object('defaults', proposal->'defaults'->r.lv,
                   'in_force', p.id, 'url', p.url, 'at', now()))),
               plan_at = null, updated_at = now()
         where id = d.id;
      end if;
      v_stripped := v_stripped || jsonb_build_object('id', d.id, 'level', r.lv);
      v_items := v_items || jsonb_build_object('level', r.lv, 'in_force', jsonb_build_object('id', p.id, 'url', p.url, 'parser', p.parser),
                                               'gives_up', jsonb_build_object('id', d.id, 'url', d.url, 'parser', d.parser));
    end loop;
  end loop;
  -- a policy left with no level is closed
  select count(*) into v_closed from pipeline.provider_policy_proposals pp
   where pp.provider_id = p_provider_id and pp.kind = 'english_policy' and pp.status = 'approved'
     and not exists (select 1 from jsonb_object_keys(coalesce(pp.proposal->'defaults', '{}'::jsonb)) k
                      where k in ('undergraduate', 'postgraduate', 'research')
                        and jsonb_typeof(pp.proposal->'defaults'->k) = 'array' and jsonb_array_length(pp.proposal->'defaults'->k) > 0
                        and not exists (select 1 from jsonb_array_elements(v_stripped) s where s->>'id' = pp.id::text and s->>'level' = k))
     and exists (select 1 from jsonb_array_elements(v_stripped) s where s->>'id' = pp.id::text);
  if p_apply and v_closed > 0 then
    update pipeline.provider_policy_proposals pp
       set status = 'superseded', decided_at = now(), updated_at = now(),
           decision_note = format('Closed %s: one English policy in force per university and level (Decision 262); its levels are held by another approved policy.', v_day)
     where pp.provider_id = p_provider_id and pp.kind = 'english_policy' and pp.status = 'approved'
       and pp.proposal->'superseded_defaults' is not null
       and not exists (select 1 from jsonb_object_keys(coalesce(pp.proposal->'defaults', '{}'::jsonb)) k
                        where jsonb_typeof(pp.proposal->'defaults'->k) = 'array' and jsonb_array_length(pp.proposal->'defaults'->k) > 0);
  end if;
  return jsonb_build_object('provider_id', p_provider_id, 'levels', jsonb_array_length(v_items), 'rows_moved', v_moved,
                            'layer4', case when p_apply then v_l4 else cardinality(v_l4_courses) end, 'closed', v_closed, 'items', v_items);
end $function$;

create or replace function security.english_policy_in_force_all_v1(p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_pid uuid; v jsonb; v_out jsonb := '[]'::jsonb; v_moved int := 0; v_l4 int := 0; v_closed int := 0; v_levels int := 0;
begin
  for v_pid in
    select pp.provider_id from pipeline.provider_policy_proposals pp, jsonb_object_keys(coalesce(pp.proposal->'defaults', '{}'::jsonb)) lv
     where pp.kind = 'english_policy' and pp.status = 'approved' and lv in ('undergraduate', 'postgraduate', 'research')
       and jsonb_typeof(pp.proposal->'defaults'->lv) = 'array' and jsonb_array_length(pp.proposal->'defaults'->lv) > 0
     group by pp.provider_id, lv having count(*) > 1
  loop
    if exists (select 1 from jsonb_array_elements(v_out) o where o->>'provider_id' = v_pid::text) then continue; end if;
    v := security.english_policy_in_force_v1(v_pid, p_apply);
    v_out := v_out || (v || jsonb_build_object('provider', (select canonical_name from catalogue.providers where id = v_pid)));
    v_levels := v_levels + (v->>'levels')::int; v_moved := v_moved + (v->>'rows_moved')::int; v_l4 := v_l4 + (v->>'layer4')::int; v_closed := v_closed + (v->>'closed')::int;
  end loop;
  if p_apply and jsonb_array_length(v_out) > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'in_force', 'english_policy', jsonb_build_object('decision', 'Decision 262', 'universities', jsonb_array_length(v_out), 'levels', v_levels,
            'rows_moved', v_moved, 'layer4', v_l4, 'closed', v_closed, 'items', v_out), null);
  end if;
  return jsonb_build_object('universities', jsonb_array_length(v_out), 'levels', v_levels, 'rows_moved', v_moved, 'layer4', v_l4, 'closed', v_closed, 'items', v_out);
end $function$;

revoke execute on function security.english_policy_in_force_v1(uuid, boolean), security.english_policy_in_force_all_v1(boolean) from public, anon, authenticated;

-- every 10-minute run settles the policy in force first, then plans and applies as before
select cron.alter_job((select jobid from cron.job where jobname = 'provider-english-defaults'),
  command := $$select security.english_policy_in_force_all_v1(true); select security.provider_policy_refresh_plans_v1(security.pipeline_num_v1('batch.provider_policy_refresh', 12)::int); select security.provider_english_apply_all_v1();$$);
update pipeline.automation_catalogue
   set description = 'Every 10 minutes: keeps one approved English policy in force per university and level (Decision 262: a real admission page with quoted values first; course rows from the others move to it when the value is the same, otherwise a person confirms in Layer 4), works out each policy''s course-by-course plan, then gives courses the English requirement from their university''s policy (the course''s own requirement where the policy names it, otherwise the default for its level). Only courses with no English requirement, no review open and no page still to read; research, double degrees and courses the policy names are held back.'
 where jobname = 'provider-english-defaults';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.english_policy_in_force_v1', 'Layer 2', 'One English policy in force per university and level (Decision 262)', 'active', '20261017040000'),
 ('function', 'security.english_policy_in_force_all_v1', 'Layer 2', 'Runs the in-force rule for every university with overlapping approved English policies', 'active', '20261017040000'),
 ('function', 'security.english_level_group', 'Layer 2', 'Study level code to English policy level (undergraduate, postgraduate, research)', 'active', '20261017040000')
on conflict (kind, name) do nothing;

-- settle the overlaps now (recorded in the admin events)
select security.english_policy_in_force_all_v1(true);

do $post$
begin
  if exists (select 1 from pipeline.provider_policy_proposals pp, jsonb_object_keys(coalesce(pp.proposal->'defaults', '{}'::jsonb)) lv
              where pp.kind = 'english_policy' and pp.status = 'approved' and lv in ('undergraduate', 'postgraduate', 'research')
                and jsonb_typeof(pp.proposal->'defaults'->lv) = 'array' and jsonb_array_length(pp.proposal->'defaults'->lv) > 0
              group by pp.provider_id, lv having count(*) > 1) then
    raise exception 'Decision 262 post-check: a university still has two approved English policies for one level';
  end if;
end $post$;
