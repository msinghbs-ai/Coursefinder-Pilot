-- CF-CHG-20260905-205 — Layer 4 mass operations, quality cross-check and audit workflow.
-- Runtime applied to Pilot on 2026-09-05. Browser access is RPC-only; underlying tables remain private.

create table if not exists pipeline.layer4_mass_operations (
  id uuid primary key default gen_random_uuid(),
  target_kind text not null check (target_kind in ('scholarship_course_scope','review_queue')),
  action text not null,
  actor_id uuid not null,
  group_key jsonb not null default '{}'::jsonb,
  reason text not null,
  before_count integer not null default 0,
  affected_count integer not null default 0,
  result jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260905-205',
  created_at timestamptz not null default now()
);
alter table pipeline.layer4_mass_operations enable row level security;
revoke all on pipeline.layer4_mass_operations from public, anon, authenticated;
grant all on pipeline.layer4_mass_operations to service_role;

create table if not exists pipeline.layer4_quality_findings (
  id uuid primary key default gen_random_uuid(),
  fingerprint text not null unique,
  finding_type text not null check (finding_type in ('error','issue','improvement')),
  domain text not null default 'layer4',
  severity text not null default 'medium' check (severity in ('info','low','medium','high','critical')),
  title text not null,
  detail text,
  group_key jsonb not null default '{}'::jsonb,
  source text not null default 'operator' check (source in ('operator','system')),
  status text not null default 'open' check (status in ('open','resolved','dismissed')),
  actor_id uuid,
  detected_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_note text,
  change_control_ref text not null default 'CF-CHG-20260905-205'
);
alter table pipeline.layer4_quality_findings enable row level security;
revoke all on pipeline.layer4_quality_findings from public, anon, authenticated;
grant all on pipeline.layer4_quality_findings to service_role;

create or replace function public.layer4_mass_summary()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select jsonb_build_object(
  'scholarship_scope_pending',(select count(*) from scholarship.course_mapping_candidates where status='needs_review'),
  'scholarship_scope_groups',(select count(*) from (select scholarship_id,candidate_reason from scholarship.course_mapping_candidates where status='needs_review' group by 1,2) g),
  'generic_review_pending',(select count(*) from pipeline.layer4_review_items where status='pending'),
  'generic_review_groups',(select count(*) from (select entity_type,field_code,coalesce(escalation_reason,'') from pipeline.layer4_review_items where status='pending' group by 1,2,3) g),
  'missing_evidence',(select count(*) from scholarship.course_mapping_candidates where status='needs_review' and evidence_id is null),
  'provider_mismatch',(select count(*) from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id where cmc.status='needs_review' and c.provider_id is distinct from s.provider_id),
  'stale_scope_candidates',(select count(*) from scholarship.course_mapping_candidates where status='needs_review' and updated_at<now()-interval '7 days'),
  'open_findings',(select count(*) from pipeline.layer4_quality_findings where status='open'),
  'recent_mass_operations',(select count(*) from pipeline.layer4_mass_operations where created_at>now()-interval '24 hours'),
  'mass_mutation_allowed',v_rank>=4,
  'role_rank',v_rank,
  'publication_changed',false
 ) into v;
 return v;
end $$;

