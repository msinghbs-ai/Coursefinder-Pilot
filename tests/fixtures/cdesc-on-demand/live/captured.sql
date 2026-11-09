-- LIVE function bodies the Fill / Recheck description change reads, captured byte for byte from production (pg_proc.prosrc, read 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp).
-- Each body is checked against its recorded md5 at the end; a transcription error fails the run.
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable security definer set search_path to '' as $body$
  -- 31 Oct 2026 (StudySearch D5a): a course whose page binding is a mismatch is held until a page is bound again (0 of 11,332 such items filled in 4 days)
  select exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.status = 'mismatch' and coalesce(g.basis, '') <> 'manual')
      or exists (select 1 from pipeline.enrichment_flags f
                  where f.entity = 'course' and f.entity_key = p_course::text and f.field in (p_field, '')
                    and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                         or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                             and f.flagged_at > now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int)
                             and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.evidence_id is not null
                                               and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at))))
$body$;

create or replace function security.enrich_item_in_flight_v1(p_provider uuid, p_course uuid, p_field text) returns boolean language sql stable security definer set search_path to '' as $body$
  -- the standing gap queue's rule (security.field_gap_queue_tick_v1): the latest item of this course (or university) and field is being
  -- worked on, or waits for a person
  select coalesce(case when p_course is not null
    then (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id = p_course and e.field = p_field and e.provider_id = p_provider order by e.id desc limit 1)
    else (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id is null and e.provider_id = p_provider and e.field = p_field order by e.id desc limit 1) end, false)
$body$;

create or replace function security.enrich_course_text_gaps_v1(p_fields text[]) returns table(provider_id uuid, course_id uuid, field text, pri integer) language plpgsql security definer set search_path to '' as $body$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int; v_gmax int := security.pipeline_num_v1('enrich.course_description_pending_global_max', 0)::int;
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    -- back-pressure (CF-247 C-DESC 8 Nov 2026): no new description readings while v_gmax descriptions already wait for a person (0 = off)
    continue when f = 'description' and v_gmax > 0
      and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending') >= v_gmax;
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc)
      select m.pid, m.cid, f, case when l.state is null then 1
                                    when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end
        from miss m left join last l on l.cid = m.cid
       where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => v_days)
              or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
         and not security.enrich_item_held_v1(m.cid, f)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
       order by 4, m.cid
       limit v_room;
  end loop;
end $body$;

create or replace function security.flag_raise_v1(p_entity text, p_key text, p_provider_id uuid, p_field text, p_code text, p_reason text, p_kind text, p_actor text, p_actor_kind text, p_evidence jsonb, p_input_mark text, p_next_check timestamptz)
returns jsonb language plpgsql security definer set search_path to '' as $body$
declare f pipeline.enrichment_flags; v_state text; v_action text; v_tries int; v_soft int := security.pipeline_num_v1('flag.soft_tries', 2)::int;
begin
  perform set_config('cf.flag_fn', '1', true);
  select * into f from pipeline.enrichment_flags x where x.entity = p_entity and x.entity_key = p_key and x.field = coalesce(p_field, '') and x.reason_code = p_code for update;
  if not found then
    v_state := case when p_kind = 'hard' or v_soft <= 1 then 'raised' else 'counting' end;
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, tries, evidence, next_check_at, input_mark, raised_by_kind, cleared_at)
    values (p_entity, p_key, p_provider_id, coalesce(p_field, ''), p_code, p_reason, p_actor, p_kind, v_state, 1, coalesce(p_evidence, '{}'::jsonb), p_next_check, p_input_mark, p_actor_kind,
            case when v_state = 'raised' then null else now() end)
    returning * into f;
    v_action := case v_state when 'raised' then 'raised' else 'counted' end;
  elsif f.state = 'raised' then
    update pipeline.enrichment_flags set reason = p_reason, evidence = coalesce(p_evidence, evidence), input_mark = coalesce(p_input_mark, input_mark),
           next_check_at = coalesce(p_next_check, next_check_at) where id = f.id;
    v_state := 'raised';  -- already held: evidence refreshed, no new history line
  else
    v_tries := case when f.state = 'counting' then f.tries + 1 else 1 end;
    v_state := case when p_kind = 'hard' or v_tries >= v_soft then 'raised' else 'counting' end;
    update pipeline.enrichment_flags set reason = p_reason, source = p_actor, kind = p_kind, state = v_state, tries = v_tries, evidence = coalesce(p_evidence, '{}'::jsonb),
           next_check_at = p_next_check, input_mark = coalesce(p_input_mark, input_mark), raised_by_kind = p_actor_kind, flagged_at = now(),
           cleared_at = case when v_state = 'raised' then null else coalesce(cleared_at, now()) end,
           released_at = case when v_state = 'raised' then null else released_at end
     where id = f.id;
    v_action := case when v_state = 'counting' then 'counted' when f.state = 'released' then 're_raised' else 'raised' end;
  end if;
  if v_action is not null then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, v_action, p_actor, p_actor_kind, p_reason, coalesce(p_evidence, '{}'::jsonb));
  end if;
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', f.id, 'state', v_state);
end $body$;

create or replace function security.flag_release_v1(p_id bigint, p_actor text, p_actor_kind text, p_reason text, p_evidence jsonb, p_keep_checks boolean)
returns jsonb language plpgsql security definer set search_path to '' as $body$
declare f pipeline.enrichment_flags; v_q text;
begin
  perform set_config('cf.flag_fn', '1', true);
  update pipeline.enrichment_flags set state = 'released', cleared_at = now(), released_at = now(), released_by = p_actor, release_kind = p_actor_kind, release_reason = p_reason,
         tries = 0, checks = case when p_keep_checks then checks + 1 else 0 end, next_check_at = null
   where id = p_id and state <> 'released' returning * into f;
  if not found then perform set_config('cf.flag_fn', '', true); return null; end if;
  insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, 'released', p_actor, p_actor_kind, p_reason, coalesce(p_evidence, '{}'::jsonb));
  v_q := security.flag_requeue_v1(f.id);
  if v_q is not null then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (f.id, 'requeued', p_actor, p_actor_kind, 'Back in the queue: ' || v_q, '{}'::jsonb);
  end if;
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('id', f.id, 'state', 'released', 'requeued', v_q);
end $body$;

do $chk$
declare r record; n int := 0;
begin
  for r in select * from (values ('security.enrich_item_held_v1(uuid,text)', '78c7102adf2804fb536eb2e263264edc'), ('security.enrich_item_in_flight_v1(uuid,uuid,text)', 'c5f63a7e6abb3c8513146e6db1f8b5c2'),
                                 ('security.enrich_course_text_gaps_v1(text[])', '5352bc7ea7bbf3ef00bd616f2897f2f4'), ('security.flag_raise_v1(text,text,uuid,text,text,text,text,text,text,jsonb,text,timestamptz)', '35abc5181879d361dcca1ca1baf420a3'),
                                 ('security.flag_release_v1(bigint,text,text,text,jsonb,boolean)', 'ab3ed1a03e4d9516c8edb1a40330d4e0')) v(sig, want) loop
    if md5((select p.prosrc from pg_proc p where p.oid = r.sig::regprocedure)) <> r.want then raise exception 'captured % differs from the live body md5 %', r.sig, r.want; end if;
    n := n + 1;
  end loop;
  raise notice 'captured live bodies: % checked against the production md5', n;
end $chk$;
