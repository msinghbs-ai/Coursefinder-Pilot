-- Layer 4: decisions for official course links and scholarship scope.
-- Official course link: Approve / Edit and approve records the link in catalogue.course_links
-- (link_type official_course), where automated admission writes it, then refreshes the course
-- in search. Checks: https only; search engines, aggregators and social sites refused.
-- Scholarship scope: decided course by course (scholarship.course_mapping_candidates) in the
-- scholarship batch tools. Approving the scholarship-level item ("mark as done") is only
-- possible once no candidate courses still need review.
-- Desk read: can_approve per category, scope_pending count, provider_domain hint for links.

create or replace function security.layer4_course_link_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','catalogue','pipeline','search'
as $function$
declare v_item pipeline.layer4_review_items%rowtype; v_url text; v_host text; v_link uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  if v_item.entity_type<>'course' then raise exception 'course links apply to courses only'; end if;
  v_url := btrim(coalesce(case jsonb_typeof(p_value) when 'string' then p_value#>>'{}' when 'object' then p_value->>'url' end,
                          case jsonb_typeof(v_item.proposed_value) when 'string' then v_item.proposed_value#>>'{}' when 'object' then v_item.proposed_value->>'url' end,''));
  if v_url='' then raise exception 'enter the official course page link, then approve'; end if;
  if v_url !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$' then raise exception 'the link must be a full https:// web address'; end if;
  v_host := lower(substring(v_url from '^https://([^/]+)'));
  if v_host ~ '(^|\.)(google|bing|duckduckgo|yahoo|facebook|linkedin|instagram|youtube|hotcourses|studyinternational|idp|studyaustralia|courseseeker|myuni)\.' then
    raise exception 'use the provider''s own course page, not a search, social or course-listing site (%)', v_host;
  end if;
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',false,'active',null,v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true);
end $function$;

create or replace function security.layer4_scholarship_scope_close_impl(p_item_id uuid)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','scholarship'
as $function$
declare v_item pipeline.layer4_review_items%rowtype; v_open int;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  select count(*) into v_open from scholarship.course_mapping_candidates where scholarship_id=v_item.entity_id and status='needs_review';
  if v_open>0 then raise exception '% course(s) still need a scope decision. Decide them in Batches, then mark this as done.', v_open; end if;
  return jsonb_build_object('scope_closed',true);
end $function$;

revoke all on function security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text) from public, anon, authenticated;
revoke all on function security.layer4_scholarship_scope_close_impl(uuid) from public, anon, authenticated;
grant execute on function security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text) to service_role;
grant execute on function security.layer4_scholarship_scope_close_impl(uuid) to service_role;

-- Route decisions (guarded substitution of the live decision function).
do $mig$
declare d text;
  a text := E'      v_scalar:=security.layer4_tuition_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));\n      v_scalar_id:=null;\n    else\n';
  b text := E'      v_scalar:=security.layer4_tuition_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));\n      v_scalar_id:=null;\n    elsif v_item.field_code=''official_course_url'' then\n      v_scalar:=security.layer4_course_link_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));\n      v_scalar_id:=null;\n    elsif v_item.entity_type=''scholarship'' and v_item.field_code=''scope_resolution'' then\n      v_scalar:=security.layer4_scholarship_scope_close_impl(v_item.id);\n      v_scalar_id:=null;\n    else\n';
begin
  d := pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure);
  if strpos(d,'layer4_course_link_apply_impl')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'decide anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;

-- Desk read: per-category can_approve, scope_pending, provider_domain (guarded substitution).
do $mig$
declare d text;
  a text := $q$'can_approve', b.entity_type='course' and (b.field_code<>'provider_current_tuition_validation' or (jsonb_typeof(b.proposed_value)='object' and lower(coalesce(b.proposed_value->>'basis','')) in ('annual','indicative_annual','per_year_explicit'))),$q$;
  b text := $q$'can_approve', case
      when b.field_code='provider_current_tuition_validation' then jsonb_typeof(b.proposed_value)='object' and lower(coalesce(b.proposed_value->>'basis','')) in ('annual','indicative_annual','per_year_explicit')
      when b.field_code='official_course_url' then jsonb_typeof(b.proposed_value)='string' or (jsonb_typeof(b.proposed_value)='object' and b.proposed_value ? 'url')
      when b.entity_type='scholarship' and b.field_code='scope_resolution' then not exists(select 1 from scholarship.course_mapping_candidates m where m.scholarship_id=b.entity_id and m.status='needs_review')
      else b.entity_type='course' end,
    'scope_pending', case when b.entity_type='scholarship' then (select count(*) from scholarship.course_mapping_candidates m where m.scholarship_id=b.entity_id and m.status='needs_review') end,
    'provider_domain', case when b.field_code='official_course_url' then (select lower(substring(l.url from '^https?://([^/]+)')) from catalogue.course_links l join catalogue.courses c2 on c2.id=l.course_id where c2.provider_id=b.provider_id and l.link_type='official_course' and l.status='active' group by 1 order by count(*) desc limit 1) end,$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'scope_pending')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'desk anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;
