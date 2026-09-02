
-- CF-CHG-20260902-080 / A30
-- Park non-deterministic Provider Contact import reconciliation in the existing Layer 4 human-resolution queue.

alter table pipeline.provider_contact_import_rows
  add column if not exists layer4_review_item_id uuid references pipeline.layer4_review_items(id) on delete set null;
create index if not exists provider_contact_import_rows_layer4_idx
  on pipeline.provider_contact_import_rows(layer4_review_item_id) where layer4_review_item_id is not null;

alter table pipeline.provider_contact_import_batches
  drop constraint if exists provider_contact_import_batches_status_check;
alter table pipeline.provider_contact_import_batches
  add constraint provider_contact_import_batches_status_check
  check(status in ('uploaded','validated','applied','applied_with_review_pending','partial','failed'));

alter table pipeline.layer4_decisions
  drop constraint if exists layer4_decisions_action_check;
alter table pipeline.layer4_decisions
  add constraint layer4_decisions_action_check check(action in (
    'approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3',
    'merge_existing','accept_incoming','keep_existing','keep_separate','map_provider_apply','reject_import'
  ));

create index if not exists layer4_review_provider_contact_reconciliation_idx
  on pipeline.layer4_review_items(status,created_at desc)
  where entity_type='provider_contact_import_row' and field_code='provider_contact_reconciliation';

