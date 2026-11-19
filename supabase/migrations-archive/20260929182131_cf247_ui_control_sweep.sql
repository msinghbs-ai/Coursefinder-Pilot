-- CF-247 UI control sweep (Platform Admin, 29 Sep 2026 23:45 IST): "Make a full sweep of the feature and functionality
-- configured ... ui is in full control of managing and operating them all ... including requesting older entries between
-- layers and managing ai model etc."
--
-- 1. Automations: every scheduled job gets a plain name, area and purpose (pipeline.automation_catalogue). Admin reads
--    and controls: pause or resume (one job or a whole area), run now, change frequency (preset intervals) and batch size.
-- 2. Send back to AI: Layer 4 items raised by Layer 3 are grouped by field and reason; a group can be sent back to Layer 3
--    and retried. Failed Layer 3 work can be retried.
-- 3. Scholarship publishing: eligible list, publish a batch (Decision 139), hold, release a hold, withdraw.
-- Controls are Platform Admin (rank >= 5) unless marked 6; reads rank >= 3. Every action is logged.

create table if not exists pipeline.automation_catalogue (
  jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false);
alter table pipeline.automation_catalogue enable row level security;
revoke all on pipeline.automation_catalogue from public, anon, authenticated;
create table if not exists pipeline.admin_control_events (
  id bigint generated always as identity primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());
