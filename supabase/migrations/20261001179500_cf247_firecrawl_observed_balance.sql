-- CF-247: the Firecrawl budget guard follows the balance Firecrawl itself reports. Found on 1 Oct 2026 (19:30 AEST):
-- the guard counted the platform's own usage per calendar month against the 100,000 plan and showed 60,839 credits
-- left; Firecrawl's own account showed 47,476 (its period runs 29 Sep to 29 Oct, and usage on 29-30 Sep and outside the
-- platform's count is invisible to it). Left alone, the reserve of 2,000 would have been passed by about 13,000 credits.
--   * pipeline.vendor_credit_observations: balances read from the vendor (Firecrawl /v1/team/credit-usage);
--   * security.firecrawl_credit_observe_tick_v1(): collects the last reading and sends the next (job firecrawl-credit,
--     every 15 minutes);
--   * security.layer2_provider_budget_status: remaining = the lower of the plan count and the last reading (under 2
--     hours old) less what the platform has used since. Edited in place, only if its body is the one checked on
--     1 Oct 2026 (md5 guard).

create table if not exists pipeline.vendor_credit_observations (
  id bigint generated always as identity primary key,
  provider_id uuid not null references pipeline.layer2_acquisition_providers(id),
  remaining_units numeric not null,
  plan_units numeric,
  period_end timestamptz,
  observed_at timestamptz not null default now(),
  raw jsonb
);
alter table pipeline.vendor_credit_observations enable row level security;
create index if not exists vendor_credit_observations_latest on pipeline.vendor_credit_observations(provider_id, observed_at desc);

create table if not exists pipeline.vendor_credit_requests (
  req_id bigint primary key,
  provider_id uuid not null,
  sent_at timestamptz not null default now(),
  collected boolean not null default false
);
alter table pipeline.vendor_credit_requests enable row level security;

create or replace function security.firecrawl_credit_observe_tick_v1() returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare r record; v jsonb; n int := 0; fc jsonb := public.svc_coverage_firecrawl(); v_pid uuid; v_req bigint;
begin
  for r in select q.req_id, q.provider_id, x.status_code, x.content from pipeline.vendor_credit_requests q
             join net._http_response x on x.id = q.req_id where not q.collected loop
    update pipeline.vendor_credit_requests set collected = true where req_id = r.req_id;
    begin v := r.content::jsonb; exception when others then v := null; end;
    if r.status_code = 200 and (v->'data'->>'remaining_credits') ~ '^[0-9]+(\.[0-9]+)?$' then
      insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, raw)
      values (r.provider_id, (v->'data'->>'remaining_credits')::numeric, nullif(v->'data'->>'plan_credits', '')::numeric,
              nullif(v->'data'->>'billing_period_end', '')::timestamptz, v->'data');
      n := n + 1;
    end if;
  end loop;
  update pipeline.vendor_credit_requests set collected = true where not collected and sent_at < now() - interval '30 minutes';
  v_pid := nullif(fc->'budget_status'->>'provider_id', '')::uuid;
  if v_pid is not null and fc->>'secret' is not null then
    v_req := net.http_get(url := 'https://api.firecrawl.dev/v1/team/credit-usage',
               headers := jsonb_build_object('Authorization', 'Bearer ' || (fc->>'secret')), timeout_milliseconds := 30000);
    insert into pipeline.vendor_credit_requests(req_id, provider_id) values (v_req, v_pid);
  end if;
  return jsonb_build_object('collected', n, 'sent', v_req);
end $fn$;
revoke all on function security.firecrawl_credit_observe_tick_v1() from public, anon, authenticated;

do $b$
declare s text; d text; v text;
  o text := E'  v_remaining:=greatest(v_limit-v_used,0);\n';
  n text := E'  v_remaining:=greatest(v_limit-v_used,0);\n'
         || E'  -- the vendor''s own balance (read every 15 minutes) less what the platform used since, when lower\n'
         || E'  v_remaining:=least(v_remaining, coalesce((select greatest(o.remaining_units\n'
         || E'      - coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.acquisition_provider_id=p_provider_id and u.at>o.observed_at),0)\n'
         || E'      - (select count(*)::numeric*v_unit from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=p_provider_id and a.started_at>o.observed_at),0)\n'
         || E'    from pipeline.vendor_credit_observations o where o.provider_id=p_provider_id and o.observed_at>now()-interval ''2 hours''\n'
         || E'    order by o.observed_at desc limit 1), v_remaining));\n';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'layer2_provider_budget_status';
  v := md5(s);
  if v is distinct from '5f76be10ad2334c9f550421e0c2fb611' then raise exception 'layer2_provider_budget_status changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'remaining line not found once'; end if;
  execute replace(d, o, n);
end $b$;

select cron.unschedule(jobid) from cron.job where jobname = 'firecrawl-credit';
select cron.schedule('firecrawl-credit', '*/15 * * * *', $$select security.firecrawl_credit_observe_tick_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('firecrawl-credit', 'Platform upkeep', 40, 'Check the Firecrawl balance',
        'Reads the Firecrawl account balance every 15 minutes; the budget guard uses it when it is lower than the platform''s own count.', 5, false)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label, description = excluded.description,
       control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;

select security.firecrawl_credit_observe_tick_v1();
