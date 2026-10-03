-- CF-247 (4 Oct 2026, 00:00 AEST). Platform Admin, 23:27 and 23:30: the live scholarship screens must match the
-- mockup. The reads and the one write behind the record drawer, the course drawer's scholarships and Scholarship
-- publishing now carry what the mockup shows; each existing function is replaced under an md5 guard on its live text.
--   A. Fix: the page-tier reader (Decision 245) checked hand locks under the wrong field names ('award', 'award_value');
--      a value entered by hand locks award_amount / award_percentage / award_value_type / award_value_text.
--   B. admin_scholarship_edit: 'set_audience' and 'set_nationalities' (kept as entered by hand; the hourly readers
--      leave them alone), and the result carries audience and nationalities.
--   C. admin_scholarship_record_read(id): the record drawer — value label and page words, tiers, who it is for and
--      nationalities with the matched phrases, how long, application, page, courses linked, status and held reasons,
--      values entered by hand, page last read, and the change history.
--   D. admin_course_scholarships: value label, nationalities, publication status and close date for each scholarship.
--   E. admin_scholarship_publishing_read_v1: the ready list shows the value label; counts and a list of published
--      scholarships that now fail a check (withdrawn at 06:17).
do $g$ declare v_oid oid; v_def text; v_old text; v_new text; begin
  -- A
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'scholarship_page_tier_candidates';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '994d9c4de7d9d1837b8a9d625b9df0d6' then raise exception 'scholarship_page_tier_candidates changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_old := $x$k.field in ('award', 'award_value')$x$;
  v_new := $x$k.field in ('award_amount', 'award_percentage', 'award_value_type', 'award_value_text')$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'A: lock fields not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);

  -- B
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admin_scholarship_edit';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '1e8c07f7235810fa7925d367ece9fac1' then raise exception 'admin_scholarship_edit changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_old := $x$  elsif p_action = 'release' then$x$;
  v_new := $x$  elsif p_action = 'set_audience' then
    v_field := 'audience';
    v_txt := btrim(coalesce(p_args->>'value', ''));
    if v_txt not in ('international', 'domestic', 'international_and_domestic', 'not_stated') then raise exception 'choose who the scholarship is for'; end if;
    v_before := to_jsonb(v_s.audience);
    update scholarship.scholarships set audience = v_txt, updated_at = now() where id = p_scholarship_id;
    perform security.manual_lock_set('scholarship', p_scholarship_id, 'audience', 'value');
    v_after := to_jsonb(v_txt);
  elsif p_action = 'set_nationalities' then
    v_field := 'nationalities';
    if jsonb_typeof(p_args->'value') is distinct from 'array' then raise exception 'give a list of nationalities'; end if;
    if exists (select 1 from jsonb_array_elements_text(p_args->'value') c where not exists (select 1 from ref.nationality_terms t where t.code = c)) then raise exception 'unknown nationality'; end if;
    v_before := to_jsonb(v_s.nationalities);
    update scholarship.scholarships set nationalities = coalesce((select array_agg(distinct c order by c) from jsonb_array_elements_text(p_args->'value') c), '{}'), updated_at = now() where id = p_scholarship_id;
    perform security.manual_lock_set('scholarship', p_scholarship_id, 'nationalities', 'value');
    v_after := p_args->'value';
  elsif p_action = 'release' then$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'B: release branch not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $x$'source_url', s.source_url, 'locks',$x$;
  v_new := $x$'source_url', s.source_url, 'audience', s.audience, 'nationalities', s.nationalities, 'value_label', scholarship.value_label(s.id), 'locks',$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'B: result object not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);

  -- D
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_course_scholarships';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'f4f6a010181049c35283bb072a4b7e30' then raise exception 'admin_course_scholarships changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_old := $x$'mapping_id',m.id,'scholarship_id',s.id,'name',s.name,'audience',s.audience,$x$;
  v_new := $x$'mapping_id',m.id,'scholarship_id',s.id,'name',s.name,'audience',s.audience,
   'value_label',scholarship.value_label(s.id),'nationalities',s.nationalities,'publication_status',s.publication_status,
   'lifecycle_status',s.lifecycle_status,'application_close_date',s.application_close_date,$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'D: item object not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);

  -- E
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_scholarship_publishing_read_v1';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'f21f413bfeff5ac2479df06e5258036f' then raise exception 'admin_scholarship_publishing_read_v1 changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_old := $x$         'value',case when s.award_value_is_maximum then 'Up to ' else '' end||case s.award_value_type when 'percentage' then round(s.award_percentage)::text||'% of tuition' when 'fixed_amount' then 'A$'||to_char(s.award_amount,'FM999,999,999') end,$x$;
  v_new := $x$         'value',scholarship.value_label(s.id),$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'E: value expression not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $x$       'active',(select count(*) from scholarship.scholarships where lifecycle_status='active')),$x$;
  v_new := $x$       'active',(select count(*) from scholarship.scholarships where lifecycle_status='active'),
       'published_failing',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.publication_status='published' and not p.publishable)),
    'published_failing',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,'reason',array_to_string(p.missing,'; ')) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published' and not p.publishable),$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'E: counts not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $g$;

-- C. the record drawer
create or replace function public.admin_scholarship_record_read(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return (
    with pub as (select * from security.scholarship_publishability_v1() x where x.scholarship_id = p_id)
    select jsonb_build_object(
      'id', s.id, 'name', s.name, 'provider_id', s.provider_id, 'provider', coalesce(pr.display_name, pr.canonical_name),
      'can_edit', v_rank >= 3,
      'status', case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce((select publishable from pub), false) then 'ready' else 'held' end,
      'held_reasons', coalesce((select missing from pub), '{}'::text[]),
      'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
      'value_label', scholarship.value_label(s.id), 'page_words', s.award_value_text,
      'award_amount', s.award_amount, 'award_percentage', s.award_percentage, 'award_value_type', s.award_value_type, 'is_maximum', s.award_value_is_maximum,
      'tiers', (select coalesce(jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code) order by t.display_order), '[]'::jsonb) from scholarship.award_tiers t where t.scholarship_id = s.id),
      'audience', s.audience,
      'audience_phrase', (select coalesce(a.phrase_both, nullif(concat_ws(' + ', a.phrase_international, a.phrase_domestic), '')) from scholarship.audience_readings a where a.scholarship_id = s.id),
      'nationalities', s.nationalities,
      'nationality_phrases', (select r.phrases from scholarship.nationality_readings r where r.scholarship_id = s.id),
      'nationality_terms', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', split_part(t.names, '|', 1)) order by t.region, split_part(t.names, '|', 1)) from ref.nationality_terms t),
      'duration_basis', s.award_duration_basis,
      'application_required', s.application_required, 'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date,
      'page', s.source_url,
      'page_read_at', (select sp.read_at from pipeline.scholarship_pages sp where sp.scholarship_id = s.id),
      'courses', (select count(*) from scholarship.course_mappings m where m.scholarship_id = s.id and m.mapping_state = 'mapped'),
      'criteria', (select coalesce(jsonb_agg(to_jsonb(cr) order by cr.criterion_type), '[]'::jsonb) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
      'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'reason', h.reason) order by h.at desc), '[]'::jsonb)
                    from (select * from pipeline.manual_edit_log l where l.entity = 'scholarship' and l.entity_id = s.id order by l.at desc limit 10) h))
    from scholarship.scholarships s left join catalogue.providers pr on pr.id = s.provider_id where s.id = p_id);
end $f$;
revoke all on function public.admin_scholarship_record_read(uuid) from public, anon;
grant execute on function public.admin_scholarship_record_read(uuid) to authenticated;
