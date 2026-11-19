-- CF-247 tuition period rule (Platform Admin, 29 Sep 2026 23:27 IST): "Tuition fees if not said for the course should
-- state per year. We can flag such entries and give platform operators and admin to edit those field."
--
-- Applies at admission, after the qualified Layer 3 check (the model, prompt and validators are unchanged, so their
-- qualification binding still holds). A tuition fee is admitted as per year and FLAGGED when:
--   * Layer 3 confirmed the fee (matched the Layer 2 candidate, verbatim quote on the page, confidence >= the profile's
--     review minimum, international students, AUD or NZD, within the amount ceiling), and
--   * the ONLY reason it was held is that the page does not state the period (interpret check "does not explicitly
--     support the resolved tuition basis", or admission hold "basis ... is not allowed").
-- Pages where the model decided the amount is not this course's tuition, wrong quotes, year problems and conflicts with
-- a value already held stay in Layer 4.
--
-- Flags: pipeline.data_flags (one per admitted value). Pipeline operators and admins (rank >= 4) confirm the value,
-- correct the amount or period, or remove it; curators (rank >= 3) can view. Every action is logged on the flag.

create table if not exists pipeline.data_flags (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null, entity_id uuid not null, field_code text not null, record_id uuid,
  flag_code text not null, detail jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open','confirmed','corrected','removed')),
  created_at timestamptz not null default now(), resolved_at timestamptz, resolved_by uuid, resolution jsonb,
  change_control_ref text not null default 'CF-CHG-20260915-247');
create unique index if not exists data_flags_record_flag_uq on pipeline.data_flags(record_id, flag_code) where record_id is not null;
create index if not exists data_flags_open_idx on pipeline.data_flags(flag_code, created_at) where status='open';
alter table pipeline.data_flags enable row level security;
revoke all on pipeline.data_flags from public, anon, authenticated;

create or replace function security.layer3_tuition_admit_assumed_annual_v1(p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security','search','ref' as $f$
declare r record; v_cand jsonb; v_amount numeric; v_cur text; v_year int; v_key text; v_fee uuid; v_ok int:=0; v_skip int:=0; v_ids uuid[]:='{}';
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  for r in
    select w.id wid, w.entity_id course_id, w.evidence_id, w.interpretation_id, l.id l4id, i.confidence, i.aggregator_response_model model, i.evidence_quotes q,
           coalesce(case when jsonb_typeof(l.layer3_state->'candidate_value')='object' then l.layer3_state->'candidate_value' end, i.candidate_value) cv,
           p.deterministic_validators dv, c.course_code, e.source_id, pg.url
      from pipeline.layer3_work_items w
      join pipeline.layer3_interpretations i on i.id=w.interpretation_id
      join pipeline.layer3_model_profiles p on p.id=i.profile_id
      join pipeline.layer4_review_items l on l.layer3_interpretation_id=i.id and l.status='pending' and l.field_code='provider_current_tuition_validation'
      left join catalogue.courses c on c.id=w.entity_id
      left join pipeline.evidence_artifacts e on e.id=w.evidence_id
      left join pipeline.coverage_course_pages pg on pg.course_id=w.entity_id and pg.evidence_id=w.evidence_id
     where w.task_class='provider_current_tuition_validation' and w.status='layer4_required'
       and coalesce((i.validator_result->>'candidate_bound')::boolean,false)
       and ( i.validator_result->'errors' = '["Evidence quote does not explicitly support the resolved tuition basis"]'::jsonb
          or (coalesce(jsonb_array_length(i.validator_result->'errors'),0)=0 and l.layer3_state->>'admission_hold' like 'basis % is not allowed') )
     order by w.updated_at limit greatest(1,least(coalesce(p_limit,100),500))
     for update of w skip locked
  loop
    v_cand:=r.cv; v_amount:=nullif(v_cand->>'amount','')::numeric; v_cur:=upper(nullif(btrim(coalesce(v_cand->>'currency_code',v_cand->>'currency')),''));
    v_year:=nullif(v_cand->>'fee_year','')::int;
    if v_amount is null or v_amount<=0 or v_amount>coalesce(nullif(r.dv->>'amount_max','')::numeric,250000)
       or lower(coalesce(v_cand->>'audience',''))<>'international' or v_cur not in ('AUD','NZD')
       or coalesce(r.confidence,0)<coalesce(nullif(r.dv->>'review_confidence_min','')::numeric,0.9)
       or r.course_code is null or r.source_id is null then v_skip:=v_skip+1; continue; end if;
    v_key:=lower(upper(btrim(r.course_code))||':international:'||coalesce(v_year::text,'current')||':annual');
    v_fee:=null;
    insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
    values (r.course_id,v_year,'international','provider_current_tuition',v_amount,v_cur,'annual',
            format('CF-247 Layer 3 admission; period not stated on the page, assumed per year (flagged for confirmation); interpretation %s; model %s',r.interpretation_id,coalesce(r.model,'unknown')),
            r.source_id,r.evidence_id,r.confidence,null,v_key,'active',now(),now(),now())
    on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do nothing
    returning id into v_fee;
    if v_fee is null then v_skip:=v_skip+1; continue; end if;   -- a fee is already held for this key: stays with a person
    insert into pipeline.data_flags(entity_type,entity_id,field_code,record_id,flag_code,detail)
    values ('course',r.course_id,'provider_current_tuition',v_fee,'tuition_period_assumed_annual',
            jsonb_build_object('amount',v_amount,'currency',v_cur,'fee_year',v_year,'page_url',r.url,'quotes',r.q,'model',r.model,'interpretation_id',r.interpretation_id))
    on conflict do nothing;
    update pipeline.layer4_review_items set status='superseded', decided_at=now(),
           escalation_reason='Admitted as per year under the Platform Admin rule (29 Sep 2026): the page does not state the period; flagged for an operator to confirm or edit.'
     where id=r.l4id;
    update pipeline.layer3_work_items set status='admitted', completed_at=now(), updated_at=now(), last_error='admitted: period not stated, assumed per year (flagged)' where id=r.wid;
    v_ok:=v_ok+1; v_ids:=v_ids||r.course_id;
  end loop;
  if cardinality(v_ids)>0 then perform search.refresh_course_enrichment_scoped_v1(v_ids,true); end if;
  return jsonb_build_object('admitted_assumed_annual',v_ok,'left_for_review',v_skip);
end $f$;
revoke all on function security.layer3_tuition_admit_assumed_annual_v1(int) from public, anon, authenticated;

-- operators' view and actions
create or replace function security.admin_data_flags_read_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','catalogue','security' as $f$
declare v_status text:=coalesce(nullif(p_args->>'status',''),'open'); v_limit int:=least(greatest(coalesce((p_args->>'limit')::int,100),1),500);
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object(
    'can_edit', security.current_role_rank()>=4,
    'counts', (select jsonb_object_agg(status,n) from (select status,count(*) n from pipeline.data_flags group by 1) x),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'flag',f.flag_code,'status',f.status,'created_at',f.created_at,'resolved_at',f.resolved_at,'resolution',f.resolution,
        'course_id',f.entity_id,'course',coalesce(to_jsonb(c)->>'title',to_jsonb(c)->>'name',to_jsonb(c)->>'course_name'),'course_code',c.course_code,
        'provider',coalesce(pv.display_name,pv.canonical_name),'amount',fe.amount,'currency',fe.currency_code,'basis',fe.basis,'fee_status',fe.status,
        'page_url',f.detail->>'page_url','quotes',f.detail->'quotes') order by f.created_at desc)
      from (select * from pipeline.data_flags where status=v_status or v_status='all' order by created_at desc limit v_limit) f
      left join catalogue.courses c on c.id=f.entity_id left join catalogue.providers pv on pv.id=c.provider_id
      left join catalogue.course_fees fe on fe.id=f.record_id),'[]'::jsonb));
