-- CF-247 (19 Oct 2026). Platform Admin 22:47, choice "Daily figure on Live activity" for measuring worker v0.32.0 (a course page re-read
-- whose text has not changed keeps the copy in use instead of storing a new one).
-- public.admin_evidence_reuse_today(): today's figure (Melbourne day) for the Live activity tile: course pages read today, how many kept
-- the copy they already had (read today, copy saved before today) and how many stored a new copy, with the space the new copies took.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

CREATE OR REPLACE FUNCTION public.admin_evidence_reuse_today()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from timestamptz := date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne'; v jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select jsonb_build_object('since', v_from,
           'read', count(*),
           'kept', count(*) filter (where coalesce(e.captured_at, e.created_at) < v_from),
           'new_copies', count(*) filter (where coalesce(e.captured_at, e.created_at) >= v_from),
           'on', security.pipeline_num_v1('evidence.reuse_unchanged_pages', 1) >= 1)
    into v
    from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id
   where g.read_status = 'read' and g.read_at >= v_from;
  return v || jsonb_build_object('new_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from pipeline.evidence_artifacts e join storage.objects o on o.bucket_id = 'evidence' and o.name = e.storage_path
                                                where e.storage_path like 'layer2/%/coverage/%' and coalesce(e.captured_at, e.created_at) >= v_from));
end $function$;
revoke execute on function public.admin_evidence_reuse_today() from public, anon;
grant execute on function public.admin_evidence_reuse_today() to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_evidence_reuse_today', 'Operations', 'Live activity: course pages read today that kept their copy (unchanged-page reuse)', 'active', '20261019140000')
on conflict (kind, name) do nothing;