alter table pipeline.admin_control_events enable row level security;
revoke all on pipeline.admin_control_events from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname,area,sort,label,description,control_rank,batch_editable) values
 ('coverage-find-site','Course pages',10,'Find provider websites','Looks up the official website of providers that do not have one yet.',5,true),
 ('coverage-discover','Course pages',20,'Discover course pages','Maps each provider''s website to find its course pages.',5,true),
 ('coverage-bind','Course pages',30,'Match pages to courses','Links each discovered page to its course using the CRICOS code printed on the page.',5,true),
 ('coverage-read','Course pages',40,'Read course pages','Fetches matched course pages and saves them as evidence.',5,true),
 ('coverage-reextract','Course pages',50,'Re-read saved pages','Extracts facts again from saved pages after the reading rules improve.',5,true),
 ('coverage-tuition-handoff','Course pages',60,'Send tuition pages to Layer 3','Hands pages with an international fee to the Layer 3 tuition check.',5,true),
 ('coverage-admit','Admission',10,'Admit official page and English','Writes checked facts (official page, English scores) where the course has none; differences go to Layer 4.',5,true),
 ('layer3-fact-admit','Admission',20,'Admit AI-checked intakes and English','Writes intakes and English scores that passed the Layer 3 check.',5,false),
 ('layer3-tuition-admission','Admission',30,'Admit AI-checked tuition','Writes tuition fees that passed the Layer 3 check.',5,true),
 ('layer3-tuition-assumed-annual','Admission',40,'Admit tuition without a stated period (flagged)','Records a confirmed fee as per year when the page states no period, and flags it for an operator.',5,true),
 ('provider-basis-rule-admit','Admission',50,'Admit tuition under provider fee rules','Writes fees covered by an approved rule for how a provider states its fees.',5,false),
 ('provider-rule-admit','Admission',60,'Admit facts under provider rules','Writes facts covered by approved provider rules.',5,false),
 ('provider-fee-profiles-apply','Admission',70,'Apply provider fee profiles','Applies provider fee schedules to their courses.',5,false),
 ('layer3-intake-route','Layer 3 AI',10,'AI check: intakes','Sends waiting pages through the intake model cascade.',5,true),
 ('layer3-english-route','Layer 3 AI',20,'AI check: English','Sends waiting pages through the English model cascade.',5,true),
 ('layer3-tuition-dispatch','Layer 3 AI',30,'AI check: tuition','Sends waiting tuition items to the qualified tuition model.',5,false),
 ('layer3-tuition-enqueue','Layer 3 AI',40,'Queue tuition for the AI check','Adds Layer 2 tuition results that need a Layer 3 check.',5,true),
 ('layer3-route-guard','Layer 3 AI',50,'OpenRouter credit guard','Checks OpenRouter credit and stops the AI checks below the US$5 floor.',5,false),
 ('layer3-operations-housekeeping','Layer 3 AI',60,'Layer 3 housekeeping','Tidies expired Layer 3 work.',5,false),
 ('scholarship-discover','Scholarships',10,'Discover scholarships','Finds scholarship pages on provider websites.',5,true),
 ('scholarship-read','Scholarships',20,'Read scholarship pages','Reads each scholarship''s own page and records value, levels, field and closing date.',5,true),
 ('scholarship-publication-review','Scholarships',30,'Nightly publication review','Withdraws published scholarships that no longer qualify.',5,false),
 ('coursefinder-scholarship-etl-scheduler','Scholarships',40,'Scholarship source refresh','Refreshes scholarship sources on their schedules.',5,false),
 ('coursefinder-scholarship-ai-change-scheduler','Scholarships',50,'Scholarship change checks','Checks scholarship pages for changes every 6 hours.',5,false),
 ('coursefinder-scholarship-maintenance','Scholarships',60,'Scholarship weekly maintenance','Weekly tidy-up of scholarship records.',5,false),
 ('coursefinder-layer1-regulatory-scheduler','Layer 1 register',10,'Register refresh scheduler','Starts register refreshes (CRICOS and others) when they are due.',5,false),
 ('layer1-run-driver','Layer 1 register',20,'Register run driver','Moves running register refreshes forward.',5,true),
 ('layer1-auto-ingest','Layer 1 register',30,'Register auto-ingest','Ingests new register files when they appear.',5,false),
 ('statistics-edition-discovery','Layer 1 register',40,'New statistics editions','Looks for new QILT and PRISMS editions each month.',5,false),
 ('coursefinder-layer1-housekeeping','Layer 1 register',50,'Layer 1 housekeeping','Daily tidy-up of register runs.',5,false),
 ('coursefinder-layer2-fanout-scheduler','Layer 2 reading',10,'Layer 2 fan-out','Starts Layer 2 reading for providers that are due.',5,false),
 ('coursefinder-layer2-refresh-dispatcher','Layer 2 reading',20,'Layer 2 refresh dispatcher','Starts Layer 2 refreshes that are due.',5,false),
 ('coursefinder-layer2-wave-scheduler','Layer 2 reading',30,'Layer 2 waves','Runs Layer 2 reading waves.',5,false),
 ('coursefinder-layer2-qualification-scheduler','Layer 2 reading',40,'Source qualification','Tests new Layer 2 sources before they are used.',5,false),
 ('coursefinder-layer2-qualification-finalizer','Layer 2 reading',50,'Source qualification results','Records the results of source tests.',5,false),
 ('layer2-auto-discovery','Layer 2 reading',60,'Layer 2 auto-discovery','Looks for new course-list pages on provider sites.',5,false),
 ('layer2-onboarding-snapshot','Layer 2 reading',70,'Provider onboarding figures','Updates the provider onboarding figures.',5,false),
 ('layer2-stale-wave-closer','Layer 2 reading',80,'Close stale waves','Closes Layer 2 waves that stopped.',5,false),
 ('coursefinder-layer2-housekeeping','Layer 2 reading',90,'Layer 2 housekeeping','Daily tidy-up of Layer 2 runs.',5,false),
 ('provider-document-check-monthly','Layer 2 reading',100,'Fee documents check (monthly)','Checks provider fee documents for new versions.',5,false),
 ('provider-document-check-weekly-q4','Layer 2 reading',110,'Fee documents check (weekly, Oct to Dec)','Checks provider fee documents weekly during the fee-publishing season.',5,false),
 ('coursefinder-m2-3-refresh-intelligence-tick','Layer 2 reading',120,'Refresh policies','Runs the refresh policies set under Scheduled jobs.',5,false),
 ('search-refresh-requested','Search and API',10,'Refresh search for changed courses','Updates search and the API for courses whose facts changed.',5,false),
 ('consumer-reference-bundle-refresh','Search and API',20,'Rebuild API reference data','Rebuilds the reference data the website API serves (providers, groups, fields).',5,false),
 ('campus-regional-class-refresh','Search and API',30,'Campus regional category','Updates each campus''s metro or regional category.',5,false),
 ('course-completeness-build','Reports',10,'Completeness score','Works out how complete each course and provider is.',5,false),
 ('course-coverage-build','Reports',20,'Coverage by attribute','Works out coverage state per course attribute.',5,false),
 ('coursefinder-cf245-enrichment-coverage-snapshot','Reports',30,'Enrichment coverage snapshot','Hourly snapshot of enrichment coverage.',5,false),
 ('coursefinder-cf245-enrichment-hourly-admin-cache','Reports',40,'Admin figures cache','Refreshes figures shown on admin screens.',5,false),
 ('coursefinder-data-quality-overview-refresh','Reports',50,'Data quality overview','Daily data quality figures.',5,false),
 ('admin-summary-snapshots-refresh','Reports',60,'Admin summary figures','Refreshes dashboard summary figures.',5,false),
 ('evidence-filter-options-refresh','Reports',70,'Evidence filter options','Refreshes the filters on the Evidence screen.',5,false),
 ('evidence-link-index','Reports',80,'Index evidence links','Links saved evidence to the records it supports.',5,true),
 ('platform-health','Platform upkeep',10,'Platform health checks','Checks jobs, queues, budgets and the database, and records issues.',6,false),
 ('platform-resource-observe','Platform upkeep',20,'Resource usage reading','Records database size and connections every hour.',5,false),
 ('coursefinder-platform-capacity-observation','Platform upkeep',30,'Capacity reading','Records platform capacity daily.',5,false),
 ('cron-history-retention','Platform upkeep',40,'Trim job history','Deletes job history older than 14 days.',6,false),
 ('evidence-storage-dedupe-daily','Platform upkeep',50,'Remove duplicate evidence files','Deletes duplicate copies of saved evidence files.',6,false)