end $f$;
revoke all on function security.admin_data_flags_read_v1(jsonb) from public, anon;
grant execute on function security.admin_data_flags_read_v1(jsonb) to authenticated;
create or replace function public.admin_data_flags_read(p_args jsonb default '{}'::jsonb) returns jsonb language sql stable security invoker as $f$ select security.admin_data_flags_read_v1(coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_data_flags_read(jsonb) from public, anon;
grant execute on function public.admin_data_flags_read(jsonb) to authenticated;

create or replace function security.admin_data_flag_resolve_v1(p_flag_id uuid, p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security','search' as $f$
declare f pipeline.data_flags%rowtype; fe catalogue.course_fees%rowtype; v_amount numeric:=nullif(p_args->>'amount','')::numeric; v_basis text:=nullif(p_args->>'basis','');
begin
  if auth.uid() is null or security.current_role_rank()<4 then raise exception 'Pipeline operator or admin role required' using errcode='42501'; end if;
  select * into f from pipeline.data_flags where id=p_flag_id for update;
  if f.id is null then raise exception 'flag not found'; end if;
  if f.status<>'open' then raise exception 'flag already resolved'; end if;
  select * into fe from catalogue.course_fees where id=f.record_id for update;
  if p_action='confirm' then
    update catalogue.course_fees set notes=coalesce(notes,'')||format(' | period confirmed per year by an operator %s',to_char(now(),'DD Mon YYYY')), last_verified_at=now(), updated_at=now() where id=fe.id;
    update pipeline.data_flags set status='confirmed', resolved_at=now(), resolved_by=auth.uid(), resolution=jsonb_build_object('action','confirm','note',p_args->>'note') where id=f.id;
  elsif p_action='correct' then
    if v_amount is null or v_amount<=0 or v_amount>1000000 then raise exception 'enter a positive amount'; end if;
    if v_basis not in ('annual','total_indicative') then raise exception 'period must be per year or whole course'; end if;
    update catalogue.course_fees set amount=v_amount, basis=v_basis, updated_at=now(), last_verified_at=now(),
           notes=coalesce(notes,'')||format(' | corrected by an operator %s: was %s %s',to_char(now(),'DD Mon YYYY'),fe.amount,fe.basis) where id=fe.id;
    update pipeline.data_flags set status='corrected', resolved_at=now(), resolved_by=auth.uid(),
           resolution=jsonb_build_object('action','correct','before',jsonb_build_object('amount',fe.amount,'basis',fe.basis),'after',jsonb_build_object('amount',v_amount,'basis',v_basis),'note',p_args->>'note') where id=f.id;
  elsif p_action='remove' then
    update catalogue.course_fees set status='inactive', updated_at=now(), notes=coalesce(notes,'')||format(' | removed by an operator %s',to_char(now(),'DD Mon YYYY')) where id=fe.id;
    update pipeline.data_flags set status='removed', resolved_at=now(), resolved_by=auth.uid(), resolution=jsonb_build_object('action','remove','note',p_args->>'note') where id=f.id;
  else raise exception 'action must be confirm, correct or remove'; end if;
  perform search.refresh_course_enrichment_scoped_v1(array[f.entity_id],true);
  return security.admin_data_flags_read_v1('{}'::jsonb);
end $f$;
revoke all on function security.admin_data_flag_resolve_v1(uuid,text,jsonb) from public, anon;
grant execute on function security.admin_data_flag_resolve_v1(uuid,text,jsonb) to authenticated;
create or replace function public.admin_data_flag_resolve(p_flag_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_data_flag_resolve_v1(p_flag_id,p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_data_flag_resolve(uuid,text,jsonb) from public, anon;
grant execute on function public.admin_data_flag_resolve(uuid,text,jsonb) to authenticated;

-- runs every 5 minutes for new tuition results; first run now
select cron.schedule('layer3-tuition-assumed-annual','4-59/5 * * * *',$$select security.layer3_tuition_admit_assumed_annual_v1(200)$$);
select security.layer3_tuition_admit_assumed_annual_v1(500);

-- daily limits: English raised to match intakes (US$10; intakes were raised on the Control tab at 23:12 IST)
update pipeline.layer3_route_budget set daily_usd_max=10 where task_class='provider_english_validation';
insert into pipeline.layer3_route_events(kind,detail) values ('admin_budget',jsonb_build_object('task','provider_english_validation','daily_usd',10,'by','Platform Admin instruction 29 Sep 2026 23:27 IST'));
