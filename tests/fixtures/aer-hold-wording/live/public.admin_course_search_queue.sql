CREATE OR REPLACE FUNCTION public.admin_course_search_queue(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_queued int; v_asked int; v_sent int; v_first timestamptz; v_ahead int; v_focus boolean; v_target boolean; v_stopped boolean; v_left numeric; v_on boolean; v_why text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select count(*) filter (where s.state = 'queued'), count(*) filter (where s.state = 'queued' and s.requested_at is not null), count(*) filter (where s.state = 'sent'),
         min(s.requested_at) filter (where s.state = 'queued')
    into v_queued, v_asked, v_sent, v_first from pipeline.course_link_search s where s.provider_id = p_provider_id;
  select count(*) into v_ahead from pipeline.course_link_search s
   where s.state = 'queued' and s.requested_at is not null and s.provider_id <> p_provider_id and s.requested_at < coalesce(v_first, now());
  v_focus := security.enrich_focus_v1(p_provider_id);
  v_target := not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
              or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = p_provider_id and tc.included);
  v_stopped := p_provider_id = any (array(select x.provider_id from security.fc_search_stopped_v1() x));
  v_left := security.fc_budget_left_v1('course_link_search');
  select enabled into v_on from pipeline.course_link_search_settings where id = 1;
  v_why := case when v_queued + v_sent = 0 then null
                when not coalesce(v_on, false) then 'course-page search is switched off (Firecrawl settings)'
                when v_stopped then 'the search for this university is stopped or held: press Search again on Firecrawl credits by university'
                when not v_target then 'this university is not a Firecrawl target university, so it is not searched'
                when v_left < 2 then 'today''s Firecrawl share for course search is used up; it continues tomorrow'
                when v_asked = 0 and v_sent = 0 and not v_focus then 'waiting: outside the focus providers, so it runs only when asked for; press Find every missing page'
                else null end;
  return jsonb_build_object('queued', v_queued, 'asked', v_asked, 'sent', v_sent, 'ahead', v_ahead, 'in_focus', v_focus, 'target', v_target,
                            'stopped', v_stopped, 'budget_left', v_left, 'runs', v_why is null and v_queued + v_sent > 0, 'why', v_why);
end $function$