create or replace function public.layer4_scholarship_scope_groups(p_limit integer default 100)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 with g as (
  select cmc.scholarship_id,cmc.candidate_reason,s.name scholarship_name,s.provider_id,p.canonical_name provider_name,
   count(*) candidate_count,
   count(cmc.evidence_id) evidence_count,
   count(*) filter(where c.provider_id is distinct from s.provider_id) provider_mismatch_count,
   count(*) filter(where exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id)) already_mapped_count,
   count(*) filter(where cmc.updated_at<now()-interval '7 days') stale_count,
   count(distinct c.study_level_id) study_level_count,
   bool_or(lower(cmc.candidate_reason) ~ '(exclusion|exact|requires governed review|country|eligib)') semantic_warning,
   min(cmc.updated_at) oldest_at,max(cmc.updated_at) newest_at,
   (array_agg(c.canonical_title order by c.canonical_title))[1:5] sample_courses
  from scholarship.course_mapping_candidates cmc
  join scholarship.scholarships s on s.id=cmc.scholarship_id
  join catalogue.providers p on p.id=s.provider_id
  join catalogue.courses c on c.id=cmc.course_id
  where cmc.status='needs_review'
  group by cmc.scholarship_id,cmc.candidate_reason,s.name,s.provider_id,p.canonical_name
  order by count(*) desc,s.name
  limit greatest(1,least(coalesce(p_limit,100),250))
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'group_id',md5(scholarship_id::text||'|'||candidate_reason),
  'scholarship_id',scholarship_id,'scholarship_name',scholarship_name,'provider_id',provider_id,'provider_name',provider_name,
  'candidate_reason',candidate_reason,'candidate_count',candidate_count,'evidence_count',evidence_count,
  'provider_mismatch_count',provider_mismatch_count,'already_mapped_count',already_mapped_count,'stale_count',stale_count,
  'study_level_count',study_level_count,'semantic_warning',semantic_warning,'structural_ready',(evidence_count=candidate_count and provider_mismatch_count=0),
  'oldest_at',oldest_at,'newest_at',newest_at,'sample_courses',to_jsonb(sample_courses)
  )), '[]'::jsonb) into v from g;
 return v;
end $$;

create or replace function public.layer4_scholarship_scope_preview(p_scholarship_id uuid,p_candidate_reason text)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_evidence int;v_mismatch int;v_mapped int;v_sample jsonb;v_name text;v_provider text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 select count(*),count(cmc.evidence_id),count(*) filter(where c.provider_id is distinct from s.provider_id),count(*) filter(where exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id)),max(s.name),max(p.canonical_name)
 into v_count,v_evidence,v_mismatch,v_mapped,v_name,v_provider
 from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.providers p on p.id=s.provider_id join catalogue.courses c on c.id=cmc.course_id
 where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into v_sample from (
  select jsonb_build_object('course_id',c.id,'course_title',c.canonical_title,'course_code',c.course_code,'has_evidence',cmc.evidence_id is not null,'already_mapped',exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id),'provider_match',c.provider_id=s.provider_id) x
  from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id
  where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason order by c.canonical_title limit 20
 ) q;
 return jsonb_build_object('ok',true,'scholarship_id',p_scholarship_id,'scholarship_name',v_name,'provider_name',v_provider,'candidate_reason',p_candidate_reason,'candidate_count',v_count,'evidence_count',v_evidence,'missing_evidence_count',v_count-v_evidence,'provider_mismatch_count',v_mismatch,'already_mapped_count',v_mapped,'semantic_warning',lower(coalesce(p_candidate_reason,'')) ~ '(exclusion|exact|requires governed review|country|eligib)','structural_ready',(v_count>0 and v_evidence=v_count and v_mismatch=0),'accept_confirmation','ACCEPT '||v_count,'reject_confirmation','REJECT '||v_count,'sample',v_sample,'publication_changed',false);
end $$;

