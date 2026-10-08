-- CF-247 Phase 2, 8 Oct 2026: the comparison of the newest archive against the catalogue failed ("invalid input syntax for type numeric")
-- because a cast of an empty duration or fee was evaluated before its guard. Each value is now converted once, only when it is a number.
-- Replaces security.register_replay_compare_v1 (migration 2000) behind an md5 guard. The newest archive's replay is set to redo its last
-- adapter slice (the failed save rolled back) and the replay schedule picks it up again. Read only for the catalogue, as before.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.register_replay_compare_v1(uuid)'::regprocedure) is distinct from 'a92345aef63ffb480d636f586d00d58e' then
    raise exception 'register_replay_compare_v1 is not the migration 2000 definition; refusing to replace it';
  end if;
end $g$;
create or replace function security.register_replay_compare_v1(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype; v jsonb; v_latest boolean; v_l1 jsonb := null; v_cat jsonb := null; v_seen timestamptz;
begin
  select * into r from pipeline.register_replay_runs where id = p_run_id;
  if not (r.reference_done and r.adapter_done) then return null; end if;
  with a as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'adapter'),
       b as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'reference')
  select jsonb_build_object(
    'reference_records', (select count(*) from b), 'adapter_records', (select count(*) from a),
    'only_reference', (select count(*) from b where not exists (select 1 from a where a.record_key = b.record_key)),
    'only_adapter', (select count(*) from a where not exists (select 1 from b where b.record_key = a.record_key)),
    'fingerprint_differs', (select count(*) from a join b using (record_key) where a.fingerprint <> b.fingerprint),
    'fields_differ', (select count(*) from a join b using (record_key) where a.fields_hash <> b.fields_hash),
    'duplicate_keys', (select count(*) from b where dup > 0),
    'sample_differs', (select coalesce(jsonb_agg(record_key), '[]'::jsonb) from (select a.record_key from a join b using (record_key) where a.fingerprint <> b.fingerprint or a.fields_hash <> b.fields_hash limit 10) s))
  into v;
  -- newest archive: also against what Layer 1 recorded and the catalogue
  v_latest := r.keep_fields;
  if v_latest then
    select max(seen_at) into v_seen from pipeline.layer1_register_row_state where source_id = r.source_id;
    with a as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'adapter'),
         s as (select * from pipeline.layer1_register_row_state where source_id = r.source_id and seen_at >= v_seen - interval '1 hour')
    select jsonb_build_object('layer1_seen', (select count(*) from s), 'matched', (select count(*) from a join s on s.record_key = a.record_key and s.fingerprint = a.fingerprint),
                              'fingerprint_differs', (select count(*) from a join s on s.record_key = a.record_key and s.fingerprint <> a.fingerprint),
                              'only_layer1', (select count(*) from s where not exists (select 1 from a where a.record_key = s.record_key)),
                              'only_adapter', (select count(*) from a where not exists (select 1 from s where s.record_key = a.record_key)))
      into v_l1;
    with a as (select k.record_key, k.fields from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'adapter'),
         c as (select a.record_key, co.duration_value, co.duration_unit,
                      case when coalesce(a.fields->>'duration_weeks', '') ~ '^[0-9]+(\.[0-9]+)?$' then (a.fields->>'duration_weeks')::numeric end weeks,
                      case when regexp_replace(coalesce(a.fields->>'tuition_fee', ''), '[^0-9.]', '', 'g') ~ '^[0-9]+(\.[0-9]+)?$'
                           then regexp_replace(a.fields->>'tuition_fee', '[^0-9.]', '', 'g')::numeric end fee,
                      (select f.amount from catalogue.course_fees f where f.course_id = co.id and f.status = 'active' and f.fee_type = 'tuition' and f.basis = 'registered_total_course' order by f.created_at desc limit 1) tuition
                 from a join catalogue.course_registrations cr on lower(cr.scheme) = 'cricos' and upper(cr.registration_code) = upper(a.record_key)
                 join catalogue.courses co on co.id = cr.course_id)
    select jsonb_build_object('courses_matched', (select count(*) from c),
                              'duration_same', (select count(*) from c where c.duration_unit = 'weeks' and c.duration_value = c.weeks),
                              'duration_differs', (select count(*) from c where c.weeks is not null and (c.duration_unit is distinct from 'weeks' or c.duration_value is distinct from c.weeks)),
                              'tuition_same', (select count(*) from c where c.tuition = c.fee),
                              'tuition_differs', (select count(*) from c where c.fee > 0 and c.tuition is distinct from c.fee))
      into v_cat;
  end if;
  v := v || jsonb_build_object('against_layer1_recorded', v_l1, 'against_catalogue', v_cat,
    'pass', (v->>'only_reference')::int = 0 and (v->>'only_adapter')::int = 0 and (v->>'fingerprint_differs')::int = 0 and (v->>'fields_differ')::int = 0
            and (v_l1 is null or ((v_l1->>'fingerprint_differs')::int = 0 and (v_l1->>'only_layer1')::int = 0 and (v_l1->>'only_adapter')::int = 0)));
  update pipeline.register_replay_runs set result = v, done_at = now() where id = p_run_id;
  return v;
end $f$;
revoke all on function security.register_replay_compare_v1(uuid) from public, anon, authenticated;

update pipeline.register_replay_runs set error = null, done_at = null, adapter_pos = 24000
 where label = 'CRICOS 30 Sep 2026 (newest)' and error like 'adapter: svc_register_replay_save_v2: invalid input syntax for type numeric%';
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()')
 where not exists (select 1 from cron.job where jobname = 'register-replay');
