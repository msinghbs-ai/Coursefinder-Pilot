-- CF-247 priority queue controlled from the admin screens (Platform Admin, 30 Sep 2026 03:22 IST: "moving uni or
-- courses queues up or down. Adding new country/State or university for priority queue").
-- 1. pipeline.priority_pins: an ordered list of pinned universities, states, countries and single courses.
-- 2. Provider order (pipeline.provider_priority) = pinned first, in pin order (a provider takes the best of its own,
--    its state's and its country's pin), then Australian providers by number of active courses, then the rest.
--    pipeline.course_priority holds pinned single courses. Recomputed on every change and daily.
-- 3. The Layer 3 intake/English claim and the page reader take pinned courses first, then providers in that order;
--    the page reader uses its Firecrawl fallback for pinned courses and the top 100 providers. Both edited in place
--    from their live definitions, only if unchanged (md5).
-- 4. Admin: public.admin_priority_read(), public.admin_priority_search(kind, q) (rank >= 3) and
--    public.admin_priority_control(action, args) (Platform Admin): add, remove, move up or down. Every change logged.
create table if not exists pipeline.priority_pins (
  id bigint generated always as identity primary key, kind text not null check (kind in ('provider','state','country','course')),
  target_id uuid not null, sort int not null, note text, created_by uuid, created_at timestamptz not null default now(), unique (kind,target_id));
alter table pipeline.priority_pins enable row level security;
revoke all on pipeline.priority_pins from public, anon, authenticated;
create table if not exists pipeline.course_priority (course_id uuid primary key, sort int not null);
alter table pipeline.course_priority enable row level security;
revoke all on pipeline.course_priority from public, anon, authenticated;
alter table pipeline.provider_priority add column if not exists pinned_by text;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid='security.provider_priority_refresh_v1()'::regprocedure)<>'c2df6a98e847cc625f9567bc8ed49876'
     or (select md5(prosrc) from pg_proc where oid='public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure)<>'e6d35639281928c42a50e791545bed84'
     or (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_next(integer)'::regprocedure)<>'2311d33b952f004a9a82c55da489de72' then
    raise exception 'cf247_priority_queue: a function changed since 20260930091000; review first';
  end if;
end $g$;

create or replace function security.provider_priority_refresh_v1() returns int language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','ref' as $f$
declare v_n int;
begin
  delete from pipeline.provider_priority;
  insert into pipeline.provider_priority(provider_id,rank,active_courses,pinned_by)
  with n as (select co.provider_id, count(*) c from catalogue.courses co where co.lifecycle_status='active' group by 1),
  p as (select pr.id provider_id, n.c, k.iso_alpha2='AU' au,
          (select min(sort) from pipeline.priority_pins x where x.kind='provider' and x.target_id=pr.id) s_p,
          (select min(sort) from pipeline.priority_pins x where x.kind='state' and x.target_id=pr.subdivision_id) s_s,
          (select min(sort) from pipeline.priority_pins x where x.kind='country' and x.target_id=pr.country_id) s_c
          from catalogue.providers pr join n on n.provider_id=pr.id left join ref.countries k on k.id=pr.country_id)
  select provider_id, row_number() over (order by least(s_p,s_s,s_c) nulls last, au desc nulls last, c desc, provider_id), c,
         case when least(s_p,s_s,s_c) is null then null when least(s_p,s_s,s_c)=s_p then 'provider' when least(s_p,s_s,s_c)=s_s then 'state' else 'country' end
    from p;
  get diagnostics v_n = row_count;
  delete from pipeline.course_priority;
  insert into pipeline.course_priority(course_id,sort) select target_id, sort from pipeline.priority_pins where kind='course';
  return v_n;
end $f$;
revoke all on function security.provider_priority_refresh_v1() from public, anon, authenticated;

do $g$
declare d text; n text;
begin
  d:=pg_get_functiondef('public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure);
  n:=replace(d,E'      left join pipeline.provider_priority pp on pp.provider_id=pg.provider_id',
               E'      left join pipeline.provider_priority pp on pp.provider_id=pg.provider_id\n      left join pipeline.course_priority cp on cp.course_id=pg.course_id');
  n:=replace(n,'order by coalesce(pp.rank,100000), md5(','order by coalesce(cp.sort,1000000), coalesce(pp.rank,100000), md5(');
  if position('pipeline.course_priority cp' in n)=0 or position('coalesce(cp.sort,1000000)' in n)=0 then raise exception 'claim edit did not apply'; end if;
  execute n;
  d:=pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure);
  n:=replace(d,'coalesce(pp.rank,100000) prank,','coalesce(pp.rank,100000) prank, coalesce(cp.sort,1000000) csort,');
  n:=replace(n,'left join pipeline.provider_priority pp on pp.provider_id=p.provider_id','left join pipeline.provider_priority pp on pp.provider_id=p.provider_id left join pipeline.course_priority cp on cp.course_id=p.course_id');
  n:=replace(n,'order by (prank>100), (st<>''bound''), rk, random()','order by csort, least(prank,101), (st<>''bound''), rk, random()');
  n:=replace(n,$s$'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false))$s$,
               $s$'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false) or exists (select 1 from pipeline.course_priority cp where cp.course_id=u.course_id))$s$);
  if position('csort' in n)=0 or position('order by csort, least(prank,101)' in n)=0 or position('exists (select 1 from pipeline.course_priority cp' in n)=0 then raise exception 'read_next edit did not apply'; end if;
  execute n;
end $g$;

-- label helper
create or replace function security.priority_pin_label(p_kind text, p_id uuid) returns jsonb language sql stable security definer set search_path to 'pg_catalog','catalogue','ref' as $f$
  select case p_kind
    when 'provider' then (select jsonb_build_object('label',coalesce(pr.display_name,pr.canonical_name),'detail',concat_ws(' · ',s.name,k.name),'courses',(select count(*) from catalogue.courses c where c.provider_id=pr.id and c.lifecycle_status='active'))
                            from catalogue.providers pr left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id where pr.id=p_id)
    when 'state' then (select jsonb_build_object('label',s.name,'detail',k.name,'courses',(select count(*) from catalogue.courses c join catalogue.providers pr on pr.id=c.provider_id where pr.subdivision_id=s.id and c.lifecycle_status='active'))
                         from ref.subdivisions s left join ref.countries k on k.id=s.country_id where s.id=p_id)
    when 'country' then (select jsonb_build_object('label',k.name,'detail','Whole country','courses',(select count(*) from catalogue.courses c join catalogue.providers pr on pr.id=c.provider_id where pr.country_id=k.id and c.lifecycle_status='active'))
                           from ref.countries k where k.id=p_id)
    else (select jsonb_build_object('label',coalesce(c.display_title,c.canonical_title),'detail',concat_ws(' · ',c.course_code,coalesce(pr.display_name,pr.canonical_name)),'courses',1)
            from catalogue.courses c left join catalogue.providers pr on pr.id=c.provider_id where c.id=p_id) end
$f$;
revoke all on function security.priority_pin_label(text,uuid) from public, anon, authenticated;

create or replace function security.admin_priority_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','catalogue','ref','security' as $f$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'pins',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'target_id',x.target_id,'sort',x.sort,'note',x.note,'at',x.created_at)||coalesce(security.priority_pin_label(x.kind,x.target_id),'{}'::jsonb) order by x.sort),'[]'::jsonb) from pipeline.priority_pins x),
    'ranking',(select coalesce(jsonb_agg(r order by (r->>'rank')::int),'[]'::jsonb) from (
       select jsonb_build_object('rank',pp.rank,'provider_id',pp.provider_id,'name',coalesce(pr.display_name,pr.canonical_name),'state',s.name,'country',k.iso_alpha2,
         'courses',pp.active_courses,'pinned_by',pp.pinned_by,
         'pages_matched',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.read_status='read' and g.identity_basis is not null),
         'pages_waiting',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.status in ('bound','ambiguous') and coalesce(g.read_status,'')<>'read' and g.read_attempts<3)) r
         from pipeline.provider_priority pp join catalogue.providers pr on pr.id=pp.provider_id left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
        where pp.rank<=60) y),
    'states',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'country',k.name) order by k.name,s.name),'[]'::jsonb)
                from ref.subdivisions s join ref.countries k on k.id=s.country_id where exists (select 1 from catalogue.providers pr where pr.subdivision_id=s.id)),
    'countries',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'name',k.name) order by k.name),'[]'::jsonb)
                from ref.countries k where exists (select 1 from catalogue.providers pr where pr.country_id=k.id)),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='priority' order by created_at desc limit 12) e));
