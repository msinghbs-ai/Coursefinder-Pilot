-- CF-247 (22 Oct 2026). Platform Admin 16:22: "How come - published providers still don't have adapters, how come the job queue run out not
-- recheck and keep working in the background. is ti correct 1410 don't have adapters, how will their courses be reflected?" Choice: "Stop
-- onboarding, label 'No courses'". And 16:10 (UTS, Adapter builder › Course pages): no bulk action, edit a course's page address, "show
-- course already read" did not work, ticks replaced the step numbers. Choice: "Yes, build them".
-- Found: of the 1,410 published providers with no adapter, 1,176 have no courses at all (Canada 1,048, New Zealand 128) and 30 Canadian
-- providers have only inactive courses; an adapter reads course pages, so there is nothing to build from. 536 of them were queued or waiting
-- in onboarding (the 22 Oct backfill), checked every hour. UTS: of 162 courses shown "Stored, not read yet", 126 were bound to a page about
-- another course (identity mismatch) and 42 to the old handbookpre2025 site (refused host); none was waiting to be read.
-- 1 Adapter status no_courses (security.provider_adapter_status_v1): a provider with no active course and no adapter. The Providers
--   Adapter filter offers it; Has an adapter and No adapter leave it out; it sorts last.
-- 2 Onboarding (security.provider_onboarding_tick_v1): a provider with no active course that is queued, at the website step or waiting for
--   courses stops with reason no_courses (no credits spent); it is queued again by itself once it has an active course.
-- 3 Adapter builder course list (admin_adapter_builder_basics): a bound page is Wrong page (about another course), Old site (refused host)
--   or Stored, waiting to be read, instead of one "Stored, not read yet"; up to 2,000 courses are listed (was 500).
-- Replaces: security.provider_adapter_status_v1; security.admin_providers_page_v2 (any/none leave no_courses out, sort); security.provider_onboarding_tick_v1 (no_courses stop and resume); public.admin_adapter_builder_basics (page states, list size). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 ---------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.provider_adapter_status_v1(uuid)', 'f34d7428492d7c355c00931834d1066a', array[
  [$o$    'none')$o$,
   $n$    -- 22 Oct 2026 (Platform Admin 16:22): no active course means nothing for an adapter to read
    case when not exists (select 1 from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active') then 'no_courses' end,
    'none')$n$]]);

select pg_temp.edit_once('security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text)', '07b991e9daaef2f0482d3c1da03d17b4', array[
  [$o$(p_adapter = 'any' and adapter_status <> 'none')$o$, $n$(p_adapter = 'any' and adapter_status not in ('none', 'no_courses'))$n$],
  [$o$array['admitting','testing','building','off','none'], adapter_status) end asc$o$, $n$array['admitting','testing','building','off','none','no_courses'], adapter_status) end asc$n$],
  [$o$array['admitting','testing','building','off','none'], adapter_status) end desc$o$, $n$array['admitting','testing','building','off','none','no_courses'], adapter_status) end desc$n$]]);

-- 2 ---------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.provider_onboarding_tick_v1()', '02b984a746bbd5226c9c3e9c6e1ddb78', array[
  [$o$  -- a missing website was entered: carry on$o$,
   $n$  -- 22 Oct 2026 (Platform Admin 16:22, "Stop onboarding, label 'No courses'"): no active course, nothing to build from: stop without
  -- spending credits, and queue again by itself once the provider has an active course
  update pipeline.provider_onboarding ob set status = 'stopped', stop_reason = 'no_courses', job_id = null, updated_at = now(),
         note = 'No active courses, so there is nothing for an adapter to read. Queued again by itself once the provider has an active course.'
   where ob.status in ('queued', 'website', 'waiting_courses')
     and not exists (select 1 from catalogue.courses c where c.provider_id = ob.provider_id and c.lifecycle_status = 'active');
  update pipeline.provider_onboarding ob set status = 'queued', stop_reason = null, job_id = null, attempts = 0, updated_at = now(), note = 'Has active courses now; queued again.'
   where ob.status = 'stopped' and ob.stop_reason = 'no_courses'
     and exists (select 1 from catalogue.courses c where c.provider_id = ob.provider_id and c.lifecycle_status = 'active');
  -- a missing website was entered: carry on$n$]]);

-- 3 ---------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.admin_adapter_builder_basics(text,jsonb)', '4ae55199dfa8d7dbfa74c7d65067c200', array[
  [$o$case st.state when 'no_page' then 1 when 'not_found' then 2 when 'searching' then 3 when 'stored' then 4 else 5 end rk$o$,
   $n$case st.state when 'no_page' then 1 when 'not_found' then 2 when 'wrong_page' then 3 when 'old_site' then 4 when 'searching' then 5 when 'stored' then 6 else 7 end rk$n$],
  [$o$cross join lateral (select case when g.read_status = 'read' then 'read' when g.url is not null then 'stored'$o$,
   $n$cross join lateral (select case when g.read_status = 'read' and coalesce(g.status, 'bound') <> 'mismatch' then 'read'
                                                        -- 22 Oct 2026 (UTS): say what is wrong with a bound page instead of "stored, not read yet"
                                                        when g.url is not null and (g.status = 'mismatch' or g.read_status = 'identity_mismatch') and g.read_status <> 'refused_host' then 'wrong_page'
                                                        when g.url is not null and g.read_status = 'refused_host' then 'old_site'
                                                        when g.url is not null then 'stored'$n$],
  [$o$where c.provider_id = p.id and c.lifecycle_status = 'active' limit 500) z),$o$,
   $n$where c.provider_id = p.id and c.lifecycle_status = 'active' limit 2000) z),  -- fixed: one university's list (was 500)$n$]]);