create or replace function security.layer4_entity_exists(p_entity_type text,p_entity_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog','catalogue','scholarship','pipeline'
as $$
  select case p_entity_type
    when 'course' then exists(select 1 from catalogue.courses where id=p_entity_id)
    when 'provider' then exists(select 1 from catalogue.providers where id=p_entity_id)
    when 'campus' then exists(select 1 from catalogue.campuses where id=p_entity_id)
    when 'scholarship' then exists(select 1 from scholarship.scholarships where id=p_entity_id)
    when 'provider_contact' then exists(select 1 from pipeline.provider_contact_observations where id=p_entity_id)
    when 'provider_contact_import_row' then exists(select 1 from pipeline.provider_contact_import_rows where id=p_entity_id)
    else false
  end
$$;

create or replace function public.svc_provider_contact_import_park_layer4(p_batch_id uuid,p_actor uuid)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','security','pipeline','catalogue'
as $$
declare
  v_batch pipeline.provider_contact_import_batches%rowtype;
  r pipeline.provider_contact_import_rows%rowtype;
  v_prior pipeline.provider_contact_import_rows%rowtype;
  v_review_id uuid;
  v_before jsonb;
  v_layer2 jsonb;
  v_candidates jsonb;
  v_reason text;
  v_count int:=0;
  v_actions jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if p_actor is null then raise exception 'actor required' using errcode='22023'; end if;

  select * into v_batch from pipeline.provider_contact_import_batches where id=p_batch_id for update;
  if not found then raise exception 'Provider Contact import not found' using errcode='P0002'; end if;
  if v_batch.status not in ('validated','uploaded') then
    return jsonb_build_object('ok',true,'batch_id',p_batch_id,'unchanged',true,'status',v_batch.status);
  end if;

  -- A repeated logical key is auto-skip only when it is the same source row semantics.
  -- Legacy/merged labels or differing payloads are judgement calls and move to L4.
  for r in
    select *
    from pipeline.provider_contact_import_rows
    where batch_id=p_batch_id
      and proposed_action in ('duplicate','provider_ambiguous','conflict')
    order by row_number
  loop
    if r.layer4_review_item_id is not null then continue; end if;

    v_before:=null;
    v_candidates:='[]'::jsonb;
    v_reason:=null;

    if r.proposed_action='duplicate' then
      select * into v_prior
      from pipeline.provider_contact_import_rows
      where batch_id=p_batch_id
        and logical_key=r.logical_key
        and row_number<r.row_number
      order by row_number
      limit 1;

      if not found then continue; end if;

      -- Exact repeat remains deterministic skip. Different legacy/source label or payload parks for human resolution.
      if coalesce(v_prior.source_institution_name,'')=coalesce(r.source_institution_name,'')
         and v_prior.normalized_payload=r.normalized_payload then
        continue;
      end if;

      v_before:=jsonb_build_object(
        'prior_import_row_id',v_prior.id,
        'prior_row_number',v_prior.row_number,
        'source_institution_name',v_prior.source_institution_name,
        'current_institution_name',v_prior.current_institution_name,
        'normalized_payload',v_prior.normalized_payload
      );
      v_reason:='duplicate_candidate_requires_human_resolution';

    elsif r.proposed_action='conflict' then
      select jsonb_build_object(
        'contact_id',c.id,'provider_id',c.provider_id,'record_type',c.record_type,'lifecycle_status',c.lifecycle_status,
        'version_id',v.id,'version_no',v.version_no,'full_name',v.full_name,'team_name',v.team_name,'job_title',v.job_title,
        'functional_area',v.functional_area,'region_scope',v.region_scope,'countries_or_markets',v.countries_or_markets,
        'work_email',v.work_email,'work_phone',v.work_phone,'staff_location',v.staff_location,
        'verification_state',v.verification_state,'verified_on',v.verified_on,'source_class',v.source_class,
        'source_authority',v.source_authority,'source_url',v.source_url,'source_page_title',v.source_page_title
      ) into v_before
      from pipeline.provider_contacts c
      left join pipeline.provider_contact_versions v on v.id=c.current_version_id
      where c.id=r.matched_contact_id;
      v_reason:='manual_current_version_conflicts_with_import';

    elsif r.proposed_action='provider_ambiguous' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'provider_id',p.id,'stable_key',p.stable_key,'provider_name',p.canonical_name
      ) order by p.canonical_name,p.stable_key),'[]'::jsonb)
      into v_candidates
      from catalogue.providers p
      where p.id in (
        select value::uuid
        from jsonb_array_elements_text(
          coalesce(r.conflict_detail#>'{provider_mapping,candidate_provider_ids}','[]'::jsonb)
        )
      );
      v_before:=jsonb_build_object('candidate_providers',v_candidates);
      v_reason:='provider_mapping_ambiguous';
    end if;

    v_layer2:=jsonb_strip_nulls(jsonb_build_object(
      'domain','provider_contact_import',
      'import_batch_id',p_batch_id,
      'import_row_id',r.id,
      'row_number',r.row_number,
      'classification',r.proposed_action,
      'logical_key',r.logical_key,
      'source_institution_name',r.source_institution_name,
      'current_institution_name',r.current_institution_name,
      'mapped_provider_id',r.mapped_provider_id,
      'matched_contact_id',r.matched_contact_id,
      'candidate_providers',v_candidates,
      'validation_errors',r.validation_errors,
      'conflict_detail',r.conflict_detail
    ));

    insert into pipeline.layer4_review_items(
      entity_type,entity_id,field_code,evidence_id,before_value,proposed_value,
      layer2_state,layer3_state,status,escalation_reason,change_control_ref
    ) values (
      'provider_contact_import_row',r.id,'provider_contact_reconciliation',v_batch.evidence_artifact_id,
      v_before,r.normalized_payload,v_layer2,
      jsonb_build_object('source','provider-contact-csv-v1','human_review_reason',v_reason),
      'pending',v_reason,'CF-CHG-20260902-080'
    )
    returning id into v_review_id;

    update pipeline.provider_contact_import_rows
    set layer4_review_item_id=v_review_id,
        conflict_detail=coalesce(conflict_detail,'{}'::jsonb)||
          jsonb_build_object('layer4_review_item_id',v_review_id,'layer4_reason',v_reason)
    where id=r.id;

    v_count:=v_count+1;
  end loop;

  select jsonb_object_agg(proposed_action,n) into v_actions
  from (
    select proposed_action,count(*) n
    from pipeline.provider_contact_import_rows
    where batch_id=p_batch_id
    group by proposed_action
  ) s;

  update pipeline.provider_contact_import_batches
  set status='validated',
      dry_run_summary=jsonb_build_object(
        'rows',(select count(*) from pipeline.provider_contact_import_rows where batch_id=p_batch_id),
        'actions',coalesce(v_actions,'{}'::jsonb),
        'layer4_review_pending',(select count(*) from pipeline.provider_contact_import_rows rr
          join pipeline.layer4_review_items l on l.id=rr.layer4_review_item_id
          where rr.batch_id=p_batch_id and l.status='pending'),
        'parser_version',parser_version,
        'validated_by',p_actor,
        'validated_at',coalesce(validated_at,now())
      )
  where id=p_batch_id;

  return jsonb_build_object(
    'ok',true,'batch_id',p_batch_id,'layer4_created',v_count,
    'layer4_review_pending',(select count(*) from pipeline.provider_contact_import_rows rr
      join pipeline.layer4_review_items l on l.id=rr.layer4_review_item_id
      where rr.batch_id=p_batch_id and l.status='pending'),
    'actions',coalesce(v_actions,'{}'::jsonb)
  );
end $$;

revoke all on function public.svc_provider_contact_import_park_layer4(uuid,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_contact_import_park_layer4(uuid,uuid) to service_role;

create or replace function public.svc_provider_contact_import_finalize_review_state(p_batch_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','pipeline'
as $$
declare
  v_pending int:=0;
  v_resolved int:=0;
  v_status text;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;

  select count(*) filter(where l.status='pending'),
         count(*) filter(where l.status<>'pending')
  into v_pending,v_resolved
  from pipeline.provider_contact_import_rows r
  join pipeline.layer4_review_items l on l.id=r.layer4_review_item_id
  where r.batch_id=p_batch_id;

  update pipeline.provider_contact_import_rows r
  set applied_action='parked_layer4',applied_at=coalesce(applied_at,now())
  from pipeline.layer4_review_items l
  where r.batch_id=p_batch_id
    and l.id=r.layer4_review_item_id
    and l.status='pending'
    and coalesce(r.applied_action,'') in ('','skipped');

  update pipeline.provider_contact_import_batches
  set status=case
        when status='partial' then 'partial'
        when v_pending>0 then 'applied_with_review_pending'
        else 'applied'
      end,
      apply_summary=coalesce(apply_summary,'{}'::jsonb)||
        jsonb_build_object('layer4_review_pending',v_pending,'layer4_resolved',v_resolved)
  where id=p_batch_id
  returning status into v_status;

  return jsonb_build_object('ok',true,'batch_id',p_batch_id,'status',v_status,'layer4_review_pending',v_pending,'layer4_resolved',v_resolved);
end $$;

revoke all on function public.svc_provider_contact_import_finalize_review_state(uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_contact_import_finalize_review_state(uuid) to service_role;

create or replace function security.provider_contact_reconciliation_decide_impl(
  p_review_item_id uuid,
  p_action text,
  p_reason text,
  p_target_provider_id uuid default null,
  p_target_contact_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','auth'
as $$
declare
  v_actor uuid:=auth.uid();
  v_rank int;
  v_item pipeline.layer4_review_items%rowtype;
  v_row pipeline.provider_contact_import_rows%rowtype;
  v_batch pipeline.provider_contact_import_batches%rowtype;
  v_contact pipeline.provider_contacts%rowtype;
  v_version pipeline.provider_contact_versions%rowtype;
  v_contact_id uuid;
  v_version_id uuid;
  v_decision_id uuid;
  v_identity text;
  v_core_in text;
  v_core_current text;
  v_status text;
  v_final jsonb;
  v_candidate_ok boolean:=false;
  v_remaining int:=0;
  v_record_type text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if p_action not in ('merge_existing','accept_incoming','keep_existing','keep_separate','map_provider_apply','reject_import') then
    raise exception 'invalid Provider Contact reconciliation action';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'decision reason required'; end if;

  select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
  if not found then raise exception 'review item not found'; end if;
  if v_item.status<>'pending' then raise exception 'review item already decided'; end if;
  if v_item.entity_type<>'provider_contact_import_row' or v_item.field_code<>'provider_contact_reconciliation' then
    raise exception 'review item is not a Provider Contact reconciliation';
  end if;

  select * into v_row from pipeline.provider_contact_import_rows where id=v_item.entity_id for update;
  if not found then raise exception 'Provider Contact import row not found'; end if;
  select * into v_batch from pipeline.provider_contact_import_batches where id=v_row.batch_id;

  v_record_type:=coalesce(nullif(v_row.source_payload->>'contact_record_type',''),'named_staff');

  if p_action='map_provider_apply' then
    if p_target_provider_id is null then raise exception 'target Provider required'; end if;
    select exists(
      select 1 from jsonb_array_elements(coalesce(v_item.layer2_state->'candidate_providers','[]'::jsonb)) x
      where nullif(x->>'provider_id','')::uuid=p_target_provider_id
    ) into v_candidate_ok;
    if not v_candidate_ok then raise exception 'target Provider is not an approved ambiguity candidate'; end if;

    v_identity:=security.provider_contact_identity_key(
      v_record_type,
      v_row.normalized_payload->>'full_name',
      v_row.normalized_payload->>'job_title',
      v_row.normalized_payload->>'region_scope',
      v_row.normalized_payload->>'work_email',
      v_row.normalized_payload->>'source_url'
    );
    if v_identity is null then raise exception 'resolved Provider row has insufficient contact identity'; end if;

    update pipeline.provider_contact_import_rows
    set mapped_provider_id=p_target_provider_id,mapping_state='mapped',
        logical_key=p_target_provider_id::text||'|'||v_identity
    where id=v_row.id;

    select * into v_contact
    from pipeline.provider_contacts
    where provider_id=p_target_provider_id and identity_key=v_identity
    limit 1;

    if found then
      v_contact_id:=v_contact.id;
      select * into v_version from pipeline.provider_contact_versions where id=v_contact.current_version_id;
      v_core_current:=security.provider_contact_core_hash(jsonb_build_object(
        'full_name',v_version.full_name,'team_name',v_version.team_name,'job_title',v_version.job_title,
        'functional_area',v_version.functional_area,'region_scope',v_version.region_scope,
        'countries_or_markets',v_version.countries_or_markets,'work_email',v_version.work_email,
        'work_phone',v_version.work_phone,'staff_location',v_version.staff_location,
        'verification_state',v_version.verification_state,
        'verified_on',case when v_version.verified_on is null then null else v_version.verified_on::text end,
        'source_url',v_version.source_url
      ));
      v_core_in:=security.provider_contact_core_hash(v_row.normalized_payload);
      if v_core_current is distinct from v_core_in then
        v_version_id:=security.provider_contact_append_version(
          v_contact_id,v_actor,v_row.normalized_payload,'import','first_party',
          'Layer 4 Provider mapping accepted incoming contact',v_row.batch_id,v_row.id,v_batch.evidence_artifact_id,null
        );
      else
        v_version_id:=v_contact.current_version_id;
      end if;
    else
      insert into pipeline.provider_contacts(
        provider_id,record_type,lifecycle_status,identity_key,created_by,updated_by,metadata
      ) values (
        p_target_provider_id,v_record_type,'active',v_identity,v_actor,v_actor,
        jsonb_build_object('origin','layer4_contact_reconciliation','import_batch_id',v_row.batch_id,'change_control','CF-CHG-20260902-080')
      ) returning id into v_contact_id;
      v_version_id:=security.provider_contact_append_version(
        v_contact_id,v_actor,v_row.normalized_payload,'import','first_party',
        'Layer 4 Provider mapping created contact',v_row.batch_id,v_row.id,v_batch.evidence_artifact_id,null
      );
    end if;

    update pipeline.provider_contact_import_rows
    set matched_contact_id=v_contact_id,applied_action='layer4_map_provider_apply',applied_at=now()
    where id=v_row.id;

  elsif p_action in ('merge_existing','accept_incoming') then
    if p_target_contact_id is not null then
      select * into v_contact from pipeline.provider_contacts where id=p_target_contact_id;
      if not found then raise exception 'target managed contact not found'; end if;
      if v_row.mapped_provider_id is not null and v_contact.provider_id<>v_row.mapped_provider_id then
        raise exception 'target managed contact belongs to a different Provider';
      end if;
      v_contact_id:=v_contact.id;
    else
      v_identity:=split_part(coalesce(v_row.logical_key,''),'|',2);
      if v_row.mapped_provider_id is not null and v_identity<>'' then
        select * into v_contact from pipeline.provider_contacts
        where provider_id=v_row.mapped_provider_id and identity_key=v_identity limit 1;
        if found then v_contact_id:=v_contact.id; end if;
      end if;
      if v_contact_id is null and v_row.matched_contact_id is not null then
        v_contact_id:=v_row.matched_contact_id;
        select * into v_contact from pipeline.provider_contacts where id=v_contact_id;
      end if;
    end if;

    if v_contact_id is null then
      raise exception 'apply deterministic import rows before resolving this duplicate/merge candidate';
    end if;

    if p_action='accept_incoming' then
      v_version_id:=security.provider_contact_append_version(
        v_contact_id,v_actor,v_row.normalized_payload,'import','first_party',
        'Layer 4 accepted incoming Provider Contact version',v_row.batch_id,v_row.id,v_batch.evidence_artifact_id,null
      );
      update pipeline.provider_contact_import_rows
      set matched_contact_id=v_contact_id,applied_action='layer4_accept_incoming',applied_at=now()
      where id=v_row.id;
    else
      update pipeline.provider_contact_import_rows
      set matched_contact_id=v_contact_id,applied_action='layer4_merge_existing',applied_at=now()
      where id=v_row.id;
    end if;

  elsif p_action='keep_existing' then
    update pipeline.provider_contact_import_rows
    set applied_action='layer4_keep_existing',applied_at=now()
    where id=v_row.id;

  elsif p_action='reject_import' then
    update pipeline.provider_contact_import_rows
    set applied_action='layer4_reject_import',applied_at=now()
    where id=v_row.id;

  elsif p_action='keep_separate' then
    if v_row.mapped_provider_id is null then
      raise exception 'map the Provider before keeping this contact separate';
    end if;

    insert into pipeline.provider_contacts(
      provider_id,record_type,lifecycle_status,identity_key,created_by,updated_by,metadata
    ) values (
      v_row.mapped_provider_id,v_record_type,'active','exception:'||v_row.id::text,v_actor,v_actor,
      jsonb_build_object(
        'origin','layer4_contact_reconciliation','identity_exception',true,
        'import_batch_id',v_row.batch_id,'import_row_id',v_row.id,'change_control','CF-CHG-20260902-080'
      )
    ) returning id into v_contact_id;

    insert into pipeline.provider_contact_versions(
      contact_id,version_no,full_name,team_name,job_title,functional_area,region_scope,countries_or_markets,
      work_email,work_phone,staff_location,verification_state,verified_on,source_class,source_authority,
      source_url,source_page_title,source_notes,evidence_id,import_batch_id,import_row_id,content_hash,
      effective_from,change_reason,created_at,created_by,metadata
    ) values (
      v_contact_id,1,
      nullif(v_row.normalized_payload->>'full_name',''),
      nullif(v_row.normalized_payload->>'team_name',''),
      nullif(v_row.normalized_payload->>'job_title',''),
      nullif(v_row.normalized_payload->>'functional_area',''),
      nullif(v_row.normalized_payload->>'region_scope',''),
      nullif(v_row.normalized_payload->>'countries_or_markets',''),
      nullif(v_row.normalized_payload->>'work_email',''),
      nullif(v_row.normalized_payload->>'work_phone',''),
      nullif(v_row.normalized_payload->>'staff_location',''),
      nullif(v_row.normalized_payload->>'verification_state',''),
      nullif(v_row.normalized_payload->>'verified_on','')::date,
      'import','first_party',
      nullif(v_row.normalized_payload->>'source_url',''),
      nullif(v_row.normalized_payload->>'source_page_title',''),
      nullif(v_row.normalized_payload->>'source_notes',''),
      v_batch.evidence_artifact_id,v_row.batch_id,v_row.id,
      security.provider_contact_payload_hash(v_row.normalized_payload),
      now(),'Layer 4 kept duplicate candidate as separate contact',now(),v_actor,
      jsonb_build_object('change_control','CF-CHG-20260902-080','identity_exception',true)
    ) returning id into v_version_id;

    update pipeline.provider_contacts
    set current_version_id=v_version_id,updated_at=now(),updated_by=v_actor
    where id=v_contact_id;

    update pipeline.provider_contact_import_rows
    set matched_contact_id=v_contact_id,applied_action='layer4_keep_separate',applied_at=now()
    where id=v_row.id;
  end if;

  v_status:=case when p_action='reject_import' then 'rejected' else 'approved' end;
  v_final:=jsonb_strip_nulls(jsonb_build_object(
    'reconciliation_action',p_action,
    'target_provider_id',p_target_provider_id,
    'target_contact_id',coalesce(p_target_contact_id,v_contact_id),
    'result_version_id',v_version_id
  ));

  update pipeline.layer4_review_items
  set status=v_status,decided_at=now()
  where id=v_item.id;

  insert into pipeline.layer4_decisions(
    review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,
    layer2_state,layer3_state,change_control_ref
  ) values (
    v_item.id,p_action,v_actor,trim(p_reason),v_item.before_value,v_item.proposed_value,v_final,
    v_item.evidence_id,v_item.layer2_state,v_item.layer3_state,'CF-CHG-20260902-080'
  ) returning id into v_decision_id;

  insert into pipeline.provider_contact_audit_events(
    contact_id,batch_id,event_type,actor_id,reason,after_version_id,metadata
  ) values (
    coalesce(v_contact_id,v_row.matched_contact_id),v_row.batch_id,'layer4_reconciliation',v_actor,trim(p_reason),v_version_id,
    jsonb_build_object(
      'layer4_review_item_id',v_item.id,'layer4_decision_id',v_decision_id,
      'action',p_action,'import_row_id',v_row.id,'change_control','CF-CHG-20260902-080'
    )
  );

  select count(*) into v_remaining
  from pipeline.provider_contact_import_rows r
  join pipeline.layer4_review_items l on l.id=r.layer4_review_item_id
  where r.batch_id=v_row.batch_id and l.status='pending';

  if v_batch.status='applied_with_review_pending' and v_remaining=0 then
    update pipeline.provider_contact_import_batches
    set status='applied',
        apply_summary=coalesce(apply_summary,'{}'::jsonb)||
          jsonb_build_object(
            'layer4_review_pending',0,
            'layer4_resolved',(select count(*) from pipeline.provider_contact_import_rows r
              join pipeline.layer4_review_items l on l.id=r.layer4_review_item_id
              where r.batch_id=v_row.batch_id and l.status<>'pending')
          )
    where id=v_row.batch_id;
  else
    update pipeline.provider_contact_import_batches
    set apply_summary=coalesce(apply_summary,'{}'::jsonb)||jsonb_build_object('layer4_review_pending',v_remaining)
    where id=v_row.batch_id;
  end if;

  return jsonb_build_object(
    'ok',true,'review_item_id',v_item.id,'decision_id',v_decision_id,'action',p_action,
    'status',v_status,'import_row_id',v_row.id,'contact_id',coalesce(v_contact_id,v_row.matched_contact_id),
    'version_id',v_version_id,'layer4_review_remaining',v_remaining
  );
end $$;

revoke all on function security.provider_contact_reconciliation_decide_impl(uuid,text,text,uuid,uuid) from public,anon;
grant execute on function security.provider_contact_reconciliation_decide_impl(uuid,text,text,uuid,uuid) to authenticated,service_role;

create or replace function public.provider_contact_reconciliation_decide(
  p_review_item_id uuid,p_action text,p_reason text,
  p_target_provider_id uuid default null,p_target_contact_id uuid default null
) returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','security'
as $$
  select security.provider_contact_reconciliation_decide_impl(
    p_review_item_id,p_action,p_reason,p_target_provider_id,p_target_contact_id
  )
$$;

revoke all on function public.provider_contact_reconciliation_decide(uuid,text,text,uuid,uuid) from public,anon;
grant execute on function public.provider_contact_reconciliation_decide(uuid,text,text,uuid,uuid) to authenticated,service_role;
