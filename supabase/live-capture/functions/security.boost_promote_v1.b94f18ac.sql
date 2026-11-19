CREATE OR REPLACE FUNCTION security.boost_promote_v1(p_batch text, p_dry boolean DEFAULT true, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_start int := security.pipeline_num_v1('boost.quiet_window_start_hour', 1)::int;
  v_end   int := security.pipeline_num_v1('boost.quiet_window_end_hour', 5)::int;
  v_rows  int := security.pipeline_num_v1('boost.promote_rows_per_run', 1000)::int;
  v_hour  int := extract(hour from (p_now at time zone 'Australia/Melbourne'))::int;
  v_out   jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and security.current_role_rank() < 6 then
    raise exception 'Platform Admin or service role required';
  end if;
  -- on demand (setting boost.on_demand_until_epoch, Platform Admin 17 Nov 2026 22:48): until that time the quiet window does not apply
  if not p_dry and not (v_hour >= v_start and v_hour < v_end) and not security.boost_on_demand_v1(p_now) then
    raise exception 'outside the Boost quiet window (% to % Melbourne time; now %)', v_start, v_end, v_hour;
  end if;
  -- the migration squash blackout holds promotion whatever the window or an on-demand run says
  if not p_dry and extract(epoch from p_now) >= security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 0)
     and extract(epoch from p_now) < security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 0) then
    raise exception 'migration squash blackout: Boost promotion is held';
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_promote'));

  create temp table if not exists cf_boost_plan (id bigint primary key, lane text, entity_id uuid, evidence_id uuid, answer jsonb,
    state text, note text) on commit drop;
  truncate cf_boost_plan;

  insert into cf_boost_plan (id, lane, entity_id, evidence_id, answer, state, note)
  select s.id, s.lane, s.entity_id, s.evidence_id, s.answer,
    case
      when s.worker_status <> 'verified' then 'refused'
      when s.lane = 'aer_entry' then 'shadow'
      when q.model is null then 'shadow'
      when s.lane = 'study_load' and (c.study_load is not null
           or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')))
        then 'refused'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'refused'
      when s.lane = 'study_load' then 'admitted'
      else 'proposed' end,
    case
      when s.worker_status <> 'verified' then 'worker: ' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(s.verdict->'problems') x), s.worker_status)
      when s.lane = 'aer_entry' then 'AER shadow reading (admitted only by the AER rule after qualification)'
      when q.model is null then 'model not qualified for this lane: ' || coalesce(s.provider, '?') || ' / ' || coalesce(s.model, '?')
      when s.lane = 'study_load' and c.study_load is not null then 'course already holds a study load'
      when s.lane = 'study_load' and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id
           and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')) then 'a manual lock holds this course''s study load'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'page does not state a study load'
      when s.lane = 'study_load' then null
      when s.lane = 'provider_accreditations' then 'check against the body''s official list (D-3, PR C)'
      else 'for the lane''s own admission rule' end
  from pipeline.boost_inbound_staging s
  left join pipeline.boost_model_qualifications q on q.lane = s.lane and q.provider = s.provider and q.model = s.model
  left join catalogue.courses c on s.lane = 'study_load' and c.id = s.entity_id
  where s.batch_id = p_batch and s.promotion_state = 'staged'
  order by s.id
  limit v_rows;

  -- one admitted row per course and lane: the earliest of the batch; later rows for the same course are refused, so the admitted count is the
  -- number of courses filled (Platform Admin 17 Nov 2026 21:18)
  update cf_boost_plan p
     set state = 'refused', note = 'an earlier row of this batch fills this course''s study load'
   where p.state = 'admitted'
     and exists (select 1 from cf_boost_plan f where f.state = 'admitted' and f.lane = p.lane and f.entity_id = p.entity_id and f.id < p.id);

  if not p_dry then
    -- study_load: only where null, one row per course (the earliest verified row of the batch), updated_at not touched
    update catalogue.courses c
       set study_load = p.answer->>'study_load', study_load_source = 'provider_page', study_load_evidence_id = p.evidence_id
      from (select distinct on (entity_id) * from cf_boost_plan where state = 'admitted' order by entity_id, id) p
     where c.id = p.entity_id and c.study_load is null;
    update pipeline.boost_inbound_staging s set promotion_state = p.state, promotion_note = p.note, promoted_at = p_now
      from cf_boost_plan p where s.id = p.id;
  end if;

  select jsonb_build_object('batch', p_batch, 'dry', p_dry, 'melbourne_hour', v_hour, 'window', jsonb_build_array(v_start, v_end),
           'rows', coalesce(sum(n), 0), 'by_state', coalesce(jsonb_object_agg(state, n) filter (where state is not null), '{}'::jsonb))
    into v_out
    from (select state, count(*) n from cf_boost_plan group by state) x;
  return v_out;
end $function$
