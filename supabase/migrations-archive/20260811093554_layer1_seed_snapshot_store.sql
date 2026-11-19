create table if not exists pipeline.layer1_seed_snapshots(
  country_code text primary key,
  snapshot jsonb not null,
  seed_source text not null default 'coursefinder-demo-layer1-core',
  seed_version text not null default '2026-08-11',
  provider_count integer not null default 0,
  course_count integer not null default 0,
  content_hash text,
  updated_at timestamptz not null default now()
);
alter table pipeline.layer1_seed_snapshots enable row level security;
revoke all on pipeline.layer1_seed_snapshots from public,anon,authenticated;
grant select,insert,update,delete on pipeline.layer1_seed_snapshots to service_role;

create or replace function public.svc_layer1_put_seed_snapshot(p_country_code text,p_snapshot jsonb,p_seed_source text default 'coursefinder-demo-layer1-core',p_seed_version text default '2026-08-11')
returns jsonb language plpgsql security definer set search_path=public,pipeline,extensions as $$
declare v_providers int; v_courses int; v_hash text;
begin
 if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
 v_providers:=jsonb_array_length(coalesce(p_snapshot,'[]'::jsonb));
 select coalesce(sum(jsonb_array_length(coalesce(x->'q','[]'::jsonb))),0)::int into v_courses from jsonb_array_elements(coalesce(p_snapshot,'[]'::jsonb)) x;
 v_hash:=encode(extensions.digest(convert_to(coalesce(p_snapshot,'[]'::jsonb)::text,'UTF8'),'sha256'),'hex');
 insert into pipeline.layer1_seed_snapshots(country_code,snapshot,seed_source,seed_version,provider_count,course_count,content_hash,updated_at)
 values(upper(p_country_code),coalesce(p_snapshot,'[]'::jsonb),p_seed_source,p_seed_version,v_providers,v_courses,v_hash,now())
 on conflict(country_code) do update set snapshot=excluded.snapshot,seed_source=excluded.seed_source,seed_version=excluded.seed_version,provider_count=excluded.provider_count,course_count=excluded.course_count,content_hash=excluded.content_hash,updated_at=now();
 return jsonb_build_object('country',upper(p_country_code),'providers',v_providers,'courses',v_courses,'content_hash',v_hash);
end $$;
revoke all on function public.svc_layer1_put_seed_snapshot(text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.svc_layer1_put_seed_snapshot(text,jsonb,text,text) to service_role;

create or replace function public.svc_layer1_get_seed_snapshot(p_country_code text)
returns jsonb language plpgsql stable security definer set search_path=public,pipeline as $$
declare v jsonb;
begin
 if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
 select snapshot into v from pipeline.layer1_seed_snapshots where country_code=upper(p_country_code);
 return coalesce(v,'[]'::jsonb);
end $$;
revoke all on function public.svc_layer1_get_seed_snapshot(text) from public,anon,authenticated;
grant execute on function public.svc_layer1_get_seed_snapshot(text) to service_role;

create or replace function public.svc_layer1_seed_status()
returns jsonb language plpgsql stable security definer set search_path=public,pipeline as $$
begin
 if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('country',country_code,'providers',provider_count,'courses',course_count,'seed_source',seed_source,'seed_version',seed_version,'content_hash',content_hash) order by country_code) from pipeline.layer1_seed_snapshots),'[]'::jsonb);
end $$;
revoke all on function public.svc_layer1_seed_status() from public,anon,authenticated;
grant execute on function public.svc_layer1_seed_status() to service_role;
