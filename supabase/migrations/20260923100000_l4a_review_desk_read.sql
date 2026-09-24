-- L4-A: enriched Layer 4 review desk read (additive; the existing queue is unchanged).
-- Gives operators what they need to decide without leaving the screen: course and
-- provider names, a plain task label, age, what is recorded now, what the AI suggested
-- (as readable text), the exact words the page shows, links, and a rule-based
-- suggestion (never applied automatically). Raw IDs and values move to "technical".
-- Same access rule as layer4_review_queue: signed in, curator role (3) or above.

create or replace function security.layer4_money_text(p jsonb)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  select case when p is null or jsonb_typeof(p)<>'object' or nullif(p->>'amount','') is null then null else
    concat_ws(' · ',
      case upper(coalesce(p->>'currency_code',p->>'currency','')) when 'AUD' then 'A$' when 'NZD' then 'NZ$' else coalesce(nullif(upper(coalesce(p->>'currency_code',p->>'currency','')),'')||' ','') end
        || to_char((p->>'amount')::numeric,'FM999,999,999')
        || case lower(coalesce(p->>'basis','')) when 'annual' then ' per year' when 'indicative_annual' then ' per year (indicative)' when 'per_year_explicit' then ' per year'
             when 'annual_or_indicative_requires_validation' then ' (frequency not confirmed)' when '' then '' else ' ('||replace(p->>'basis','_',' ')||')' end,
      nullif(p->>'fee_year',''),
      nullif(lower(p->>'audience'),''))
  end
$f$;

create or replace function security.layer4_clean_quote(q text)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  -- "Fees[A$60952](https://...)Duration" -> "Fees A$60952 Duration"
  select nullif(btrim(regexp_replace(regexp_replace(coalesce(q,''), '\[([^\]]*)\]\([^)]*\)', ' \1 ', 'g'), '\s+', ' ', 'g')),'')
$f$;

create or replace function security.layer4_url_query(t text)
returns text language sql immutable set search_path to 'pg_catalog' as $f$
  select replace(replace(replace(replace(replace(replace(btrim(coalesce(t,'')),'%','%25'),'&','%26'),'+','%2B'),'#','%23'),'/','%2F'),' ','+')
$f$;

