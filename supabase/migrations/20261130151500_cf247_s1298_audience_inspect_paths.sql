-- CF-247 s1298 (S1-Build; SS-Programme-Control 27 Nov 2026 12:08 AEDT, "Phase B — International Audience Verification"; design coursefinder-admin #1271 §5, §6).
-- The read-only worker mode audience_inspect (coverage-sweep v1.0.55) reads the stored copy of each named course's bound course page and returns its audience and
-- identity signals (no model, no fetch, no write). This function gives the worker, for at most 20 courses, the stored copy path of the course page
-- (pipeline.coverage_course_pages -> pipeline.evidence_artifacts) and the course code (service role only, as svc_entry_matrix_inspect_paths).
-- Read-only; writes nothing. G1: no job. G2: 20 is a diagnostic batch bound (fixed). G3: 75/48 checked. Locks unchanged. Nothing dropped or deleted.
-- Replaces: nothing. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function create

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
end $g$;

create or replace function public.svc_audience_inspect_paths_v1(p_course_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('course_id', c.id, 'course_code', c.course_code, 'url', g.url, 'storage_path', e.storage_path,
                 'evidence_id', e.id, 'captured_at', e.captured_at) order by c.course_code), '[]'::jsonb)
            from catalogue.courses c
            left join pipeline.coverage_course_pages g on g.course_id = c.id
            left join pipeline.evidence_artifacts e on e.id = g.evidence_id
           where c.id = any(p_course_ids[1:20]));  -- fixed: diagnostic batch cap
end $$;
revoke all on function public.svc_audience_inspect_paths_v1(uuid[]) from public, anon, authenticated;
grant execute on function public.svc_audience_inspect_paths_v1(uuid[]) to service_role;
comment on function public.svc_audience_inspect_paths_v1(uuid[]) is 'CF-247 s1298: stored course-page copy paths of up to 20 courses for the read-only worker mode audience_inspect (service role only; reads nothing else)';

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
end $c$;
