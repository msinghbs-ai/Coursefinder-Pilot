-- CF-247 v2.15.265 (Platform Admin, 13 Oct 2026: "Refusals per university"): Toolsets › Firecrawl › Credits by university also lists
-- today's refused spends by university and reason (pipeline.firecrawl_refusals_by_provider), with each university's search order tier and
-- whether its course search is held. Read only; nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.admin_firecrawl_credits(integer)": "356e6842666e39d49e50a352fe9c5d6d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.admin_firecrawl_credits(p_hours integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return security.firecrawl_credits_report_v1(p_hours) || jsonb_build_object('can_manage', v_rank >= 6,
    -- v2.15.265: today's refusals by university (Melbourne day), most first
    'refused_by_uni', (select coalesce(jsonb_agg(z order by z.n desc, z.name), '[]'::jsonb) from (
        select r.provider_id, coalesce(p.display_name, p.canonical_name) as name, security.coverage_country(r.provider_id) as country,
               security.fc_provider_tier_v1(r.provider_id) as tier, sum(r.n)::int as n,
               jsonb_object_agg(r.grp || ':' || r.reason, r.n) as reasons,
               exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = r.provider_id
                        and not exists (select 1 from pipeline.firecrawl_search_resumes x where x.provider_id = h.provider_id and x.resumed_at > h.held_at)) as held
          from pipeline.firecrawl_refusals_by_provider r join catalogue.providers p on p.id = r.provider_id
         where r.day = (now() at time zone 'Australia/Melbourne')::date
         group by r.provider_id, p.display_name, p.canonical_name order by sum(r.n) desc limit 100) z));
end $function$;

do $post$
declare v_expected jsonb := '{"public.admin_firecrawl_credits(integer)": "21ae40b41afee9809e2fd02e61135291"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.265 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