on conflict (jobname) do update set area=excluded.area, sort=excluded.sort, label=excluded.label, description=excluded.description,
  control_rank=excluded.control_rank, batch_editable=excluded.batch_editable;

-- batch size in a job command: {"limit":N} in a nonce body, or the single integer argument of a SQL call
create or replace function security.automation_batch(p_command text) returns int language sql immutable as $f$
  select coalesce((substring(p_command from '"limit"\s*:\s*(\d+)'))::int, (substring(p_command from '\(\s*(\d+)\s*\)'))::int)
$f$;

create or replace function security.admin_automations_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','cron','security' as $f$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('generated_at',now(),'rank',security.current_role_rank(),
    'jobs',(select coalesce(jsonb_agg(jsonb_build_object(
        'job',j.jobname,'area',coalesce(c.area,'Other'),'sort',coalesce(c.sort,999),'label',coalesce(c.label,j.jobname),'description',coalesce(c.description,''),
        'schedule',j.schedule,'active',j.active,'control_rank',coalesce(c.control_rank,6),
        'batch',case when coalesce(c.batch_editable,false) then security.automation_batch(j.command) end,
        'last',(select jsonb_build_object('at',d.start_time,'status',d.status,'seconds',round(extract(epoch from (d.end_time-d.start_time))::numeric,1),'message',case when d.status<>'succeeded' then left(d.return_message,200) end)
                  from cron.job_run_details d where d.jobid=j.jobid order by d.start_time desc limit 1),
        'runs_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours'),
        'failed_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours' and d.status='failed')
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e));
end $f$;
revoke all on function security.admin_automations_read_v1() from public, anon;
grant execute on function security.admin_automations_read_v1() to authenticated;
create or replace function public.admin_automations_read() returns jsonb language sql stable security invoker as $f$ select security.admin_automations_read_v1() $f$;
revoke all on function public.admin_automations_read() from public, anon;
grant execute on function public.admin_automations_read() to authenticated;