end $f$;

create or replace function security.admin_priority_search_v1(p_kind text, p_q text)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','pipeline','catalogue','ref','security' as $f$
declare q text:='%'||btrim(coalesce(p_q,''))||'%';
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_q,'')))<2 then return '[]'::jsonb; end if;
  if p_kind='provider' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',pr.id,'label',coalesce(pr.display_name,pr.canonical_name),'detail',concat_ws(' · ',s.name,k.name)) x
      from catalogue.providers pr left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
     where pr.display_name ilike q or pr.canonical_name ilike q or pr.short_name ilike q order by length(coalesce(pr.display_name,pr.canonical_name)) limit 20) y);
  elsif p_kind='course' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',c.id,'label',coalesce(c.display_title,c.canonical_title),'detail',concat_ws(' · ',c.course_code,coalesce(pr.display_name,pr.canonical_name))) x
      from catalogue.courses c left join catalogue.providers pr on pr.id=c.provider_id
     where c.lifecycle_status='active' and (c.course_code ilike q or c.canonical_title ilike q or c.display_title ilike q) limit 20) y);
  end if;
  raise exception 'search by provider or course';
end $f$;

create or replace function security.admin_priority_control_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_kind text:=p_args->>'kind'; v_target uuid:=nullif(p_args->>'target_id','')::uuid; v_id bigint:=nullif(p_args->>'id','')::bigint; p pipeline.priority_pins%rowtype; o pipeline.priority_pins%rowtype; v_label jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action='add' then
    if v_kind not in ('provider','state','country','course') or v_target is null then raise exception 'choose a university, state, country or course'; end if;
    v_label:=security.priority_pin_label(v_kind,v_target);
    if v_label is null then raise exception 'not found'; end if;
    insert into pipeline.priority_pins(kind,target_id,sort,note,created_by)
    values (v_kind,v_target,case when coalesce((p_args->>'top')::boolean,false) then coalesce((select min(sort) from pipeline.priority_pins),1)-1 else coalesce((select max(sort) from pipeline.priority_pins),0)+1 end,
            nullif(btrim(coalesce(p_args->>'note','')),''),auth.uid())
    on conflict (kind,target_id) do nothing;
  elsif p_action='remove' then
    select * into p from pipeline.priority_pins where id=v_id; if p.id is null then raise exception 'not found'; end if;
    v_label:=security.priority_pin_label(p.kind,p.target_id); v_kind:=p.kind;
    delete from pipeline.priority_pins where id=v_id;
  elsif p_action='move' then
    select * into p from pipeline.priority_pins where id=v_id; if p.id is null then raise exception 'not found'; end if;
    v_label:=security.priority_pin_label(p.kind,p.target_id); v_kind:=p.kind;
    if p_args->>'direction'='up' then select * into o from pipeline.priority_pins where sort<p.sort order by sort desc limit 1;
    else select * into o from pipeline.priority_pins where sort>p.sort order by sort limit 1; end if;
    if o.id is not null then
      update pipeline.priority_pins set sort=-999999 where id=p.id;
      update pipeline.priority_pins set sort=p.sort where id=o.id;
      update pipeline.priority_pins set sort=o.sort where id=p.id;
    end if;
  else raise exception 'unknown action'; end if;
  perform security.provider_priority_refresh_v1();
  insert into pipeline.admin_control_events(area,action,target,detail,actor)
  values ('priority',p_action,coalesce(v_label->>'label',v_id::text),p_args||jsonb_build_object('kind',v_kind),auth.uid());
  return security.admin_priority_read_v1();
