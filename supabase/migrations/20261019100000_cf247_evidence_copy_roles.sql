-- CF-247 (19 Oct 2026). Platform Admin 22:13 (with captures of the Evidence list for one course and its panel): "evidence still duplicated".
-- The list showed four rows for one course: two copies of the course page (read 3 and 5 Oct, before v0.32.0 kept unchanged pages once),
-- the provider's facts page and the provincial catalogue file. Nothing said which copy is in use, which is an older copy, or that the other
-- two are different pages. public.admin_evidence_copy_roles(uuid[]) answers that for the rows on screen: for a course page, in use now,
-- older copy whose values are still in use, or older copy (with its place among the copies); otherwise what kind of saved file it is.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

CREATE OR REPLACE FUNCTION public.admin_evidence_copy_roles(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_out jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 200 then raise exception 'at most 200 ids'; end if;  -- fixed: one list page (the list's own limit)
  with e as (
    select x.id, x.evidence_type, x.storage_path, coalesce(x.captured_at, x.created_at) t,
           case when x.storage_path like 'layer2/%/coverage/%' then split_part(x.storage_path, '/', 5) end k
      from pipeline.evidence_artifacts x where x.id = any(p_ids)),
  c as materialized (  -- every copy of the course pages on screen, read once
    select split_part(y.storage_path, '/', 5) k, y.evidence_type, coalesce(y.captured_at, y.created_at) t from pipeline.evidence_artifacts y
     where y.storage_path like 'layer2/%/coverage/%' and split_part(y.storage_path, '/', 5) in (select e.k from e where e.k is not null)),
  r as (
    select e.id, e.k,
           case when e.k is null then null else (select g.evidence_id = e.id from pipeline.coverage_course_pages g
                                                  where g.course_id = case when e.k ~* '^[0-9a-f-]{36}$' then e.k::uuid end) end in_use,
           e.k is not null and (exists (select 1 from catalogue.course_fees f where f.evidence_id = e.id) or exists (select 1 from catalogue.course_intakes i where i.evidence_id = e.id)
             or exists (select 1 from catalogue.course_english_requirements q where q.evidence_id = e.id) or exists (select 1 from catalogue.course_links l where l.evidence_id = e.id)
             or exists (select 1 from catalogue.course_campuses cc where cc.evidence_id = e.id)) values_live,
           (select count(*) from c where c.k = e.k and c.evidence_type = e.evidence_type) copies,
           (select count(*) from c where c.k = e.k and c.evidence_type = e.evidence_type and c.t <= e.t) nth,
           case when e.k is not null then 'course_page'
                when e.storage_path like 'layer2/%/provider-facts/%' then 'provider_facts'
                when e.evidence_type = 'regulatory_snapshot' then 'register_file'
                when e.evidence_type in ('website_screenshot', 'screenshot') then 'screenshot' else 'other' end kind
      from e)
  select coalesce(jsonb_object_agg(r.id, jsonb_build_object('kind', r.kind,
           'role', case when r.kind <> 'course_page' then null when r.in_use then 'in_use' when r.values_live then 'older_values_live' else 'older' end,
           'copy', r.nth, 'copies', r.copies)), '{}'::jsonb) into v_out from r;
  return v_out;
end $function$;
revoke execute on function public.admin_evidence_copy_roles(uuid[]) from public, anon;
grant execute on function public.admin_evidence_copy_roles(uuid[]) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_evidence_copy_roles', 'Operations', 'Evidence list: which copy of a course page is in use, older, or a different kind of page', 'active', '20261019100000')
on conflict (kind, name) do nothing;