create or replace function security.admin_automation_control_v1(p_job text, p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','cron','security' set statement_timeout to '100s' as $f$
declare j cron.job%rowtype; c pipeline.automation_catalogue%rowtype; v_rank int:=security.current_role_rank(); v_n int; v_every int; v_sched text; v_cmd text; r record;
begin
  if auth.uid() is null or v_rank<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action in ('pause_area','resume_area') then
    for r in select j2.jobid, j2.jobname from cron.job j2 join pipeline.automation_catalogue c2 on c2.jobname=j2.jobname where c2.area=p_args->>'area' and c2.control_rank<=v_rank loop
      perform cron.alter_job(r.jobid, active => p_action='resume_area');
    end loop;
    insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_args->>'area',p_args,auth.uid());
    return security.admin_automations_read_v1();
  end if;
  select * into j from cron.job where jobname=p_job;
  if j.jobid is null then raise exception 'unknown automation'; end if;
  select * into c from pipeline.automation_catalogue where jobname=p_job;
  if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation needs a higher role to change' using errcode='42501'; end if;
  if p_action in ('pause','resume') then
    perform cron.alter_job(j.jobid, active => p_action='resume');
  elsif p_action='run_now' then
    execute j.command;
  elsif p_action='set_every' then
    v_every:=(p_args->>'minutes')::int;
    if v_every not in (1,2,3,5,10,15,20,30,60,120,360,1440) then raise exception 'choose 1, 2, 3, 5, 10, 15, 20, 30 or 60 minutes, or 2, 6 or 24 hours'; end if;
    v_sched:=case when v_every=1 then '* * * * *'
                  when v_every<60 then (abs(hashtext(p_job))%v_every)::text||'-59/'||v_every||' * * * *'
                  when v_every=60 then (abs(hashtext(p_job))%60)::text||' * * * *'
                  when v_every=1440 then (abs(hashtext(p_job))%60)::text||' '||(abs(hashtext(p_job||'h'))%24)::text||' * * *'
                  else (abs(hashtext(p_job))%60)::text||' */'||(v_every/60)||' * * *' end;
    perform cron.alter_job(j.jobid, schedule => v_sched);
  elsif p_action='set_batch' then
    if not coalesce(c.batch_editable,false) then raise exception 'batch size cannot be changed for this automation'; end if;
    v_n:=(p_args->>'batch')::int;
    if v_n is null or v_n<1 or v_n>500 then raise exception 'batch size must be 1-500'; end if;
    v_cmd:=case when j.command ~ '"limit"\s*:\s*\d+' then regexp_replace(j.command,'"limit"\s*:\s*\d+','"limit":'||v_n)
                else regexp_replace(j.command,'\(\s*\d+\s*\)','('||v_n||')') end;
    perform cron.alter_job(j.jobid, command => v_cmd);
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_job,p_args,auth.uid());
  return security.admin_automations_read_v1();
end $f$;
revoke all on function security.admin_automation_control_v1(text,text,jsonb) from public, anon;
grant execute on function security.admin_automation_control_v1(text,text,jsonb) to authenticated;
create or replace function public.admin_automation_control(p_job text, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_automation_control_v1(p_job,p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_automation_control(text,text,jsonb) from public, anon;
grant execute on function public.admin_automation_control(text,text,jsonb) to authenticated;

-- 2. Send back to AI
create or replace function security.admin_requeue_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','security' as $f$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'groups',(select coalesce(jsonb_agg(jsonb_build_object('field',g.field_code,'reason',g.reason,'items',g.n,'oldest',g.oldest) order by g.n desc),'[]'::jsonb)
      from (select l.field_code, l.escalation_reason reason, count(*) n, min(l.created_at) oldest from pipeline.layer4_review_items l
             where l.status='pending' and l.layer3_interpretation_id is not null and l.before_value is null
               and l.field_code in ('course_intake','course_english','provider_current_tuition_validation') group by 1,2) g),
    'stays_with_person',(select jsonb_object_agg(field_code,n) from (select field_code,count(*) n from pipeline.layer4_review_items where status='pending' and (layer3_interpretation_id is null or before_value is not null) group by 1) x),
    'layer3_failed',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from pipeline.layer3_work_items where status in ('failed','parked') group by 1) y),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='requeue' order by created_at desc limit 10) e));
