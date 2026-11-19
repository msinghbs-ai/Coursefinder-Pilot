-- CF-CHG-20260902-080 / A30 Provider Contacts CSV Evidence/import service contracts

create or replace function public.svc_provider_contact_import_register(
 p_country_code text,p_original_filename text,p_mime_type text,p_byte_size bigint,p_content_hash text,p_storage_path text,p_uploaded_by uuid
) returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','pipeline'
as $$
declare v_existing uuid;v_evidence uuid;v_batch uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 if upper(coalesce(p_country_code,'')) !~ '^[A-Z]{2}$' then raise exception 'valid country code required' using errcode='22023'; end if;
 if coalesce(btrim(p_original_filename),'')='' then raise exception 'original filename required' using errcode='22023'; end if;
 if p_byte_size is null or p_byte_size<=0 then raise exception 'positive byte size required' using errcode='22023'; end if;
 if coalesce(btrim(p_content_hash),'')='' then raise exception 'content hash required' using errcode='22023'; end if;
 if coalesce(btrim(p_storage_path),'')='' then raise exception 'storage path required' using errcode='22023'; end if;
 if p_uploaded_by is null then raise exception 'uploader required' using errcode='22023'; end if;

 select id into v_existing from pipeline.provider_contact_import_batches where content_hash=p_content_hash limit 1;
 if v_existing is not null then return jsonb_build_object('duplicate',true,'batch_id',v_existing); end if;

 insert into pipeline.evidence_artifacts(evidence_type,storage_path,content_hash,mime_type,captured_at,metadata,retention_class,review_state,capture_version,evidence_group_key)
 values('provider_contact_import_file',p_storage_path,p_content_hash,p_mime_type,now(),
  jsonb_build_object('country_code',upper(p_country_code),'original_filename',p_original_filename,'byte_size',p_byte_size,'uploaded_by',p_uploaded_by,
   'manual_upload',true,'parser_contract','provider-contact-csv-v1','change_control','CF-CHG-20260902-080'),
  'source_evidence','pending_review',1,'provider_contacts:'||upper(p_country_code))
 returning id into v_evidence;

 insert into pipeline.provider_contact_import_batches(country_code,evidence_artifact_id,original_filename,mime_type,byte_size,content_hash,storage_path,uploaded_by,metadata)
 values(upper(p_country_code),v_evidence,p_original_filename,p_mime_type,p_byte_size,p_content_hash,p_storage_path,p_uploaded_by,jsonb_build_object('change_control','CF-CHG-20260902-080'))
 returning id into v_batch;

 return jsonb_build_object('duplicate',false,'batch_id',v_batch,'evidence_id',v_evidence,'status','uploaded');
