-- CF-247 s1168 (S1-RM-Design; Global Autonomous PIM step 2 extended; Platform Admin 25 Nov 2026 23:12 AEDT: "Extend replacement safety to relevant AER and Scholarship writers,
-- including the s871 regression.").
-- Evidence read live before writing (supersessions of the last 21 days, not reversed):
--   aer-det-reread (s871) superseded 1,924 pending course entry reads; for 1,650 of those courses there is now no other pending read and no active entry row.
--   aer-det-propose (s1009) superseded 229; 132 likewise. cdesc-prompt-supersede superseded 4,788 description reads; 2,328 courses now have no description and no pending read.
--   Scholarship AI reviews: 1,302 superseded, 990 with no other pending or admitted review and no active scholarship.
-- The rule (Master Plan section 6.3, step 2): nothing is superseded without a verified successor in the same transaction, else HELD:NO_SUCCESSOR.
--   1. pipeline.supersede_guard_scope: which replaceable things are guarded (data, not code).
--   2. security.supersede_successor_v1(target, id): the successor test.
--        layer4 item: another pending item for the same entity and field, or the value is held now (active entry rows, a course or provider description), or the entity is no longer active;
--        scholarship review: another pending or admitted review for the same candidate, scholarship or page, or the scholarship is active;
--        course entry row: another active entry row of the course, or the course is no longer active.
--   3. Deferred constraint triggers check each supersession at commit (a writer may add its successor before or after in the same transaction; s1165 does the same for fees).
--   4. The s871 reader (security.aer_det_reread_v1) now tests the successor first: a read with none is held (verdict held_no_successor) and stays with a person in Layer 4,
--      so its action never fails as a whole. s1009 (aer_det_propose) proposes its successor in the same transaction, so it passes.
-- Past supersessions are not changed here (the EQUALS recovery is a separate Platform Admin decision). S1-Build's model qualification supersedes nothing and is not touched.
-- G1: no job. G2: scope is data. G3: no consumer API object altered (checked before and after). Locks and cron unchanged.
-- Replaces: the live security.aer_det_reread_v1 (one verdict added, md5 guarded). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the trigger creates
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.aer_det_reread_v1(text,uuid[],text,text)'::regprocedure)) <> '7a79bb260028ea1943a20240c5a42037' then
    raise exception 'guard: security.aer_det_reread_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1168_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1168_cron on commit drop as select count(*) n from cron.job where active;

create table if not exists pipeline.supersede_guard_scope (
  target text not null check (target in ('layer4', 'scholarship_review', 'course_entry_row', 'course_fee')),
  code text not null,
  active boolean not null default true,
  basis text not null,
  created_at timestamptz not null default now(),
  primary key (target, code));
comment on table pipeline.supersede_guard_scope is 'PIM replacement guard scope (s1168): which replaceable things need a verified successor before they are superseded. code is a Layer 4 field_code, or * for the whole target.';
alter table pipeline.supersede_guard_scope enable row level security;
revoke all on table pipeline.supersede_guard_scope from public, anon, authenticated;
grant select on table pipeline.supersede_guard_scope to service_role;

insert into pipeline.supersede_guard_scope(target, code, basis) values
  ('course_fee', '*', 's1165: a fee is superseded only with an active fee of the same type (its own trigger)'),
  ('course_entry_row', '*', 's1168: an active entry row is superseded only with another active entry row of the course'),
  ('layer4', 'course_entry_first_read', 's1168 (s871 regression): a pending course entry read is superseded only with a newer pending read or entry rows held'),
  ('layer4', 'course_description_first_read', 's1168: a pending course description read is superseded only with a newer pending read or a description held'),
  ('layer4', 'provider_description', 's1168: a pending provider description read is superseded only with a newer pending read or a description held'),
  ('scholarship_review', '*', 's1168: a pending scholarship review is superseded only with another pending or admitted review of the same page or scholarship, or the scholarship active')
on conflict (target, code) do nothing;

create or replace function security.supersede_successor_v1(p_target text, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare i record; s record; e record;
begin
  if p_target = 'layer4' then
    select x.id, x.entity_type, x.entity_id, x.field_code into i from pipeline.layer4_review_items x where x.id = p_id;
    if i.id is null then return jsonb_build_object('ok', true, 'basis', 'not_found'); end if;
    if exists (select 1 from pipeline.layer4_review_items o where o.entity_type = i.entity_type and o.entity_id = i.entity_id and o.field_code = i.field_code
                and o.id <> i.id and o.status = 'pending') then
      return jsonb_build_object('ok', true, 'basis', 'newer_pending_item');
    end if;
    if (i.entity_type = 'course' and not exists (select 1 from catalogue.courses c where c.id = i.entity_id and c.lifecycle_status = 'active'))
       or (i.entity_type = 'provider' and not exists (select 1 from catalogue.providers p where p.id = i.entity_id and p.lifecycle_status = 'active')) then
      return jsonb_build_object('ok', true, 'basis', 'entity_not_active');
    end if;
    if (i.field_code = 'course_entry_first_read' and exists (select 1 from catalogue.course_entry_requirements q where q.course_id = i.entity_id and q.status = 'active'))
       or (i.field_code = 'course_description_first_read' and exists (select 1 from catalogue.courses c where c.id = i.entity_id and nullif(btrim(coalesce(c.description, '')), '') is not null))
       or (i.field_code = 'provider_description' and exists (select 1 from catalogue.providers p where p.id = i.entity_id and nullif(btrim(coalesce(p.description, '')), '') is not null)) then
      return jsonb_build_object('ok', true, 'basis', 'value_held');
    end if;
    return jsonb_build_object('ok', false, 'held', 'NO_SUCCESSOR');
  elsif p_target = 'scholarship_review' then
    select r.id, r.candidate_id, r.scholarship_id, r.url into s from pipeline.scholarship_ai_reviews r where r.id = p_id;
    if s.id is null then return jsonb_build_object('ok', true, 'basis', 'not_found'); end if;
    if exists (select 1 from pipeline.scholarship_ai_reviews o where o.id <> s.id and o.status in ('pending', 'admitted')
                and (o.candidate_id = s.candidate_id or (s.scholarship_id is not null and o.scholarship_id = s.scholarship_id) or o.url = s.url)) then
      return jsonb_build_object('ok', true, 'basis', 'other_review');
    end if;
    if exists (select 1 from scholarship.scholarships x where x.id = s.scholarship_id and x.lifecycle_status = 'active') then
      return jsonb_build_object('ok', true, 'basis', 'value_held');
    end if;
    return jsonb_build_object('ok', false, 'held', 'NO_SUCCESSOR');
  elsif p_target = 'course_entry_row' then
    select q.id, q.course_id into e from catalogue.course_entry_requirements q where q.id = p_id;
    if e.id is null then return jsonb_build_object('ok', true, 'basis', 'not_found'); end if;
    if not exists (select 1 from catalogue.courses c where c.id = e.course_id and c.lifecycle_status = 'active') then
      return jsonb_build_object('ok', true, 'basis', 'entity_not_active');
    end if;
    if exists (select 1 from catalogue.course_entry_requirements o where o.course_id = e.course_id and o.status = 'active' and o.id <> e.id) then
      return jsonb_build_object('ok', true, 'basis', 'value_held');
    end if;
    return jsonb_build_object('ok', false, 'held', 'NO_SUCCESSOR');
  end if;
  raise exception 'INVALID_INPUT: unknown target' using errcode = '22023';
end $f$;
comment on function security.supersede_successor_v1(text, uuid) is 'PIM replacement guard (s1168): is there a verified successor for this Layer 4 item, scholarship review or entry row; ok, or held NO_SUCCESSOR.';
revoke all on function security.supersede_successor_v1(text, uuid) from public, anon, authenticated;
grant execute on function security.supersede_successor_v1(text, uuid) to service_role;

create or replace function security.supersede_guard_tg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
declare v_target text := tg_argv[0]; v_code text := '*'; g jsonb;
begin
  if v_target = 'layer4' then v_code := new.field_code; end if;
  if not exists (select 1 from pipeline.supersede_guard_scope s where s.target = v_target and s.code in (v_code, '*') and s.active) then return null; end if;
  g := security.supersede_successor_v1(v_target, new.id);
  if (g->>'ok')::boolean is not true then
    raise exception 'HELD:NO_SUCCESSOR: % % (%) cannot be superseded without a verified successor', v_target, new.id, v_code using errcode = 'P0001';
  end if;
  return null;
end $f$;
comment on function security.supersede_guard_tg() is 'Deferred constraint trigger function (s1168): a supersession in pipeline.supersede_guard_scope needs a verified successor when the transaction commits.';
revoke all on function security.supersede_guard_tg() from public, anon, authenticated;

create constraint trigger layer4_supersede_successor
  after update of status on pipeline.layer4_review_items deferrable initially deferred for each row
  when (old.status = 'pending' and new.status = 'superseded') execute function security.supersede_guard_tg('layer4');
create constraint trigger scholarship_review_supersede_successor
  after update of status on pipeline.scholarship_ai_reviews deferrable initially deferred for each row
  when (old.status = 'pending' and new.status = 'superseded') execute function security.supersede_guard_tg('scholarship_review');
create constraint trigger course_entry_supersede_successor
  after update of status on catalogue.course_entry_requirements deferrable initially deferred for each row
  when (old.status = 'active' and new.status = 'superseded') execute function security.supersede_guard_tg('course_entry_row');

-- the s871 reader: hold a read with no successor instead of superseding it (it stays pending with a person)
do $r$
declare d text := pg_get_functiondef('security.aer_det_reread_v1(text,uuid[],text,text)'::regprocedure);
        a constant text := E'      else ''rereadable'' end;';
        b constant text := E'      when not coalesce((security.supersede_successor_v1(''layer4'', r.id)->>''ok'')::boolean, false) then ''held_no_successor''  -- s1168: nothing is superseded without a successor\n' || a;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the reread verdict anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); g jsonb; x uuid; v_err text;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1168_locks) then raise exception 'guard: a manual lock was removed'; end if;  -- people may add locks while this runs; none is ever removed
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron jobs above the ceiling of 140'; end if;  -- fixed: the protected ceiling; this change schedules nothing, and other lanes may switch jobs while it runs
  if (select count(*) from pg_trigger t where t.tgname in ('layer4_supersede_successor', 'scholarship_review_supersede_successor', 'course_entry_supersede_successor') and t.tgdeferrable and t.tginitdeferred) <> 3 then
    raise exception 'guard: the three deferred constraint triggers are not in place';
  end if;
  -- a pending course entry read with no other read and no rows: held; the reread action reports it and changes nothing
  select i.id into x from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id and c.lifecycle_status = 'active'
   where i.field_code = 'course_entry_first_read' and i.status = 'pending'
     and not exists (select 1 from pipeline.layer4_review_items o where o.entity_id = i.entity_id and o.field_code = i.field_code and o.id <> i.id and o.status = 'pending')
     and not exists (select 1 from catalogue.course_entry_requirements q where q.course_id = i.entity_id and q.status = 'active')
   order by i.id limit 1;  -- fixed: one sample item for the rehearsal
  if x is not null then
    g := security.supersede_successor_v1('layer4', x);
    if g->>'held' is distinct from 'NO_SUCCESSOR' then raise exception 'guard: a read with no successor was not held: %', g; end if;
    -- the trigger itself: a direct supersession is refused at commit (forced here, then undone)
    begin
      update pipeline.layer4_review_items set status = 'superseded' where id = x;
      set constraints pipeline.layer4_supersede_successor immediate;
      raise exception 's1168_not_held';
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err not like 'HELD:NO_SUCCESSOR%' then raise exception 'guard: a direct supersession was not held: %', v_err; end if;
    set constraints pipeline.layer4_supersede_successor deferred;
    if (select status from pipeline.layer4_review_items where id = x) <> 'pending' then raise exception 'guard: the sample item changed'; end if;
  end if;
  if position('held_no_successor' in pg_get_functiondef('security.aer_det_reread_v1(text,uuid[],text,text)'::regprocedure)) = 0 then raise exception 'guard: the reread is not patched'; end if;
end $c$;
