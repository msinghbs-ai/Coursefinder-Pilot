CREATE OR REPLACE FUNCTION public.scholarship_course_fill_service(p_actor uuid, p_action text, p_country_code text DEFAULT NULL::text, p_provider_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline'
AS $function$
declare v_rank integer:=0; v_courses integer:=0; v_scholarships integer:=0; v_pairs integer:=0; v_candidates integer:=0; v_written integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if p_action not in('preview','fill','queue_review') then raise exception 'unsupported action' using errcode='22023'; end if;

 with scoped_courses as(
   select c.id,c.provider_id
   from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (p_provider_id is null or c.provider_id=p_provider_id)
     and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
 ), deterministic as(
   select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
     case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
   from scholarship.scholarships s
   join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
   join scoped_courses c on (sc.scope_type='course' and sc.course_id=c.id) or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
   where not exists(
     select 1 from scholarship.scopes ex
     where ex.scholarship_id=s.id and ex.include_exclude='exclude'
       and ((ex.scope_type='course' and ex.course_id=c.id) or (ex.scope_type='provider' and ex.provider_id=c.provider_id))
   )
 ), provider_candidates as(
   select distinct s.id scholarship_id,c.id course_id,coalesce(s.evidence_id,null) evidence_id
   from scholarship.scholarships s join scoped_courses c on c.provider_id=s.provider_id
   where s.provider_id is not null
     and not exists(select 1 from deterministic d where d.scholarship_id=s.id and d.course_id=c.id)
     and not exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.include_exclude='include' and sc.scope_type in('course','provider'))
 )
 select (select count(*) from scoped_courses),
        (select count(distinct s.id) from scholarship.scholarships s where
          exists(select 1 from scoped_courses c where c.provider_id=s.provider_id) or exists(select 1 from deterministic d where d.scholarship_id=s.id)),
        (select count(*) from deterministic),
        (select count(*) from provider_candidates)
 into v_courses,v_scholarships,v_pairs,v_candidates;

 if p_action='preview' then
   return jsonb_build_object('ok',true,'courses',v_courses,'scholarships',v_scholarships,'deterministic_mappings',v_pairs,
     'provider_level_candidates',v_candidates,'existing_mappings',(select count(*) from scholarship.course_mappings m where exists(
       select 1 from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
       where c.id=m.course_id and (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
     )),
     'rule','Only explicit course/provider include scopes are materialised. Provider ownership without explicit scope remains review-only.');
 end if;

 if p_action='fill' then
   with scoped_courses as(
     select c.id,c.provider_id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
     where (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
   ), deterministic as(
     select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
       case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
     from scholarship.scholarships s join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
     join scoped_courses c on (sc.scope_type='course' and sc.course_id=c.id) or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
     where not exists(select 1 from scholarship.scopes ex where ex.scholarship_id=s.id and ex.include_exclude='exclude'
       and ((ex.scope_type='course' and ex.course_id=c.id) or (ex.scope_type='provider' and ex.provider_id=c.provider_id)))
   ), ins as(
     insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,source_scope_id,evidence_id,mapped_by)
     select scholarship_id,course_id,'mapped',basis,scope_id,evidence_id,p_actor from deterministic
     on conflict(scholarship_id,course_id) do update
       set mapping_state='mapped',mapping_basis=excluded.mapping_basis,source_scope_id=excluded.source_scope_id,
           evidence_id=excluded.evidence_id,mapped_by=excluded.mapped_by,updated_at=now()
     returning 1
   ) select count(*) into v_written from ins;
   return jsonb_build_object('ok',true,'status','filled','written_or_refreshed',v_written,'deterministic_mappings',v_pairs,
     'canonical_course_fields_changed',false,'publication_changed',false);
 end if;

 with scoped_courses as(
   select c.id,c.provider_id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (p_provider_id is null or c.provider_id=p_provider_id) and (p_country_code is null or upper(co.iso_alpha2::text)=upper(p_country_code))
 ), candidates as(
   select distinct s.id scholarship_id,c.id course_id,s.evidence_id
   from scholarship.scholarships s join scoped_courses c on c.provider_id=s.provider_id
   where s.provider_id is not null
     and not exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.include_exclude='include' and sc.scope_type in('course','provider'))
 )
 insert into scholarship.course_mapping_candidates(scholarship_id,course_id,candidate_reason,evidence_id)
 select scholarship_id,course_id,'provider_owned_but_no_explicit_course_or_provider_scope',evidence_id from candidates
 on conflict(scholarship_id,course_id) do update set updated_at=now(),status='needs_review';
 get diagnostics v_written=row_count;
 return jsonb_build_object('ok',true,'status','review_candidates_queued','written_or_refreshed',v_written,
   'publication_changed',false,'eligibility_manufactured',false);
end $function$