create or replace function public.layer4_scholarship_scope_bulk_decide(p_scholarship_id uuid,p_candidate_reason text,p_action text,p_reason text,p_confirmation text)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_missing int;v_mismatch int;v_inserted int:=0;v_affected int:=0;v_op uuid;v_expected text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<4 then raise exception 'pipeline_operator role required for mass decisions' using errcode='42501';end if;
 if p_action not in('accept','reject') then raise exception 'invalid mass action';end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
 select count(*),count(*) filter(where cmc.evidence_id is null),count(*) filter(where c.provider_id is distinct from s.provider_id)
 into v_count,v_missing,v_mismatch
 from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id
 where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason;
 if v_count=0 then raise exception 'no pending candidates in this cohort';end if;
 v_expected:=upper(p_action)||' '||v_count;if trim(coalesce(p_confirmation,''))<>v_expected then raise exception 'confirmation must exactly match %',v_expected;end if;
 if p_action='accept' and (v_missing>0 or v_mismatch>0) then raise exception 'structural blockers prevent bulk accept: missing evidence %, provider mismatch %',v_missing,v_mismatch;end if;
 insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count,result)
 values('scholarship_course_scope',p_action,v_actor,jsonb_build_object('scholarship_id',p_scholarship_id,'candidate_reason',p_candidate_reason),trim(p_reason),v_count,jsonb_build_object('confirmation',p_confirmation,'semantic_warning',lower(coalesce(p_candidate_reason,'')) ~ '(exclusion|exact|requires governed review|country|eligib)')) returning id into v_op;
 if p_action='accept' then
  insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by)
  select cmc.scholarship_id,cmc.course_id,'mapped','layer4_mass_review:'||v_op::text,cmc.evidence_id,v_actor
  from scholarship.course_mapping_candidates cmc where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason
  on conflict(scholarship_id,course_id) do nothing;
  get diagnostics v_inserted=row_count;
  update scholarship.course_mapping_candidates set status='accepted',updated_at=now() where status='needs_review' and scholarship_id=p_scholarship_id and candidate_reason=p_candidate_reason;
  get diagnostics v_affected=row_count;
 else
  update scholarship.course_mapping_candidates set status='rejected',updated_at=now() where status='needs_review' and scholarship_id=p_scholarship_id and candidate_reason=p_candidate_reason;
  get diagnostics v_affected=row_count;
 end if;
 update pipeline.layer4_mass_operations set affected_count=v_affected,result=result||jsonb_build_object('mappings_inserted',v_inserted,'missing_evidence',v_missing,'provider_mismatch',v_mismatch,'publication_changed',false) where id=v_op;
 return jsonb_build_object('ok',true,'operation_id',v_op,'action',p_action,'affected_count',v_affected,'mappings_inserted',v_inserted,'publication_changed',false,'search_refresh_required',false);
end $$;

create or replace function public.layer4_review_groups(p_limit integer default 100)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 with g as(select entity_type,field_code,coalesce(escalation_reason,'') escalation_reason,count(*) item_count,min(created_at) oldest_at,max(created_at) newest_at,count(*) filter(where evidence_id is null) missing_evidence_count from pipeline.layer4_review_items where status='pending' group by 1,2,3 order by count(*) desc limit greatest(1,least(coalesce(p_limit,100),250)))
 select coalesce(jsonb_agg(jsonb_build_object('group_id',md5(entity_type||'|'||field_code||'|'||escalation_reason),'entity_type',entity_type,'field_code',field_code,'escalation_reason',escalation_reason,'item_count',item_count,'missing_evidence_count',missing_evidence_count,'oldest_at',oldest_at,'newest_at',newest_at)),'[]'::jsonb) into v from g;return v;
end $$;

