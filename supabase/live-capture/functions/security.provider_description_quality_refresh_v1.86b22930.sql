CREATE OR REPLACE FUNCTION security.provider_description_quality_refresh_v1(p_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ids uuid[]; v_total bigint; v_n int; v_by jsonb;
begin
  if p_ids is null then
    select coalesce(array_agg(x.id), array[]::uuid[]) into v_ids from (
      select p.id from catalogue.providers p) x;
  else
    select coalesce(array_agg(x.id), array[]::uuid[]) into v_ids from (select distinct i id from unnest(p_ids) i) x;
  end if;
  select count(*) into v_total from catalogue.providers;
  insert into pipeline.provider_description_quality as t(provider_id, quality_class, description_present, admission_state, source_tier, reader_state, reader_rule, l4_status, hold_reason, next_retry_at, last_read_ok_at,
                                                         admitted_at, website_state, zoho_state, website_publication, zoho_publication, readback_at, missing_fields, class_since, computed_at)
  select q.provider_id, q.quality_class, q.description_filled, q.admission_state, q.source_tier, q.reader_state, q.reader_rule, q.l4_status, q.hold_reason, q.next_retry_at, q.last_read_ok_at,
         q.admitted_at, q.website_state, q.zoho_state, q.website_publication, q.zoho_publication, q.readback_at, coalesce(q.missing_fields, '{}'), now(), now()
    from security.provider_description_quality_v1(v_ids, true) q where q.quality_class is not null
  on conflict (provider_id) do update set
    quality_class = excluded.quality_class, description_present = excluded.description_present, admission_state = excluded.admission_state, source_tier = excluded.source_tier,
    reader_state = excluded.reader_state, reader_rule = excluded.reader_rule, l4_status = excluded.l4_status, hold_reason = excluded.hold_reason, next_retry_at = excluded.next_retry_at,
    last_read_ok_at = excluded.last_read_ok_at, admitted_at = excluded.admitted_at, website_state = excluded.website_state, zoho_state = excluded.zoho_state,
    website_publication = excluded.website_publication, zoho_publication = excluded.zoho_publication, readback_at = excluded.readback_at, missing_fields = excluded.missing_fields,
    class_since = case when t.quality_class is distinct from excluded.quality_class then now() else t.class_since end, computed_at = now();
  get diagnostics v_n = row_count;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_by from (select quality_class k, count(*) n from pipeline.provider_description_quality where provider_id = any(v_ids) group by 1) z;
  return jsonb_build_object('refreshed', v_n, 'asked', cardinality(v_ids), 'providers_total', v_total, 'by_class', v_by, 'as_at', now());
end
$function$
