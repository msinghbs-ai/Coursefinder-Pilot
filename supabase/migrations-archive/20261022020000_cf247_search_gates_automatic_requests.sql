-- CF-247 (22 Oct 2026). Found while setting up the daily resolution measures: NZ title search still bound 374 wrong pages for 4 right
-- after the search gates went live. Onboarding asks for its course searches the way a person does (requested_at), and a request went
-- through every gate, so the 726 providers queued for onboarding at 11:47 were searched even where the site lists too few course pages.
-- The gates (site lists too few course pages, site not checked yet, universities' site list first) now let through only what a person asked
-- for: a request from bulk onboarding (new provider or a backfill wave) waits like any other search, unless someone pressed Search again.
-- Replaces: public.svc_course_link_search_next (person's request only passes the gates). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure)) <> '745ff5da0f4b2e9e32380db248689f8b' then
    raise exception 'live public.svc_course_link_search_next differs from the definition this change replaces';
  end if;
end $guard$;

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

create or replace function security.search_asked_by_person_v1(p_provider uuid, p_requested_at timestamptz) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 22 Oct 2026: a search request counts as a person's unless the provider was put through onboarding in bulk (new provider or a
  -- backfill wave, which ask for searches the same way) and nobody pressed Search again for it since
  select p_requested_at is not null
     and not exists (select 1 from pipeline.provider_onboarding o
                      where o.provider_id = p_provider and o.source in ('backfill', 'new_provider')
                        and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = p_provider and r.resumed_at > o.created_at))
$$;
comment on function security.search_asked_by_person_v1(uuid, timestamptz) is 'CF-247 22 Oct 2026: true when a course search was asked for by a person (not by bulk onboarding, unless Search again was pressed since); only such searches pass the search gates.';
revoke all on function security.search_asked_by_person_v1(uuid, timestamptz) from public;

select pg_temp.edit_once('public.svc_course_link_search_next(integer)', '745ff5da0f4b2e9e32380db248689f8b', array[
  [$o$and (s.requested_at is not null or not security.site_few_course_pages_v1(s.provider_id))$o$,
   $n$and (security.search_asked_by_person_v1(s.provider_id, s.requested_at) or not security.site_few_course_pages_v1(s.provider_id))$n$],
  [$o$and (s.requested_at is not null or security.site_list_match_done_v1(s.course_id, s.provider_id))$o$,
   $n$and (security.search_asked_by_person_v1(s.provider_id, s.requested_at) or security.site_list_match_done_v1(s.course_id, s.provider_id))$n$],
  [$o$and (s.requested_at is not null or not security.site_not_checked_v1(s.provider_id))$o$,
   $n$and (security.search_asked_by_person_v1(s.provider_id, s.requested_at) or not security.site_not_checked_v1(s.provider_id))$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.search_asked_by_person_v1', 'Course pages', 'A course search asked for by a person passes the search gates', 'active', '{}', '20261022020000')
on conflict (kind, name) do nothing;
