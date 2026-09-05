-- CF-CHG-20260905-206 — Evidence-bound reusable Layer 4 Scholarship Course-scope rules.
-- Rules are exact Scholarship + candidate reason + first-party Evidence + Provider decisions.
-- A changed Evidence version deliberately falls back to Layer 4 review rather than inheriting an old decision.

create table if not exists pipeline.layer4_scope_rules (
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id),
  candidate_reason text not null,
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  provider_id uuid not null references catalogue.providers(id),
  decision text not null check (decision in ('accept','reject')),
  rule_reason text not null,
  conditions jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_applied_at timestamptz,
  apply_count bigint not null default 0,
  change_control_ref text not null default 'CF-CHG-20260905-206',
  unique(scholarship_id,candidate_reason,evidence_id)
);
alter table pipeline.layer4_scope_rules enable row level security;
revoke all on pipeline.layer4_scope_rules from public,anon,authenticated;
grant all on pipeline.layer4_scope_rules to service_role;

create or replace function public.layer4_scope_rules_read(p_limit integer default 100)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth' as $$
declare v_actor uuid:=auth.uid(); v_rank int; v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v from (
   select r.id,r.scholarship_id,s.name scholarship_name,r.provider_id,p.canonical_name provider_name,r.candidate_reason,r.evidence_id,r.decision,r.rule_reason,r.conditions,r.enabled,r.created_by,r.created_at,r.updated_at,r.last_applied_at,r.apply_count,r.change_control_ref
   from pipeline.layer4_scope_rules r join scholarship.scholarships s on s.id=r.scholarship_id join catalogue.providers p on p.id=r.provider_id
   order by r.updated_at desc limit greatest(1,least(coalesce(p_limit,100),250))
 ) x;
 return v;
end$$;

