-- CF-247 v2.15.255 (12 Oct 2026). Found while checking onboarding live: the course-page search had nearly stopped (5 searches done
-- in 6 hours, 3,764 waiting). The worker picks searches by CRICOS code first, but 754 of those belong to universities that are not
-- Firecrawl targets (target-only is on), so the worker refused them and put them back every minute, and searches for target
-- universities (all the onboarding ones) never got a turn. 8 universities stopped onboarding with "0 course pages could be read".
-- The picker now takes only target universities while target-only is on. The 8 are sent back to the course-page step.
-- Guarded on the live definition; nothing dropped.
do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "1359e0d8038c886520411395e1429d08"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       -- v2.15.255: while Firecrawl is for target universities only, take only their searches (others were refused and starved the queue)
       and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
            or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included))
     order by (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
     for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

update pipeline.provider_onboarding o set status = 'course_pages', stop_reason = null, job_id = null, attempts = 0, step_started_at = now(),
       note = 'The course-page search was held up (v2.15.255 fix); searching again.', updated_at = now()
 where o.status = 'stopped' and o.stop_reason = 'too_few_pages'
   and not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read');

do $post$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "f0aa2519e42b7258e3951deb736db72f"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.255 link search post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