create or replace function security.layer4_review_desk_v1_impl(p_status text default 'pending', p_limit integer default 250)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','auth'
as $function$
declare v_items jsonb; v_summary jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;

  with base as (
    select r.*, c.id course_id, coalesce(nullif(c.display_title,''),c.canonical_title) course_title, c.course_code, c.course_url,
           coalesce(nullif(p.display_name,''),p.canonical_name,nullif(p2.display_name,''),p2.canonical_name) provider_name, coalesce(p.id,p2.id) provider_id,
           e.source_url page_url, e.captured_at page_captured_at,
           i.evidence_quotes, i.confidence ai_confidence,
           lower(coalesce((select string_agg(security.layer4_clean_quote(q),' ') from jsonb_array_elements_text(coalesce(i.evidence_quotes,'[]'::jsonb)) q),'')) quotes_text,
           (select security.layer4_money_text(jsonb_build_object('amount',f.amount,'currency_code',f.currency_code,'basis',f.basis,'fee_year',f.fee_year,'audience',f.audience))
              from catalogue.course_fees f where r.entity_type='course' and f.course_id=r.entity_id and f.fee_type='provider_current_tuition' and f.status='active'
              order by f.fee_year desc nulls last limit 1) recorded_fee
    from pipeline.layer4_review_items r
    left join catalogue.courses c on r.entity_type='course' and c.id=r.entity_id
    left join catalogue.providers p on p.id=c.provider_id
    left join catalogue.providers p2 on r.entity_type='provider' and p2.id=r.entity_id
    left join pipeline.evidence_artifacts e on e.id=r.evidence_id
    left join pipeline.layer3_interpretations i on i.id=r.layer3_interpretation_id
    where (p_status is null or p_status='' or r.status=p_status)
    order by r.created_at asc
    limit least(greatest(coalesce(p_limit,250),1),500)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'status', b.status, 'field_code', b.field_code,
    'task', case b.field_code when 'provider_current_tuition_validation' then 'Tuition fee' when 'official_course_url' then 'Official course link'
              when 'scope_resolution' then 'Scope' else initcap(replace(b.field_code,'_',' ')) end,
    'created_at', b.created_at, 'decided_at', b.decided_at, 'assigned_to', b.assigned_to,
    'age_days', floor(extract(epoch from now()-b.created_at)/86400)::int,
    'reason', case
      when b.escalation_reason is null then null
      when b.escalation_reason ~* '(firecrawl|zenrows|gatekeeper|governed layer|discovery exhausted|deterministic|fall-?out)' then
        case b.field_code
          when 'official_course_url' then 'We couldn''t find this course''s official page automatically. Find it on the provider''s website and add the link.'
          when 'scope_resolution' then 'We couldn''t tell automatically which provider or course this belongs to. Please check and confirm.'
          when 'provider_current_tuition_validation' then 'We couldn''t confirm this fee automatically. Please check the page and confirm the fee.'
          else 'This couldn''t be resolved automatically. Please check and decide.' end
      else b.escalation_reason end,
    'search_url', 'https://www.google.com/search?q='||security.layer4_url_query(concat_ws(' ',b.course_title,b.course_code,b.provider_name,case b.field_code when 'provider_current_tuition_validation' then 'international fees' else 'course' end)),
    'entity', jsonb_build_object('type',b.entity_type,'title',b.course_title,'code',b.course_code,'provider',b.provider_name,'provider_id',b.provider_id),
    'recorded', case when b.field_code='provider_current_tuition_validation' then coalesce(b.recorded_fee,'No fee recorded') else null end,
    'ai_suggested', coalesce(security.layer4_money_text(b.proposed_value), case when b.proposed_value is not null and jsonb_typeof(b.proposed_value)='string' then b.proposed_value#>>'{}' end),
    'page_quote', (select security.layer4_clean_quote(q) from jsonb_array_elements_text(coalesce(b.evidence_quotes,'[]'::jsonb)) q limit 1),
    'links', jsonb_build_object('page_url',b.page_url,'page_captured_at',b.page_captured_at,'course_url',b.course_url,'evidence_id',b.evidence_id),
    'suggestion', case
      when b.field_code<>'provider_current_tuition_validation' then jsonb_build_object('action','check','text','Check the page, then decide.')
      when b.quotes_text ~ '\m(total|whole course|full course|entire course)\M' then jsonb_build_object('action','reject','text','The page shows this amount as a course total, not a yearly fee.')
      when b.quotes_text ~ '\m(per semester|per trimester|per unit|per credit|per subject)\M' then jsonb_build_object('action','reject','text','The page shows this amount per semester or per unit, not per year.')
      when b.quotes_text ~ '\m(annual|annually|per year|per annum|a year|yearly)\M' then jsonb_build_object('action','approve','text','The page shows this amount as a yearly fee.')
      when b.quotes_text='' then jsonb_build_object('action','check','text','The AI could not quote this fee from the page. Check the page.')
      else jsonb_build_object('action','check','text','The page does not say how often this fee is charged. Check the page.') end,
    'technical', jsonb_build_object('original_reason',b.escalation_reason,'entity_id',b.entity_id,'evidence_id',b.evidence_id,'layer3_interpretation_id',b.layer3_interpretation_id,
      'ai_confidence',b.ai_confidence,'before_value',b.before_value,'proposed_value',b.proposed_value,'layer2_state',b.layer2_state,'layer3_state',b.layer3_state,'change_control_ref',b.change_control_ref)
  ) order by b.created_at asc),'[]'::jsonb) into v_items from base b;

  select jsonb_build_object(
    'waiting',(select count(*) from pipeline.layer4_review_items where status='pending'),
    'oldest_days',(select floor(extract(epoch from now()-min(created_at))/86400)::int from pipeline.layer4_review_items where status='pending'),
    'target_days',7,
    'by_task',(select coalesce(jsonb_object_agg(t,n),'{}'::jsonb) from (select case field_code when 'provider_current_tuition_validation' then 'Tuition fee' when 'official_course_url' then 'Official course link' when 'scope_resolution' then 'Scope' else initcap(replace(field_code,'_',' ')) end t, count(*) n from pipeline.layer4_review_items where status='pending' group by 1) x)
  ) into v_summary;

  return jsonb_build_object('items',v_items,'summary',v_summary);
end $function$;

create or replace function public.layer4_review_desk_v1(p_status text default 'pending', p_limit integer default 250)
returns jsonb language sql stable set search_path to 'pg_catalog','security'
as $function$ select security.layer4_review_desk_v1_impl(p_status,p_limit) $function$;

revoke all on function security.layer4_review_desk_v1_impl(text,integer) from public, anon;
revoke all on function public.layer4_review_desk_v1(text,integer) from public, anon;
grant execute on function security.layer4_review_desk_v1_impl(text,integer) to authenticated, service_role;
grant execute on function public.layer4_review_desk_v1(text,integer) to authenticated, service_role;
revoke all on function security.layer4_money_text(jsonb) from public, anon;
revoke all on function security.layer4_clean_quote(text) from public, anon;
revoke all on function security.layer4_url_query(text) from public, anon;
grant execute on function security.layer4_clean_quote(text) to authenticated, service_role;
grant execute on function security.layer4_url_query(text) to authenticated, service_role;
grant execute on function security.layer4_money_text(jsonb) to authenticated, service_role;
