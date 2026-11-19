-- CF-247 scholarship course links (Platform Admin, 1 Oct 2026: scholarship selection, "Clear the 37,200 links").
-- 37,200 scholarship-to-course links wait for review, but they come from only 87 scholarships: a provider's scholarship
-- with no stated scope was proposed for every course of that provider. So the decision is one per scholarship, not one
-- per link. For each scholarship a Pipeline Operator (rank 4) or above chooses:
--   all   - it applies to every proposed course;
--   filter- only courses that match chosen study levels, broad fields of study, words in the title, or picked courses;
--   none  - it is not tied to particular courses (for example a travel grant or a government award).
-- The decision accepts the matching links into scholarship.course_mappings (basis scope_decision:<decision>) and
-- rejects the rest. It is saved (pipeline.scholarship_scope_decisions), shown with who made it and why, can be changed
-- (links it added that no longer match are removed; links from other sources are never touched), and an hourly job
-- applies it to new links proposed later for the same scholarship. A suggestion is offered from the scholarship's name
-- (for example "Master of ..." suggests that course title; "research" suggests research degrees), never applied on
-- its own. Every decision is logged in pipeline.layer4_mass_operations.

create table if not exists pipeline.scholarship_scope_decisions (
  scholarship_id uuid primary key references scholarship.scholarships(id),
  decision text not null check (decision in ('all','filter','none')),
  filter jsonb not null default '{}'::jsonb,
  reason text,
  decided_by uuid, decided_at timestamptz not null default now(),
  accepted int not null default 0, rejected int not null default 0, last_applied_at timestamptz);
alter table pipeline.scholarship_scope_decisions enable row level security;
revoke all on pipeline.scholarship_scope_decisions from public, anon, authenticated;

-- Broad field of study (ASCED two-digit) of a field.
create or replace function security.broad_field_id(p_field_id uuid) returns uuid language sql stable set search_path = '' as $$
  select coalesce((select b.id from ref.fields_of_study f join ref.fields_of_study b on b.path = 'asced/' || split_part(f.path, '/', 2)
                    where f.id = p_field_id and f.path like 'asced/%' limit 1), p_field_id)
$$;
revoke all on function security.broad_field_id(uuid) from public, anon, authenticated;

-- Does a course match a filter {levels:[uuid], fields:[uuid broad], title:"a, b", courses:[uuid]}?
create or replace function security.scholarship_scope_match(p_course_id uuid, p_decision text, p_filter jsonb) returns boolean
language sql stable set search_path = '' as $$
  select case p_decision when 'all' then true when 'none' then false else
    exists (select 1 from catalogue.courses c
             where c.id = p_course_id
               and (   c.id::text in (select jsonb_array_elements_text(coalesce(p_filter->'courses', '[]'::jsonb)))
                    or (    (jsonb_array_length(coalesce(p_filter->'levels', '[]'::jsonb)) > 0 or jsonb_array_length(coalesce(p_filter->'fields', '[]'::jsonb)) > 0
                             or nullif(btrim(coalesce(p_filter->>'title', '')), '') is not null)
                        and (jsonb_array_length(coalesce(p_filter->'levels', '[]'::jsonb)) = 0
                             or c.study_level_id::text in (select jsonb_array_elements_text(p_filter->'levels')))
                        and (jsonb_array_length(coalesce(p_filter->'fields', '[]'::jsonb)) = 0
                             or security.broad_field_id(c.primary_field_id)::text in (select jsonb_array_elements_text(p_filter->'fields')))
                        and (nullif(btrim(coalesce(p_filter->>'title', '')), '') is null
                             or exists (select 1 from regexp_split_to_table(p_filter->>'title', '\s*,\s*') w
                                         where btrim(w) <> '' and coalesce(c.display_title, c.canonical_title) ilike '%' || btrim(w) || '%')))))
  end
$$;
revoke all on function security.scholarship_scope_match(uuid, text, jsonb) from public, anon, authenticated;

