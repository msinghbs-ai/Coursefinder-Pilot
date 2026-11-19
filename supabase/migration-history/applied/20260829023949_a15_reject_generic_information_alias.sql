-- A15: retain but reject generic information aliases that do not specifically identify
-- an international recruitment/admissions/student contact function.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_generic_information_alias',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where source_class='first_party'
  and is_current=true
  and lower(split_part(coalesce(work_email,''),'@',1)) in ('info','information','enquiries','enquiry')
  and nullif(trim(coalesce(job_title,'')),'') is null
  and nullif(trim(coalesce(territory_text,'')),'') is null;
