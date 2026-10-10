create table if not exists pipeline.statistics_dataset_registry (
  dataset_key text primary key,
  label text not null,
  dataset_type text not null check (dataset_type in ('statistics','ranking','index')),
  description text not null default '',
  display_enabled boolean not null default true,
  display_order integer not null default 100,
  dataset_route text,
  compare_enabled boolean not null default true,
  source_system_code text,
  source_authority text,
  admin_import_system text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table pipeline.statistics_dataset_registry enable row level security;

insert into pipeline.statistics_dataset_registry(dataset_key,label,dataset_type,description,display_enabled,display_order,dataset_route,compare_enabled,source_system_code,source_authority,admin_import_system) values
('qilt','QILT','statistics','Student experience, graduate outcomes and employment benchmarks from Australia’s Quality Indicators for Learning and Teaching.',true,10,'Outcomes (QILT)',true,null,'QILT',null),
('prisms','PRISMS','statistics','International student enrolment and commencement flow observations retained at their governed reporting grain.',true,20,'Student Flow (PRISMS)',true,null,'Australian Government PRISMS',null),
('qs_wur','QS World University Rankings','ranking','Global institutional ranking comparing universities across academic reputation, employer reputation, research and internationalisation indicators.',true,30,null,true,'qs_wur','QS Quacquarelli Symonds','qs_wur'),
('the_wur','Times Higher Education World University Rankings','ranking','Global institutional ranking covering teaching, research environment, research quality, industry engagement and international outlook.',true,40,null,true,'the_wur','Times Higher Education','the_wur'),
('arwu','Academic Ranking of World Universities','ranking','Research-focused global university ranking published by ShanghaiRanking, emphasising academic and research performance.',false,50,null,true,'arwu','ShanghaiRanking Consultancy','arwu'),
('diversity_index','University Diversity Index','index','Contextual international-diversity view showing the breadth of nationalities and international-student representation at an institution.',false,60,null,true,null,'Hotcourses Diversity Index',null)
on conflict (dataset_key) do update set label=excluded.label,dataset_type=excluded.dataset_type,description=excluded.description,dataset_route=excluded.dataset_route,compare_enabled=excluded.compare_enabled,source_system_code=excluded.source_system_code,source_authority=excluded.source_authority,admin_import_system=excluded.admin_import_system,updated_at=now();

create or replace function public.statistics_dataset_registry_read()
returns jsonb language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if security.current_role_rank() < 1 then raise exception 'not_authorised'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.display_order,x.label) from (
    select dataset_key,label,dataset_type,description,display_enabled,display_order,dataset_route,compare_enabled,source_system_code,source_authority,admin_import_system
    from pipeline.statistics_dataset_registry
  ) x),'[]'::jsonb);
end $$;

create or replace function public.statistics_dataset_registry_write(p_dataset jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$
declare k text; r pipeline.statistics_dataset_registry;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if security.current_role_rank() < 4 then raise exception 'admin_role_required'; end if;
  k:=lower(trim(coalesce(p_dataset->>'dataset_key','')));
  if k !~ '^[a-z0-9_]{2,64}$' then raise exception 'invalid_dataset_key'; end if;
  insert into pipeline.statistics_dataset_registry(dataset_key,label,dataset_type,description,display_enabled,display_order,dataset_route,compare_enabled,source_system_code,source_authority,admin_import_system,updated_at)
  values(k,trim(coalesce(p_dataset->>'label',k)),coalesce(nullif(p_dataset->>'dataset_type',''),'statistics'),coalesce(p_dataset->>'description',''),coalesce((p_dataset->>'display_enabled')::boolean,true),coalesce((p_dataset->>'display_order')::integer,100),nullif(p_dataset->>'dataset_route',''),coalesce((p_dataset->>'compare_enabled')::boolean,true),nullif(p_dataset->>'source_system_code',''),nullif(p_dataset->>'source_authority',''),nullif(p_dataset->>'admin_import_system',''),now())
  on conflict(dataset_key) do update set label=excluded.label,dataset_type=excluded.dataset_type,description=excluded.description,display_enabled=excluded.display_enabled,display_order=excluded.display_order,dataset_route=excluded.dataset_route,compare_enabled=excluded.compare_enabled,source_system_code=excluded.source_system_code,source_authority=excluded.source_authority,admin_import_system=excluded.admin_import_system,updated_at=now()
  returning * into r;
  return to_jsonb(r);
end $$;

revoke all on function public.statistics_dataset_registry_read() from public,anon;
revoke all on function public.statistics_dataset_registry_write(jsonb) from public,anon;
grant execute on function public.statistics_dataset_registry_read() to authenticated;
grant execute on function public.statistics_dataset_registry_write(jsonb) to authenticated;
