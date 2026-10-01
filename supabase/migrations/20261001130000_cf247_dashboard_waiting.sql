-- CF-247 Dashboard "Waiting for you" (screen review 1 Oct 2026, Dashboard: "dash-missing-todo" - one row per queue that
-- needs a person: count, oldest item, and the place to act). Read only; each row says the lowest role that can open it,
-- and the page shows only the rows the viewer can act on. A row that cannot be counted is left out rather than failing.
create or replace function public.admin_waiting_read() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_rows jsonb := '[]'::jsonb; v_n bigint; v_old timestamptz;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.layer4_review_items where status = 'pending';
    v_rows := v_rows || jsonb_build_object('key','review','label','Review items to decide','count',v_n,'oldest',v_old,'href','#layer-4-review','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.data_flags where status = 'open';
    v_rows := v_rows || jsonb_build_object('key','flags','label','Flagged values to check','count',v_n,'oldest',v_old,'href','#layer-4-review?tab=flags','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.fee_wording_rules where status = 'draft';
    v_rows := v_rows || jsonb_build_object('key','rules','label','Fee rules waiting for approval','count',v_n,'oldest',v_old,'href','#layer-4-review?tab=rules','min',5);
  exception when others then null; end;
  begin
    select count(distinct c.scholarship_id), min(c.created_at) into v_n, v_old from scholarship.course_mapping_candidates c where c.status = 'needs_review';
    v_rows := v_rows || jsonb_build_object('key','scholarship_links','label','Scholarships to link to courses','count',v_n,'oldest',v_old,'href','#scholarships?tab=links','min',4);
  exception when others then null; end;
  begin
    select count(*) into v_n from security.scholarship_publishability_v1() x join scholarship.scholarships s on s.id = x.scholarship_id
     where x.publishable and coalesce(s.publication_status, '') <> 'published';
    v_rows := v_rows || jsonb_build_object('key','scholarships_ready','label','Scholarships ready to publish','count',v_n,'oldest',null,'href','#scholarships?tab=publishing','min',5);
  exception when others then null; end;
  begin
    select count(*) into v_n from pipeline.important_links where retired_at is null and enabled and health_status = 'degraded';
    v_rows := v_rows || jsonb_build_object('key','reference','label','Reference sites not reachable','count',v_n,'oldest',null,'href','#reference-data?tab=links','min',3);
  exception when others then null; end;
  begin
    select count(*), min(coalesce(starts_on, starts_at::date))::timestamptz into v_n, v_old from pipeline.important_dates
     where status = 'active' and coalesce(starts_on, starts_at::date) between current_date and current_date + warning_window;
    v_rows := v_rows || jsonb_build_object('key','dates','label','Key dates coming up','count',v_n,'oldest',v_old,'href','#reference-data?tab=dates','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.jobs where status = 'failed' and created_at > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_jobs','label','Jobs that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs?tab=jobs','min',4);
  exception when others then null; end;
  begin
    select count(distinct d.jobid), min(d.start_time) into v_n, v_old from cron.job_run_details d where d.status = 'failed' and d.start_time > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_automations','label','Automations that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs','min',4);
  exception when others then null; end;
  return jsonb_build_object('rank', v_rank, 'generated_at', now(),
    'rows', (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(v_rows) r where (r->>'min')::int <= v_rank));
end $f$;
revoke all on function public.admin_waiting_read() from public, anon;
grant execute on function public.admin_waiting_read() to authenticated;