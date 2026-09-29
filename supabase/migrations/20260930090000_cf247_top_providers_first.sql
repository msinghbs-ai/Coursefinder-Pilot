-- CF-247 top universities first (Platform Admin, 30 Sep 2026 03:05 IST: "I want maximum data for top unis").
-- pipeline.provider_priority ranks Australian providers by active courses (the same ranking the Coverage screen's
-- provider tiers use: top 10, 11-40, 41-100). The Layer 3 intake/English claim now takes pages from the highest-ranked
-- providers first (previously random order). Refreshed daily. The claim is edited in place from its live definition,
-- only if unchanged since 20260930061000 (md5).
create table if not exists pipeline.provider_priority (provider_id uuid primary key, rank int not null, active_courses int not null, refreshed_at timestamptz not null default now());
alter table pipeline.provider_priority enable row level security;
revoke all on pipeline.provider_priority from public, anon, authenticated;

create or replace function security.provider_priority_refresh_v1() returns int language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','ref' as $f$
declare v_n int;
begin
  delete from pipeline.provider_priority;
  insert into pipeline.provider_priority(provider_id,rank,active_courses)
  select provider_id, row_number() over (order by count(*) desc, provider_id), count(*)
    from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id
   where co.lifecycle_status='active' and k.iso_alpha2='AU' group by co.provider_id;
  get diagnostics v_n = row_count;
  return v_n;
end $f$;
revoke all on function security.provider_priority_refresh_v1() from public, anon, authenticated;
select security.provider_priority_refresh_v1();
select cron.schedule('provider-priority-refresh','33 20 * * *','select security.provider_priority_refresh_v1()');
insert into pipeline.automation_catalogue(jobname,area,sort,label,description,control_rank,batch_editable)
values ('provider-priority-refresh','Reports',90,'Rank providers by size','Ranks providers by number of active courses so the largest (top universities) are worked first.',5,false)
on conflict (jobname) do nothing;

do $g$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure)<>'a67562b9b9e1300239ac993be3eb48e4' then
    raise exception 'cf247_top_providers_first: layer3_fact_claim_service changed since 20260930061000; review first';
  end if;
  d:=pg_get_functiondef('public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure);
  n:=replace(d,'      left join pipeline.layer3_fact_handoffs h on h.course_id=pg.course_id and h.task_class=p_task_class and h.evidence_id=pg.evidence_id',
               E'      left join pipeline.layer3_fact_handoffs h on h.course_id=pg.course_id and h.task_class=p_task_class and h.evidence_id=pg.evidence_id\n      left join pipeline.provider_priority pp on pp.provider_id=pg.provider_id');
  n:=replace(n,$s$order by md5(pg.course_id::text||to_char(now(),'YYYYMMDDHH24'))$s$,$s$order by coalesce(pp.rank,100000), md5(pg.course_id::text||to_char(now(),'YYYYMMDDHH24'))$s$);
  if position('pipeline.provider_priority pp' in n)=0 or position('order by coalesce(pp.rank,100000)' in n)=0 then raise exception 'claim edit did not apply'; end if;
  execute n;
end $g$;
