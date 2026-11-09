-- CF-247 AER lock agreement fixture: production shape of the locks (live, read only, 9 Nov 2026). 97 waiting course entry reads belong to courses a person bound to an
-- official page by hand on 5 Oct 2026: manual_locks course_url and official_url, mode value, one setter, nothing on entry_requirements. Here: one lock pair on each
-- of the cases below, one lock on a single page field, one lock on entry_requirements (the case the rule already knew) and one on a field D-R2 does not list.
create table fxl.cases(k text primary key, item uuid not null, course uuid not null);
do $$
declare v_who uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b'; v_at timestamptz := '2026-10-05 03:54:28.710141+00'; r record;
begin
  -- candidates in a fixed order, from the live rule; each case takes the next unlocked item of its class
  create temp table cand on commit drop as
  select i.id item, i.entity_id course, security.aer_recovery_rule_v1(i.id)->>'class' cls, row_number() over (partition by security.aer_recovery_rule_v1(i.id)->>'class' order by i.id) rn
    from pipeline.layer4_review_items i
   where i.status = 'pending' and i.field_code = 'course_entry_first_read'
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id);
  insert into fxl.cases(k, item, course)
  select k, item, course from (values
    ('pair_a',        'reread_eligible', 1), ('pair_b', 'reread_eligible', 2), ('single_official', 'reread_eligible', 3), ('entry_req', 'reread_eligible', 4),
    ('other_field',   'reread_eligible', 5), ('unlocked', 'reread_eligible', 6), ('pair_changed', 'changed_conditions', 1),
    ('pair_rowlimit', 'row_limit', 1), ('pair_ready', 'ready', 1), ('pair_stale', 'stale', 1), ('pair_human', 'human_assisted', 1)) v(k, cls, rn)
  join cand c on c.cls = v.cls and c.rn = v.rn;
  if (select count(*) from fxl.cases) <> 11 then raise exception 'the fixture lacks a candidate for each case: %', (select count(*) from fxl.cases); end if;
  for r in select * from fxl.cases where k like 'pair\_%' loop
    insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at) values ('course', r.course, 'course_url', 'value', v_who, v_at), ('course', r.course, 'official_url', 'value', v_who, v_at);
  end loop;
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at) select 'course', course, 'official_url', 'value', v_who, v_at from fxl.cases where k = 'single_official';
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at) select 'course', course, 'entry_requirements', 'value', v_who, v_at from fxl.cases where k = 'entry_req';
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at) select 'course', course, 'tuition', 'value', v_who, v_at from fxl.cases where k = 'other_field';
end $$;
-- the lane's run under the live rule, as it runs each hour
select security.aer_technical_recovery_v1() is not null;