end $f$;
revoke all on function security.admin_requeue_read_v1() from public, anon;
grant execute on function security.admin_requeue_read_v1() to authenticated;
create or replace function public.admin_requeue_read() returns jsonb language sql stable security invoker as $f$ select security.admin_requeue_read_v1() $f$;
revoke all on function public.admin_requeue_read() from public, anon;
grant execute on function public.admin_requeue_read() to authenticated;

create or replace function security.admin_requeue_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_field text:=p_args->>'field'; v_reason text:=p_args->>'reason'; v_task text:=p_args->>'task'; v_n int:=0; v_tuition uuid;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='send_back' then
    if v_field not in ('course_intake','course_english','provider_current_tuition_validation') then raise exception 'unsupported field'; end if;
    select id into v_tuition from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and retired_at is null
       and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc limit 1;
    with l4 as (
      update pipeline.layer4_review_items l set status='superseded', decided_at=now(),
             escalation_reason='Superseded: sent back to Layer 3 to be retried (Admin control).'
       where l.status='pending' and l.layer3_interpretation_id is not null and l.before_value is null and l.field_code=v_field
         and (v_reason is null or l.escalation_reason=v_reason)
      returning l.layer3_interpretation_id),
    fact as (
      update pipeline.layer3_work_items w set status='failed', updated_at=now(), last_error='released: sent back to Layer 3 (Admin control)'
        from l4 where v_field<>'provider_current_tuition_validation' and w.interpretation_id=l4.layer3_interpretation_id and w.status='layer4_required'
      returning w.id),
    hand as (update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=0 from fact where h.work_item_id=fact.id returning h.id),
    tui as (
      update pipeline.layer3_work_items w set status='pending', profile_id=v_tuition, reserved_at=null, reserved_by=null, interpretation_id=null, available_at=now(), updated_at=now(),
             last_error='requeued: sent back to Layer 3 (Admin control)'
        from l4 where v_field='provider_current_tuition_validation' and v_tuition is not null and w.interpretation_id=l4.layer3_interpretation_id and w.status='layer4_required'
      returning w.id)
    select (select count(*) from l4) into v_n;
  elsif p_action='retry_failed' then
    if v_task in ('provider_intake_validation','provider_english_validation') then
      update pipeline.layer3_fact_handoffs h set attempts=0 where h.task_class=v_task and h.work_item_id is null and h.attempts>0;
      get diagnostics v_n = row_count;
    elsif v_task='provider_current_tuition_validation' then
      select id into v_tuition from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and retired_at is null
         and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc limit 1;
      update pipeline.layer3_work_items set status='pending', profile_id=v_tuition, reserved_at=null, reserved_by=null, interpretation_id=null, available_at=now(), updated_at=now(),
             last_error='requeued: retry failed (Admin control)'
       where task_class=v_task and status in ('failed','parked') and v_tuition is not null;
      get diagnostics v_n = row_count;
    else raise exception 'unknown task'; end if;
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('requeue',p_action,coalesce(v_field,v_task),p_args||jsonb_build_object('moved',v_n),auth.uid());
  return security.admin_requeue_read_v1()||jsonb_build_object('moved',v_n);