create or replace function public.layer4_scope_rule_save(p_scholarship_id uuid,p_candidate_reason text,p_decision text,p_reason text,p_confirmation text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_missing int;v_mismatch int;v_evidence_versions int;v_evidence uuid;v_provider uuid;v_expected text;v_rule uuid;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if p_decision not in('accept','reject') then raise exception 'invalid rule decision'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'rule reason must be at least 8 characters'; end if;
 select count(*),count(*) filter(where cmc.evidence_id is null),count(*) filter(where c.provider_id is distinct from s.provider_id),count(distinct cmc.evidence_id),max(cmc.evidence_id),max(s.provider_id)
 into v_count,v_missing,v_mismatch,v_evidence_versions,v_evidence,v_provider
 from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id
 where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason;
 if v_count=0 then raise exception 'no pending candidates in cohort'; end if;
 v_expected:='SAVE RULE '||v_count; if trim(coalesce(p_confirmation,''))<>v_expected then raise exception 'confirmation must exactly match %',v_expected; end if;
 if v_missing>0 or v_mismatch>0 or v_evidence_versions<>1 then raise exception 'rule blocked: missing evidence %, provider mismatch %, evidence versions %',v_missing,v_mismatch,v_evidence_versions; end if;
 insert into pipeline.layer4_scope_rules(scholarship_id,candidate_reason,evidence_id,provider_id,decision,rule_reason,conditions,created_by)
 values(p_scholarship_id,p_candidate_reason,v_evidence,v_provider,p_decision,trim(p_reason),jsonb_build_object('exact_evidence_required',true,'exact_provider_required',true,'source_cohort_count',v_count),v_actor)
 on conflict(scholarship_id,candidate_reason,evidence_id) do update set provider_id=excluded.provider_id,decision=excluded.decision,rule_reason=excluded.rule_reason,conditions=excluded.conditions,enabled=true,updated_at=now(),created_by=v_actor
 returning id into v_rule;
 return jsonb_build_object('ok',true,'rule_id',v_rule,'cohort_count',v_count,'decision',p_decision,'evidence_id',v_evidence,'provider_id',v_provider,'publication_changed',false);
end$$;

create or replace function security.layer4_scope_rule_apply_one_impl(p_candidate_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','security','pipeline','scholarship','catalogue' as $$
declare v_c scholarship.course_mapping_candidates%rowtype;v_s scholarship.scholarships%rowtype;v_course catalogue.courses%rowtype;v_rule pipeline.layer4_scope_rules%rowtype;v_inserted int:=0;
begin
 select * into v_c from scholarship.course_mapping_candidates where id=p_candidate_id for update;
 if not found or v_c.status<>'needs_review' or v_c.evidence_id is null then return jsonb_build_object('applied',false,'reason','not_eligible'); end if;
 select * into v_s from scholarship.scholarships where id=v_c.scholarship_id;
 select * into v_course from catalogue.courses where id=v_c.course_id;
 if v_course.provider_id is distinct from v_s.provider_id then return jsonb_build_object('applied',false,'reason','provider_mismatch'); end if;
 select * into v_rule from pipeline.layer4_scope_rules r where r.enabled and r.scholarship_id=v_c.scholarship_id and r.candidate_reason=v_c.candidate_reason and r.evidence_id=v_c.evidence_id and r.provider_id=v_s.provider_id order by r.updated_at desc limit 1;
 if not found then return jsonb_build_object('applied',false,'reason','no_matching_rule'); end if;
 if v_rule.decision='accept' then
   insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by)
   values(v_c.scholarship_id,v_c.course_id,'mapped','layer4_reusable_rule:'||v_rule.id::text,v_c.evidence_id,v_rule.created_by)
   on conflict(scholarship_id,course_id) do nothing;
   get diagnostics v_inserted=row_count;
   update scholarship.course_mapping_candidates set status='accepted',updated_at=now() where id=v_c.id;
 else
   update scholarship.course_mapping_candidates set status='rejected',updated_at=now() where id=v_c.id;
 end if;
 update pipeline.layer4_scope_rules set apply_count=apply_count+1,last_applied_at=now(),updated_at=now() where id=v_rule.id;
 return jsonb_build_object('applied',true,'rule_id',v_rule.id,'decision',v_rule.decision,'mapping_inserted',v_inserted);
end$$;
revoke all on function security.layer4_scope_rule_apply_one_impl(uuid) from public,anon,authenticated;
grant execute on function security.layer4_scope_rule_apply_one_impl(uuid) to service_role;

create or replace function public.layer4_scope_rule_apply(p_rule_id uuid,p_limit integer default 1000)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_rule pipeline.layer4_scope_rules%rowtype;r record;v_ok int:=0;v_skip int:=0;v_res jsonb;v_op uuid;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select * into v_rule from pipeline.layer4_scope_rules where id=p_rule_id and enabled; if not found then raise exception 'enabled rule not found'; end if;
 insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count)
 select 'scholarship_course_scope','rule_'||v_rule.decision,v_actor,jsonb_build_object('rule_id',v_rule.id,'scholarship_id',v_rule.scholarship_id,'candidate_reason',v_rule.candidate_reason),v_rule.rule_reason,count(*)
 from scholarship.course_mapping_candidates where status='needs_review' and scholarship_id=v_rule.scholarship_id and candidate_reason=v_rule.candidate_reason and evidence_id=v_rule.evidence_id returning id into v_op;
 for r in select id from scholarship.course_mapping_candidates where status='needs_review' and scholarship_id=v_rule.scholarship_id and candidate_reason=v_rule.candidate_reason and evidence_id=v_rule.evidence_id order by created_at limit greatest(1,least(coalesce(p_limit,1000),5000)) loop
   v_res:=security.layer4_scope_rule_apply_one_impl(r.id);
   if coalesce((v_res->>'applied')::boolean,false) then v_ok:=v_ok+1; else v_skip:=v_skip+1; end if;
 end loop;
 update pipeline.layer4_mass_operations set affected_count=v_ok,result=jsonb_build_object('rule_id',v_rule.id,'applied',v_ok,'skipped',v_skip,'publication_changed',false,'search_refresh_required',false) where id=v_op;
 return jsonb_build_object('ok',true,'operation_id',v_op,'rule_id',v_rule.id,'applied',v_ok,'skipped',v_skip,'publication_changed',false,'search_refresh_required',false);
end$$;

create or replace function security.layer4_scope_rule_candidate_trigger()
returns trigger language plpgsql security definer
set search_path='pg_catalog','security','pipeline','scholarship','catalogue' as $$
begin
 if new.status='needs_review' and new.evidence_id is not null then perform security.layer4_scope_rule_apply_one_impl(new.id); end if;
 return new;
end$$;
drop trigger if exists trg_layer4_scope_rule_candidate on scholarship.course_mapping_candidates;
create trigger trg_layer4_scope_rule_candidate after insert or update of status,evidence_id,candidate_reason on scholarship.course_mapping_candidates for each row when (new.status='needs_review') execute function security.layer4_scope_rule_candidate_trigger();

revoke all on function public.layer4_scope_rules_read(integer) from public,anon;
revoke all on function public.layer4_scope_rule_save(uuid,text,text,text,text) from public,anon;
revoke all on function public.layer4_scope_rule_apply(uuid,integer) from public,anon;
grant execute on function public.layer4_scope_rules_read(integer) to authenticated,service_role;
grant execute on function public.layer4_scope_rule_save(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.layer4_scope_rule_apply(uuid,integer) to authenticated,service_role;