create or replace function public.layer4_review_bulk_decide(p_entity_type text,p_field_code text,p_escalation_reason text,p_action text,p_reason text,p_confirmation text,p_limit integer default 500)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_expected text;v_ok int:=0;v_failed int:=0;v_op uuid;r record;v_err jsonb:='[]'::jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<4 then raise exception 'pipeline_operator role required for mass decisions' using errcode='42501';end if;
 if p_action not in('reject','request_more_evidence','return_layer2','return_layer3') then raise exception 'unsupported generic mass action';end if;if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
 select count(*) into v_count from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'');if v_count=0 then raise exception 'no pending review items in group';end if;
 v_count:=least(v_count,greatest(1,least(coalesce(p_limit,500),500)));v_expected:=upper(p_action)||' '||v_count;if trim(coalesce(p_confirmation,''))<>v_expected then raise exception 'confirmation must exactly match %',v_expected;end if;
 insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count) values('review_queue',p_action,v_actor,jsonb_build_object('entity_type',p_entity_type,'field_code',p_field_code,'escalation_reason',coalesce(p_escalation_reason,'')),trim(p_reason),v_count) returning id into v_op;
 for r in select id from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'') order by created_at limit v_count loop
  begin perform security.layer4_review_decide_impl(r.id,p_action,trim(p_reason),null);v_ok:=v_ok+1;exception when others then v_failed:=v_failed+1;if jsonb_array_length(v_err)<10 then v_err:=v_err||jsonb_build_array(jsonb_build_object('review_item_id',r.id,'error',sqlerrm));end if;end;
 end loop;
 update pipeline.layer4_mass_operations set affected_count=v_ok,result=jsonb_build_object('failed_count',v_failed,'sample_errors',v_err,'publication_changed',false) where id=v_op;
 return jsonb_build_object('ok',v_failed=0,'operation_id',v_op,'action',p_action,'processed',v_ok,'failed',v_failed,'remaining_in_group',greatest((select count(*) from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'')),0),'sample_errors',v_err,'publication_changed',false);
end $$;

create or replace function public.layer4_quality_diagnostics()
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 with d as(
  select 'error' type,'high' severity,'Scholarship scope candidates missing Evidence' title,'Cannot safely bulk-accept without retained Evidence.' detail,(select count(*) from scholarship.course_mapping_candidates where status='needs_review' and evidence_id is null)::int count,'Return affected cohorts to evidence acquisition before acceptance.' recommendation
  union all select 'error','critical','Scholarship/Course provider mismatch','Candidate Course belongs to a different Provider from its Scholarship.',(select count(*) from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id where cmc.status='needs_review' and c.provider_id is distinct from s.provider_id)::int,'Do not accept; inspect identity/source mapping.'
  union all select 'issue','medium','Stale Scholarship scope review','Scope candidates have remained unresolved for more than seven days.',(select count(*) from scholarship.course_mapping_candidates where status='needs_review' and updated_at<now()-interval '7 days')::int,'Resolve by cohort, reject, or refine the eligibility rule.'
  union all select 'issue','medium','Stale generic Layer 4 review','Generic Layer 4 items have remained pending for more than seven days.',(select count(*) from pipeline.layer4_review_items where status='pending' and created_at<now()-interval '7 days')::int,'Use grouped return/reject actions instead of one-by-one review.'
  union all select 'issue','medium','Accepted candidates without canonical mapping','Accepted Scholarship scope candidates must have a matching Course mapping.',(select count(*) from scholarship.course_mapping_candidates cmc where cmc.status='accepted' and not exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id))::int,'Reconcile candidate/mapping integrity before publication.'
  union all select 'improvement','info','Large review cohorts','Large cohorts are better handled as governed rules than individual rows.',(select count(*) from (select scholarship_id,candidate_reason from scholarship.course_mapping_candidates where status='needs_review' group by 1,2 having count(*)>=100) x)::int,'Cross-check one sample set and source rule, then take one audited cohort decision.'
 ) select coalesce(jsonb_agg(jsonb_build_object('type',type,'severity',severity,'title',title,'detail',detail,'count',count,'recommendation',recommendation,'active',count>0)),'[]'::jsonb) into v from d;
 return v;
end $$;