end $f$;

revoke all on function security.admin_priority_read_v1() from public, anon;
revoke all on function security.admin_priority_search_v1(text,text) from public, anon;
revoke all on function security.admin_priority_control_v1(text,jsonb) from public, anon;
grant execute on function security.admin_priority_read_v1() to authenticated;
grant execute on function security.admin_priority_search_v1(text,text) to authenticated;
grant execute on function security.admin_priority_control_v1(text,jsonb) to authenticated;
create or replace function public.admin_priority_read() returns jsonb language sql stable security invoker as $f$ select security.admin_priority_read_v1() $f$;
create or replace function public.admin_priority_search(p_kind text, p_q text) returns jsonb language sql stable security invoker as $f$ select security.admin_priority_search_v1(p_kind,p_q) $f$;
create or replace function public.admin_priority_control(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language sql volatile security invoker as $f$ select security.admin_priority_control_v1(p_action,coalesce(p_args,'{}'::jsonb)) $f$;
revoke all on function public.admin_priority_read() from public, anon;
revoke all on function public.admin_priority_search(text,text) from public, anon;
revoke all on function public.admin_priority_control(text,jsonb) from public, anon;
grant execute on function public.admin_priority_read() to authenticated;
grant execute on function public.admin_priority_search(text,text) to authenticated;
grant execute on function public.admin_priority_control(text,jsonb) to authenticated;

select security.provider_priority_refresh_v1();