end $$;
revoke all on function public.svc_provider_contact_import_register(text,text,text,bigint,text,text,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_contact_import_register(text,text,text,bigint,text,text,uuid) to service_role;

create or replace function public.svc_provider_contact_import_validate(p_batch_id uuid,p_rows jsonb,p_actor uuid)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','security','pipeline','catalogue'
as $$
declare
 v_batch pipeline.provider_contact_import_batches%rowtype;v_row jsonb;v_ord bigint;v_map jsonb;v_provider uuid;v_mapping_state text;
 v_record_type text;v_full_name text;v_job_title text;v_function text;v_region text;v_markets text;v_email text;v_phone text;v_location text;
 v_verify text;v_verified text;v_source_url text;v_source_title text;v_notes text;v_identity text;v_logical text;v_errors jsonb;v_action text;
 v_matched uuid;v_lifecycle text;v_current_source text;v_current_core text;v_row_core text;v_norm_payload jsonb;v_counts jsonb;v_domain text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='22023'; end if;
 if jsonb_typeof(p_rows)<>'array' then raise exception 'rows array required' using errcode='22023'; end if;
 select * into v_batch from pipeline.provider_contact_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Provider Contact import not found' using errcode='P0002'; end if;
 if v_batch.status in ('applied','partial') then raise exception 'applied import cannot be revalidated' using errcode='22023'; end if;

 delete from pipeline.provider_contact_import_rows where batch_id=p_batch_id;
 for v_row,v_ord in select value,ordinality from jsonb_array_elements(p_rows) with ordinality loop
  v_errors:='[]'::jsonb;v_provider:=null;v_matched:=null;v_lifecycle:=null;v_current_source:=null;v_current_core:=null;
  v_record_type:=lower(btrim(coalesce(v_row->>'contact_record_type','')));
  v_full_name:=nullif(btrim(coalesce(v_row->>'staff_name','')),'');v_job_title:=nullif(btrim(coalesce(v_row->>'job_title','')),'');
  v_function:=nullif(btrim(coalesce(v_row->>'functional_area','')),'');v_region:=nullif(btrim(coalesce(v_row->>'region_scope','')),'');
  v_markets:=nullif(btrim(coalesce(v_row->>'countries_or_markets','')),'');v_email:=nullif(lower(btrim(coalesce(v_row->>'email',''))),'');
  v_phone:=nullif(btrim(coalesce(v_row->>'phone','')),'');v_location:=nullif(btrim(coalesce(v_row->>'staff_location','')),'');
  v_verify:=nullif(lower(btrim(coalesce(v_row->>'verification_status',''))),'');v_verified:=nullif(btrim(coalesce(v_row->>'verified_on','')),'');
  v_source_url:=nullif(btrim(coalesce(v_row->>'official_source_url','')),'');v_source_title:=nullif(btrim(coalesce(v_row->>'source_page_title','')),'');
  v_notes:=nullif(btrim(coalesce(v_row->>'notes','')),'');

  if v_record_type not in ('named_staff','team_contact') then v_errors:=v_errors||jsonb_build_array('invalid_contact_record_type'); end if;
  if v_record_type='named_staff' and v_full_name is null then v_errors:=v_errors||jsonb_build_array('named_staff_requires_staff_name'); end if;
  if coalesce(v_email,v_phone,v_job_title,v_function,v_region,v_source_url) is null then v_errors:=v_errors||jsonb_build_array('meaningful_assignment_contact_or_source_required'); end if;
  if v_email is not null then
   if v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then v_errors:=v_errors||jsonb_build_array('invalid_professional_email');
   else v_domain:=split_part(v_email,'@',2);
    if v_domain in ('gmail.com','googlemail.com','yahoo.com','yahoo.com.au','hotmail.com','outlook.com','live.com','icloud.com','proton.me','protonmail.com') then
     v_errors:=v_errors||jsonb_build_array('personal_free_mail_not_permitted');
    end if;
   end if;
  end if;
  if v_source_url is not null and v_source_url !~* '^https?://' then v_errors:=v_errors||jsonb_build_array('invalid_official_source_url'); end if;
  if v_verified is not null and v_verified !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then v_errors:=v_errors||jsonb_build_array('verified_on_must_be_iso_date'); end if;

  v_map:=security.provider_contact_provider_map(v_batch.country_code,v_row->>'current_institution_name');
  v_mapping_state:=coalesce(v_map->>'state','unmatched');
  if v_mapping_state='mapped' then v_provider:=(v_map->>'provider_id')::uuid; end if;
  v_identity:=case when v_mapping_state='mapped' then security.provider_contact_identity_key(v_record_type,v_full_name,v_job_title,v_region,v_email,v_source_url) else null end;
  if v_mapping_state='mapped' and v_identity is null then v_errors:=v_errors||jsonb_build_array('insufficient_contact_identity'); end if;

  v_norm_payload:=jsonb_strip_nulls(jsonb_build_object(
   'full_name',v_full_name,'team_name',case when v_record_type='team_contact' then coalesce(v_full_name,v_function,v_job_title) else null end,
   'job_title',v_job_title,'functional_area',v_function,'region_scope',v_region,'countries_or_markets',v_markets,'work_email',v_email,'work_phone',v_phone,
   'staff_location',v_location,'verification_state',v_verify,'verified_on',v_verified,'source_class','import','source_authority','first_party',
   'source_url',v_source_url,'source_page_title',v_source_title,'source_notes',v_notes));
  v_row_core:=security.provider_contact_core_hash(v_norm_payload);
  v_logical:=case when v_provider is null or v_identity is null then null else v_provider::text||'|'||v_identity end;

  if jsonb_array_length(v_errors)>0 then v_action:='invalid';
  elsif v_mapping_state='unmatched' then v_action:='provider_unmatched';
  elsif v_mapping_state='ambiguous' then v_action:='provider_ambiguous';
  elsif exists(select 1 from pipeline.provider_contact_import_rows rr where rr.batch_id=p_batch_id and rr.logical_key=v_logical) then v_action:='duplicate';
  else
   select c.id,c.lifecycle_status,cv.source_class,security.provider_contact_core_hash(jsonb_build_object(
    'full_name',cv.full_name,'team_name',cv.team_name,'job_title',cv.job_title,'functional_area',cv.functional_area,'region_scope',cv.region_scope,
    'countries_or_markets',cv.countries_or_markets,'work_email',cv.work_email,'work_phone',cv.work_phone,'staff_location',cv.staff_location,
    'verification_state',cv.verification_state,'verified_on',case when cv.verified_on is null then null else cv.verified_on::text end,'source_url',cv.source_url))
   into v_matched,v_lifecycle,v_current_source,v_current_core
   from pipeline.provider_contacts c left join pipeline.provider_contact_versions cv on cv.id=c.current_version_id
   where c.provider_id=v_provider and c.identity_key=v_identity limit 1;

   if v_matched is null then v_action:='create';
   elsif v_current_core=v_row_core then v_action:=case when v_lifecycle='deleted' then 'restore' else 'unchanged' end;
   elsif v_current_source='manual' then v_action:='conflict';
   elsif v_lifecycle='deleted' then v_action:='restore';
   else v_action:='update';
   end if;
  end if;

  insert into pipeline.provider_contact_import_rows(batch_id,row_number,row_hash,logical_key,source_payload,normalized_payload,source_institution_name,current_institution_name,
   mapped_provider_id,mapping_state,matched_contact_id,proposed_action,validation_errors,conflict_detail)
  values(p_batch_id,v_ord::int,md5(v_row::text),v_logical,v_row,v_norm_payload,nullif(btrim(v_row->>'gug_2026_university_name'),''),
   nullif(btrim(v_row->>'current_institution_name'),''),v_provider,v_mapping_state,v_matched,v_action,v_errors,
   case when v_mapping_state='ambiguous' then jsonb_build_object('provider_mapping',v_map)
    when v_action='conflict' then jsonb_build_object('reason','manual_current_version_differs','current_contact_id',v_matched)
    when v_action='duplicate' then jsonb_build_object('reason','duplicate_logical_contact_within_batch') else '{}'::jsonb end);
 end loop;

 select jsonb_object_agg(proposed_action,n) into v_counts from (
  select proposed_action,count(*) n from pipeline.provider_contact_import_rows where batch_id=p_batch_id group by proposed_action)s;
 update pipeline.provider_contact_import_batches set status='validated',validated_at=now(),dry_run_summary=jsonb_build_object(
  'rows',jsonb_array_length(p_rows),'actions',coalesce(v_counts,'{}'::jsonb),'parser_version',parser_version,'validated_by',p_actor,'validated_at',now())
 where id=p_batch_id;
 return jsonb_build_object('ok',true,'batch_id',p_batch_id,'rows',jsonb_array_length(p_rows),'actions',coalesce(v_counts,'{}'::jsonb));
end $$;
revoke all on function public.svc_provider_contact_import_validate(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_contact_import_validate(uuid,jsonb,uuid) to service_role;

create or replace function public.svc_provider_contact_import_apply(p_batch_id uuid,p_actor uuid)
returns jsonb
language plpgsql
security invoker
set search_path to 'pg_catalog','public','security','pipeline'
as $$
declare
 v_batch pipeline.provider_contact_import_batches%rowtype;r pipeline.provider_contact_import_rows%rowtype;v_contact pipeline.provider_contacts%rowtype;
 v_contact_id uuid;v_version_id uuid;v_old_version uuid;v_identity text;v_current_core text;v_row_core text;
 v_created int:=0;v_updated int:=0;v_restored int:=0;v_unchanged int:=0;v_skipped int:=0;v_failed int:=0;v_error text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='22023'; end if;
 select * into v_batch from pipeline.provider_contact_import_batches where id=p_batch_id for update;
 if not found then raise exception 'Provider Contact import not found' using errcode='P0002'; end if;
 if v_batch.status='uploaded' then raise exception 'validate import before apply' using errcode='22023'; end if;
 if v_batch.status='applied' then return jsonb_build_object('ok',true,'batch_id',p_batch_id,'unchanged',true,'summary',v_batch.apply_summary); end if;

 for r in select * from pipeline.provider_contact_import_rows where batch_id=p_batch_id order by row_number loop
  if r.applied_action is not null then continue; end if;
  if r.proposed_action='unchanged' then update pipeline.provider_contact_import_rows set applied_action='unchanged',applied_at=now() where id=r.id;v_unchanged:=v_unchanged+1;continue;
  elsif r.proposed_action in ('duplicate','provider_unmatched','provider_ambiguous','invalid','conflict') then update pipeline.provider_contact_import_rows set applied_action='skipped',applied_at=now() where id=r.id;v_skipped:=v_skipped+1;continue;
  end if;

  begin
   v_contact_id:=r.matched_contact_id;v_identity:=split_part(coalesce(r.logical_key,''),'|',2);
   if r.proposed_action='create' then
    insert into pipeline.provider_contacts(provider_id,record_type,lifecycle_status,identity_key,created_by,updated_by,metadata)
    values(r.mapped_provider_id,coalesce(nullif(r.source_payload->>'contact_record_type',''),'named_staff'),'active',v_identity,p_actor,p_actor,
     jsonb_build_object('origin','import','import_batch_id',p_batch_id,'change_control','CF-CHG-20260902-080'))
    on conflict(provider_id,identity_key) where identity_key is not null do nothing returning id into v_contact_id;
    if v_contact_id is null then select id into v_contact_id from pipeline.provider_contacts where provider_id=r.mapped_provider_id and identity_key=v_identity limit 1;
     if v_contact_id is null then raise exception 'concurrent contact identity conflict'; end if;
    end if;
    v_version_id:=security.provider_contact_append_version(v_contact_id,p_actor,r.normalized_payload,'import','first_party','Provider Contact CSV import create',p_batch_id,r.id,v_batch.evidence_artifact_id,null);
    insert into pipeline.provider_contact_audit_events(contact_id,batch_id,event_type,actor_id,reason,after_version_id,metadata)
    values(v_contact_id,p_batch_id,'import_create',p_actor,'Provider Contact CSV import create',v_version_id,jsonb_build_object('import_row_id',r.id,'change_control','CF-CHG-20260902-080'));
    update pipeline.provider_contact_import_rows set matched_contact_id=v_contact_id,applied_action='create',applied_at=now() where id=r.id;v_created:=v_created+1;

   elsif r.proposed_action='update' then
    select * into v_contact from pipeline.provider_contacts where id=v_contact_id for update;
    if not found then raise exception 'matched contact disappeared'; end if;if v_contact.lifecycle_status='deleted' then raise exception 'contact became deleted after validation'; end if;
    v_old_version:=v_contact.current_version_id;
    v_version_id:=security.provider_contact_append_version(v_contact_id,p_actor,r.normalized_payload,'import','first_party','Provider Contact CSV import update',p_batch_id,r.id,v_batch.evidence_artifact_id,null);
    insert into pipeline.provider_contact_audit_events(contact_id,batch_id,event_type,actor_id,reason,before_version_id,after_version_id,metadata)
    values(v_contact_id,p_batch_id,'import_update',p_actor,'Provider Contact CSV import update',v_old_version,v_version_id,jsonb_build_object('import_row_id',r.id,'change_control','CF-CHG-20260902-080'));
    update pipeline.provider_contact_import_rows set applied_action='update',applied_at=now() where id=r.id;v_updated:=v_updated+1;

   elsif r.proposed_action='restore' then
    select * into v_contact from pipeline.provider_contacts where id=v_contact_id for update;if not found then raise exception 'matched contact disappeared'; end if;
    v_old_version:=v_contact.current_version_id;
    select security.provider_contact_core_hash(jsonb_build_object('full_name',cv.full_name,'team_name',cv.team_name,'job_title',cv.job_title,'functional_area',cv.functional_area,
     'region_scope',cv.region_scope,'countries_or_markets',cv.countries_or_markets,'work_email',cv.work_email,'work_phone',cv.work_phone,'staff_location',cv.staff_location,
     'verification_state',cv.verification_state,'verified_on',case when cv.verified_on is null then null else cv.verified_on::text end,'source_url',cv.source_url))
    into v_current_core from pipeline.provider_contact_versions cv where cv.id=v_contact.current_version_id;
    v_row_core:=security.provider_contact_core_hash(r.normalized_payload);
    update pipeline.provider_contacts set lifecycle_status='active',deleted_at=null,deleted_by=null,delete_reason=null,restored_at=now(),restored_by=p_actor,updated_at=now(),updated_by=p_actor where id=v_contact_id;
    if v_current_core is distinct from v_row_core then
     v_version_id:=security.provider_contact_append_version(v_contact_id,p_actor,r.normalized_payload,'import','first_party','Provider Contact CSV import restore/update',p_batch_id,r.id,v_batch.evidence_artifact_id,null);
    else v_version_id:=v_old_version;end if;
    insert into pipeline.provider_contact_audit_events(contact_id,batch_id,event_type,actor_id,reason,before_version_id,after_version_id,metadata)
    values(v_contact_id,p_batch_id,'restore',p_actor,'Provider Contact CSV import restore',v_old_version,v_version_id,jsonb_build_object('import_row_id',r.id,'change_control','CF-CHG-20260902-080'));
    update pipeline.provider_contact_import_rows set applied_action='restore',applied_at=now() where id=r.id;v_restored:=v_restored+1;
   else raise exception 'unsupported proposed action %',r.proposed_action;
   end if;
  exception when others then
   get stacked diagnostics v_error=message_text;
   update pipeline.provider_contact_import_rows set applied_action='failed',applied_at=now(),conflict_detail=coalesce(conflict_detail,'{}'::jsonb)||jsonb_build_object('apply_error',v_error) where id=r.id;
   v_failed:=v_failed+1;
  end;
 end loop;

 update pipeline.provider_contact_import_batches set status=case when v_failed>0 then 'partial' else 'applied' end,applied_at=now(),
 apply_summary=jsonb_build_object('created',v_created,'updated',v_updated,'restored',v_restored,'unchanged',v_unchanged,'skipped',v_skipped,'failed',v_failed,'applied_by',p_actor,'applied_at',now())
 where id=p_batch_id;
 insert into pipeline.provider_contact_audit_events(batch_id,event_type,actor_id,reason,metadata)
 values(p_batch_id,'import_apply',p_actor,'Provider Contact CSV batch apply',jsonb_build_object('created',v_created,'updated',v_updated,'restored',v_restored,'unchanged',v_unchanged,'skipped',v_skipped,'failed',v_failed,'change_control','CF-CHG-20260902-080'));
 return jsonb_build_object('ok',v_failed=0,'batch_id',p_batch_id,'summary',jsonb_build_object('created',v_created,'updated',v_updated,'restored',v_restored,'unchanged',v_unchanged,'skipped',v_skipped,'failed',v_failed));
end $$;
revoke all on function public.svc_provider_contact_import_apply(uuid,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_contact_import_apply(uuid,uuid) to service_role;