create or replace function public.layer4_quality_finding_upsert(p_finding_type text,p_domain text,p_title text,p_detail text,p_severity text,p_group_key jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_id uuid;v_fp text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 if p_finding_type not in('error','issue','improvement') then raise exception 'invalid finding type';end if;if p_severity not in('info','low','medium','high','critical') then raise exception 'invalid severity';end if;if length(trim(coalesce(p_title,'')))<4 then raise exception 'title required';end if;
 v_fp:=md5(lower(trim(p_finding_type))||'|'||lower(trim(coalesce(p_domain,'layer4')))||'|'||lower(trim(p_title))||'|'||coalesce(p_group_key,'{}'::jsonb)::text);
 insert into pipeline.layer4_quality_findings(fingerprint,finding_type,domain,severity,title,detail,group_key,source,status,actor_id) values(v_fp,p_finding_type,coalesce(nullif(trim(p_domain),''),'layer4'),p_severity,trim(p_title),nullif(trim(coalesce(p_detail,'')),''),coalesce(p_group_key,'{}'::jsonb),'operator','open',v_actor)
 on conflict(fingerprint) do update set severity=excluded.severity,detail=excluded.detail,last_seen_at=now(),status='open',resolved_at=null,resolution_note=null,actor_id=v_actor returning id into v_id;
 return jsonb_build_object('ok',true,'finding_id',v_id,'fingerprint',v_fp);
end $$;

create or replace function public.layer4_quality_finding_resolve(p_finding_id uuid,p_status text,p_note text)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;if p_status not in('resolved','dismissed','open') then raise exception 'invalid status';end if;
 update pipeline.layer4_quality_findings set status=p_status,resolved_at=case when p_status='open' then null else now() end,resolution_note=case when p_status='open' then null else nullif(trim(coalesce(p_note,'')),'') end,actor_id=v_actor,last_seen_at=now() where id=p_finding_id;if not found then raise exception 'finding not found';end if;return jsonb_build_object('ok',true,'finding_id',p_finding_id,'status',p_status);
end $$;

create or replace function public.layer4_quality_findings_read(p_status text default 'open',p_limit integer default 100)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v from (select id,finding_type,domain,severity,title,detail,group_key,source,status,actor_id,detected_at,last_seen_at,resolved_at,resolution_note from pipeline.layer4_quality_findings where p_status is null or status=p_status order by case severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 when 'low' then 4 else 5 end,last_seen_at desc limit greatest(1,least(coalesce(p_limit,100),250))) x;return v;
end $$;

create or replace function public.layer4_mass_operations_history(p_limit integer default 50)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v from (select id,target_kind,action,actor_id,group_key,reason,before_count,affected_count,result,change_control_ref,created_at from pipeline.layer4_mass_operations order by created_at desc limit greatest(1,least(coalesce(p_limit,50),100))) x;return v;
end $$;

revoke all on function public.layer4_mass_summary() from public,anon;
revoke all on function public.layer4_scholarship_scope_groups(integer) from public,anon;
revoke all on function public.layer4_scholarship_scope_preview(uuid,text) from public,anon;
revoke all on function public.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) from public,anon;
revoke all on function public.layer4_review_groups(integer) from public,anon;
revoke all on function public.layer4_review_bulk_decide(text,text,text,text,text,text,integer) from public,anon;
revoke all on function public.layer4_quality_diagnostics() from public,anon;
revoke all on function public.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) from public,anon;
revoke all on function public.layer4_quality_finding_resolve(uuid,text,text) from public,anon;
revoke all on function public.layer4_quality_findings_read(text,integer) from public,anon;
revoke all on function public.layer4_mass_operations_history(integer) from public,anon;
grant execute on function public.layer4_mass_summary() to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_groups(integer) to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_preview(uuid,text) to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.layer4_review_groups(integer) to authenticated,service_role;
grant execute on function public.layer4_review_bulk_decide(text,text,text,text,text,text,integer) to authenticated,service_role;
grant execute on function public.layer4_quality_diagnostics() to authenticated,service_role;
grant execute on function public.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) to authenticated,service_role;
grant execute on function public.layer4_quality_finding_resolve(uuid,text,text) to authenticated,service_role;
grant execute on function public.layer4_quality_findings_read(text,integer) to authenticated,service_role;
grant execute on function public.layer4_mass_operations_history(integer) to authenticated,service_role;
