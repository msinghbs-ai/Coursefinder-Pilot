-- CF-247: align the platform health OpenRouter check with the Layer 3 routes activated on 29 Sep 2026 (daily guards:
-- intake US$4, English US$4, tuition US$5; credit floor US$5). The health check still used the plan v1.1 US$5 total,
-- so it reported "critical" while every route was inside its own guard. New rule: combined daily ceiling US$14
-- (the three guards plus US$1 for benchmarks and scholarship AI), warning at 80%; plus a credit check from the latest
-- OpenRouter credit observation: warning below US$10 remaining, critical at or below the US$5 floor (routes stop there).
do $patch$
declare v text; a text; b text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.platform_health_check_v1(boolean)'::regprocedure)<>'ba7d0e94c18314afc6e3d8bf5f7becce' then
    raise exception 'platform_health_check_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure);
  a:=$o$      if v_num>=5 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','critical','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||', at or over the US$5 daily ceiling',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',5));
      elsif v_num>=4 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','warning','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||' (80% of the US$5 daily ceiling)',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',5));
      end if;$o$;
  b:=$n$      if v_num>=14 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','critical','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||', at or over the US$14 combined daily ceiling',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',14));
      elsif v_num>=11.2 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','warning','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||' (80% of the US$14 combined daily ceiling)',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',14));
      end if;
      select o.remaining_usd into v_num from pipeline.layer3_openrouter_observations o where o.kind='credits' and o.remaining_usd is not null order by o.observed_at desc limit 1;
      if v_num is not null and v_num<=5 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_credit','critical','budgets',
          'OpenRouter credit is US$'||round(v_num,2)||': at the US$5 floor, so automated Layer 3 admission has stopped. Top up the credit.',jsonb_build_object('remaining_usd',round(v_num,2),'floor_usd',5));
      elsif v_num is not null and v_num<10 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_credit','warning','budgets',
          'OpenRouter credit is US$'||round(v_num,2)||': automated Layer 3 admission stops at US$5. Top up soon.',jsonb_build_object('remaining_usd',round(v_num,2),'floor_usd',5));
      end if;$n$;
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'budget anchor not found exactly once'; end if;
  execute replace(v,a,b);
end $patch$;
select security.platform_health_check_v1(true);
