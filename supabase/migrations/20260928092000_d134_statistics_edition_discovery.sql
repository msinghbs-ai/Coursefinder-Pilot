-- CF-247 / R6 (Decision 134): statistics datasets as families with editions found from a stable publisher page.
-- Each family member (a QILT survey, the PRISMS SA4 publication) has one stable listing page and a rule that
-- finds its files. A monthly discovery job reads the pages, records any file it has not seen as an edition
-- candidate, checks it with a dry run (count and hash, nothing written), and shows it on the family card. A
-- Pipeline Operator applies a checked candidate; the apply creates the new edition, which becomes current while
-- earlier editions are kept. Nothing is applied automatically. A new family or country adds rows, not columns.

create table if not exists pipeline.statistics_edition_rules(
  member_code text primary key,
  family_code text not null,
  family_label text not null,
  member_label text not null,
  worker text not null,
  worker_member text,
  listing_url text not null,
  file_pattern text not null,
  year_group int,
  authority_domain text not null,
  current_source_id uuid references pipeline.sources(id),
  active boolean not null default true,
  created_at timestamptz not null default now());
alter table pipeline.statistics_edition_rules enable row level security;
revoke all on pipeline.statistics_edition_rules from public, anon, authenticated;

create table if not exists pipeline.statistics_edition_candidates(
  id bigint generated always as identity primary key,
  member_code text not null references pipeline.statistics_edition_rules(member_code),
  file_url text not null,
  edition_year int,
  status text not null default 'found' check (status in ('found','checked','check_failed','applied','known','dismissed')),
  check_result jsonb,
  found_at timestamptz not null default now(),
  checked_at timestamptz,
  applied_at timestamptz,
  applied_by uuid,
  applied_source_id uuid,
  unique (member_code, file_url));
alter table pipeline.statistics_edition_candidates enable row level security;
revoke all on pipeline.statistics_edition_candidates from public, anon, authenticated;

insert into pipeline.statistics_edition_rules(member_code,family_code,family_label,member_label,worker,worker_member,listing_url,file_pattern,year_group,authority_domain,current_source_id) values
 ('qilt_gos','au_qilt_gos','QILT (Quality Indicators for Learning and Teaching)','Graduate Outcomes Survey','qilt-au-etl','gos',
  'https://www.qilt.edu.au/surveys/graduate-outcomes-survey-(gos)','/gos_(\d{4})_national_report_tables\.zip',1,'qilt.edu.au','d817ea87-a96c-4e06-adbf-f6c957344d87'),
 ('qilt_gosl','au_qilt_gosl','QILT (Quality Indicators for Learning and Teaching)','Graduate Outcomes Survey – Longitudinal','qilt-au-etl','gosl',
  'https://www.qilt.edu.au/surveys/graduate-outcomes-survey---longitudinal-(gos-l)','/gosl_(\d{4})_national_report_tables\.zip',1,'qilt.edu.au','84bd8ff0-4932-49bd-bb99-f09cf118a0c6'),
 ('qilt_ess','au_qilt_ess','QILT (Quality Indicators for Learning and Teaching)','Employer Satisfaction Survey','qilt-au-etl','ess',
  'https://www.qilt.edu.au/surveys/employer-satisfaction-survey-(ess)','/ess_(\d{4})_national_report_tables\.zip',1,'qilt.edu.au','a37a569c-105e-4d9e-b802-44b68ff7ecc6'),
 ('qilt_ses','au_qilt_ses','QILT (Quality Indicators for Learning and Teaching)','Student Experience Survey','qilt-au-etl','ses',
  'https://www.qilt.edu.au/surveys/student-experience-survey-(ses)','/ses_(\d{4})_national_report_tables\.zip',1,'qilt.edu.au','925f5942-7c5e-4408-8307-1c2a4d4117d4'),
 ('prisms_sa4','au_prisms_student_flow','PRISMS International Student Flow','Enrolments and commencements by ABS SA4','prisms-au-etl',null,
  'https://www.education.gov.au/international-education-data-and-research/international-student-enrolment-and-commencement-data-abs-sa4',
  '/download/\d+/international-student-enrolment-and-commencement-data[^"''\s<>]*',null,'education.gov.au','37f1776c-77a3-4083-8ec7-7d76ad7a9ad8')
on conflict (member_code) do nothing;

-- Files already ingested are known, so discovery only reports genuinely new ones.
insert into pipeline.statistics_edition_candidates(member_code,file_url,edition_year,status,checked_at)
select r.member_code, s.url, (s.metadata->>'edition_year')::int, 'known', now()
  from pipeline.statistics_edition_rules r join pipeline.sources s on s.id=r.current_source_id
