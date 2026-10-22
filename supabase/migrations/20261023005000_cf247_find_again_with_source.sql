-- CF-247 (23 Oct 2026). Course sources › Find again did nothing for a university that already had a course or programme list: the finder
-- only looks at universities without one. Find again now marks the run (work.again) and the finder takes such a university first, whatever
-- sources it has; a source it finds is added beside the existing ones (same address: nothing changes). Worker v0.40.7 learns up to three
-- course folders per university (UNSW: postgraduate and undergraduate).
-- Replaces: public.svc_source_find_next and public.admin_course_sources (md5-guarded edits)
-- Retires: nothing
do $do$
declare v_def text := pg_get_functiondef('public.svc_source_find_next(integer,uuid[])'::regprocedure);
  v_old text := $o$     where r.step is not null and coalesce(r.leased_until, '-infinity') < now() and coalesce(r.work->>'test', 'false') <> 'true'$o$;
  v_new text := $n$     where (r.step is not null or (r.work->>'again' = 'true' and coalesce(r.next_try_at, now()) <= now()))  -- 23 Oct 2026: or asked to find again
       and coalesce(r.leased_until, '-infinity') < now() and coalesce(r.work->>'test', 'false') <> 'true'$n$;
begin
  if md5(v_def) <> 'fc835f84dc06484b93eadcf3c48bd81a' then raise exception 'public.svc_source_find_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'source find next: expected one in-progress pick'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;
do $do$
declare v_def text := pg_get_functiondef('public.admin_course_sources(text,jsonb)'::regprocedure);
  v_old text := $o$    update pipeline.source_find_runs set next_try_at = now(), state = case when state in ('found', 'tested') then 'none' else state end where provider_id = v_pid;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at) values (v_pid, 'none', now()) on conflict (provider_id) do nothing;$o$;
  v_new text := $n$    update pipeline.source_find_runs set next_try_at = now(), step = null, leased_until = null, work = jsonb_build_object('again', true),
           state = case when state in ('found', 'tested') then 'none' else state end where provider_id = v_pid;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at, work) values (v_pid, 'none', now(), jsonb_build_object('again', true)) on conflict (provider_id) do nothing;$n$;
begin
  if md5(v_def) <> 'f4cd3ce1e7ab727baeefd6a4a39c569c' then raise exception 'public.admin_course_sources is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'course sources: expected one find_again'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

select 'find again works with a source' ok;
