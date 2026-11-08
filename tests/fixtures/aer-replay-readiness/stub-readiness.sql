-- Stand-in for security.layer4_readiness_items_v1(uuid[]) (live: released with 20261108040000; its own behaviour is guarded by the aer-review-ready fixture).
-- Here it only records what it was asked to assess, so the replay's call can be checked. A setting makes it fail, to prove a failure never undoes the replay.
create table if not exists public.readiness_calls(id bigserial primary key, items uuid[] not null, called_at timestamptz not null default now());
create or replace function security.layer4_readiness_items_v1(p_items uuid[]) returns jsonb language plpgsql as $$
begin
  if current_setting('aerrr.fail', true) = '1' then raise exception 'readiness stub failed on purpose'; end if;
  insert into public.readiness_calls(items) values (p_items);
  return jsonb_build_object('classified', cardinality(p_items), 'gates', 0);
end $$;
