do $$
declare v_count int; v_refs int; r record;
begin
  select count(*) into v_count
  from catalogue.course_identifiers ci
  join catalogue.provider_identifiers pi on pi.provider_id=ci.provider_id and pi.scheme='ircc_dli'
  where pi.identifier='O19396019469' and ci.scheme='niagara_program_code';
  if v_count <> 133 then raise exception 'Niagara rollback guard failed: expected 133 identities, found %',v_count; end if;
  select count(*) into v_refs from scholarship.scopes s where s.course_id in (
    select ci.course_id from catalogue.course_identifiers ci join catalogue.provider_identifiers pi on pi.provider_id=ci.provider_id and pi.scheme='ircc_dli' where pi.identifier='O19396019469' and ci.scheme='niagara_program_code'
  );
  if v_refs <> 0 then raise exception 'Niagara rollback guard failed: scholarship references exist'; end if;
  for r in select ci.course_id from catalogue.course_identifiers ci join catalogue.provider_identifiers pi on pi.provider_id=ci.provider_id and pi.scheme='ircc_dli' where pi.identifier='O19396019469' and ci.scheme='niagara_program_code' loop
    delete from catalogue.courses where id=r.course_id;
    delete from pim.entity_registry where id=r.course_id and entity_type='course';
  end loop;
  update pipeline.jobs set status='blocked',completed_at=now(),error_text='Niagara programme code rejected as base identity: code 0122 reused across three distinct Broadcasting streams',result=jsonb_build_object('workerVersion','niagara-lifecycle-uat-v0.1','gate','blocked','reason','non_unique_programme_code','conflicting_code','0122','rollback_courses',133) where id='87d44f3d-3832-4b48-91e9-33e149e4e00b';
  update pipeline.sources s set metadata=metadata||jsonb_build_object('identity_candidate_rejected','niagara_program_code','identity_blocker','programme code 0122 reused across distinct Broadcasting streams','management_plane_uat_rollback',133,'apply_enabled',false,'course_subgate_status','identity_key_reassessment') - 'course_identity_scheme',updated_at=now() from integration.systems i where s.system_id=i.id and i.code='ca_on_niagara_availability';
end $$;