-- A suggestion from the scholarship's name (never applied on its own).
create or replace function security.scholarship_scope_suggest(p_scholarship_id uuid) returns jsonb
language plpgsql stable set search_path = '' as $$
declare v_name text; v_title text; v_levels jsonb := '[]'::jsonb; v_fields jsonb := '[]'::jsonb; v_why text[] := '{}';
begin
  select s.name into v_name from scholarship.scholarships s where s.id = p_scholarship_id;
  if v_name is null then return null; end if;
  if v_name ~* '\y(travel|conference|accommodation|hardship|emergency|relocation|prize|placement|exchange|study abroad|mobility|internship)\y' then
    return jsonb_build_object('decision', 'none', 'filter', '{}'::jsonb, 'why', 'The name suggests support that is not tied to a course''s tuition (for example travel or hardship).');
  end if;
  v_title := substring(v_name from '((?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Doctor) of [A-Z][A-Za-z&'' ]+?)(?:\s+(?:Scholarship|Award|Prize|Bursary|Grant|Pioneers|International|Excellence)|$)');
  if v_title is not null then
    return jsonb_build_object('decision', 'filter', 'filter', jsonb_build_object('title', v_title), 'why', 'The name mentions one course: ' || v_title || '.');
  end if;
  if v_name ~* '\y(research|phd|doctoral|hdr|higher degree)\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Doctorate / PhD','Masters Degree (Research)')); v_why := v_why || 'research degrees';
  elsif v_name ~* '\yundergraduate\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Bachelor','Bachelor Honours Degree','Diploma','Advanced Diploma','Associate Degree')); v_why := v_why || 'undergraduate courses';
  elsif v_name ~* '\y(postgraduate|masters|master''s)\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Masters Degree (Coursework)','Masters Degree (Extended)','Graduate Certificate','Graduate Diploma','Masters')); v_why := v_why || 'postgraduate coursework';
  end if;
  v_fields := (select jsonb_agg(id) from ref.fields_of_study where path ~ '^asced/[0-9]{2}$' and (
                  (path = 'asced/02' and v_name ~* '\y(IT|information technology|computing|computer|data science|cyber)\y')
               or (path = 'asced/03' and v_name ~* '\yengineering\y')
               or (path = 'asced/04' and v_name ~* '\y(architecture|built environment|building)\y')
               or (path = 'asced/06' and v_name ~* '\y(health|medicine|medical|nursing|pharmacy|dentistry|physiotherapy)\y')
               or (path = 'asced/07' and v_name ~* '\y(education|teaching)\y')
               or (path = 'asced/08' and v_name ~* '\y(business|commerce|accounting|finance|MBA|management|economics)\y')
               or (path = 'asced/09' and v_name ~* '\y(law|arts|humanities|social science|psychology)\y')
               or (path = 'asced/10' and v_name ~* '\y(creative|music|design|fine art|media)\y')
               or (path = 'asced/01' and v_name ~* '\yscience\y' and v_name !~* '\y(computer|data|social) science\y')));
  if v_fields is not null then v_why := v_why || 'the field named in the title'; end if;
  if jsonb_array_length(coalesce(v_levels, '[]'::jsonb)) > 0 or v_fields is not null then
    return jsonb_build_object('decision', 'filter', 'filter', jsonb_strip_nulls(jsonb_build_object('levels', v_levels, 'fields', v_fields)),
                              'why', 'The name points to ' || array_to_string(v_why, ' and ') || '.');
  end if;
  return jsonb_build_object('decision', 'all', 'filter', '{}'::jsonb, 'why', 'The name does not narrow it down; check the scholarship page before accepting all.');
end $$;
revoke all on function security.scholarship_scope_suggest(uuid) from public, anon, authenticated;

