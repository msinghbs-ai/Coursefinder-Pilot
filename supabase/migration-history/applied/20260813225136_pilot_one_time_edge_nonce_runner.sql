create table if not exists pipeline.pilot_edge_nonces(
  id uuid primary key default extensions.gen_random_uuid(),
  function_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
alter table pipeline.pilot_edge_nonces enable row level security;
revoke all on pipeline.pilot_edge_nonces from public, anon, authenticated;
grant select,update on pipeline.pilot_edge_nonces to service_role;

create or replace function public.svc_pilot_consume_nonce(p_function text,p_nonce uuid)
returns boolean
language sql
security invoker
set search_path to 'pipeline','public'
as $function$
  with consumed as (
    update pipeline.pilot_edge_nonces
       set used_at=now()
     where id=p_nonce
       and function_name=p_function
       and used_at is null
       and expires_at>now()
     returning id
  )
  select exists(select 1 from consumed);
$function$;
revoke all on function public.svc_pilot_consume_nonce(text,uuid) from public, anon, authenticated;
grant execute on function public.svc_pilot_consume_nonce(text,uuid) to service_role;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'pipeline','net','public','extensions'
as $function$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in ('layer1-ca-niagara-catalogue') then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds:=30000
  ) into v_id;
  return v_id;
end $function$;
revoke all on function pipeline.svc_pilot_submit_nonce(text,jsonb) from public, anon, authenticated;
grant execute on function pipeline.svc_pilot_submit_nonce(text,jsonb) to service_role;
