-- CF-202 — explicit trusted sibling-host support for first-party Scholarship detail acquisition.
update pipeline.sources
set metadata=metadata||jsonb_build_object('first_party_hosts',jsonb_build_array('unsw.edu.au','scholarships.unsw.edu.au'),'host_qualification_ref','CF-202'),updated_at=now()
where id='dce5d20e-5840-4ad7-b41b-c567017c1593'::uuid;

do $$
declare
  v_def text;
  v_old text := '(target_host<>'''' and catalogue_host<>'''' and (target_host=catalogue_host or target_host like ''%.''||catalogue_host or catalogue_host like ''%.''||target_host)) same_first_party_host';
  v_new text := '(target_host<>'''' and catalogue_host<>'''' and (target_host=catalogue_host or target_host like ''%.''||catalogue_host or catalogue_host like ''%.''||target_host or exists(select 1 from jsonb_array_elements_text(coalesce(metadata->''first_party_hosts'',''[]''::jsonb)) h(host) where regexp_replace(lower(h.host),''^www\\.'','''')=target_host))) same_first_party_host';
begin
  select pg_get_functiondef('public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)'::regprocedure) into v_def;
  if position(v_old in v_def)=0 then raise exception 'CF-202 expected host gate not found; refusing unsafe function rewrite'; end if;
  execute replace(v_def,v_old,v_new);
end $$;

insert into pipeline.layer2_scholarship_discovery_candidates(source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title,status,classification,classification_reason,classified_at,detail_target_url)
select 'dce5d20e-5840-4ad7-b41b-c567017c1593'::uuid,
       '78e56d38-c11d-497b-aa51-c11743dcd49c'::uuid,
       '93985055-bca2-4bcf-841d-0a9840ada711'::uuid,
       'https://www.scholarships.unsw.edu.au/international-student-award',
       'International Student Award','discovered','detail_ready',
       'CF-202 verified institutional sibling host scholarships.unsw.edu.au allowlisted on first-party UNSW catalogue source; individual international award',now(),
       'https://www.scholarships.unsw.edu.au/international-student-award'
where not exists(select 1 from pipeline.layer2_scholarship_discovery_candidates d where d.source_id='dce5d20e-5840-4ad7-b41b-c567017c1593'::uuid and rtrim(lower(d.scholarship_url),'/')='https://www.scholarships.unsw.edu.au/international-student-award');

comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is 'CF-202: first-party detail gate accepts the catalogue host, direct subdomains, or explicit trusted source metadata first_party_hosts. This supports institutional sibling hosts such as scholarships.unsw.edu.au without broad eTLD matching; all other CF-186 semantic and international gates remain.';