-- Apply a decision to every proposed link of the scholarship (re-deciding moves links it added; other links untouched).
create or replace function security.scholarship_scope_apply_v1(p_scholarship_id uuid, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d pipeline.scholarship_scope_decisions%rowtype; n_acc int := 0; n_rej int := 0; n_removed int := 0;
begin
  select * into d from pipeline.scholarship_scope_decisions where scholarship_id = p_scholarship_id;
  if d.scholarship_id is null then return jsonb_build_object('applied', false); end if;
  create temp table if not exists pg_temp._ssa(candidate_id uuid, course_id uuid, evidence_id uuid, status text, ok boolean) on commit drop;
  truncate pg_temp._ssa;
  insert into pg_temp._ssa select c.id, c.course_id, c.evidence_id, c.status, security.scholarship_scope_match(c.course_id, d.decision, d.filter)
    from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id
    join scholarship.scholarships s on s.id = c.scholarship_id
   where c.scholarship_id = p_scholarship_id and co.provider_id = s.provider_id;
  insert into scholarship.course_mappings(scholarship_id, course_id, mapping_state, mapping_basis, evidence_id, mapped_by)
  select p_scholarship_id, x.course_id, 'mapped', 'scope_decision:' || d.decision, x.evidence_id, p_actor from pg_temp._ssa x where x.ok
  on conflict (scholarship_id, course_id) do nothing;
  get diagnostics n_acc = row_count;
  delete from scholarship.course_mappings m using pg_temp._ssa x
   where m.scholarship_id = p_scholarship_id and m.course_id = x.course_id and not x.ok and m.mapping_basis like 'scope_decision:%';
  get diagnostics n_removed = row_count;
  update scholarship.course_mapping_candidates c set status = case when x.ok then 'accepted' else 'rejected' end, updated_at = now()
    from pg_temp._ssa x where c.id = x.candidate_id and c.status is distinct from case when x.ok then 'accepted' else 'rejected' end;
  select count(*) filter (where ok), count(*) filter (where not ok) into n_acc, n_rej from pg_temp._ssa;
  update pipeline.scholarship_scope_decisions set accepted = n_acc, rejected = n_rej, last_applied_at = now() where scholarship_id = p_scholarship_id;
  return jsonb_build_object('applied', true, 'accepted', n_acc, 'rejected', n_rej, 'removed', n_removed);
end $$;
revoke all on function security.scholarship_scope_apply_v1(uuid, uuid) from public, anon, authenticated;

-- Hourly: saved decisions applied to links proposed after the decision.
create or replace function security.scholarship_scope_apply_saved_v1() returns int language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in select distinct d.scholarship_id, d.decided_by from pipeline.scholarship_scope_decisions d
             join scholarship.course_mapping_candidates c on c.scholarship_id = d.scholarship_id and c.status = 'needs_review' loop
    perform security.scholarship_scope_apply_v1(r.scholarship_id, r.decided_by); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function security.scholarship_scope_apply_saved_v1() from public, anon, authenticated;

-- Read: list
create or replace function public.admin_scholarship_links_read(p_view text default 'waiting', p_q text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_decide', v_rank >= 4,
    'summary', (select jsonb_build_object('waiting_links', count(*) filter (where c.status = 'needs_review'),
                   'waiting_scholarships', count(distinct c.scholarship_id) filter (where c.status = 'needs_review'),
                   'decided_scholarships', (select count(*) from pipeline.scholarship_scope_decisions),
                   'accepted_links', count(*) filter (where c.status = 'accepted'), 'rejected_links', count(*) filter (where c.status = 'rejected'))
                  from scholarship.course_mapping_candidates c),
    'items', (select coalesce(jsonb_agg(x order by (x->>'waiting')::int desc, x->>'name'), '[]'::jsonb) from (
       select jsonb_build_object('scholarship_id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name),
              'award_type', s.award_value_type, 'award', coalesce(s.award_value_text, case when s.award_percentage is not null then s.award_percentage || '%' end,
                        case when s.award_amount is not null then s.award_currency_code || ' ' || s.award_amount end),
              'source_url', s.source_url, 'waiting', count(*) filter (where c.status = 'needs_review'), 'proposed', count(*),
              'accepted', count(*) filter (where c.status = 'accepted'),
              'decision', (select jsonb_build_object('decision', d.decision, 'at', d.decided_at, 'by', u.email, 'accepted', d.accepted, 'rejected', d.rejected)
                             from pipeline.scholarship_scope_decisions d left join auth.users u on u.id = d.decided_by where d.scholarship_id = s.id),
              'suggestion', security.scholarship_scope_suggest(s.id)) x
         from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id = c.scholarship_id
         left join catalogue.providers p on p.id = s.provider_id
        where (p_q is null or s.name ilike '%' || p_q || '%' or coalesce(p.display_name, p.canonical_name) ilike '%' || p_q || '%')
        group by s.id, s.name, p.display_name, p.canonical_name
       having case coalesce(p_view, 'waiting') when 'waiting' then count(*) filter (where c.status = 'needs_review') > 0
                                                 when 'decided' then exists (select 1 from pipeline.scholarship_scope_decisions d where d.scholarship_id = s.id)
                                                 else true end
        limit 300) y));
end $$;
revoke all on function public.admin_scholarship_links_read(text, text) from public, anon;
grant execute on function public.admin_scholarship_links_read(text, text) to authenticated;

-- Read: one scholarship with the breakdown and a preview of a filter
create or replace function public.admin_scholarship_links_detail(p_scholarship_id uuid, p_decision text default null, p_filter jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_s scholarship.scholarships%rowtype; v_dec text; v_f jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  select * into v_s from scholarship.scholarships where id = p_scholarship_id;
  if v_s.id is null then raise exception 'scholarship not found'; end if;
  select coalesce(p_decision, d.decision, sg->>'decision'), coalesce(p_filter, d.filter, sg->'filter') into v_dec, v_f
    from (select security.scholarship_scope_suggest(p_scholarship_id) sg) z left join pipeline.scholarship_scope_decisions d on d.scholarship_id = p_scholarship_id;
  return (with cc as (select c.id candidate_id, c.status, co.id course_id, coalesce(co.display_title, co.canonical_title) title, co.course_code,
                             co.study_level_id, security.broad_field_id(co.primary_field_id) field_id,
                             security.scholarship_scope_match(co.id, v_dec, v_f) ok
                        from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id
                       where c.scholarship_id = p_scholarship_id)
    select jsonb_build_object(
      'scholarship', jsonb_build_object('id', v_s.id, 'name', v_s.name, 'award', v_s.award_value_text, 'award_type', v_s.award_value_type,
                     'award_percentage', v_s.award_percentage, 'award_amount', v_s.award_amount, 'currency', v_s.award_currency_code,
                     'source_url', v_s.source_url, 'audience', v_s.audience, 'academic_year', v_s.academic_year,
                     'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_s.provider_id)),
      'proposed', (select count(*) from cc), 'waiting', (select count(*) from cc where status = 'needs_review'),
      'levels', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'count', n) order by l.sort_order), '[]'::jsonb)
                   from (select study_level_id, count(*) n from cc group by 1) g join ref.study_levels l on l.id = g.study_level_id),
      'fields', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'count', n) order by n desc), '[]'::jsonb)
                   from (select field_id, count(*) n from cc group by 1) g join ref.fields_of_study f on f.id = g.field_id),
      'suggestion', security.scholarship_scope_suggest(p_scholarship_id),
      'decision', (select jsonb_build_object('decision', d.decision, 'filter', d.filter, 'reason', d.reason, 'at', d.decided_at, 'by', u.email,
                          'accepted', d.accepted, 'rejected', d.rejected)
                     from pipeline.scholarship_scope_decisions d left join auth.users u on u.id = d.decided_by where d.scholarship_id = p_scholarship_id),
      'preview', jsonb_build_object('decision', v_dec, 'filter', v_f,
                   'matched', (select count(*) from cc where ok), 'not_matched', (select count(*) from cc where not ok),
                   'sample_matched', (select coalesce(jsonb_agg(jsonb_build_object('id', course_id, 'title', title, 'code', course_code)), '[]'::jsonb) from (select * from cc where ok order by title limit 12) a),
                   'sample_not_matched', (select coalesce(jsonb_agg(jsonb_build_object('id', course_id, 'title', title, 'code', course_code)), '[]'::jsonb) from (select * from cc where not ok order by title limit 8) b)),
      'can_decide', v_rank >= 4));