end $f$;
revoke all on function security.admin_requeue_v1(text,jsonb) from public, anon;
grant execute on function security.admin_requeue_v1(text,jsonb) to authenticated;
create or replace function public.admin_requeue(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_requeue_v1(p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_requeue(text,jsonb) from public, anon;
grant execute on function public.admin_requeue(text,jsonb) to authenticated;

-- 3. Scholarship publishing (eligible = exactly what scholarship_publish_batch_v1 would publish)
create or replace function security.admin_scholarship_publishing_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','scholarship','catalogue','security' as $f$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (with p as (select * from security.scholarship_publishability_v1())
  select jsonb_build_object('can_control',security.current_role_rank()>=5,
    'counts',jsonb_build_object('published',(select count(*) from scholarship.scholarships where publication_status='published'),
       'eligible',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
         and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id)),
       'held',(select count(*) from pipeline.scholarship_publication_holds where released_at is null),
       'active',(select count(*) from scholarship.scholarships where lifecycle_status='active')),
    'not_publishable_reasons',(select jsonb_object_agg(m,n) from (select unnest(p.missing) m,count(*) n from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' group by 1) x),
    'eligible',(select coalesce(jsonb_agg(x order by x->>'provider',x->>'name'),'[]'::jsonb) from (select jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),
         'value',case s.award_value_type when 'percentage' then round(s.award_percentage)::text||'% of tuition' when 'fixed_amount' then 'A$'||to_char(s.award_amount,'FM999,999,999') end,
         'page',s.source_url,'courses',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')) x
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
        and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id) limit 300) y),
    'held',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'reason',h.reason,'at',h.held_at) order by h.held_at desc),'[]'::jsonb)
       from pipeline.scholarship_publication_holds h join scholarship.scholarships s on s.id=h.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where h.released_at is null),
    'published',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from scholarship.scholarships s left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published'),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='scholarships' order by created_at desc limit 10) e)));
end $f$;
revoke all on function security.admin_scholarship_publishing_read_v1() from public, anon;
grant execute on function security.admin_scholarship_publishing_read_v1() to authenticated;
create or replace function public.admin_scholarship_publishing_read() returns jsonb language sql stable security invoker as $f$ select security.admin_scholarship_publishing_read_v1() $f$;
revoke all on function public.admin_scholarship_publishing_read() from public, anon;
grant execute on function public.admin_scholarship_publishing_read() to authenticated;

create or replace function security.admin_scholarship_publishing_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','scholarship','security' as $f$
declare v_id uuid:=nullif(p_args->>'id','')::uuid; v_res jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='publish_batch' then
    if coalesce(btrim(p_args->>'approval'),'')='' then raise exception 'an approval note is required'; end if;
    if (security.scholarship_publish_batch_v1('dry run',false)->>'eligible')::int<>(p_args->>'expected')::int then raise exception 'the eligible list changed; refresh and check again'; end if;
    v_res:=security.scholarship_publish_batch_v1('CF-CHG-20260915-247; Decision 139; '||btrim(p_args->>'approval'),true);
  elsif p_action='hold' then
    if coalesce(btrim(p_args->>'reason'),'')='' then raise exception 'a reason is required'; end if;
    insert into pipeline.scholarship_publication_holds(scholarship_id,reason,held_by) values (v_id,btrim(p_args->>'reason'),'admin')
    on conflict (scholarship_id) do update set reason=excluded.reason, held_by='admin', held_at=now(), released_at=null, release_note=null;
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=v_id and publication_status='published';
  elsif p_action='release' then
    update pipeline.scholarship_publication_holds set released_at=now(), release_note=coalesce(p_args->>'note','released by an admin') where scholarship_id=v_id and released_at is null;
  elsif p_action='withdraw' then
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=v_id and publication_status='published';
    insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('withdraw','Admin control: '||coalesce(p_args->>'reason','withdrawn'),array[v_id]);
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('scholarships',p_action,v_id::text,p_args||coalesce(jsonb_build_object('result',v_res),'{}'::jsonb),auth.uid());
  return security.admin_scholarship_publishing_read_v1();
end $f$;
revoke all on function security.admin_scholarship_publishing_v1(text,jsonb) from public, anon;
grant execute on function security.admin_scholarship_publishing_v1(text,jsonb) to authenticated;
create or replace function public.admin_scholarship_publishing(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_scholarship_publishing_v1(p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_scholarship_publishing(text,jsonb) from public, anon;
grant execute on function public.admin_scholarship_publishing(text,jsonb) to authenticated;
