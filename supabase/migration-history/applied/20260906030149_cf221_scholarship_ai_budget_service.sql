create or replace function public.scholarship_ai_budget_service(p_country_code text)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','pipeline' as $$
declare s pipeline.scholarship_ai_settings%rowtype; v_spend numeric;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into s from pipeline.scholarship_ai_settings where country_code=upper(p_country_code);
 select coalesce(sum(cost_usd),0) into v_spend from pipeline.scholarship_ai_runs where country_code=upper(p_country_code) and created_at>=date_trunc('day',now());
 return jsonb_build_object('enabled',coalesce(s.enabled,false),'daily_budget_usd',coalesce(s.daily_budget_usd,0),'today_spend_usd',v_spend,'remaining_usd',greatest(coalesce(s.daily_budget_usd,0)-v_spend,0));
end $$;
revoke all on function public.scholarship_ai_budget_service(text) from public,anon,authenticated;
grant execute on function public.scholarship_ai_budget_service(text) to service_role;