end $$;
revoke all on function public.admin_scholarship_links_detail(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_links_detail(uuid, text, jsonb) to authenticated;

-- Decide (Pipeline Operator and above)
create or replace function public.admin_scholarship_links_decide(p_scholarship_id uuid, p_decision text, p_filter jsonb default '{}'::jsonb, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_res jsonb; v_before jsonb; v_f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if p_decision not in ('all','filter','none') then raise exception 'choose all courses, only matching courses, or no courses'; end if;
  if p_decision = 'filter' and jsonb_array_length(coalesce(v_f->'levels', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_f->'fields', '[]'::jsonb)) = 0
     and nullif(btrim(coalesce(v_f->>'title', '')), '') is null and jsonb_array_length(coalesce(v_f->'courses', '[]'::jsonb)) = 0 then
    raise exception 'choose at least one study level, field, title word or course';
  end if;
  if not exists (select 1 from scholarship.course_mapping_candidates where scholarship_id = p_scholarship_id) then raise exception 'this scholarship has no proposed course links'; end if;
  select to_jsonb(d) into v_before from pipeline.scholarship_scope_decisions d where scholarship_id = p_scholarship_id;
  insert into pipeline.scholarship_scope_decisions(scholarship_id, decision, filter, reason, decided_by, decided_at)
  values (p_scholarship_id, p_decision, case when p_decision = 'filter' then v_f else '{}'::jsonb end, nullif(btrim(coalesce(p_reason, '')), ''), auth.uid(), now())
  on conflict (scholarship_id) do update set decision = excluded.decision, filter = excluded.filter, reason = excluded.reason,
         decided_by = excluded.decided_by, decided_at = now();
  v_res := security.scholarship_scope_apply_v1(p_scholarship_id, auth.uid());
  insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
  values ('scholarship_course_scope', 'scope_decision_' || p_decision, auth.uid(), jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_f, 'previous', v_before),
          coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Scholarship course links decided on the Course links screen'),
          coalesce((v_res->>'accepted')::int, 0) + coalesce((v_res->>'rejected')::int, 0), coalesce((v_res->>'accepted')::int, 0), v_res, 'CF-CHG-20260915-247');
  return public.admin_scholarship_links_detail(p_scholarship_id) || jsonb_build_object('result', v_res);
end $$;
revoke all on function public.admin_scholarship_links_decide(uuid, text, jsonb, text) from public, anon;
grant execute on function public.admin_scholarship_links_decide(uuid, text, jsonb, text) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('scholarship-scope-apply', 'Scholarships', 40, 'Apply scholarship course-link decisions',
  'Applies each saved scholarship decision (all courses, matching courses or none) to course links proposed after the decision.', 5, false)
on conflict (jobname) do nothing;
select cron.schedule('scholarship-scope-apply', '19 * * * *', 'select security.scholarship_scope_apply_saved_v1()');