on conflict (member_code,file_url) do nothing;

-- Each QILT survey keeps its own edition family (pipeline.layer1_dataset_families); the Layer 1 screen shows the
-- four survey families together as one QILT card with a tab per survey.

create or replace function public.svc_statistics_edition_rules()
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('member_code',r.member_code,'worker',r.worker,'worker_member',r.worker_member,'listing_url',r.listing_url,
         'file_pattern',r.file_pattern,'year_group',r.year_group,'authority_domain',r.authority_domain,
         'known',(select coalesce(jsonb_agg(c.file_url),'[]'::jsonb) from pipeline.statistics_edition_candidates c where c.member_code=r.member_code))),'[]'::jsonb)
    from pipeline.statistics_edition_rules r where r.active
$f$;
create or replace function public.svc_statistics_candidate_record(p_member_code text, p_file_url text, p_edition_year int, p_status text, p_check jsonb)
returns bigint language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_id bigint;
begin
  if p_status not in ('found','checked','check_failed') then raise exception 'invalid status'; end if;
  insert into pipeline.statistics_edition_candidates(member_code,file_url,edition_year,status,check_result,checked_at)
  values(p_member_code,p_file_url,p_edition_year,p_status,p_check,case when p_status<>'found' then now() end)
  on conflict (member_code,file_url) do update set status=excluded.status, check_result=excluded.check_result, checked_at=excluded.checked_at,
     edition_year=coalesce(excluded.edition_year,pipeline.statistics_edition_candidates.edition_year)
   where pipeline.statistics_edition_candidates.status in ('found','checked','check_failed')
  returning id into v_id;
  return v_id;
end $f$;
create or replace function public.svc_statistics_candidate_context(p_candidate_id bigint)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select jsonb_build_object('id',c.id,'member_code',c.member_code,'file_url',c.file_url,'edition_year',c.edition_year,'status',c.status,
         'worker',r.worker,'worker_member',r.worker_member,'authority_domain',r.authority_domain)
    from pipeline.statistics_edition_candidates c join pipeline.statistics_edition_rules r on r.member_code=c.member_code where c.id=p_candidate_id
$f$;
create or replace function public.svc_statistics_candidate_applied(p_candidate_id bigint, p_actor uuid, p_result jsonb)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_member text; v_source uuid;
begin
  select member_code into v_member from pipeline.statistics_edition_candidates where id=p_candidate_id;
  v_source:=nullif(p_result->>'sourceId','')::uuid;
  update pipeline.statistics_edition_candidates set status='applied', applied_at=now(), applied_by=p_actor, applied_source_id=v_source,
         check_result=coalesce(check_result,'{}'::jsonb)||jsonb_build_object('apply',p_result) where id=p_candidate_id;
  if v_source is not null then update pipeline.statistics_edition_rules set current_source_id=v_source where member_code=v_member; end if;
end $f$;
revoke all on function public.svc_statistics_edition_rules() from public, anon, authenticated;
revoke all on function public.svc_statistics_candidate_record(text,text,int,text,jsonb) from public, anon, authenticated;
revoke all on function public.svc_statistics_candidate_context(bigint) from public, anon, authenticated;
revoke all on function public.svc_statistics_candidate_applied(bigint,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.svc_statistics_edition_rules() to service_role;
grant execute on function public.svc_statistics_candidate_record(text,text,int,text,jsonb) to service_role;
grant execute on function public.svc_statistics_candidate_context(bigint) to service_role;
grant execute on function public.svc_statistics_candidate_applied(bigint,uuid,jsonb) to service_role;

-- Card read: candidates per family (Pipeline Operator).
create or replace function public.layer1_statistics_candidates_read()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline' as $f$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<4 then raise exception 'Pipeline Operator role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'family_code',r.family_code,'member_code',r.member_code,'member_label',r.member_label,
          'file_url',c.file_url,'edition_year',c.edition_year,'status',c.status,'found_at',c.found_at,'checked_at',c.checked_at,
          'rows',coalesce(c.check_result->>'candidateObservations',c.check_result->>'observations'),'error',c.check_result->>'error',
          'period',coalesce(c.check_result->>'collectionVersion',c.check_result->>'period')) order by c.found_at desc)
     from pipeline.statistics_edition_candidates c join pipeline.statistics_edition_rules r on r.member_code=c.member_code
    where c.status in ('found','checked','check_failed')),'[]'::jsonb);
end $f$;
revoke all on function public.layer1_statistics_candidates_read() from public, anon;
grant execute on function public.layer1_statistics_candidates_read() to authenticated;
