CREATE OR REPLACE FUNCTION security.scholarship_audience_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_changed int := 0; v_read int := 0; v_counts jsonb;
  c_intl constant text := '\m(international students?|overseas students?|student visa|subclass 500|onshore|offshore|citizens? of (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|cambodia|kenya|nigeria|colombia|brazil|mexico|chile|peru|hong kong|singapore|japan|korea|taiwan|turkey|saudi|uae|iran|iraq|egypt|ghana|south africa|canada|usa|united states|uk|united kingdom|germany|france|italy|spain)|from (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|latin america|africa|asia|europe|the americas)|full[- ]fee[- ]paying international|global excellence|international (merit|excellence|academic))\M';
  c_dom constant text := '\m(domestic students?|australian citizens?|australian permanent residents?|permanent residen(t|cy) of australia|commonwealth supported|csp|hecs|fee[- ]help|home students?|new zealand citizens?|humanitarian visa|aboriginal|torres strait|indigenous|first nations)\M';
  c_dom_nz constant text := '\m(domestic students?|new zealand citizens?|new zealand permanent residents?|permanent residen(t|cy) of new zealand|australian citizens?|home students?|fees[- ]free|studylink|student allowance|maori|māori|pasifika)\M';
  c_dom_ca constant text := '\m(domestic students?|canadian citizens?|canadian permanent residents?|permanent residents? of canada|protected persons?|indigenous|first nations|métis|metis|inuit|osap|canada student (loans?|grants?)|residents? of (british columbia|alberta|ontario|quebec|québec|manitoba|saskatchewan|nova scotia|new brunswick))\M';
  c_both constant text := '\m(all students|domestic and international|international and domestic|regardless of (citizenship|residency|nationality)|open to all)\M';
begin
  with t as (
    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt,
           (select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id = pp.country_id where pp.id = s.provider_id) cc
      from scholarship.scholarships s where s.lifecycle_status = 'active'),
  r as (
    select t.id, substring(t.txt from c_intl) p_intl, substring(t.txt from case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca when 'AU' then c_dom else coalesce((select '\m(' || o.domestic_terms || ')\M' from scholarship.country_onboarding o where o.country_code = t.cc and coalesce(o.domestic_terms, '') <> ''), c_dom) end) p_dom, substring(t.txt from c_both) p_both from t),
  v as (
    select r.id, case when r.p_both is not null or (r.p_intl is not null and r.p_dom is not null) then 'international_and_domestic'
                      when r.p_intl is not null then 'international' when r.p_dom is not null then 'domestic' else 'not_stated' end audience,
           r.p_intl, r.p_dom, r.p_both from r),
  up as (
    insert into scholarship.audience_readings(scholarship_id, audience, phrase_international, phrase_domestic, phrase_both, reader_version, read_at)
    select v.id, v.audience, v.p_intl, v.p_dom, v.p_both, 'scholarship-audience-v1', now() from v
    on conflict (scholarship_id) do update set audience = excluded.audience, phrase_international = excluded.phrase_international, phrase_domestic = excluded.phrase_domestic, phrase_both = excluded.phrase_both, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id)
  select count(*) into v_read from up;
  update scholarship.scholarships s set audience = a.audience, updated_at = now() from scholarship.audience_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.audience is distinct from a.audience and not security.scholarship_from_record_register(s.id) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'audience');
  get diagnostics v_changed = row_count;
  select jsonb_object_agg(x.audience, x.n) into v_counts from (select a.audience, count(*) n from scholarship.audience_readings a group by 1) x;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'audience_read', 'Audience read from each scholarship''s wording', jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts, 'decision', 'Decision 244'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts);
end $function$
