-- CF-247 Standing Review Rule 6, unclear page identity (8 Oct 2026, Platform Admin, multiple choice):
--   * a course bound to a page whose address names another course: "Do nothing if cricos code matches up on providers course page";
--   * pages shared by several courses whose address names none of them: "Keep everything".
-- This migration only measures the first case: it lists the courses whose bound, read page is shared with a course of a different
-- title and whose address names that other course (140 on 8 Oct), and lets the coverage-sweep worker (mode page_codes, v0.17.18)
-- read the stored page and record every CRICOS-shaped code on it. Nothing is unbound or withdrawn here; what happens to a course
-- whose code is not on the page is a separate Platform Admin decision.
create table if not exists pipeline.rule6_page_checks (
  course_id uuid primary key, provider_id uuid not null, url text not null, evidence_id uuid, storage_path text, course_code text,
  named_course text, codes text[], found boolean, error text, listed_at timestamptz not null default now(), checked_at timestamptz);
alter table pipeline.rule6_page_checks enable row level security;
revoke all on pipeline.rule6_page_checks from public, anon, authenticated;

create or replace function security.rule6_list_v1()
returns int language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  with s as (select url, provider_id from pipeline.coverage_course_pages where read_status = 'read' group by 1, 2 having count(*) > 1),
  r as (select pg.url, pg.provider_id, pg.course_id, pg.evidence_id, c.display_title,
               regexp_replace(lower(c.display_title), '[^a-z]', '', 'g') t,
               regexp_replace(lower(regexp_replace(pg.url, '^https?://[^/]+', '')), '[^a-z]', '', 'g') u
          from pipeline.coverage_course_pages pg join s using (url, provider_id) join catalogue.courses c on c.id = pg.course_id
         where pg.read_status = 'read'),
  g as (select url, provider_id from r group by 1, 2 having count(distinct t) > 1),
  m as (select r.*,
               (select r2.display_title from r r2 where r2.url = r.url and r2.provider_id = r.provider_id and strpos(r2.u, r2.t) > 0 order by length(r2.t) desc limit 1) named,
               (select max(length(r2.t)) from r r2 where r2.url = r.url and r2.provider_id = r.provider_id and strpos(r2.u, r2.t) > 0) best_len
          from r join g using (url, provider_id))
  insert into pipeline.rule6_page_checks(course_id, provider_id, url, evidence_id, storage_path, course_code, named_course)
  select m.course_id, m.provider_id, m.url, m.evidence_id, e.storage_path,
         (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = m.course_id and lower(cr.scheme) = 'cricos' limit 1), m.named
    from m left join pipeline.evidence_artifacts e on e.id = m.evidence_id
   where m.best_len is not null and not (strpos(m.u, m.t) > 0 and length(m.t) = m.best_len)
  on conflict (course_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.rule6_list_v1() from public, anon, authenticated;

create or replace function public.svc_rule6_next(p_limit int default 20)
returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('course_id', course_id, 'storage_path', storage_path))
                     from (select course_id, storage_path from pipeline.rule6_page_checks where checked_at is null and storage_path is not null
                            order by listed_at, course_id limit least(greatest(p_limit, 1), 50)) x), '[]'::jsonb);
end $f$;

create or replace function public.svc_rule6_done(p_results jsonb)
returns int language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.rule6_page_checks c
     set codes = coalesce(array(select jsonb_array_elements_text(x->'codes')), '{}'), error = left(x->>'error', 300), checked_at = now(),
         found = case when x->>'error' is null then c.course_code is not null and upper(c.course_code) = any(array(select upper(jsonb_array_elements_text(x->'codes')))) end
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) x
   where c.course_id = (x->>'course_id')::uuid;
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function public.svc_rule6_next(int), public.svc_rule6_done(jsonb) from public, anon, authenticated;
grant execute on function public.svc_rule6_next(int), public.svc_rule6_done(jsonb) to service_role;

select security.rule6_list_v1();
