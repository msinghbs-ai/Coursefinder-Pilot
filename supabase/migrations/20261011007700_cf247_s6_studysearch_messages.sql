-- CF-247 v2.15.241 (S6): the platform is renamed StudySearch (customer request, 11 Oct 2026; the repositories keep their names until
-- production). Every database message and label people see that said "CourseFinder" now says "StudySearch" ("StudySearch role
-- required", credential labels, reader names). Only that word changes in each function; identifiers, setting names, secret names and
-- the Wix and Zoho contract names (lowercase coursefinder_...) are unchanged. md5-checked before and after; nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('pipeline.svc_layer2_provider_probe_start(text, text, text)', '99ea0b4652fa3b6adc00a0897b32a278', 'public.admin_catalogue_edit_rows(text, uuid[])', '25ccf17fb2764a106a75ecf9397d7ea8', 'public.admin_course_edit_read(uuid)', '81a45c663e11be9943804c8cc1e42a04', 'public.admin_course_links_read(uuid)', 'a5500063ca996745985996573a95b4f6', 'public.admin_fee_rule_preview(uuid, text, text)', 'e67ef20adb3a6de574f7c5911d12024b', 'public.admin_fee_rules_read()', '909b03179fc6bf0e371bff14a7c9330f', 'public.admin_key_dates_read()', 'd699869c06bd8c3b10988c1b4c9c0c32', 'public.admin_link_refresh_read()', '41015bbb7778c0afeb95635508251904', 'public.admin_platform_notices_read(integer)', 'a3bf8c86866df37c9a402c9ad777c8f3', 'public.admin_provider_applicants_read(uuid)', '04a59f69ce2108fc907a09138cd098e0', 'public.admin_provider_edit_read(uuid)', 'c09d51ed8c463712b05f3842dc5f98d9', 'public.admin_reference_source_save(uuid, jsonb, text)', '25b8ae71d7fc57e7a75f83afda223a8b', 'public.admin_reference_sources_read()', '5760b7ad4df0b76d2dea54b9b56d3fe4', 'public.admin_scholarship_layer_read(integer)', '979a3f527299b6a848a64a93c808e3e3', 'public.admin_scholarship_links_detail(uuid, text, jsonb)', 'ceb8e3c51a144ef21afa12bd5157f9b0', 'public.admin_scholarship_links_read(text, text)', 'a96d709e000f286df47f1670937bb2bc', 'public.admin_scholarship_record_read(uuid)', '2f40a0a80a09044f361f198ec15bc436', 'public.admin_search_pass_read()', '4006e02774af985b6b314f0d3288be44', 'public.admin_toolset_samples_read(uuid)', '7c1ffb7d291fcc69c120d51296f60333', 'public.admin_toolsets_read()', '4bf84bcb9655e2afafeff7c00554c254', 'public.admin_value_note_add(uuid, text, text)', '60d503c45b29520f7c5f0baed4d9d861', 'public.admin_waiting_read()', 'c952e2b37d7be20d2e2f626b475c9cc9', 'public.layer2_provider_control(uuid, text, jsonb)', 'd0aaf565d29869382d93564a497b63b2', 'public.layer2_scale_qualification_prepare(uuid)', 'cdda6ea13c420723a15c56f38ddd1ad8', 'public.platform_environment_control_service(uuid, text, jsonb)', 'e83bcd3050011ddd55747eae7ca540ea', 'public.svc_admin_access_replace_roles(uuid, uuid, text[], timestamp with time zone)', 'fa0b96b23e684efc4580090cf0af50ab', 'public.ui_courses_decision_page(integer, integer, text, text, text, uuid, text, text, text, text, text, boolean, boolean, boolean, boolean, numeric, text, text, text, boolean, boolean, text)', 'bf909941b162a8923bbecd37a056703d', 'public.ui_prisms_student_flow_page(integer, integer, text, text, text, text, text, boolean, text, text)', 'e55eb94d3ed877e0ce0b37502b3d449c', 'public.ui_qilt_outcomes_page(integer, integer, text, text, text, uuid, text, integer, text, text)', 'de0d9c060c2d9b3b2bd785a119debd61', 'public.ui_scholarships_page(integer, integer, text, text, text, text, text, text)', '69da2a485bc032421ec18d81abf9d08b', 'security.admin_a15_acceptance_status()', 'd218e30cca616f86c1686734c926f23d', 'security.admin_automations_read_v1()', '75f43933df9b3cce00ae6963b9000fc1', 'security.admin_campus_detail(uuid)', '270e2a94a32175ca054ca4e6bad54b51', 'security.admin_campus_page_fast(jsonb)', '65c5228f0d43c64aef2f521d4ab9541f', 'security.admin_catalogue_filter_options(text, jsonb)', '85ee60dc774e4ca3c19e40065a491103', 'security.admin_catalogue_filter_page(jsonb)', '95aa0ab65f634ddc11c931affa462b18', 'security.admin_catalogue_page(text, jsonb)', '15cc21b80caaf2f51242c7632605cf98', 'security.admin_course_coverage_read(text, jsonb)', '121833022b10e6cf2581814fe3f08099', 'security.admin_course_entry_summary(uuid)', '2f22b400a0eb52d7788c98ab73aac82d', 'security.admin_course_fee_summary(uuid)', 'eeb8fd0961c6021a5fec21f16c1a3a84', 'security.admin_course_field_states(uuid)', 'f52fdc23bfd1f61818bafb76fa6ee8c5', 'security.admin_course_page_fast(jsonb)', '4ee13eecae8e4e8cfa637363eedd5f63', 'security.admin_course_page_fast_base(jsonb)', '3296eb130f6c3d6603e370fd2df06651', 'security.admin_course_page_search_state(jsonb)', 'e449dc9cd88327870ff28e81148c3905', 'security.admin_course_page_unfiltered_fast(jsonb)', '537c480c080c2dbf95ef037d22834517', 'security.admin_course_rankings(uuid, integer)', '1574faf9eddbd68998e6bea779e90f9f', 'security.admin_course_scholarships(uuid)', '3766e3b7d8f9e2fe96fe583ca80efdfa', 'security.admin_course_state_summary(uuid)', 'bb19c0f600b913741acdcb51a03b867c', 'security.admin_course_taxonomy_summary(uuid)', '1f5d37a2ac723a9d14e27789b3502543', 'security.admin_dashboard_maturity()', '142d79d46675d55e6124cb6e4f729103', 'security.admin_data_flags_read_v1(jsonb)', '868fecb2fe4f559454230dfe1d4aefce', 'security.admin_data_quality_read(text, jsonb)', 'd0b26394620841fe2c099c201a863921', 'security.admin_filter_option_page(jsonb)', '78e090691304cf0f89150f97e5914e02', 'security.admin_insights_read(text, jsonb)', '820e32092da90202f1a6276102c5709e', 'security.admin_layer3_control_read_v1()', 'aac5fce002eb745059ad43611f826b0c', 'security.admin_layer_status_summary()', '180d056a61ade41e865ff52efa7a2976', 'security.admin_live_activity_v1()', '8aae7dbbf161d3d4ef46b5823c5841bc', 'security.admin_priority_read_v1()', 'e0550d6998163ea2a64984260951bed2', 'security.admin_priority_search_v1(text, text)', '2e205561bdfbd8f46cf25e83ccdef430', 'security.admin_provider_asset_read(text, jsonb)', 'a7c2c058eebe70f4f83f59f9fcb1c860', 'security.admin_provider_contact_read(text, jsonb)', '7d2c857e20207c2f593f6624ac3c9b8f', 'security.admin_provider_contacts(uuid)', '02c9308c17ba68daea1a3ebbb4e8704c', 'security.admin_provider_detail(uuid)', 'ef03c4963292cecc17836b69b32653cb', 'security.admin_provider_identity_quality_summary()', '0cf0daebb5ae46486ab1a0a89ea19cb7', 'security.admin_provider_rankings(uuid, integer)', '38ab463000b3dee3aafac1bf3600ce3a', 'security.admin_provider_scholarships(uuid)', 'b28613c27e89db09418a87b4fcf71509', 'security.admin_providers_page(integer, integer, text, text, text, text, text, text, text, text)', 'ec1d5153b018a9da3483a8292414143d', 'security.admin_publication_overview()', '901c5dbcf7520804a3d2083e10c5d349', 'security.admin_ranking_links_read(text, jsonb)', 'ffde81d599044a3a5849db6e7b6ff284', 'security.admin_ranking_read(text, jsonb)', '57b8f89e8250750544497e933fe8dee3', 'security.admin_read_impl(text, jsonb)', '453548ac1d4199d2e2dbdc286e277ff2', 'security.admin_requeue_read_v1()', 'fbf8afe75caebbaea72ef6f2235985ae', 'security.admin_scholarship_publishing_read_v1()', '0adc3e353240fcda3300ff636bcfa34d', 'security.admin_scholarship_semantic_summary(uuid)', '9663678593d725b239519753d274f261', 'security.admin_scholarships_page(jsonb)', '520204c37aba99d872b8b8bf1e7bc6fa', 'security.admin_source_comparison_read_v1(text, uuid)', '008f128c855d1a6bb838e01fdd85fa5d', 'security.course_link_reverse_tick_v1(integer)', '2bc0be6820440f8f9bf2fd6d5504ab42', 'security.layer3_provider_credential_set_impl(uuid, uuid, text, text)', '9e7708fcf06759635f10c06431d1ce0a', 'security.platform_notices_v1()', '942d7dc610bc3ef4c532ba2138721290', 'security.provider_contact_disposition_current(uuid)', 'b95b73cf912ba1f58d5c4f7ce4209c16', 'security.scholarship_selection_for_course_browser_bridge(uuid)', 'c4334a8c31952320444701a55e8df59c', 'security.scholarship_selection_for_provider_browser_bridge(uuid)', '67c609ba8c5f08ba5c2556fadcf4965f');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION pipeline.svc_layer2_provider_probe_start(p_profile_key text, p_provider_key text, p_target_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'vault', 'net', 'public'
AS $function$
declare v_cfg jsonb;v_provider record;v_secret text;v_host text;v_allowed boolean:=false;v_req bigint;v_url text;v_params jsonb:='{}';v_body jsonb:='{}';v_headers jsonb:='{}';begin
 select v.configuration into v_cfg from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.profile_key=p_profile_key and p.enabled and not p.paused and v.validation_status='valid';
 if v_cfg is null then raise exception 'executable source profile not found';end if;
 v_host:=lower(split_part(split_part(p_target_url,'://',2),'/',1));if v_host='' then raise exception 'invalid target url';end if;
 select exists(select 1 from jsonb_array_elements_text(coalesce(v_cfg->'url_patterns','[]'::jsonb)) x where lower(split_part(split_part(x,'://',2),'/',1))=v_host or v_host like '%.'||lower(split_part(split_part(x,'://',2),'/',1))) or lower(split_part(split_part(coalesce(v_cfg->>'base_domain',''),'://',2),'/',1))=v_host into v_allowed;
 if not v_allowed then raise exception 'target url outside source profile boundary';end if;
 select p.* into v_provider from pipeline.layer2_acquisition_providers p join pipeline.layer2_profile_provider_routes r on r.acquisition_provider_id=p.id join pipeline.layer2_source_profiles sp on sp.id=r.profile_id where sp.profile_key=p_profile_key and p.provider_key=p_provider_key and p.enabled and r.enabled;
 if not found then raise exception 'provider is not an enabled route for profile';end if;
 if v_provider.auth_scheme<>'none' then select decrypted_secret into v_secret from vault.decrypted_secrets where id=v_provider.vault_secret_id;if v_secret is null then raise exception 'provider credential missing';end if;end if;
 if v_provider.adapter_type='direct_http' then v_req:=net.http_get(p_target_url,'{}',jsonb_build_object('User-Agent','StudySearch Layer2 bounded probe/1.1'),least(v_provider.timeout_seconds*1000,120000));
 elsif v_provider.provider_key='firecrawl' then v_body:=coalesce(v_provider.request_template->'static_body','{}')||jsonb_build_object(coalesce(v_provider.request_template->>'target_url_field','url'),p_target_url);v_headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_secret);v_req:=net.http_post(v_provider.base_url,v_body,'{}',v_headers,least(v_provider.timeout_seconds*1000,120000));
 else v_url:=v_provider.base_url;v_params:=coalesce(v_provider.request_template->'static_query','{}')||jsonb_build_object(coalesce(v_provider.request_template->>'target_url_parameter','url'),p_target_url);if v_provider.auth_scheme='query_param' then v_params:=v_params||jsonb_build_object(coalesce(v_provider.auth_field_name,'token'),v_secret);elsif v_provider.auth_scheme='bearer' then v_headers:=jsonb_build_object('Authorization','Bearer '||v_secret);elsif v_provider.auth_scheme='header' then v_headers:=jsonb_build_object(coalesce(v_provider.auth_field_name,'X-API-Key'),v_secret);end if;v_req:=net.http_get(v_url,v_params,v_headers,least(v_provider.timeout_seconds*1000,120000));end if;
 insert into pipeline.layer2_provider_probe_requests(request_id,profile_key,provider_key,target_url) values(v_req,p_profile_key,p_provider_key,p_target_url);
 return jsonb_build_object('ok',true,'request_id',v_req,'profile_key',p_profile_key,'provider_key',p_provider_key,'queued_at',now());
end$function$;

CREATE OR REPLACE FUNCTION public.admin_catalogue_edit_rows(p_type text, p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 100 then raise exception 'at most 100 rows at a time'; end if;
  if p_type = 'course' then
    return jsonb_build_object('can_edit', v_rank >= 3,
      'english_tests', (select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name) order by t.code), '[]'::jsonb)
                          from ref.english_tests t where t.status = 'active'),
      'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'display_title', coalesce(c.display_title, c.canonical_title),
        'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'official_url', coalesce((select l.url from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course'
                                    and l.status = 'active' order by l.is_primary desc, l.updated_at desc limit 1), c.course_url),
        'tuition', (select jsonb_build_object('amount', f.amount, 'fee_year', f.fee_year, 'basis', f.basis, 'currency', f.currency_code)
                      from catalogue.course_fees f where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
                     order by f.fee_year desc nulls last, f.updated_at desc limit 1),
        'intakes', (select coalesce(jsonb_agg(jsonb_build_object('label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date)
                                     order by i.intake_year nulls last, i.start_date nulls last, i.intake_label), '[]'::jsonb)
                      from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active'),
        'english', (select coalesce(jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)
                                     order by t.code), '[]'::jsonb)
                      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                     where e.course_id = c.id and e.status = 'active'),
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.courses c where c.id = any(p_ids)));
  elsif p_type = 'provider' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
        'display_name', coalesce(p.display_name, p.canonical_name), 'primary_city', p.primary_city, 'website', p.website,
        'phone', p.phone, 'email', p.email,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p.id))), '{}'::jsonb)
      from catalogue.providers p where p.id = any(p_ids)));
  elsif p_type = 'campus' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'name', c.name, 'address_line1', c.address_line1, 'city', c.city, 'postcode', c.postcode, 'phone', c.phone, 'website', c.website,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'campus' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.campuses c where c.id = any(p_ids)));
  elsif p_type = 'scholarship' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(s.id, jsonb_build_object(
        'name', s.name, 'award_value_text', s.award_value_text, 'award_amount', s.award_amount, 'award_percentage', s.award_percentage,
        'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date, 'source_url', s.source_url,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id))), '{}'::jsonb)
      from scholarship.scholarships s where s.id = any(p_ids)));
  end if;
  raise exception 'unknown list %', p_type;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_course_edit_read(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  return (select jsonb_build_object(
    'course', jsonb_build_object('id', c.id, 'provider_id', c.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'course_code', c.course_code,
               'canonical_title', c.canonical_title, 'display_title', c.display_title, 'description', c.description, 'duration_value', c.duration_value,
               'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode, 'lifecycle_status', c.lifecycle_status, 'course_url', c.course_url,
               'manual_course', c.stable_key like 'manual:%'),
    'official_links', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'is_primary', l.is_primary, 'source', s.label,
               'manual', s.source_type = 'manual_entry', 'updated_at', l.updated_at) order by l.is_primary desc, l.updated_at desc), '[]'::jsonb)
               from catalogue.course_links l left join pipeline.sources s on s.id = l.source_id
              where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active'),
    'intakes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date,
               'source', s.label, 'manual', s.source_type = 'manual_entry') order by i.start_date nulls last, i.intake_label), '[]'::jsonb)
               from catalogue.course_intakes i left join pipeline.sources s on s.id = i.source_id where i.course_id = c.id and i.status = 'active'),
    'english', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'test', t.code, 'test_name', t.name, 'overall', e.overall_score,
               'components', e.component_scores, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by t.name), '[]'::jsonb)
               from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id left join pipeline.sources s on s.id = e.source_id
              where e.course_id = c.id and e.status = 'active'),
    'tuition', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year,
               'basis', f.basis, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by f.updated_at desc), '[]'::jsonb)
               from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
              where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'),
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'course' and entity_id = c.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'english_tests', (select jsonb_agg(jsonb_build_object('code', code, 'name', name) order by name) from ref.english_tests),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_course_links_read(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); c record;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select co.id, co.open_to_international, co.open_to_domestic, co.applicant_basis, p.enrols_international, p.enrols_international_basis,
         coalesce(p.display_name, p.canonical_name) provider_name, k.iso_alpha2::text country_code
    into c from catalogue.courses co join catalogue.providers p on p.id = co.provider_id left join ref.countries k on k.id = p.country_id
   where co.id = p_course_id;
  if c.id is null then raise exception 'course not found'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 3,
    'types', (select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label, 'description', t.description, 'applicant', t.applicant) order by t.sort), '[]'::jsonb)
                from ref.course_link_types t where t.status = 'active'),
    'links', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', l.id, 'link_type', l.link_type, 'type_label', t.label, 'url', l.url, 'label', l.label, 'audience', l.audience,
                 'status', l.status, 'is_primary', l.is_primary, 'confidence', l.confidence, 'last_verified_at', l.last_verified_at,
                 'updated_at', l.updated_at, 'source', s.label, 'source_type', s.source_type,
                 'by_hand', s.source_type = 'manual_entry') order by t.sort, (l.status = 'active') desc, l.is_primary desc, l.updated_at desc), '[]'::jsonb)
                from catalogue.course_links l join ref.course_link_types t on t.code = l.link_type left join pipeline.sources s on s.id = l.source_id
               where l.course_id = p_course_id),
    'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k
               where k.entity = 'course' and k.entity_id = p_course_id and (k.field like 'link:%' or k.field in ('official_url','open_to_international','open_to_domestic'))),
    'applicants', jsonb_build_object('open_to_international', c.open_to_international, 'open_to_domestic', c.open_to_domestic, 'basis', c.applicant_basis,
                    'provider_enrols_international', c.enrols_international, 'provider_basis', c.enrols_international_basis,
                    'english_expected', c.open_to_international is true, 'provider', c.provider_name, 'country', c.country_code));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_fee_rule_preview(p_provider_id uuid, p_phrase text, p_url_pattern text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_phrase, ''))) < 6 then raise exception 'type at least 6 characters of the words that come before the fee'; end if;
  return (select jsonb_build_object(
      'would_admit', count(*) filter (where amounts = 1 and not has_fee and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition')),
      'ambiguous', count(*) filter (where amounts > 1), 'already_had_fee', count(*) filter (where amounts = 1 and has_fee),
      'amount_range', jsonb_build_object('min', min(amount), 'max', max(amount)),
      'samples', (select coalesce(jsonb_agg(s), '[]'::jsonb) from (
          select jsonb_build_object('course_id', m2.course_id, 'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', m2.amount,
                 'fee_year', m2.fee_year, 'text', m2.matched_text, 'url', m2.url, 'has_fee', m2.has_fee, 'amounts', m2.amounts) s
            from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m2 join catalogue.courses c on c.id = m2.course_id
           order by m2.amounts desc, m2.amount limit 15) z))
    from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_fee_rules_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_create', v_rank >= 4, 'can_approve', v_rank >= 5,
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'provider_id', r.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
                'label', r.label, 'phrase', r.phrase, 'basis', r.basis, 'url_pattern', r.url_pattern, 'status', r.status, 'admitted', r.admitted,
                'created_at', r.created_at, 'created_by', cu.email, 'approved_at', r.approved_at, 'approved_by', au.email, 'last_run_at', r.last_run_at, 'note', r.note)
                order by r.status = 'active' desc, r.created_at desc), '[]'::jsonb)
                from pipeline.fee_wording_rules r left join catalogue.providers p on p.id = r.provider_id
                left join auth.users cu on cu.id = r.created_by left join auth.users au on au.id = r.approved_by),
    'suggestions', (select coalesce(jsonb_agg(s order by (s->>'pages')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('provider_id', w.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'phrase', w.phrase,
              'pages', count(distinct w.course_id), 'example', min(w.example),
              'has_rule', exists (select 1 from pipeline.fee_wording_rules r where r.provider_id = w.provider_id and lower(r.phrase) = lower(w.phrase))) s
         from (select g.provider_id, g.course_id, security.fee_suggest_phrase(c->>'context', (c->>'amount')::numeric) phrase, left(c->>'context', 240) example
                 from pipeline.coverage_course_pages g
                 join pipeline.provider_priority pp on pp.provider_id = g.provider_id and pp.rank <= 100
                 cross join lateral jsonb_array_elements(coalesce(g.candidates->'fee'->'candidates', '[]'::jsonb)) c
                where g.read_status = 'read' and g.identity_basis in ('cricos_code','manual') and coalesce(g.candidates->'fee'->>'safe', 'false') <> 'true'
                  and coalesce((c->>'domestic')::boolean, false) = false
                  and not exists (select 1 from catalogue.course_fees f where f.course_id = g.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active')) w
         join catalogue.providers p on p.id = w.provider_id
        where w.phrase is not null
        group by w.provider_id, p.display_name, p.canonical_name, w.phrase
       having count(distinct w.course_id) >= 10
        order by count(distinct w.course_id) desc limit 25) z),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', a.admitted_at, 'rule_id', a.rule_id, 'course_id', a.course_id,
                'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', a.amount, 'fee_year', a.fee_year, 'basis', a.basis, 'text', a.matched_text)
                order by a.admitted_at desc), '[]'::jsonb)
                from (select * from pipeline.fee_rule_admissions order by admitted_at desc limit 30) a join catalogue.courses c on c.id = a.course_id));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_key_dates_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_edit', v_rank >= 3,
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'country', d.country_code, 'event_type', d.event_type, 'title', d.title,
                'source_url', d.source_url, 'precision', d.date_precision, 'starts_on', coalesce(d.starts_on, (d.starts_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date),
                'ends_on', coalesce(d.ends_on, (d.ends_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date), 'wording', d.source_wording,
                'warning_days', extract(day from d.warning_window)::int, 'scope', d.scope_type, 'refresh_layer', d.refresh_layer, 'status', d.status, 'updated_at', d.updated_at)
              order by d.status <> 'active', coalesce(d.starts_on, d.starts_at::date) nulls last, d.title), '[]'::jsonb) from pipeline.important_dates d),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'key_dates' order by created_at desc limit 15) e left join auth.users u on u.id = e.actor));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_link_refresh_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 4,
    'policies', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'country', k.iso_alpha2, 'country_name', k.name, 'provider_id', r.provider_id,
                   'provider', coalesce(p.display_name, p.canonical_name), 'link_type', r.link_type, 'type_label', t.label, 'every_days', r.every_days,
                   'active', r.active, 'notes', r.notes, 'last_run_at', r.last_run_at, 'last_result', r.last_result)
                   order by t.sort, k.iso_alpha2 nulls first, p.canonical_name nulls first), '[]'::jsonb)
                   from pipeline.link_refresh_policies r join ref.course_link_types t on t.code = r.link_type
                   left join ref.countries k on k.id = r.country_id left join catalogue.providers p on p.id = r.provider_id),
    'portals', (select coalesce(jsonb_agg(jsonb_build_object('code', lp.code, 'label', lp.label, 'country', k.iso_alpha2, 'kind', lp.kind,
                   'link_type', lp.link_type, 'base_url', lp.base_url, 'applicant', lp.applicant, 'active', lp.active, 'every_days', lp.every_days,
                   'last_run_at', lp.last_run_at, 'last_result', lp.last_result, 'notes', lp.notes) order by k.iso_alpha2, lp.code), '[]'::jsonb)
                  from pipeline.link_portals lp left join ref.countries k on k.id = lp.country_id),
    'types', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort), '[]'::jsonb) from ref.course_link_types where status = 'active'),
    'countries', (select coalesce(jsonb_agg(distinct k.iso_alpha2), '[]'::jsonb) from catalogue.providers p join ref.countries k on k.id = p.country_id));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_platform_notices_read(p_layer integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v := security.platform_notices_v1() || coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb);
  return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(),
    'notices', coalesce((select jsonb_agg(n || jsonb_build_object('acknowledged', a.acknowledged_at is not null and a.acknowledged_at >= (n->>'last_at')::timestamptz,
                                                                   'acknowledged_at', a.acknowledged_at, 'ack_reason', a.reason)
                                          order by case n->>'severity' when 'high' then 0 when 'warning' then 1 else 2 end, (n->>'last_at') desc)
                         from jsonb_array_elements(v) n left join pipeline.platform_notice_acks a on a.notice_key = n->>'key'
                         where p_layer is null or (n->>'layer')::int = p_layer), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_applicants_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); p record;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select pr.id, pr.enrols_international, pr.enrols_international_basis, k.iso_alpha2::text country into p
    from catalogue.providers pr left join ref.countries k on k.id = pr.country_id where pr.id = p_provider_id;
  if p.id is null then raise exception 'provider not found'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 4,
    'enrols_international', p.enrols_international,
    'basis', p.enrols_international_basis,
    'country', p.country,
    'locked', exists (select 1 from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p_provider_id and k.field = 'enrols_international'),
    'courses', (select jsonb_build_object(
                  'open_to_international', count(*) filter (where c.open_to_international is true),
                  'domestic_only', count(*) filter (where c.open_to_international is false),
                  'not_known', count(*) filter (where c.open_to_international is null),
                  'set_by_hand', count(*) filter (where exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'open_to_international')))
                  from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active'));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_edit_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  return (select jsonb_build_object(
    'provider', jsonb_build_object('id', p.id, 'canonical_name', p.canonical_name, 'display_name', p.display_name, 'short_name', p.short_name,
               'website', p.website, 'phone', p.phone, 'email', p.email, 'description', p.description, 'primary_city', p.primary_city,
               'address_line1', p.address_line1, 'postcode', p.postcode, 'lifecycle_status', p.lifecycle_status, 'country', k.name, 'state', s.name,
               'manual_provider', p.stable_key like 'manual:%', 'website_verdict', security.provider_site_verdict_v1(p.id, p.website),
               'active_courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
    'course_finder', (select jsonb_build_object('address', d.website, 'status', d.status, 'pages_found', d.kept_count, 'mapped_at', d.mapped_at,
                               'verdict', security.provider_site_verdict_v1(p.id, d.website), 'source', d.site_source)
                        from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'link_recipe', (select jsonb_build_object('search_domain', r.search_domain, 'patterns', r.patterns, 'active', r.active)
                      from pipeline.course_link_recipes r where r.provider_id = p.id),
    -- v2.15.234 (Fix 2): where the public phone and email came from, and (PIM Operator and above) the regulator's contact, internal only
    'public_contact', (select jsonb_build_object('phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'public_general' and cp.is_current),
    'regulatory_contact', case when v_rank >= 5 then (select jsonb_build_object('name', cp.name, 'title', cp.title, 'phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'regulatory_peo' and cp.is_current) end,
    'regulatory_check', case when v_rank >= 5 then (select jsonb_build_object('outcome', k.outcome, 'at', k.checked_at) from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo') end,
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'provider' and entity_id = p.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    -- v2.15.238 (R5): why and when the provider was archived
    'archive', (select jsonb_build_object('source', a.source, 'reason', a.reason, 'at', a.archived_at) from pipeline.provider_archives a where a.provider_id = p.id and a.restored_at is null),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id where p.id = p_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_reference_source_save(p_id uuid, p_fields jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_old pipeline.important_links%rowtype; v_new pipeline.important_links%rowtype;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_changed text[]; v_inuse bigint;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'nothing to save'; end if;
  if exists (select 1 from jsonb_object_keys(p_fields) k where k not in ('name','url','purpose','country','category','domain','uses','enabled','ref_key')) then
    raise exception 'unknown field'; end if;
  if p_id is null or exists (select 1 from jsonb_object_keys(p_fields) k where k in ('domain','uses','enabled','ref_key','category')) then
    if v_rank < 5 then raise exception 'PIM Operator role or above required to add a site or change how it is used' using errcode = '42501'; end if;
    if v_reason is null or length(v_reason) < 3 then raise exception 'give a short reason'; end if;
  end if;
  if p_id is null then
    insert into pipeline.important_links(country_code, authority_category, authority_name, url, domain, uses, enabled, ref_key, purpose, owner_label,
      verification_cadence, next_verification_at, health_status, change_control_ref, created_by, updated_by)
    values (upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')), coalesce(p_fields->>'category', 'third_party_directory'),
      btrim(coalesce(p_fields->>'name', '')), btrim(coalesce(p_fields->>'url', '')), nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), ''),
      coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array['reference']::text[]),
      coalesce((p_fields->>'enabled')::boolean, true), nullif(btrim(coalesce(p_fields->>'ref_key', '')), ''), btrim(coalesce(p_fields->>'purpose', '')),
      'StudySearch Data Ops', interval '90 days', now() + interval '90 days', 'unverified', 'CF-CHG-20260915-247', auth.uid(), auth.uid())
    returning * into v_new;
    if length(v_new.authority_name) < 2 then raise exception 'give the site a name'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reference_sources', 'add', v_new.authority_name, jsonb_build_object('id', v_new.id, 'domain', v_new.domain, 'uses', to_jsonb(v_new.uses), 'reason', v_reason), auth.uid());
    return public.admin_reference_sources_read() || jsonb_build_object('saved', v_new.id);
  end if;
  select * into v_old from pipeline.important_links where id = p_id for update;
  if not found then raise exception 'site not found'; end if;
  update pipeline.important_links set
    authority_name = case when p_fields ? 'name' then btrim(p_fields->>'name') else authority_name end,
    url = case when p_fields ? 'url' then btrim(p_fields->>'url') else url end,
    purpose = case when p_fields ? 'purpose' then btrim(coalesce(p_fields->>'purpose', '')) else purpose end,
    country_code = case when p_fields ? 'country' then upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')) else country_code end,
    authority_category = case when p_fields ? 'category' then p_fields->>'category' else authority_category end,
    domain = case when p_fields ? 'domain' then nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), '') else domain end,
    uses = case when p_fields ? 'uses' then coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array[]::text[]) else uses end,
    enabled = case when p_fields ? 'enabled' then (p_fields->>'enabled')::boolean else enabled end,
    ref_key = case when p_fields ? 'ref_key' then nullif(btrim(coalesce(p_fields->>'ref_key', '')), '') else ref_key end,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id returning * into v_new;
  if length(coalesce(v_new.authority_name, '')) < 2 then raise exception 'give the site a name'; end if;
  if 'scholarship_placeholder' = any(v_old.uses) and v_old.enabled and v_old.retired_at is null
     and (not v_new.enabled or not ('scholarship_placeholder' = any(v_new.uses)) or v_new.domain is distinct from v_old.domain) then
    v_inuse := security.reference_placeholder_in_use(v_old.domain);
    if v_inuse > 0 then raise exception '% active scholarships are sourced only from this site; they would look publishable. Give them a university page first.', v_inuse; end if;
  end if;
  select array_agg(k) into v_changed from jsonb_object_keys(p_fields) k;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reference_sources', 'change', v_new.authority_name, jsonb_build_object('id', p_id, 'fields', to_jsonb(v_changed),
          'before', jsonb_build_object('name', v_old.authority_name, 'url', v_old.url, 'domain', v_old.domain, 'uses', to_jsonb(v_old.uses),
                    'enabled', v_old.enabled, 'category', v_old.authority_category, 'country', v_old.country_code, 'ref_key', v_old.ref_key, 'purpose', v_old.purpose),
          'reason', v_reason), auth.uid());
  return public.admin_reference_sources_read() || jsonb_build_object('saved', p_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_reference_sources_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  update pipeline.important_links l set last_check_http = r.status_code, last_check_at = coalesce(r.created, now()), last_check_request = null,
         last_verified_at = now(), next_verification_at = now() + l.verification_cadence,
         health_status = case when l.retired_at is not null then 'retired' when r.status_code between 200 and 399 then 'healthy' else 'degraded' end
    from net._http_response r where l.last_check_request = r.id;
  return jsonb_build_object(
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5,
    'uses', jsonb_build_array(
      jsonb_build_object('key','reference','label','Reference link','help','Shown to staff for looking things up.'),
      jsonb_build_object('key','data_source','label','Data source','help','The platform reads data from it.'),
      jsonb_build_object('key','not_provider_site','label','Never a university website','help','Skipped when finding or checking a university''s own website.'),
      jsonb_build_object('key','not_course_page','label','Never a course page','help','Refused when binding a course page.'),
      jsonb_build_object('key','scholarship_placeholder','label','Scholarship placeholder','help','A scholarship sourced only from here needs a university page before it can be published.'),
      jsonb_build_object('key','logo_directory','label','Logo directory','help','Used only to find university logos.'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher','help','Default source address on Ranking imports.')),
    'categories', jsonb_build_array(
      jsonb_build_object('key','regulatory_authority','label','Regulator or register'),
      jsonb_build_object('key','official_scholarship','label','Official scholarships'),
      jsonb_build_object('key','statistics_data','label','Statistics'),
      jsonb_build_object('key','quality_outcomes','label','Outcomes'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher'),
      jsonb_build_object('key','third_party_directory','label','Third-party directory'),
      jsonb_build_object('key','general_web','label','Search, social or listing site'),
      jsonb_build_object('key','international_student_immigration','label','Student visas'),
      jsonb_build_object('key','qualification_framework','label','Qualification framework'),
      jsonb_build_object('key','official_policy_change','label','Policy changes'),
      jsonb_build_object('key','accepted_provider_course_source','label','Accepted course source'),
      jsonb_build_object('key','source_health','label','Source health')),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'country', l.country_code, 'category', l.authority_category,
                 'name', l.authority_name, 'url', l.url, 'domain', l.domain, 'uses', to_jsonb(l.uses), 'enabled', l.enabled,
                 'ref_key', l.ref_key, 'purpose', l.purpose, 'retired', l.retired_at is not null, 'health', l.health_status,
                 'checked_at', coalesce(l.last_check_at, l.last_verified_at), 'http', l.last_check_http, 'checking', l.last_check_request is not null,
                 'scholarships', case when 'scholarship_placeholder' = any(l.uses) then security.reference_placeholder_in_use(l.domain) end,
                 'updated_at', l.updated_at)
               order by l.retired_at is not null, l.authority_category, l.authority_name), '[]'::jsonb) from pipeline.important_links l),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'detail', e.detail, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'reference_sources' order by created_at desc limit 20) e left join auth.users u on u.id = e.actor));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_layer_read(p_layer integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v := jsonb_build_object('layer', p_layer, 'can_manage', v_rank >= 6,
    'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'min', s.min_value, 'max', s.max_value, 'unit', s.unit, 'updated_at', s.updated_at, 'reason', s.reason) order by s.key), '[]'::jsonb)
                   from pipeline.scholarship_layer_settings s where s.layer = p_layer),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('jobname', j.jobname, 'label', j.label, 'what', j.what, 'settings', j.setting_keys, 'schedule', c.schedule, 'active', c.active,
                     'runs_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days'),
                     'failed_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days' and d.status <> 'succeeded'),
                     'last_run', (select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid),
                     'last_failure', (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = c.jobid and d.status <> 'succeeded' order by d.start_time desc limit 1)) order by j.sort), '[]'::jsonb)
               from pipeline.scholarship_jobs j left join cron.job c on c.jobname = j.jobname where j.layer = p_layer));
  if p_layer = 1 then
    v := v || jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'enabled', k.scholarship_ingestion_enabled, 'currency', k.default_currency_code,
                       'providers', (select count(*) from catalogue.providers p where p.country_id = k.id),
                       'universities_queued', (select count(*) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id),
                       'scholarships', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active'),
                       'published', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active' and s.publication_status = 'published'),
                       'detail_sources', (select count(*) from pipeline.sources x where x.country_id = k.id and x.source_type = 'scholarship_detail')) order by k.iso_alpha2), '[]'::jsonb)
                     from ref.countries k where k.iso_alpha2 in ('AU', 'NZ', 'CA', 'GB', 'US')),
      'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'country', coalesce(k.iso_alpha2, 'ALL'), 'type', x.source_type, 'role', coalesce(x.metadata->>'scholarship_role', 'reference'),
                     'label', x.label, 'url', x.url, 'status', x.status, 'use', x.metadata->>'use', 'ingestion', x.metadata->>'ingestion', 'reader', x.metadata->>'reader',
                     'qualification', (select q.qualification_status from pipeline.scholarship_source_qualifications q where q.source_key = x.metadata->>'scholarship_source_key' limit 1),
                     'records', (select count(*) from scholarship.scholarships s where s.source_id = x.id and s.lifecycle_status = 'active'),
                     'feed', (select jsonb_build_object('feed', e.feed, 'enabled', e.enabled, 'cadence_hours', e.cadence_hours, 'last_dispatched_at', e.last_dispatched_at, 'next_due_at', e.next_due_at, 'last_error', e.last_error)
                                from pipeline.scholarship_etl_schedules e where e.source_key = x.metadata->>'scholarship_source_key' limit 1))
                     order by coalesce(k.iso_alpha2, 'ZZ'), case coalesce(x.metadata->>'scholarship_role', 'reference') when 'ingest' then 1 when 'provider_pages' then 2 when 'validation' then 3 else 4 end, x.label), '[]'::jsonb)
                   from pipeline.sources x left join ref.countries k on k.id = x.country_id
                  where x.source_type in ('government_scholarship_program', 'scholarship_catalogue', 'scholarship_reference')));
  elsif p_layer = 2 then
    v := v || jsonb_build_object('countries', (
      select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2,
        'discovery', (select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select d.status, count(*) n from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id group by 1) z),
        'pages_found', (select count(*) from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id),
        'page_reads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.read_status, 'waiting') st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'outcomes', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.admit_status, case when c.matched_scholarship_id is not null then 'matched_existing' when c.read_status is null then 'waiting' else 'not_decided' end) st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'refusals', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.r, 'pages', z.n) order by z.n desc), '[]'::jsonb) from (select r, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id cross join unnest(c.admit_reasons) r where p.country_id = k.id and c.admit_status = 'rejected' group by 1 order by 2 desc limit 6) z),
        'rereads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(sp.read_status, 'waiting') st, count(*) n from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id group by 1) z)
      ) order by case k.iso_alpha2 when 'AU' then 1 when 'NZ' then 2 when 'CA' then 3 else 4 end), '[]'::jsonb)
      from ref.countries k where k.scholarship_ingestion_enabled and exists (select 1 from catalogue.providers p where p.country_id = k.id)),
      'firecrawl', jsonb_build_object(
        'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
        'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
        'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
        'by_purpose', (select coalesce(jsonb_object_agg(z.purpose, jsonb_build_object('all', z.n, 'last_7_days', z.n7)), '{}'::jsonb)
                         from (select u.purpose, sum(u.units) n, coalesce(sum(u.units) filter (where u.at > now() - interval '7 days'), 0) n7 from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape') group by 1) z)),
      'worker', (select coalesce(jsonb_agg(jsonb_build_object('mode', z.mode, 'sent', z.sent, 'answered', z.answered, 'ok', z.ok, 'failed', z.failed, 'last_failure', z.lf)), '[]'::jsonb) from (
        select l.mode, count(*) sent, count(r.id) answered, count(*) filter (where r.status_code between 200 and 299) ok,
               count(*) filter (where r.status_code >= 300 or r.timed_out or r.error_msg is not null) failed,
               (select left(coalesce(r2.error_msg, r2.content::text), 200) from pipeline.edge_request_log l2 join net._http_response r2 on r2.id = l2.request_id where l2.mode = l.mode and (r2.status_code >= 300 or r2.timed_out or r2.error_msg is not null) order by l2.created_at desc limit 1) lf
          from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id
         where l.mode like 'scholarship%' and l.created_at > now() - interval '6 hours' group by l.mode) z));
  elsif p_layer = 3 then
    v := v || jsonb_build_object(
      'ai', (select coalesce(jsonb_agg(jsonb_build_object('country', a.country_code, 'enabled', a.enabled, 'state', a.metadata->>'state', 'profile', (select p.code from pipeline.layer3_model_profiles p where p.id = a.default_profile_id),
                 'task', a.default_task_class, 'budget_usd', a.daily_budget_usd, 'max_records', a.max_records_per_run, 'on_change', a.schedule_on_change,
                 'runs', (select count(*) from pipeline.scholarship_ai_runs r where r.country_code = a.country_code)) order by a.country_code), '[]'::jsonb) from pipeline.scholarship_ai_settings a),
      'profiles', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'model', p.model_identifier, 'enabled', p.enabled, 'paused', p.paused, 'benchmark_pass', coalesce((p.quality_benchmark->>'pass')::boolean, false)) order by p.code), '[]'::jsonb)
                     from pipeline.layer3_model_profiles p where p.code like '%scholarship%' and p.retired_at is null));
  end if;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_links_detail(p_scholarship_id uuid, p_decision text DEFAULT NULL::text, p_filter jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_s scholarship.scholarships%rowtype; v_dec text; v_f jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_links_read(p_view text DEFAULT 'waiting'::text, p_q text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_record_read(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
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
      'course_list', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'level', x.level, 'code', x.course_code) order by x.so, x.title), '[]'::jsonb)
                        from (select co.id, coalesce(co.display_title, co.canonical_title) title, sl.name level, coalesce(sl.sort_order, 99) so, co.course_code
                                from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                               where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active'
                               order by coalesce(sl.sort_order, 99), coalesce(co.display_title, co.canonical_title) limit 200) x),
      'course_levels', (select coalesce(jsonb_agg(jsonb_build_object('level', y.level, 'courses', y.n) order by y.so), '[]'::jsonb)
                          from (select coalesce(sl.name, 'Other') level, min(coalesce(sl.sort_order, 99)) so, count(*) n
                                  from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                                 where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active' group by 1) y),
      'criteria', (select coalesce(jsonb_agg(to_jsonb(cr) order by cr.criterion_type), '[]'::jsonb) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
      'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'reason', h.reason) order by h.at desc), '[]'::jsonb)
                    from (select * from pipeline.manual_edit_log l where l.entity = 'scholarship' and l.entity_id = s.id order by l.at desc limit 10) h))
    from scholarship.scholarships s left join catalogue.providers pr on pr.id = s.provider_id where s.id = p_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_search_pass_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'status_note', r.status_note, 'credits_used', r.credits_used, 'created_at', r.created_at, 'reason', r.reason,
               'courses', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id), 'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done')) order by r.created_at desc), '[]'::jsonb)
             from pipeline.toolset_sample_runs r where r.applies),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'refind', z.refind, 'state', z.state, 'n', z.n)), '[]'::jsonb)
              from (select k.iso_alpha2 cc, l.refind, l.state, count(*) n from pipeline.search_pass_links l join catalogue.providers p on p.id = l.provider_id join ref.countries k on k.id = p.country_id group by 1, 2, 3) z),
    'reading', (select coalesce(jsonb_agg(jsonb_build_object('read_status', z.rs, 'n', z.n)), '[]'::jsonb)
                from (select coalesce(p.read_status, 'waiting') rs, count(*) n from pipeline.search_pass_links l join pipeline.coverage_course_pages p on p.course_id = l.course_id and p.url = l.bound_url where l.state = 'found' group by 1) z),
    'repairs', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n, 'last_at', z.last_at)), '[]'::jsonb)
                from (select reason, count(*) n, max(at) last_at from pipeline.page_link_repairs group by 1) z));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_toolset_samples_read(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'toolset', r.toolset_key, 'purpose', r.purpose, 'countries', r.countries, 'status', r.status, 'status_note', r.status_note,
                'credits_used', r.credits_used, 'reason', r.reason, 'created_at', r.created_at, 'finished_at', r.finished_at,
                'cases', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id),
                'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done'),
                'usd_per_1k_credits', r.settings->'usd_per_1k_credits', 'plan_name', r.settings->'plan_name') order by r.created_at desc), '[]'::jsonb)
             from (select * from pipeline.toolset_sample_runs order by created_at desc limit 30) r),
    'summary', (select coalesce(jsonb_agg(jsonb_build_object('toolset', z.toolset_key, 'purpose', z.purpose, 'country', z.country, 'outcome', z.outcome, 'n', z.n,
                    'credits', z.credits, 'avg_latency_ms', z.lat) order by z.toolset_key, z.purpose, z.country, z.n desc), '[]'::jsonb)
                from (select r.toolset_key, r.purpose, i.country, i.outcome, count(*) n, sum(i.credits) credits, round(avg(i.latency_ms)) lat
                      from pipeline.toolset_sample_items i join pipeline.toolset_sample_runs r on r.id = i.run_id
                      where i.status = 'done' and (p_run_id is null or r.id = p_run_id) group by 1, 2, 3, 4) z),
    'backlog', (select coalesce(jsonb_agg(jsonb_build_object('toolset', t.toolset, 'purpose', t.purpose, 'country', c.cc, 'n', (select count(*) from security.toolset_backlog(t.purpose, c.cc)))), '[]'::jsonb)
                from (values ('serper', 'find_course_page'), ('serper', 'find_provider_site'), ('scrapingbee', 'render_page')) t(toolset, purpose)
                cross join lateral (select jsonb_array_elements_text(coalesce(security.toolset_setting(t.toolset, 'sample_countries'), '[]'::jsonb)) cc) c),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('country', i.country, 'input', i.input, 'outcome', i.outcome, 'http_status', i.http_status, 'credits', i.credits,
                 'latency_ms', i.latency_ms, 'result', i.result, 'done_at', i.done_at) order by i.country, i.outcome, i.done_at), '[]'::jsonb)
              from pipeline.toolset_sample_items i where p_run_id is not null and i.run_id = p_run_id and i.status = 'done'));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t),
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      'guards', (select coalesce(jsonb_agg(jsonb_build_object('task_class', b.task_class, 'daily_usd_max', b.daily_usd_max, 'credit_floor_usd', b.credit_floor_usd,
                    'spent_today', (select coalesce(sum(i.estimated_cost_usd), 0) from pipeline.layer3_interpretations i where i.task_class = b.task_class
                                    and i.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) order by b.task_class), '[]'::jsonb)
                 from pipeline.layer3_route_budget b),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select (i.created_at at time zone 'UTC')::date as day, round(sum(i.estimated_cost_usd), 4) usd, count(*) calls
                             from pipeline.layer3_interpretations i where i.created_at > now() - interval '14 days' group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_value_note_add(p_course_id uuid, p_field text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_field text := lower(btrim(coalesce(p_field, 'other')));
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if v_field not in ('official_url', 'intakes', 'english', 'tuition', 'scholarship', 'title', 'duration', 'delivery', 'description', 'other') then raise exception 'unknown field %', p_field; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  insert into pipeline.data_flags(entity_type, entity_id, field_code, flag_code, detail, status, change_control_ref)
  values ('course', p_course_id, v_field, 'note',
          jsonb_build_object('note', left(btrim(p_note), 1000), 'source', 'admin', 'by', auth.uid(), 'quotes', jsonb_build_array(left(btrim(p_note), 1000))),
          'open', 'CF-247')
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('notes', 'add', v_field, jsonb_build_object('course_id', p_course_id, 'flag_id', v_id), auth.uid());
  return jsonb_build_object('flag_id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_waiting_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_rows jsonb := '[]'::jsonb; v_n bigint; v_old timestamptz;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.layer4_review_items where status = 'pending';
    v_rows := v_rows || jsonb_build_object('key','review','label','Review items to decide','count',v_n,'oldest',v_old,'href','#layer-4-review','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.data_flags where status = 'open';
    v_rows := v_rows || jsonb_build_object('key','flags','label','Flagged values to check','count',v_n,'oldest',v_old,'href','#layer-4-review?tab=flags','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.fee_wording_rules where status = 'draft';
    v_rows := v_rows || jsonb_build_object('key','rules','label','Fee rules waiting for approval','count',v_n,'oldest',v_old,'href','#layer-4-review?tab=rules','min',5);
  exception when others then null; end;
  begin
    select count(distinct c.scholarship_id), min(c.created_at) into v_n, v_old from scholarship.course_mapping_candidates c where c.status = 'needs_review';
    v_rows := v_rows || jsonb_build_object('key','scholarship_links','label','Scholarships to link to courses','count',v_n,'oldest',v_old,'href','#scholarships?tab=links','min',4);
  exception when others then null; end;
  begin
    select count(*) into v_n from security.scholarship_publishability_v1() x join scholarship.scholarships s on s.id = x.scholarship_id
     where x.publishable and coalesce(s.publication_status, '') <> 'published';
    v_rows := v_rows || jsonb_build_object('key','scholarships_ready','label','Scholarships ready to publish','count',v_n,'oldest',null,'href','#scholarships?tab=publishing','min',5);
  exception when others then null; end;
  begin
    select count(*) into v_n from pipeline.important_links where retired_at is null and enabled and health_status = 'degraded';
    v_rows := v_rows || jsonb_build_object('key','reference','label','Reference sites not reachable','count',v_n,'oldest',null,'href','#reference-data?tab=links','min',3);
  exception when others then null; end;
  begin
    select count(*), min(coalesce(starts_on, starts_at::date))::timestamptz into v_n, v_old from pipeline.important_dates
     where status = 'active' and coalesce(starts_on, starts_at::date) between current_date and current_date + warning_window;
    v_rows := v_rows || jsonb_build_object('key','dates','label','Key dates coming up','count',v_n,'oldest',v_old,'href','#reference-data?tab=dates','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.jobs where status = 'failed' and created_at > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_jobs','label','Jobs that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs?tab=jobs','min',4);
  exception when others then null; end;
  begin
    select count(distinct d.jobid), min(d.start_time) into v_n, v_old from cron.job_run_details d where d.status = 'failed' and d.start_time > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_automations','label','Automations that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs','min',4);
  exception when others then null; end;
  return jsonb_build_object('rank', v_rank, 'generated_at', now(),
    'rows', (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(v_rows) r where (r->>'min')::int <= v_rank));
end $function$;

CREATE OR REPLACE FUNCTION public.layer2_provider_control(p_actor uuid, p_action text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'pipeline', 'vault'
AS $function$declare v_rank int:=0;v_id uuid;v_secret_id uuid;v_profile uuid;v_provider uuid;begin
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if p_action in ('create_provider','update_provider','set_secret') and v_rank<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
 if p_action='upsert_route' and v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
 if p_action in ('create_provider','update_provider') and (security.layer2_provider_has_secret_keys(p_payload->'capabilities') or security.layer2_provider_has_secret_keys(p_payload->'request_template') or security.layer2_provider_has_secret_keys(p_payload->'billing_config')) then raise exception 'provider configuration contains secret-like keys; use credential control' using errcode='22023';end if;
 if p_action='upsert_route' and (security.layer2_provider_has_secret_keys(p_payload->'request_overrides') or security.layer2_provider_has_secret_keys(p_payload->'required_capabilities')) then raise exception 'route configuration contains secret-like keys' using errcode='22023';end if;
 if p_action='create_provider' then
   if coalesce(trim(p_payload->>'provider_key'),'')='' or coalesce(trim(p_payload->>'display_name'),'')='' then raise exception 'provider key and display name required' using errcode='22023';end if;
   insert into pipeline.layer2_acquisition_providers(provider_key,display_name,adapter_type,base_url,auth_scheme,auth_field_name,capabilities,request_template,billing_config,enabled,priority,rate_limit_per_minute,concurrency,timeout_seconds,operational_owner,change_control_ref)
   values(trim(p_payload->>'provider_key'),trim(p_payload->>'display_name'),p_payload->>'adapter_type',nullif(trim(p_payload->>'base_url'),''),coalesce(nullif(p_payload->>'auth_scheme',''),'none'),nullif(trim(p_payload->>'auth_field_name'),''),coalesce(p_payload->'capabilities','{}'::jsonb),coalesce(p_payload->'request_template','{}'::jsonb),coalesce(p_payload->'billing_config','{}'::jsonb),coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'priority')::int,100),nullif(p_payload->>'rate_limit_per_minute','')::int,coalesce((p_payload->>'concurrency')::int,1),coalesce((p_payload->>'timeout_seconds')::int,30),nullif(trim(p_payload->>'operational_owner'),''),coalesce(nullif(trim(p_payload->>'change_control_ref'),''),'CF-CHG-20260823-029')) returning id into v_id; return jsonb_build_object('ok',true,'id',v_id);
 elsif p_action='update_provider' then
   v_id:=(p_payload->>'id')::uuid; update pipeline.layer2_acquisition_providers set display_name=coalesce(nullif(trim(p_payload->>'display_name'),''),display_name),base_url=case when p_payload?'base_url' then nullif(trim(p_payload->>'base_url'),'') else base_url end,auth_scheme=coalesce(nullif(p_payload->>'auth_scheme',''),auth_scheme),auth_field_name=case when p_payload?'auth_field_name' then nullif(trim(p_payload->>'auth_field_name'),'') else auth_field_name end,capabilities=coalesce(p_payload->'capabilities',capabilities),request_template=coalesce(p_payload->'request_template',request_template),billing_config=coalesce(p_payload->'billing_config',billing_config),enabled=coalesce((p_payload->>'enabled')::boolean,enabled),priority=coalesce((p_payload->>'priority')::int,priority),rate_limit_per_minute=case when p_payload?'rate_limit_per_minute' then nullif(p_payload->>'rate_limit_per_minute','')::int else rate_limit_per_minute end,concurrency=coalesce((p_payload->>'concurrency')::int,concurrency),timeout_seconds=coalesce((p_payload->>'timeout_seconds')::int,timeout_seconds),operational_owner=case when p_payload?'operational_owner' then nullif(trim(p_payload->>'operational_owner'),'') else operational_owner end,updated_at=now() where id=v_id; if not found then raise exception 'provider not found' using errcode='22023';end if;return jsonb_build_object('ok',true,'id',v_id);
 elsif p_action='set_secret' then
   v_id:=(p_payload->>'id')::uuid;if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023';end if;select vault_secret_id into v_secret_id from pipeline.layer2_acquisition_providers where id=v_id for update;if not found then raise exception 'provider not found' using errcode='22023';end if;if v_secret_id is null then select vault.create_secret(p_payload->>'secret','coursefinder_l2_provider_'||v_id::text,'StudySearch Layer 2 provider credential',null) into v_secret_id;update pipeline.layer2_acquisition_providers set vault_secret_id=v_secret_id,updated_at=now() where id=v_id;else perform vault.update_secret(v_secret_id,p_payload->>'secret',null,null,null);end if;return jsonb_build_object('ok',true,'id',v_id,'credential_configured',true);
 elsif p_action='upsert_route' then
   v_profile:=(p_payload->>'profile_id')::uuid;v_provider:=(p_payload->>'provider_id')::uuid;
   insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref) values(v_profile,v_provider,coalesce((p_payload->>'priority')::int,100),coalesce((p_payload->>'enabled')::boolean,true),coalesce(p_payload->'required_capabilities','{}'::jsonb),coalesce(p_payload->'request_overrides','{}'::jsonb),coalesce(p_payload->'evidence_policy','{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true}'::jsonb),coalesce(p_payload->'fallback_on','["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb),coalesce(nullif(trim(p_payload->>'change_control_ref'),''),'CF-CHG-20260823-029')) on conflict(profile_id,acquisition_provider_id) do update set priority=excluded.priority,enabled=excluded.enabled,required_capabilities=excluded.required_capabilities,request_overrides=excluded.request_overrides,evidence_policy=excluded.evidence_policy,fallback_on=excluded.fallback_on,updated_at=now();return jsonb_build_object('ok',true);
 end if;raise exception 'unsupported provider action' using errcode='22023';
end$function$;

CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_prepare(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_run pipeline.layer2_scale_qualification_runs%rowtype;
  r record;
  v_source uuid;
  v_profile uuid;
  v_version uuid;
  v_cfg jsonb;
  v_hash text;
  v_validation jsonb;
  v_country text;
  v_profiles jsonb:='[]'::jsonb;
  v_ready integer:=0;
  v_limited integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_run from pipeline.layer2_scale_qualification_runs where id=p_run_id for update;
  if not found then raise exception 'qualification run not found' using errcode='22023'; end if;
  if v_run.status in ('completed','cancelled') then
    return jsonb_build_object('ok',true,'status',v_run.status,'run_id',p_run_id);
  end if;

  select iso_alpha2::text into v_country from ref.countries where id=v_run.country_id;

  for r in
    select distinct qi.provider_id,p.canonical_name,p.website,p.country_id
    from pipeline.layer2_scale_qualification_items qi
    join catalogue.providers p on p.id=qi.provider_id
    where qi.run_id=p_run_id
      and qi.status in ('selected','qualifying')
    order by p.canonical_name
  loop
    if r.website is null
       or btrim(r.website)=''
       or r.website !~* '^https?://[^[:space:]]+$'
       or lower(r.website) like 'https://https://%'
       or lower(r.website) like 'http://http://%'
    then
      update pipeline.layer2_scale_qualification_items
      set status='source_limited',
          outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
            'stage','source_seed_qualification',
            'outcome','source_limited',
            'reason','missing_or_invalid_layer1_provider_website',
            'layer1_provider_website',r.website,
            'handoff','layer4_source_resolution',
            'canonical_mutation_authorised',false,
            'search_mutation_authorised',false,
            'publication_mutation_authorised',false
          )
      where run_id=p_run_id and provider_id=r.provider_id;
      v_limited:=v_limited+1;
      continue;
    end if;

    select lp.id,s.id into v_profile,v_source
    from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where s.provider_id=r.provider_id
      and lp.authority_class='qualification_candidate'
      and lp.domain='course_facts'
    order by lp.created_at desc
    limit 1;

    if v_profile is null then
      insert into pipeline.sources(
        source_type,provider_id,country_id,url,label,trust_rank,status,metadata
      ) values(
        'web_catalogue',r.provider_id,r.country_id,btrim(r.website),
        'A11 qualification — '||r.canonical_name,60,'active',
        jsonb_build_object(
          'layer',2,
          'qualification_candidate',true,
          'qualification_run_id',p_run_id,
          'change_control_ref','CF-CHG-20260830-048',
          'canonical_mutation_authorised',false
        )
      ) returning id into v_source;

      insert into pipeline.layer2_source_profiles(
        source_id,profile_key,domain,acquisition_method,target_entity_type,
        authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text
      ) values(
        v_source,
        'qualification-'||lower(v_country)||'-'||left(replace(r.provider_id::text,'-',''),16),
        'course_facts','website','course_fact','qualification_candidate',
        true,false,'PIM/Data Operations',168,'qualification_only'
      ) returning id into v_profile;

      v_cfg:=jsonb_build_object(
        'acquisition_method','website',
        'base_domain',btrim(r.website),
        'discovery_url',btrim(r.website),
        'url_patterns',jsonb_build_array(btrim(r.website)),
        'inclusion_rules',jsonb_build_array(),
        'exclusion_rules',jsonb_build_array(),
        'headers',jsonb_build_object('user_agent','StudySearch Layer2 Qualification/1.0'),
        'authentication',jsonb_build_object('mechanism','none'),
        'rate_limit_per_minute',30,
        'concurrency',1,
        'timeout_seconds',30,
        'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),
        'robots_policy','respect',
        'allowed_mime_types',jsonb_build_array('text/html','application/json'),
        'max_payload_mb',10,
        'parser_profile','generic-first-party-source-qualification-v1',
        'target_entity_type','course_fact',
        'mapping_strategy','qualification_only_no_canonical_mutation',
        'stable_identifier_strategy','layer1_provider_id_plus_first_party_host',
        'regulatory_code_extraction',jsonb_build_object('cricos',null,'nzqa',null),
        'evidence_required',true,
        'freshness_sla_hours',168,
        'schedule','qualification_only',
        'content_change_policy','evidence_only_never_direct_canonical_mutation',
        'source_authority','first_party_candidate_unqualified',
        'operational_owner','PIM/Data Operations',
        'change_control_ref','CF-CHG-20260830-048'
      );
      v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
      v_validation:=security.layer2_validate_profile_config(v_cfg);

      insert into pipeline.layer2_source_profile_versions(
        profile_id,version_no,configuration,configuration_hash,
        validation_status,validation_result,change_control_ref,uat_ref
      ) values(
        v_profile,1,v_cfg,v_hash,
        case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end,
        v_validation,'CF-CHG-20260830-048','M2.4.2-A11-source-qualification'
      ) returning id into v_version;

      update pipeline.layer2_source_profiles set current_version_id=v_version where id=v_profile;

      insert into pipeline.layer2_profile_provider_routes(
        profile_id,acquisition_provider_id,priority,enabled,
        required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref
      )
      select
        v_profile,ap.id,
        case ap.provider_key
          when 'firecrawl' then 5
          when 'direct-http' then 20
          when 'scrape-do' then 80
          when 'scraperapi' then 90
          when 'zenrows' then 100
          else 120
        end,
        case when ap.provider_key in ('firecrawl','direct-http') then true else false end,'{}'::jsonb,'{}'::jsonb,
        '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb,
        '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
        'CF-CHG-20260830-048'
      from pipeline.layer2_acquisition_providers ap
      where ap.enabled
      on conflict do nothing;
    end if;

    update pipeline.layer2_scale_qualification_items
    set status='qualifying',
        outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
          'stage','source_seed_qualification',
          'qualification_profile_id',v_profile,
          'qualification_source_id',v_source,
          'layer1_provider_website',r.website,
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
    where run_id=p_run_id and provider_id=r.provider_id and status in ('selected','qualifying');

    v_profiles:=v_profiles||jsonb_build_array(jsonb_build_object(
      'provider_id',r.provider_id,'provider_name',r.canonical_name,
      'website',r.website,'profile_id',v_profile,'source_id',v_source
    ));
    v_ready:=v_ready+1;
  end loop;

  update pipeline.layer2_scale_qualification_runs
  set status=case when v_ready>0 then 'running' else 'completed' end,
      result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
        'stage','source_seed_qualification',
        'providers_ready_for_acquisition',v_ready,
        'providers_source_limited',v_limited,
        'identity_safety_required',true,
        'canonical_mutation_authorised',false,
        'search_mutation_authorised',false,
        'publication_mutation_authorised',false
      ),
      completed_at=case when v_ready=0 then now() else null end
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'providers_ready_for_acquisition',v_ready,
    'providers_source_limited',v_limited,
    'profiles',v_profiles,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$;

CREATE OR REPLACE FUNCTION public.platform_environment_control_service(p_actor uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'vault', 'private', 'extensions'
AS $function$
declare
  v_rank int:=0;
  v_key text;
  v_secret_name text;
  v_secret_id uuid;
  v_status text;
  v_token text;
  v_hash text;
  v_name text;
begin
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;

  if p_action='set_setting' then
    v_key=trim(p_payload->>'setting_key');
    update pipeline.environment_settings
      set setting_value=case when p_payload?'value' then p_payload->'value' else setting_value end,
          status=case when p_payload?'value' and p_payload->'value' is not null and p_payload->'value'<>'null'::jsonb then 'configured' else 'pending' end,
          updated_by=p_actor,updated_at=now()
    where setting_key=v_key and management_mode='admin_edit';
    if not found then raise exception 'setting not admin-editable' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'setting_key',v_key);

  elsif p_action='set_integration_secret' then
    v_key=trim(p_payload->>'integration_key');
    if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023'; end if;
    select secret_name into v_secret_name
    from pipeline.integration_secret_registry
    where integration_key=v_key and admin_settable;
    if v_secret_name is null then raise exception 'integration secret not admin-settable' using errcode='22023'; end if;

    select id into v_secret_id from vault.secrets where name=v_secret_name;
    if v_secret_id is null then
      select vault.create_secret(p_payload->>'secret',v_secret_name,'StudySearch integration credential: '||v_key,null) into v_secret_id;
    else
      perform vault.update_secret(v_secret_id,p_payload->>'secret',null,null,null);
    end if;
    update pipeline.integration_secret_registry set updated_at=now() where integration_key=v_key;
    return jsonb_build_object('ok',true,'integration_key',v_key,'configured',true);

  elsif p_action='set_consumer_token' then
    v_key=trim(p_payload->>'integration_key');
    v_token=trim(p_payload->>'token');
    v_name=coalesce(nullif(trim(p_payload->>'credential_name'),''),case v_key when 'zoho_api' then 'zoho-production' when 'website_api' then 'website-production' else null end);
    if v_key not in('zoho_api','website_api') then raise exception 'unsupported consumer integration' using errcode='22023';end if;
    if length(v_token)<24 then raise exception 'consumer token must be at least 24 characters' using errcode='22023';end if;
    v_hash=encode(extensions.digest(v_token,'sha256'),'hex');

    if v_key='zoho_api' then
      update private.zoho_integration_credentials set enabled=false where enabled;
      insert into private.zoho_integration_credentials(credential_name,token_sha256,enabled,created_at,rotated_at)
      values(v_name,v_hash,true,now(),now())
      on conflict(credential_name) do update set token_sha256=excluded.token_sha256,enabled=true,rotated_at=now();
    else
      update private.website_integration_credentials set enabled=false where enabled;
      insert into private.website_integration_credentials(credential_name,token_sha256,enabled,created_at,rotated_at)
      values(v_name,v_hash,true,now(),now())
      on conflict(credential_name) do update set token_sha256=excluded.token_sha256,enabled=true,rotated_at=now();
    end if;

    return jsonb_build_object('ok',true,'integration_key',v_key,'credential_name',v_name,'configured',true,'storage_mode','sha256_only');

  elsif p_action='set_manifest_status' then
    v_key=trim(p_payload->>'component_key');
    v_status=trim(p_payload->>'target_status');
    if v_status not in('pending','ready','verified','blocked','not_applicable') then raise exception 'invalid target status' using errcode='22023'; end if;
    update pipeline.production_migration_manifest
    set target_status=v_status,updated_by=p_actor,updated_at=now()
    where component_key=v_key;
    if not found then raise exception 'manifest component not found' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'component_key',v_key,'target_status',v_status);
  end if;

  raise exception 'unsupported environment action' using errcode='22023';
end $function$;

CREATE OR REPLACE FUNCTION public.svc_admin_access_replace_roles(p_actor_user_id uuid, p_target_user_id uuid, p_role_codes text[], p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare
  v_roles text[];
  v_before jsonb;
  v_after jsonb;
  v_other_platform_admins integer := 0;
  v_target_is_platform_admin boolean := false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from security.user_roles ur
    join security.roles r on r.code=ur.role_code
    join auth.users u on u.id=ur.user_id
    where ur.user_id=p_actor_user_id
      and r.code='platform_admin' and r.status='active'
      and (ur.expires_at is null or ur.expires_at>now())
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now())
  ) then
    raise exception 'active platform admin actor required' using errcode='42501';
  end if;

  if not exists (select 1 from auth.users where id=p_target_user_id and deleted_at is null) then
    raise exception 'target user not found' using errcode='22023';
  end if;

  select coalesce(array_agg(distinct btrim(x) order by btrim(x)), '{}'::text[])
  into v_roles
  from unnest(coalesce(p_role_codes,'{}'::text[])) x
  where btrim(coalesce(x,''))<>'';

  if cardinality(v_roles)=0 then
    raise exception 'at least one StudySearch role is required' using errcode='22023';
  end if;

  if exists (
    select 1 from unnest(v_roles) x
    left join security.roles r on r.code=x and r.status='active'
    where r.code is null
  ) then
    raise exception 'unknown or inactive role code' using errcode='22023';
  end if;

  if p_actor_user_id=p_target_user_id and not ('platform_admin'=any(v_roles)) then
    raise exception 'platform admin cannot remove own platform_admin role' using errcode='42501';
  end if;

  if 'platform_admin'=any(v_roles) and p_expires_at is not null then
    raise exception 'platform_admin assignment cannot expire' using errcode='22023';
  end if;

  select exists (
    select 1 from security.user_roles ur
    where ur.user_id=p_target_user_id and ur.role_code='platform_admin'
      and (ur.expires_at is null or ur.expires_at>now())
  ) into v_target_is_platform_admin;

  if v_target_is_platform_admin and not ('platform_admin'=any(v_roles)) then
    select count(distinct ur.user_id)::integer into v_other_platform_admins
    from security.user_roles ur
    join security.roles r on r.code=ur.role_code
    join auth.users u on u.id=ur.user_id
    where ur.user_id<>p_target_user_id
      and ur.role_code='platform_admin' and r.status='active'
      and (ur.expires_at is null or ur.expires_at>now())
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now());
    if v_other_platform_admins=0 then
      raise exception 'cannot remove the last active platform admin' using errcode='42501';
    end if;
  end if;

  select jsonb_build_object(
    'roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)
  ) into v_before
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_target_user_id;
  v_before:=coalesce(v_before,jsonb_build_object('roles','[]'::jsonb));

  delete from security.user_roles where user_id=p_target_user_id;

  insert into security.user_roles(user_id,role_code,granted_by,expires_at)
  select p_target_user_id,x,p_actor_user_id,p_expires_at
  from unnest(v_roles) x;

  select jsonb_build_object(
    'roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)
  ) into v_after
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_target_user_id;
  v_after:=coalesce(v_after,jsonb_build_object('roles','[]'::jsonb));

  insert into security.user_access_events(actor_user_id,target_user_id,action,before_state,after_state)
  values(p_actor_user_id,p_target_user_id,'roles_replaced',v_before,v_after);

  return v_after;
end
$function$;

CREATE OR REPLACE FUNCTION public.ui_courses_decision_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_provider_id uuid DEFAULT NULL::uuid, p_level_code text DEFAULT NULL::text, p_field_code text DEFAULT NULL::text, p_delivery_mode text DEFAULT NULL::text, p_lifecycle_status text DEFAULT NULL::text, p_publication_status text DEFAULT NULL::text, p_has_fee boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_min_completeness numeric DEFAULT NULL::numeric, p_freshness text DEFAULT NULL::text, p_sort text DEFAULT 'course'::text, p_direction text DEFAULT 'asc'::text, p_has_state boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_university_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'catalogue', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_limit int:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset int:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'course'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return (
    with base as (
      select
        c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
        c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
        coalesce(p.display_name,p.canonical_name) provider_name,
        co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
        sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,
        case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else c.delivery_mode end delivery_mode,
        fee.amount fee_amount,fee.currency_code::text fee_currency,
        sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
        round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
        round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
        sch.has_scholarship,
        exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and l.status='active') has_link,
        coalesce(geo.region_count,0)>0 has_state,
        coalesce(geo.campus_count,0) campus_count,
        case when geo.region_count=1 then geo.single_code else null end subdivision_code,
        case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else null end subdivision_name,
        coalesce(geo.region_count,0) region_count
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      left join ref.study_levels sl on sl.id=c.study_level_id
      left join ref.fields_of_study fos on fos.id=c.primary_field_id
      left join lateral (
        select cf.amount,cf.currency_code
        from catalogue.course_fees cf
        where cf.course_id=c.id
          and cf.fee_type='tuition'
          and cf.basis='registered_total_course'
          and coalesce(cf.status,'active')='active'
        order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
        limit 1
      ) fee on true
      cross join lateral (
        select
          exists(select 1 from catalogue.course_registrations r where r.course_id=c.id) has_registration,
          (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)) has_structure,
          exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active') has_fee,
          exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active') has_intake,
          exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active') has_english,
          (c.description is not null and length(trim(c.description))>0) has_description
      ) sig
      cross join lateral (
        select exists(
          select 1 from scholarship.scopes ss
          where coalesce(ss.include_exclude,'include')='include'
            and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id))
        ) has_scholarship
      ) sch
      left join lateral (
        select count(distinct cc.campus_id)::int campus_count,count(distinct s.id)::int region_count,min(s.code) single_code,min(s.name) single_name
        from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        left join ref.subdivisions s on s.id=ca.subdivision_id
        where cc.course_id=c.id
      ) geo on true
      left join lateral (
        select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
        from catalogue.course_campuses cc
        where cc.course_id=c.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
      ) dm on true
      where (nullif(trim(coalesce(p_query,'')),'') is null
        or c.canonical_title ilike '%'||trim(p_query)||'%'
        or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.course_code,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.stable_key,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id join ref.subdivisions s on s.id=ca.subdivision_id
          where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
        and (p_provider_id is null or c.provider_id=p_provider_id)
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or c.provider_id in (select security.university_group_provider_ids(p_university_group)))
        and (nullif(trim(coalesce(p_level_code,'')),'') is null or sl.code=trim(p_level_code))
        and (nullif(trim(coalesce(p_field_code,'')),'') is null or fos.code=trim(p_field_code))
        and (nullif(trim(coalesce(p_delivery_mode,'')),'') is null or coalesce(c.delivery_mode,'')=trim(p_delivery_mode)
          or exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_delivery_mode)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or c.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or c.publication_status=trim(p_publication_status))
    ), filtered as (
      select * from base
      where (p_has_fee is null or has_fee=p_has_fee)
        and (p_has_intake is null or has_intake=p_has_intake)
        and (p_has_english is null or has_english=p_has_english)
        and (p_has_scholarship is null or has_scholarship=p_has_scholarship)
        and (p_has_state is null or has_state=p_has_state)
        and (p_has_link is null or has_link=p_has_link)
        and (p_min_completeness is null or completeness_score_v2>=p_min_completeness)
        and (nullif(trim(coalesce(p_freshness,'')),'') is null
          or (p_freshness='never_verified' and last_verified_at is null)
          or (p_freshness='modified_7d' and updated_at>=now()-interval '7 days')
          or (p_freshness='modified_30d' and updated_at>=now()-interval '30 days')
          or (p_freshness='stale_180d' and (last_verified_at is null or last_verified_at<now()-interval '180 days')))
    ), numbered as (
      select *,count(*) over() total_count from filtered
    ), ordered as (
      select * from numbered order by
        case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
        case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
        case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
        case when v_sort='fee' and v_dir='asc' then fee_amount end asc nulls last,
        case when v_sort='fee' and v_dir='desc' then fee_amount end desc nulls last,
        case when v_sort='completeness' and v_dir='asc' then completeness_score_v2 end asc,
        case when v_sort='completeness' and v_dir='desc' then completeness_score_v2 end desc,
        case when v_sort='modified' and v_dir='asc' then updated_at end asc,
        case when v_sort='modified' and v_dir='desc' then updated_at end desc,
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
        lower(canonical_title),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg((to_jsonb(o)-'total_count')||jsonb_build_object('university_groups',security.provider_university_groups(o.provider_id))),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir
    ) from ordered o
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.ui_prisms_student_flow_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_study_area_code text DEFAULT NULL::text, p_sector_code text DEFAULT NULL::text, p_remoteness_area text DEFAULT NULL::text, p_suppressed boolean DEFAULT NULL::boolean, p_sort text DEFAULT 'geography'::text, p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'geography'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return (
    with raw as (
      select sfo.*,om.code metric_code,sub.code subdivision_code,sub.name subdivision_name,
        src.label source_label,src.url source_url,e.source_url evidence_url,e.captured_at evidence_captured_at,
        nullif(sfo.metadata->>'source_row','')::integer source_row
      from catalogue.student_flow_observations sfo
      join ref.outcome_surveys os on os.id=sfo.survey_id and os.code='prisms_international_students'
      join ref.outcome_metrics om on om.id=sfo.metric_id
      left join ref.subdivisions sub on sub.id=sfo.subdivision_id
      left join pipeline.sources src on src.id=sfo.source_id
      left join pipeline.evidence_artifacts e on e.id=sfo.evidence_id
      where (nullif(trim(coalesce(p_query,'')),'') is null
        or coalesce(sfo.source_geography_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_study_area_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_sector_code,'') ilike '%'||trim(p_query)||'%'
        or coalesce(sfo.source_remoteness_area,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or sub.code=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_study_area_code,'')),'') is null or sfo.source_study_area_code=trim(p_study_area_code))
        and (nullif(trim(coalesce(p_sector_code,'')),'') is null or sfo.source_sector_code=trim(p_sector_code))
        and (nullif(trim(coalesce(p_remoteness_area,'')),'') is null or sfo.source_remoteness_area=trim(p_remoteness_area))
        and (p_suppressed is null or sfo.is_suppressed=p_suppressed)
    ), paired as (
      select md5(concat_ws('|',coalesce(source_row::text,''),coalesce(source_geography_key,''),coalesce(source_study_area_code,''),coalesce(source_sector_code,''),coalesce(source_remoteness_area,''),coalesce(period_start::text,''),coalesce(period_end::text,''))) id,
        source_row,subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,
        source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,
        max(metric_value) filter(where metric_code='enrolments') enrolments,
        max(metric_value) filter(where metric_code='commencements') commencements,
        bool_or(is_suppressed) suppressed,
        string_agg(distinct suppression_code,', ' order by suppression_code) filter(where suppression_code is not null) suppression_codes,
        count(distinct evidence_id)::bigint evidence_count,
        max(evidence_captured_at) evidence_captured_at,max(evidence_url) evidence_url,max(source_label) source_label,max(source_url) source_url,
        max(updated_at) updated_at
      from raw
      group by source_row,subdivision_code,subdivision_name,source_geography_key,source_geography_name,source_geography_type,source_study_area_code,source_study_area_name,source_sector_code,source_remoteness_area,period_start,period_end,period_type,audience,source_nationality_code,source_provider_type
    ), numbered as (select *,count(*) over()::bigint total_count from paired), ordered as (
      select * from numbered order by
        case when v_sort='geography' and v_dir='asc' then lower(source_geography_name) end asc,
        case when v_sort='geography' and v_dir='desc' then lower(source_geography_name) end desc,
        case when v_sort='state' and v_dir='asc' then subdivision_code end asc,
        case when v_sort='state' and v_dir='desc' then subdivision_code end desc,
        case when v_sort='study_area' and v_dir='asc' then lower(source_study_area_name) end asc,
        case when v_sort='study_area' and v_dir='desc' then lower(source_study_area_name) end desc,
        case when v_sort='enrolments' and v_dir='asc' then enrolments end asc nulls first,
        case when v_sort='enrolments' and v_dir='desc' then enrolments end desc nulls last,
        case when v_sort='commencements' and v_dir='asc' then commencements end asc nulls first,
        case when v_sort='commencements' and v_dir='desc' then commencements end desc nulls last,
        case when v_sort='period' and v_dir='asc' then period_end end asc,
        case when v_sort='period' and v_dir='desc' then period_end end desc,
        lower(source_geography_name),lower(source_study_area_name),source_sector_code,source_row,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end $function$;

CREATE OR REPLACE FUNCTION public.ui_qilt_outcomes_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_survey_code text DEFAULT NULL::text, p_metric_code text DEFAULT NULL::text, p_provider_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_year integer DEFAULT NULL::integer, p_sort text DEFAULT 'provider'::text, p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return (
    with base as (
      select po.id,po.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
        c.iso_alpha2::text country_code,c.name country_name,
        os.code survey_code,os.name survey_name,om.code metric_code,om.name metric_name,om.unit metric_unit,om.category metric_category,
        po.metric_value,po.national_benchmark,po.response_count,po.audience,po.collection_year_from,po.collection_year_to,
        po.observed_at,po.status,po.source_institution_key,po.source_cohort_code,po.updated_at,
        po.evidence_id,e.source_url evidence_url,e.captured_at evidence_captured_at,
        po.source_id,s.label source_label,s.url source_url
      from catalogue.provider_outcomes po
      join catalogue.providers p on p.id=po.provider_id
      join ref.countries c on c.id=p.country_id
      join ref.outcome_surveys os on os.id=po.survey_id and os.code like 'qilt_%'
      join ref.outcome_metrics om on om.id=po.metric_id
      left join pipeline.evidence_artifacts e on e.id=po.evidence_id
      left join pipeline.sources s on s.id=po.source_id
      where (nullif(trim(coalesce(p_query,'')),'') is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
          or os.name ilike '%'||trim(p_query)||'%'
          or om.name ilike '%'||trim(p_query)||'%'
          or coalesce(po.source_institution_key,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_survey_code,'')),'') is null or os.code=trim(p_survey_code))
        and (nullif(trim(coalesce(p_metric_code,'')),'') is null or om.code=trim(p_metric_code))
        and (p_provider_id is null or po.provider_id=p_provider_id)
        and (nullif(trim(coalesce(p_status,'')),'') is null or po.status=trim(p_status))
        and (p_year is null or p_year between coalesce(po.collection_year_from,p_year) and coalesce(po.collection_year_to,p_year))
    ), numbered as (select *,count(*) over()::bigint total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='survey' and v_dir='asc' then survey_code end asc,
        case when v_sort='survey' and v_dir='desc' then survey_code end desc,
        case when v_sort='metric' and v_dir='asc' then metric_code end asc,
        case when v_sort='metric' and v_dir='desc' then metric_code end desc,
        case when v_sort='value' and v_dir='asc' then metric_value end asc nulls first,
        case when v_sort='value' and v_dir='desc' then metric_value end desc nulls last,
        case when v_sort='benchmark' and v_dir='asc' then national_benchmark end asc nulls first,
        case when v_sort='benchmark' and v_dir='desc' then national_benchmark end desc nulls last,
        case when v_sort='responses' and v_dir='asc' then response_count end asc nulls first,
        case when v_sort='responses' and v_dir='desc' then response_count end desc nulls last,
        case when v_sort='year' and v_dir='asc' then collection_year_to end asc nulls first,
        case when v_sort='year' and v_dir='desc' then collection_year_to end desc nulls last,
        lower(provider_name),survey_code,metric_code,id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end $function$;

CREATE OR REPLACE FUNCTION public.ui_scholarships_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_lifecycle_status text DEFAULT NULL::text, p_publication_status text DEFAULT NULL::text, p_sort text DEFAULT 'scholarship'::text, p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'scholarship', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare v_limit int:=least(greatest(coalesce(p_limit,50),1),200);v_offset int:=greatest(coalesce(p_offset,0),0);v_sort text:=lower(coalesce(p_sort,'scholarship'));v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 if security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
 return (with base as (
  select s.id,s.stable_key,s.name,s.scholarship_type,s.description,s.audience,s.award_value_text,s.award_value_type,s.award_percentage,s.award_amount,s.award_currency_code,s.academic_year,s.application_required,s.application_open_date,s.application_close_date,s.lifecycle_status,s.publication_status,s.source_url,s.created_at,s.updated_at,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
   (select count(*)::int from scholarship.offering_cycles oc where oc.scholarship_id=s.id) cycle_count,
   (select count(*)::int from scholarship.application_windows aw where aw.scholarship_id=s.id) window_count,
   (select count(*)::int from pipeline.evidence_artifacts e where e.entity_id=s.id)+case when s.evidence_id is not null then 1 else 0 end evidence_count,
   (select count(*)::int from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped') mapped_course_count,
   (select count(*)::int from scholarship.course_mapping_candidates mc where mc.scholarship_id=s.id and mc.status='needs_review') review_course_count,
   left(regexp_replace(coalesce(s.description,''),'\s+',' ','g'),220) description_excerpt
  from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id left join ref.countries co on co.id=p.country_id
  where (nullif(trim(coalesce(p_query,'')),'') is null or s.name ilike '%'||trim(p_query)||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%' or coalesce(s.stable_key,'') ilike '%'||trim(p_query)||'%' or coalesce(s.description,'') ilike '%'||trim(p_query)||'%' or coalesce(s.award_value_text,'') ilike '%'||trim(p_query)||'%' or coalesce(s.scholarship_type,'') ilike '%'||trim(p_query)||'%' or coalesce(s.academic_year::text,'') ilike '%'||trim(p_query)||'%')
   and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
   and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or s.lifecycle_status=trim(p_lifecycle_status))
   and (nullif(trim(coalesce(p_publication_status,'')),'') is null or s.publication_status=trim(p_publication_status))
 ), numbered as(select *,count(*) over() total_count from base), ordered as(select * from numbered order by
   case when v_sort='scholarship' and v_dir='asc' then lower(name) end asc,case when v_sort='scholarship' and v_dir='desc' then lower(name) end desc,
   case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
   case when v_sort='award' and v_dir='asc' then coalesce(award_percentage,award_amount) end asc nulls last,case when v_sort='award' and v_dir='desc' then coalesce(award_percentage,award_amount) end desc nulls last,
   case when v_sort='year' and v_dir='asc' then academic_year end asc nulls last,case when v_sort='year' and v_dir='desc' then academic_year end desc nulls last,
   case when v_sort='close' and v_dir='asc' then application_close_date end asc nulls last,case when v_sort='close' and v_dir='desc' then application_close_date end desc nulls last,
   case when v_sort='courses' and v_dir='asc' then mapped_course_count end asc,case when v_sort='courses' and v_dir='desc' then mapped_course_count end desc,
   case when v_sort='evidence' and v_dir='asc' then evidence_count end asc,case when v_sort='evidence' and v_dir='desc' then evidence_count end desc,
   case when v_sort='updated' and v_dir='asc' then updated_at end asc,case when v_sort='updated' and v_dir='desc' then updated_at end desc,
   lower(name),id limit v_limit offset v_offset)
 select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_a15_acceptance_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'search', 'publishing', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_metrics jsonb;
  v_key_contacts jsonb;
  v_watch jsonb;
  v_security jsonb;
  v_authority jsonb;
  v_ok boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  v_metrics:=jsonb_build_object(
    'profile_total',(select count(*) from pipeline.provider_contact_profiles),
    'profile_au',(select count(*) from pipeline.provider_contact_profiles p join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU'),
    'profile_nz',(select count(*) from pipeline.provider_contact_profiles p join ref.countries c on c.id=p.country_id where c.iso_alpha2='NZ'),
    'profile_success',(select count(*) from pipeline.provider_contact_profiles where last_success_at is not null and last_error is null),
    'profile_errors',(select count(*) from pipeline.provider_contact_profiles where last_error is not null),
    'current_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected'),
    'contact_providers',(select count(distinct provider_id) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected'),
    'territory_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(territory_text),'') is not null),
    'rejected_contacts',(select count(*) from pipeline.provider_contact_observations where verification_state='rejected'),
    'email_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(work_email),'') is not null),
    'phone_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(work_phone),'') is not null),
    'reviewed_rejection_violations',(
      select count(*) from pipeline.provider_contact_observations
      where metadata ? 'a15_quality_review_at'
        and metadata ? 'a15_quality_disposition'
        and not (metadata ? 'a15_quality_reconciliation')
        and (verification_state<>'rejected' or is_current)
    )
  );

  v_key_contacts:=jsonb_build_object(
    'uow',(
      select count(*)=5
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='university of wollongong'
        and o.is_current and o.verification_state='current'
        and o.metadata->>'a15_quality_reconciliation'='uow_first_party_regional_experts'
    ),
    'vu',(
      select count(*)=2
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='victoria university'
        and o.is_current and o.verification_state='current'
        and o.full_name is null and o.job_title='International Student Enquiries'
        and o.team_name='VU International' and o.work_email='international@vu.edu.au'
        and o.work_phone='+61 3 9919 1164'
        and o.metadata->>'a15_quality_reconciliation'='vu_final_preferred_contact'
    ),
    'wellington',exists(
      select 1
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='victoria university of wellington'
        and o.is_current and o.verification_state='current' and o.full_name is null
        and o.job_title='International Student Experience' and o.team_name='International Student Experience'
        and o.work_email='international-support@vuw.ac.nz' and o.work_phone='+64 4 463 5350'
        and o.metadata->>'a15_quality_reconciliation'='wellington_international_student_experience'
    ),
    'sydney',(
      select count(*)=4
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='the university of sydney'
        and o.is_current and o.verification_state='current'
        and o.team_name='International Recruitment'
        and o.source_url='https://www.sydney.edu.au/study/applying/how-to-apply/international-students/contact-our-regional-experts.html'
        and o.metadata->>'a15_quality_reconciliation'='sydney_first_party_regional_experts'
        and (o.full_name,o.job_title,o.territory_text,o.work_email) in (
          ('Chris Lawrance','Regional Manager','Americas and Europe','chris.lawrance@sydney.edu.au'),
          ('Nishant Jadhav','Senior Regional Manager','Central Asia, South Asia, Middle East and Africa','nishant.jadhav@sydney.edu.au'),
          ('Sean Lee','Senior Regional Manager','Asia (excluding China, Hong Kong and Macau)','sean.lee@sydney.edu.au'),
          ('Sherrie Huan','Senior Regional Manager','China, Hong Kong and Macau','sherrie.huan@sydney.edu.au')
        )
    ),
    'otago',exists(
      select 1 from pipeline.provider_contact_observations o join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='university of otago'
        and o.is_current and o.verification_state='current' and o.full_name is null
        and o.job_title='International Marketing and Recruitment'
        and o.team_name='International Marketing and Recruitment'
        and o.metadata->>'a15_quality_reconciliation'='otago_team_contact'
    )
  );

  v_watch:=jsonb_build_object(
    'contact_removed_count',(select count(*) from pipeline.provider_contact_watch_events where event_type='contact_removed'),
    'contact_restored_count',(select count(*) from pipeline.provider_contact_watch_events where event_type='contact_restored'),
    'removal_supported',position('contact_removed' in pg_get_functiondef('public.provider_contact_profile_reconcile_service(uuid,text[],integer)'::regprocedure))>0,
    'restoration_supported',position('contact_restored' in pg_get_functiondef('public.provider_contact_observation_upsert_service(jsonb)'::regprocedure))>0
  );

  v_security:=jsonb_build_object(
    'rls_enabled',(
      select bool_and(c.relrowsecurity)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='pipeline' and c.relname in (
        'provider_contact_profiles','provider_contact_observations',
        'provider_contact_watch_events','provider_contact_enrichment_attempts'
      )
    ),
    'no_direct_table_grants',not exists(
      select 1 from information_schema.role_table_grants
      where table_schema='pipeline'
        and table_name in (
          'provider_contact_profiles','provider_contact_observations',
          'provider_contact_watch_events','provider_contact_enrichment_attempts'
        )
        and grantee in ('anon','authenticated','PUBLIC')
    ),
    'service_upsert_private',
      not has_function_privilege('anon','public.provider_contact_observation_upsert_service(jsonb)','execute')
      and not has_function_privilege('authenticated','public.provider_contact_observation_upsert_service(jsonb)','execute'),
    'service_reconcile_private',
      not has_function_privilege('anon','public.provider_contact_profile_reconcile_service(uuid,text[],integer)','execute')
      and not has_function_privilege('authenticated','public.provider_contact_profile_reconcile_service(uuid,text[],integer)','execute')
  );

  v_authority:=jsonb_build_object(
    'providers',(select count(*) from catalogue.providers),
    'courses',(select count(*) from catalogue.courses),
    'search_documents',(select count(*) from search.course_documents),
    'publication_entity_states',(select count(*) from publishing.entity_states),
    'publication_events',(select count(*) from publishing.publication_events),
    'publication_approvals',(select count(*) from publishing.publication_approvals),
    'expected',jsonb_build_object(
      'providers',3085,'courses',43461,'search_documents',33105,
      'publication_entity_states',0,'publication_events',9,'publication_approvals',2
    )
  );

  v_ok:=v_metrics @> jsonb_build_object(
      'profile_total',60,'profile_au',52,'profile_nz',8,'profile_success',60,'profile_errors',0,
      'current_contacts',31,'contact_providers',11,'territory_contacts',17,'rejected_contacts',45,
      'email_contacts',30,'phone_contacts',18,'reviewed_rejection_violations',0
    )
    and coalesce((v_key_contacts->>'uow')::boolean,false)
    and coalesce((v_key_contacts->>'vu')::boolean,false)
    and coalesce((v_key_contacts->>'wellington')::boolean,false)
    and coalesce((v_key_contacts->>'sydney')::boolean,false)
    and coalesce((v_key_contacts->>'otago')::boolean,false)
    and coalesce((v_watch->>'removal_supported')::boolean,false)
    and coalesce((v_watch->>'restoration_supported')::boolean,false)
    and coalesce((v_watch->>'contact_removed_count')::integer,0)>0
    and coalesce((v_security->>'rls_enabled')::boolean,false)
    and coalesce((v_security->>'no_direct_table_grants')::boolean,false)
    and coalesce((v_security->>'service_upsert_private')::boolean,false)
    and coalesce((v_security->>'service_reconcile_private')::boolean,false)
    and (v_authority-'expected')=(v_authority->'expected');

  return jsonb_build_object(
    'ok',v_ok,
    'change_control','CF-CHG-20260829-046',
    'frozen_baseline','A15-60-profile-first-party-v1',
    'metrics',v_metrics,
    'key_contacts',v_key_contacts,
    'watch_events',v_watch,
    'security',v_security,
    'authority',v_authority,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$;

CREATE OR REPLACE FUNCTION security.admin_automations_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return jsonb_build_object('generated_at',now(),'rank',security.current_role_rank(),
    'jobs',(select coalesce(jsonb_agg(jsonb_build_object(
        'job',j.jobname,'area',coalesce(c.area,'Other'),'sort',coalesce(c.sort,999),'label',coalesce(c.label,j.jobname),'description',coalesce(c.description,''),
        'schedule',j.schedule,'active',j.active,'control_rank',coalesce(c.control_rank,6),
        'batch',case when coalesce(c.batch_editable,false) then security.automation_batch(j.command) end,
        'last',(select jsonb_build_object('at',d.start_time,'status',d.status,'seconds',round(extract(epoch from (d.end_time-d.start_time))::numeric,1),'message',case when d.status<>'succeeded' then left(d.return_message,200) end)
                  from cron.job_run_details d where d.jobid=j.jobid order by d.start_time desc limit 1),
        'runs_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours'),
        'failed_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours' and d.status='failed')
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_campus_detail(p_campus_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,
    'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),
    'country_code',co.iso_alpha2,'country_name',co.name,'subdivision_code',sd.code,'subdivision_name',sd.name,
    'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,
    'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,
    'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,
    'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,
    'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),
    'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,
    'courses_page',coalesce((
      with base as (
        select c.id,c.stable_key,c.canonical_title,c.course_code,c.lifecycle_status,c.publication_status,cc.delivery_mode,cc.is_primary
        from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
        where cc.campus_id=ca.id
      ), numbered as (select *,count(*) over() total_count from base), ordered as (
        select * from numbered order by lower(canonical_title),id limit 25
      )
      select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0) from ordered o
    ),jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'scholarship_count',(select count(distinct ss.scholarship_id) from scholarship.scopes ss where ss.campus_id=ca.id and coalesce(ss.include_exclude,'include')='include')
  ) into v_result
  from catalogue.campuses ca
  join catalogue.providers p on p.id=ca.provider_id
  join ref.countries co on co.id=ca.country_id
  left join ref.subdivisions sd on sd.id=ca.subdivision_id
  left join pipeline.sources s on s.id=ca.source_id
  left join pipeline.evidence_artifacts e on e.id=ca.evidence_id
  where ca.id=p_campus_id;

  return coalesce(v_result,'{}'::jsonb);
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_campus_page_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  v_simple :=
    nullif(trim(coalesce(p_args->>'query','')),'') is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'status','') is null
    and nullif(p_args->>'publication_status','') is null
    and v_sort in ('name','campus')
    and v_dir='asc';

  if not v_simple then
    return security.admin_catalogue_page('campuses_page',p_args);
  end if;

  select count(*) into v_total from catalogue.campuses;

  with paged as (
    select
      ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,
      ca.subdivision_id,ca.city,ca.status,ca.publication_status,
      ca.last_verified_at,ca.created_at,ca.updated_at
    from catalogue.campuses ca
    order by lower(ca.name),ca.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.name,pg.campus_code,pg.provider_id,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,
      sd.code subdivision_code,sd.name subdivision_name,
      pg.city,pg.status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,
      coalesce(cc.course_count,0)::int course_count
    from paged pg
    join catalogue.providers p on p.id=pg.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.subdivisions sd on sd.id=pg.subdivision_id
    left join lateral (
      select count(*)::int course_count
      from catalogue.course_campuses cc
      where cc.campus_id=pg.id
    ) cc on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'sort','name',
    'direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  )
  into v_result
  from enriched e;

  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_options(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_country text := upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text := upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  if p_operation='provider_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct c.iso_alpha2::text code,c.name
          from ref.countries c
          where exists(select 1 from catalogue.providers p where p.country_id=c.id)
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from ref.subdivisions s
          join ref.countries c on c.id=s.country_id
          where (v_country is null or c.iso_alpha2::text=v_country)
            and (
              exists(select 1 from catalogue.providers p where p.subdivision_id=s.id)
              or exists(select 1 from catalogue.campuses cp where cp.subdivision_id=s.id)
            )
        ) x
      ),'[]'::jsonb)
    );
  elsif p_operation='course_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct co.iso_alpha2::text code,co.name
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          join catalogue.course_campuses cc on cc.course_id=c.id
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where (v_country is null or co.iso_alpha2::text=v_country)
        ) x
      ),'[]'::jsonb),
      'providers',coalesce((
        select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name)
        from (
          select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1
              from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'levels',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name)
        from (
          select distinct sl.code,sl.name,sl.sort_order
          from catalogue.courses c
          join ref.study_levels sl on sl.id=c.study_level_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'fields',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct fos.code,fos.name
          from catalogue.courses c
          join ref.fields_of_study fos on fos.id=c.primary_field_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'delivery_modes',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code)
        from (
          select distinct cc.delivery_mode code
          from catalogue.course_campuses cc
          join catalogue.courses c on c.id=cc.course_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
            and (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc2
              join catalogue.campuses cp2 on cp2.id=cc2.campus_id
              join ref.subdivisions s2 on s2.id=cp2.subdivision_id
              where cc2.course_id=c.id and s2.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb)
    );
  end if;

  raise exception 'unsupported catalogue filter operation: %',p_operation using errcode='22023';
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text:=upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),10);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if v_kind='country' then
    with q as (
      select distinct co.iso_alpha2::text value,co.name label,co.iso_alpha2::text meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where v_query is null or lower(co.name||' '||co.iso_alpha2::text) like '%'||v_query||'%'
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='subdivision' then
    with q as (
      select distinct s.code value,s.name label,s.code meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      join catalogue.course_campuses cc on cc.course_id=c.id
      join catalogue.campuses cp on cp.id=cc.campus_id
      join ref.subdivisions s on s.id=cp.subdivision_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='provider' then
    with q as (
      select distinct p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='level' then
    with q as (
      select distinct sl.code value,sl.name label,sl.code meta,sl.sort_order
      from catalogue.courses c
      join ref.study_levels sl on sl.id=c.study_level_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(sl.name||' '||sl.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select value,label,meta from q order by sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta)) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='field' then
    with q as (
      select distinct fos.code value,fos.name label,fos.code meta
      from catalogue.courses c
      join ref.fields_of_study fos on fos.id=c.primary_field_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    with q as (
      select distinct cc.delivery_mode value,cc.delivery_mode label,cc.delivery_mode meta
      from catalogue.course_campuses cc
      join catalogue.courses c on c.id=cc.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
        and (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc2
          join catalogue.campuses cp2 on cp2.id=cc2.campus_id
          join ref.subdivisions s2 on s2.id=cp2.subdivision_id
          where cc2.course_id=c.id and s2.code=v_subdivision
        ))
        and (v_query is null or lower(cc.delivery_mode) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  elsif v_kind='university_group' then
    with q as (
      select replace(ic.code,'au_','') value,ic.name label,
             (select count(*)::int from security.university_group_provider_ids(ic.code) g) provider_count,
             (select count(*)::int from catalogue.courses c where c.provider_id in (select security.university_group_provider_ids(ic.code))) course_count
      from ref.institution_collections ic
      join ref.countries co on co.id=ic.country_id
      where ic.collection_type='university_group' and ic.status='active'
        and (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(ic.name||' '||replace(ic.code,'au_','')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,
                       'meta',provider_count||case when provider_count=1 then ' university' else ' universities' end,
                       'count',course_count,'course_count',course_count,'provider_count',provider_count) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  else
    raise exception 'unsupported catalogue filter kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  );
end $function$;

CREATE OR REPLACE FUNCTION security.admin_catalogue_page(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'catalogue', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_result jsonb;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if p_operation='providers_page' then
    return security.admin_providers_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''));
  elsif p_operation='courses_page' then
    return public.ui_courses_decision_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),v_has_fee,v_has_intake,v_has_english,v_has_scholarship,nullif(p_args->>'min_completeness','')::numeric,nullif(p_args->>'freshness',''),coalesce(nullif(p_args->>'sort',''),'course'),v_dir,v_has_state,v_has_link,nullif(p_args->>'university_group',''));
  elsif p_operation='scholarships_page' then
    return security.admin_scholarships_page(p_args);
  elsif p_operation='campuses_page' then
    with base as (
      select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,sd.code subdivision_code,sd.name subdivision_name,ca.city,ca.status,ca.publication_status,ca.last_verified_at,ca.created_at,ca.updated_at,(select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
      from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=p.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null or ca.name ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.campus_code,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.stable_key,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.city,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (nullif(p_args->>'subdivision_code','') is null or sd.code=upper(p_args->>'subdivision_code'))
        and (v_provider_id is null or ca.provider_id=v_provider_id)
        and (nullif(p_args->>'status','') is null or ca.status=p_args->>'status')
        and (nullif(p_args->>'publication_status','') is null or ca.publication_status=p_args->>'publication_status')
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort in ('name','campus') and v_dir='asc' then lower(name) end asc,
        case when v_sort in ('name','campus') and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,
        case when v_sort='courses' and v_dir='desc' then course_count end desc,
        case when v_sort='modified' and v_dir='asc' then updated_at end asc,
        case when v_sort='modified' and v_dir='desc' then updated_at end desc,
        lower(name),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o;
    return v_result;
  else
    raise exception 'unsupported catalogue page operation: %',p_operation using errcode='22023';
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_coverage_read(p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'auth'
AS $function$
declare v_tier text:=nullif(p_args->>'tier',''); v jsonb;
  v_cstate text:=nullif(p_args->>'completeness_state','');
  -- Decision 213: country (ISO code) and provider filters
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country','')),''));
  v_provider uuid:=nullif(p_args->>'provider','')::uuid;
  c_states constant text[]:=array['present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected'];
  c_attrs constant text[]:=array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'];
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if p_operation='course_coverage_providers' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',q.provider_id,'name',q.name,'country',q.country_code,'courses',q.n) order by q.n desc, q.name)
      from (select x.provider_id, max(coalesce(p.display_name,p.canonical_name)) name, max(x.country_code) country_code, count(*) n
              from pipeline.course_completeness x join catalogue.providers p on p.id=x.provider_id
             where (v_country is null or x.country_code=v_country)
               and (coalesce(p_args->>'query','')='' or coalesce(p.display_name,p.canonical_name) ilike '%'||(p_args->>'query')||'%' or p.canonical_name ilike '%'||(p_args->>'query')||'%')
             group by x.provider_id order by count(*) desc limit 30) q),'[]'::jsonb);
  elsif p_operation='course_coverage' then
    with a as (select * from pipeline.course_attribute_coverage x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
         cc as (select * from pipeline.course_completeness x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider))
    select jsonb_build_object(
      'computed_at',(select max(computed_at) from pipeline.course_attribute_coverage),
      'courses',(select count(distinct course_id) from a),
      'providers',(select count(distinct provider_id) from a),
      'tier',v_tier,'country',v_country,
      'provider',case when v_provider is null then null else (select jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.canonical_name)) from catalogue.providers p where p.id=v_provider) end,
      'countries',(select jsonb_agg(jsonb_build_object('code',country_code,'courses',n,'providers',pn) order by n desc) from (
          select country_code, count(*) n, count(distinct provider_id) pn from pipeline.course_completeness group by 1) k),
      'attributes',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',states,'total',total) order by ord) from (
          select attribute, jsonb_object_agg(state,n) states, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute,state,count(*) n from a group by 1,2) s group by attribute) x),
      'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'courses',n,'providers',p) order by tier) from (
          select tier, count(distinct course_id) n, count(distinct provider_id) p from pipeline.course_attribute_coverage
           where (v_country is null or country_code=v_country) group by tier) t),
      -- daily history has no provider dimension: no attribute trend for one provider
      'trend',case when v_provider is null then (select jsonb_agg(jsonb_build_object('date',snapshot_date,'attribute',attribute,'admitted',adm,'total',tot) order by snapshot_date, attribute) from (
          select snapshot_date, attribute, sum(courses) filter (where state='admitted') adm, sum(courses) tot
            from pipeline.course_coverage_daily_by_country where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) and (v_country is null or country_code=v_country) group by 1,2) d) end,
      'completeness_states',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',
            (select jsonb_object_agg(k, coalesce((cs->>k)::int,0)) from unnest(c_states) k),'total',total) order by ord) from (
          select attribute, jsonb_object_agg(cstate,n) cs, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute, security.coverage_completeness_state(state) cstate, sum(n) n from (
                    select attribute,state,count(*) n from a group by 1,2) s0
                  group by 1,2) s group by attribute) x),
      -- Who supplied intakes, English and fees (adapter, central page, reader, hand-entered, other, or missing); snapshot rebuilt hourly.
      'field_sources',(select jsonb_agg(jsonb_build_object('field',z.field,'source',z.src,'courses',z.n) order by z.field,z.src) from (
          select 'intakes' field, s.intakes_src src, count(*) n from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2
          union all select 'english', s.english_src, count(*) from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2
          union all select 'fee', s.fee_src, count(*) from pipeline.course_field_source s where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2) z),
      'field_sources_at',(select max(computed_at) from pipeline.course_field_source),
      'completeness_state_map',(select jsonb_object_agg(s, security.coverage_completeness_state(s))
          from unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']) s),
      'completeness',(select jsonb_build_object(
            'computed_at',max(cc.computed_at),
            'courses',count(*),
            'attributes',max(cc.attributes),
            'completeness',round(avg(cc.completeness),1),
            'accounted_pct',round(avg(cc.accounted_pct),1),
            'fully_complete',count(*) filter (where cc.admitted=cc.attributes),
            'by_admitted',(select jsonb_agg(jsonb_build_object('admitted',b.admitted,'courses',b.n) order by b.admitted) from (
                select c2.admitted, count(*) n from cc c2 group by 1) b),
            'trend',case when v_tier is null then (select jsonb_agg(jsonb_build_object('date',d.snapshot_date,'courses',d.courses,'completeness',d.completeness,
                        'accounted_pct',d.accounted_pct,'fully_complete',d.fully_complete,'computed_at',d.computed_at) order by d.snapshot_date)
                      from pipeline.completeness_daily d where d.snapshot_date>=current_date-60
                       and case when v_provider is not null then d.scope='provider' and d.scope_id=v_provider
                                when v_country is not null then d.scope='country:'||v_country
                                else d.scope='platform' end) end)
          from cc)
    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then
    if v_cstate is not null and not (v_cstate = any(c_states)) then raise exception 'unknown completeness state %', v_cstate; end if;
    select jsonb_build_object('total',(select count(*) from pipeline.course_attribute_coverage x where x.attribute=p_args->>'attribute'
                 and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
                 and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
      'items',coalesce((select jsonb_agg(r) from (
        select x.course_id, c.canonical_title title, coalesce(p.display_name,p.canonical_name) provider_name, x.tier, x.country_code,
               (select min(registration_code) from catalogue.course_registrations cr where cr.course_id=x.course_id and lower(cr.scheme)='cricos') cricos,
               x.state, security.coverage_completeness_state(x.state) completeness_state, cc.completeness, cc.accounted_pct
          from pipeline.course_attribute_coverage x join catalogue.courses c on c.id=x.course_id join catalogue.providers p on p.id=x.provider_id
          left join pipeline.course_completeness cc on cc.course_id=x.course_id
         where x.attribute=p_args->>'attribute'
           and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
           and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)
         order by coalesce(p.display_name,p.canonical_name), c.canonical_title
         limit least(coalesce(nullif(p_args->>'limit','')::int,50),200) offset greatest(coalesce(nullif(p_args->>'offset','')::int,0),0)) r),'[]'::jsonb))
      into v;
    return v;
  end if;
  raise exception 'unknown coverage operation %', p_operation;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_entry_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_rank integer;
begin
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'intakes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'intake_year', i.intake_year,
          'intake_label', i.intake_label,
          'start_date', i.start_date,
          'application_deadline', i.application_deadline,
          'campus_id', i.campus_id,
          'campus', case when ca.id is null then null else jsonb_build_object(
            'id', ca.id,
            'stable_key', ca.stable_key,
            'name', ca.name,
            'city', ca.city,
            'subdivision_code', sd.code,
            'subdivision_name', sd.name,
            'country_code', co.iso_alpha2
          ) end,
          'status', i.status,
          'confidence', i.confidence,
          'source_intake_key', i.source_intake_key,
          'source', jsonb_build_object(
            'source_id', i.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'valid_from', e.valid_from,
            'valid_to', e.valid_to,
            'content_hash', e.content_hash
          ) end
        ) order by i.intake_year, i.start_date nulls last, i.intake_label
      )
      from catalogue.course_intakes i
      left join catalogue.campuses ca on ca.id=i.campus_id
      left join ref.countries co on co.id=ca.country_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      left join pipeline.sources s on s.id=i.source_id
      left join pipeline.evidence_artifacts e on e.id=i.evidence_id
      where i.course_id=p_course_id
    ), '[]'::jsonb),
    'english_requirements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', er.id,
          'test_id', et.id,
          'test_code', et.code,
          'test_name', et.name,
          'score_scale', et.score_scale,
          'overall_score', er.overall_score,
          'component_scores', er.component_scores,
          'notes', er.notes,
          'status', er.status,
          'confidence', er.confidence,
          'source_requirement_key', er.source_requirement_key,
          'valid_from', er.valid_from,
          'valid_to', er.valid_to,
          'last_verified_at', er.last_verified_at,
          'scope', 'course',
          'source', jsonb_build_object(
            'source_id', er.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'valid_from', e.valid_from,
            'valid_to', e.valid_to,
            'content_hash', e.content_hash
          ) end
        ) order by et.code
      )
      from catalogue.course_english_requirements er
      join ref.english_tests et on et.id=er.english_test_id
      left join pipeline.sources s on s.id=er.source_id
      left join pipeline.evidence_artifacts e on e.id=er.evidence_id
      where er.course_id=p_course_id
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_fee_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'auth'
AS $function$
declare
  v_rank integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'fee_used',security.course_fee_used_v1(p_course_id),
    'cricos_registered',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,
        'fee_type',cf.fee_type,
        'amount',cf.amount,
        'currency',cf.currency_code,
        'basis',cf.basis,
        'load_basis',cf.load_basis,
        'fee_year',cf.fee_year,
        'audience',cf.audience,
        'campus_id',cf.campus_id,
        'valid_from',cf.valid_from,
        'valid_to',cf.valid_to,
        'status',cf.status,
        'source_fee_key',cf.source_fee_key,
        'source_id',cf.source_id,
        'source_snapshot_at',cf.source_snapshot_at,
        'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id,
        'source',case when s.id is null then null else jsonb_build_object(
          'id',s.id,'label',s.label,'type',s.source_type,'url',s.url
        ) end,
        'evidence',case when e.id is null then null else jsonb_build_object(
          'id',e.id,'type',e.evidence_type,'source_url',e.source_url,
          'content_hash',e.content_hash,'captured_at',e.captured_at
        ) end
      ) order by case cf.fee_type when 'tuition' then 1 when 'non_tuition' then 2 when 'estimated_total_course_cost' then 3 else 9 end,cf.fee_type)
      from catalogue.course_fees cf
      left join pipeline.sources s on s.id=cf.source_id
      left join pipeline.evidence_artifacts e on e.id=cf.evidence_id
      where cf.course_id=p_course_id
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb),
    'provider_current',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,
        'fee_type',cf.fee_type,
        'amount',cf.amount,
        'currency',cf.currency_code,
        'basis',cf.basis,
        'load_basis',cf.load_basis,
        'fee_year',cf.fee_year,
        'audience',cf.audience,
        'campus_id',cf.campus_id,
        'valid_from',cf.valid_from,
        'valid_to',cf.valid_to,
        'status',cf.status,
        'source_fee_key',cf.source_fee_key,
        'source_id',cf.source_id,
        'source_snapshot_at',cf.source_snapshot_at,
        'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id,
        'source',case when s.id is null then null else jsonb_build_object(
          'id',s.id,'label',s.label,'type',s.source_type,'url',s.url
        ) end,
        'evidence',case when e.id is null then null else jsonb_build_object(
          'id',e.id,'type',e.evidence_type,'source_url',e.source_url,
          'content_hash',e.content_hash,'captured_at',e.captured_at
        ) end
      ) order by cf.fee_year desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc)
      from catalogue.course_fees cf
      left join pipeline.sources s on s.id=cf.source_id
      left join pipeline.evidence_artifacts e on e.id=cf.evidence_id
      where cf.course_id=p_course_id
        and cf.fee_type ~ '^provider_current_'
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb),
    'other',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,
        'basis',cf.basis,'load_basis',cf.load_basis,'fee_year',cf.fee_year,'audience',cf.audience,
        'campus_id',cf.campus_id,'valid_from',cf.valid_from,'valid_to',cf.valid_to,'status',cf.status,
        'source_id',cf.source_id,'source_snapshot_at',cf.source_snapshot_at,'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id
      ) order by cf.created_at desc)
      from catalogue.course_fees cf
      where cf.course_id=p_course_id
        and cf.basis is distinct from 'registered_total_course'
        and not (cf.fee_type ~ '^provider_current_')
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_field_states(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'pim', 'ref', 'security', 'auth'
AS $function$
declare
  c catalogue.courses%rowtype;
  v_l4 text[]:=array[]::text[];
  v_codes text[];
  v_domains text[]:=array[]::text[];
  v_course_url text; v_url_ev uuid;
  v_fee record; v_fee_l3 record; v_reg_tuition int:=0; v_l3_open text;
  v_mode_count int:=0; v_intake_count int:=0; v_english_count int:=0; v_campus_count int:=0; v_reg_count int:=0; v_academic_count int:=0; v_category_count int:=0; v_collection_count int:=0;
  v_fee_state jsonb;
  function_result jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  select * into c from catalogue.courses where id=p_course_id;
  if c.id is null then return '[]'::jsonb; end if;

  select coalesce(array_agg(distinct field_code),array[]::text[]) into v_l4 from pipeline.layer4_course_field_resolutions where course_id=c.id and status='applied';
  -- Provider-scoped Layer 2 sources (Decision 149): the provider's CRICOS codes and the domains its qualified sources admit.
  select coalesce(array_agg(distinct upper(btrim(pr.registration_code))),array[]::text[]) into v_codes
    from catalogue.provider_registrations pr where pr.provider_id=c.provider_id and lower(pr.registration_scheme)='cricos';
  select coalesce(array_agg(distinct d),array[]::text[]) into v_domains
    from pipeline.course_fact_source_qualifications q, unnest(q.admitted_domains) d
   where upper(btrim(q.provider_cricos))=any(v_codes) and q.qualification_status in ('qualified','bounded')
     and not exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type='provider_fee_schedule');

  select cl.url, cl.evidence_id into v_course_url, v_url_ev from catalogue.course_links cl
   where cl.course_id=c.id and cl.link_type='official_course' and coalesce(cl.status,'active')='active'
   order by (cl.audience='international') desc, cl.last_verified_at desc nulls last, cl.created_at desc limit 1;
  v_course_url:=coalesce(nullif(c.course_url,''),v_course_url);

  select f.id, f.evidence_id, f.source_id into v_fee from catalogue.course_fees f
   where f.course_id=c.id and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active'
   order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
  if v_fee.id is not null then
    select w.id, coalesce(p.model_identifier, p.code) model into v_fee_l3 from pipeline.layer3_work_items w
      left join pipeline.layer3_interpretations i on i.id=w.interpretation_id
      left join pipeline.layer3_model_profiles p on p.id=coalesce(i.profile_id,w.profile_id)
     where w.entity_id=c.id and w.status='admitted' and w.evidence_id=v_fee.evidence_id order by w.updated_at desc limit 1;
  end if;
  select count(*) into v_reg_tuition from catalogue.course_fees f
   where f.course_id=c.id and f.fee_type='tuition' and f.basis='registered_total_course' and coalesce(f.status,'active')='active';
  select case when bool_or(w.status in ('pending','reserved','interpreting','validated','admission_pending','failed')) then 'awaiting_l3'
              when bool_or(w.status='layer4_required') then 'awaiting_l4' end
    into v_l3_open from pipeline.layer3_work_items w where w.entity_id=c.id and w.task_class='provider_current_tuition_validation';

  select count(*) into v_intake_count from catalogue.course_intakes i where i.course_id=c.id and coalesce(i.status,'active')='active';
  select count(*) into v_english_count from catalogue.course_english_requirements e where e.course_id=c.id and coalesce(e.status,'active')='active';
  select count(*), count(*) filter (where nullif(cc.delivery_mode,'') is not null) into v_campus_count, v_mode_count from catalogue.course_campuses cc where cc.course_id=c.id;
  select count(*) into v_reg_count from catalogue.course_regulatory_observations r where r.course_id=c.id and r.valid_to is null;
  select count(*) into v_academic_count from catalogue.course_academic_options a where a.course_id=c.id and coalesce(a.status,'active')='active';
  select count(*) into v_category_count from pim.entity_categories ec join pim.entity_registry er on er.id=ec.entity_id where er.entity_type='course' and er.stable_key=c.stable_key;
  select count(*) into v_collection_count from catalogue.course_collection_memberships m where m.course_id=c.id;

  -- Provider tuition (Decision 162: CRICOS registered tuition is the Layer 1 figure; provider tuition is a refinement).
  if v_fee.id is not null then
    v_fee_state:=jsonb_build_object('value_state','resolved',
      'resolved_layer',case when 'provider_current_tuition'=any(v_l4) then 4 when v_fee_l3.id is not null then 3 else 2 end,
      'resolved_by',case when 'provider_current_tuition'=any(v_l4) then 'Layer 4 resolution' when v_fee_l3.id is not null then 'Layer 3 · '||coalesce(v_fee_l3.model,'qualified model') when exists (select 1 from pipeline.sources fs where fs.id=v_fee.source_id and fs.source_type='provider_fee_schedule') then 'Layer 2 provider fee schedule' else 'Layer 2 provider rule' end,
      'evidence_id',v_fee.evidence_id);
  elsif v_l3_open is not null then
    v_fee_state:=jsonb_build_object('value_state',v_l3_open,'resolved_layer',null);
  elsif 'international_fee'=any(v_domains) then
    v_fee_state:=jsonb_build_object('value_state','awaiting_l2','resolved_layer',null);
  elsif v_reg_tuition>0 then
    v_fee_state:=jsonb_build_object('value_state','l1_covers','resolved_layer',1,'resolved_by','CRICOS registered international tuition applies');
  else
    v_fee_state:=jsonb_build_object('value_state','not_collected','resolved_layer',null);
  end if;

  function_result:=jsonb_build_array(
    jsonb_build_object('code','provider','label','Provider','group','Identity','value_state',case when c.provider_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','course_code','label','CRICOS / Course code','group','Identity','value_state',case when nullif(c.course_code,'') is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','study_level','label','Study level','group','Identity','value_state',case when c.study_level_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','field_of_study','label','Field of study','group','Identity','value_state',case when c.primary_field_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','duration','label','Duration','group','Course facts','value_state',case when c.duration_value is not null then 'resolved' else 'not_collected' end,'resolved_layer',case when 'duration'=any(v_l4) then 4 when c.duration_value is not null then 1 end,'resolved_by',case when 'duration'=any(v_l4) then 'Layer 4 resolution' else 'CRICOS' end,'editable_l4',true,'authority','Layer 1'),
    jsonb_build_object('code','delivery_mode','label','Delivery mode','group','Course facts','value_state',case when nullif(c.delivery_mode,'') is not null or v_mode_count>0 then 'resolved' else 'not_collected' end,'resolved_layer',case when 'delivery_mode'=any(v_l4) then 4 when nullif(c.delivery_mode,'') is not null or v_mode_count>0 then 1 end,'resolved_by',case when 'delivery_mode'=any(v_l4) then 'Layer 4 resolution' else 'CRICOS course locations' end,'editable_l4',true,'authority','Layer 1'),
    jsonb_build_object('code','official_course_url','label','Official Course URL','group','Course facts','value_state',case when v_course_url is not null then 'resolved' when 'official_course_url'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'official_course_url'=any(v_l4) then 4 when v_course_url is not null then 2 end,'resolved_by',case when 'official_course_url'=any(v_l4) then 'Layer 4 resolution' when v_course_url is not null then 'Layer 2 provider rule' end,'evidence_id',v_url_ev,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','course_description','label','Course description','group','Course facts','value_state',case when nullif(c.description,'') is not null then 'resolved' when 'official_course_url'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'course_description'=any(v_l4) then 4 when nullif(c.description,'') is not null then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','provider_current_tuition','label','Current Provider tuition','group','Fees','editable_l4',true,'authority','Enrichment')||v_fee_state,
    jsonb_build_object('code','intakes','label','Intakes','group','Entry & availability','value_state',case when v_intake_count>0 then 'resolved' when 'intake'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'intakes'=any(v_l4) then 4 when v_intake_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','english_requirement','label','English requirement','group','Entry & availability','value_state',case when v_english_count>0 then 'resolved' when 'english_requirement'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'english_requirement'=any(v_l4) then 4 when v_english_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','campuses','label','Campuses','group','Delivery','value_state',case when v_campus_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','academic_options','label','Academic options','group','Structure','value_state',case when v_academic_count>0 then 'resolved' else 'not_collected' end,'resolved_layer',case when v_academic_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','categories','label','Categories','group','Structure','value_state',case when v_category_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_category_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','collections','label','Collections','group','Structure','value_state',case when v_collection_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_collection_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','regulatory_facts','label','Regulatory facts','group','Regulatory','value_state',case when v_reg_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','publication','label','Publication','group','Governance','value_state','resolved','resolved_layer',null,'editable_l4',false,'authority','Governed action')
  );
  return function_result;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'public', 'auth'
AS $function$
declare
  v_q text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_provider_id uuid;
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  v_simple :=
    v_q is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'level_code','') is null
    and nullif(p_args->>'field_code','') is null
    and nullif(p_args->>'delivery_mode','') is null
    and nullif(p_args->>'lifecycle_status','') is null
    and nullif(p_args->>'publication_status','') is null
    and nullif(p_args->>'has_fee','') is null
    and nullif(p_args->>'has_intake','') is null
    and nullif(p_args->>'has_english','') is null
    and nullif(p_args->>'has_scholarship','') is null
    and nullif(p_args->>'has_state','') is null
    and nullif(p_args->>'has_link','') is null
    and nullif(p_args->>'min_completeness','') is null
    and nullif(p_args->>'freshness','') is null
    and nullif(p_args->>'university_group','') is null
    and nullif(p_args->>'applicant','') is null
    and v_sort='course' and v_dir='asc';

  if v_simple then
    return security.admin_course_page_unfiltered_fast(p_args);
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where c.stable_key=v_q limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where upper(c.course_code)=upper(v_q) limit 1;
  end if;

  if v_provider_id is not null and nullif(p_args->>'provider_id','') is null then
    return security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text));
  end if;

  return security.admin_course_page_fast_base(p_args);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_fast_base(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
  v_min_completeness numeric:=nullif(p_args->>'min_completeness','')::numeric;
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  -- Fee/readiness ordering is still intentionally not promoted by the v2.10 UI.
  -- Preserve the accepted legacy implementation only for explicit direct callers of
  -- those derived sorts. All normal derived filters remain in the bounded fast path.
  if v_sort in ('fee','completeness') then
    return security.admin_course_page_search_state(public.ui_courses_decision_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,
      nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      v_has_fee,v_has_intake,v_has_english,v_has_scholarship,v_min_completeness,nullif(p_args->>'freshness',''),
      v_sort,v_dir,v_has_state,v_has_link,v_group
    ));
  end if;

  with base as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    where (nullif(trim(coalesce(p_args->>'query','')),'') is null
      or c.canonical_title ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%')
      and (nullif(trim(coalesce(p_args->>'country_code','')),'') is null or co.iso_alpha2::text=upper(trim(p_args->>'country_code')))
      and (v_provider_id is null or c.provider_id=v_provider_id)
      and (v_group is null or c.provider_id in (select security.university_group_provider_ids(v_group)))
      and (nullif(trim(coalesce(p_args->>'level_code','')),'') is null or sl.code=trim(p_args->>'level_code'))
      and (nullif(trim(coalesce(p_args->>'field_code','')),'') is null or fos.code=trim(p_args->>'field_code'))
      and (nullif(trim(coalesce(p_args->>'lifecycle_status','')),'') is null or c.lifecycle_status=trim(p_args->>'lifecycle_status'))
      and (nullif(trim(coalesce(p_args->>'publication_status','')),'') is null or c.publication_status=trim(p_args->>'publication_status'))
      and (nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        join ref.subdivisions sd on sd.id=ca.subdivision_id
        where cc.course_id=c.id and sd.code=upper(trim(p_args->>'subdivision_code'))))
      and (nullif(trim(coalesce(p_args->>'delivery_mode','')),'') is null
        or coalesce(c.delivery_mode,'')=trim(p_args->>'delivery_mode')
        or exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_args->>'delivery_mode')))
      and (nullif(trim(coalesce(p_args->>'freshness','')),'') is null
        or (p_args->>'freshness'='never_verified' and c.last_verified_at is null)
        or (p_args->>'freshness'='modified_7d' and c.updated_at>=now()-interval '7 days')
        or (p_args->>'freshness'='modified_30d' and c.updated_at>=now()-interval '30 days')
        or (p_args->>'freshness'='stale_180d' and (c.last_verified_at is null or c.last_verified_at<now()-interval '180 days')))
      and (v_has_fee is null or exists(
        select 1 from catalogue.course_fees cf
        where cf.course_id=c.id and coalesce(cf.status,'active')='active')=v_has_fee)
      and (v_has_intake is null or exists(
        select 1 from catalogue.course_intakes ci
        where ci.course_id=c.id and coalesce(ci.status,'active')='active')=v_has_intake)
      and (v_has_english is null or exists(
        select 1 from catalogue.course_english_requirements er
        where er.course_id=c.id and coalesce(er.status,'active')='active')=v_has_english)
      and (v_has_scholarship is null or exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)))=v_has_scholarship)
      and (v_has_state is null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        where cc.course_id=c.id and ca.subdivision_id is not null)=v_has_state)
      and (v_has_link is null or exists(
        select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and l.status='active')=v_has_link)
      and (nullif(p_args->>'applicant','') is null
        or (p_args->>'applicant'='international' and c.open_to_international is true)
        or (p_args->>'applicant'='domestic_only' and c.open_to_international is false)
        or (p_args->>'applicant'='both' and c.open_to_international is true and c.open_to_domestic is true)
        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
      and (v_min_completeness is null or (
        (exists(select 1 from catalogue.course_registrations r where r.course_id=c.id))::int
        +(c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id))::int
        +(exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'))::int
        +(c.description is not null and length(trim(c.description))>0)::int
      )*100.0/6.0 >= v_min_completeness)
  ), numbered as (
    select *,count(*) over() total_count from base
  ), paged as (
    select * from numbered order by
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
      case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
      case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
      case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
      case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
      case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
      case when v_sort='modified' and v_dir='asc' then updated_at end asc,
      case when v_sort='modified' and v_dir='desc' then updated_at end desc,
      case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
      case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
      lower(canonical_title),id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.open_to_international,pg.open_to_domestic,pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else pg.canonical_delivery_mode end delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,coalesce(geo.region_count,0)>0 has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else null end subdivision_name,
      coalesce(geo.region_count,0) region_count,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups,
      pg.total_count
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code from catalogue.course_fees cf
      where cf.course_id=pg.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (select exists(select 1 from scholarship.scopes ss where coalesce(ss.include_exclude,'include')='include' and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))) has_scholarship) sch
    cross join lateral (select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,count(distinct sd.id)::int region_count,min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id left join ref.subdivisions sd on sd.id=ca.subdivision_id where cc.course_id=pg.id
    ) geo on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'),'[]'::jsonb),
    'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
    'execution_profile','paged_enrichment_v3'
  ) into v_result from enriched e;
  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_search_state(p_page jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'search', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(
    i.item || jsonb_build_object(
      'search_projected', d.course_id is not null,
      'search_projection_status', d.publication_status,
      'search_projection_completeness', d.completeness_score,
      'search_projection_version', d.projection_version,
      'search_catalogue_generation', d.catalogue_generation,
      'search_projection_updated_at', d.updated_at,
      'search_projection_generated_at', d.generated_at,
      'search_has_fee', d.has_fee,
      'search_has_intake', d.has_intake,
      'search_has_english', d.has_english,
      'search_has_scholarship', d.has_scholarship
    ) order by i.ord
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(p_page->'items','[]'::jsonb)) with ordinality as i(item,ord)
  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid;

  return jsonb_set(coalesce(p_page,'{}'::jsonb),'{items}',v_items,true);
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_unfiltered_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select count(*) into v_total from catalogue.courses;

  with paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    order by lower(c.canonical_title),c.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else pg.canonical_delivery_mode end delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,coalesce(geo.region_count,0)>0 has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else null end subdivision_name,
      coalesce(geo.region_count,0) region_count,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code
      from catalogue.course_fees cf
      where cf.course_id=pg.id
        and cf.fee_type='tuition'
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
      limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (
      select exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))
      ) has_scholarship
    ) sch
    cross join lateral (
      select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link
    ) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,
             count(distinct sd.id)::int region_count,
             min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc
      join catalogue.campuses ca on ca.id=cc.campus_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where cc.course_id=pg.id
    ) geo on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc
      where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,'limit',v_limit,'offset',v_offset,
    'sort','course','direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  ) into v_result
  from enriched e;

  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_rankings(p_course_id uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_provider_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  select c.provider_id into v_provider_id from catalogue.courses c where c.id=p_course_id;
  if v_provider_id is null then return '{}'::jsonb; end if;
  return security.admin_provider_rankings(v_provider_id,p_limit);
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_scholarships(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'auth'
AS $function$
declare v_rank integer; v_items jsonb; v_candidates integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'mapping_id',m.id,'scholarship_id',s.id,'name',s.name,'audience',s.audience,
   'value_label',scholarship.value_label(s.id),'nationalities',s.nationalities,'publication_status',s.publication_status,
   'lifecycle_status',s.lifecycle_status,'application_close_date',s.application_close_date,
   'award_value_text',case when fc.calculation_status='calculated' then
      concat_ws(' · ',s.award_value_text,
        concat('Saving ',trim(fc.currency_code::text),' ',to_char(fc.scholarship_saving_amount,'FM999G999G999G990D00'),case when fc.fee_basis='annual' then ' a year'||coalesce(' ('||fc.fee_year||' fee)','') end),
        concat('Net fee ',trim(fc.currency_code::text),' ',to_char(fc.net_fee_amount,'FM999G999G999G990D00'),case when fc.fee_basis='annual' then ' a year' end))
      else s.award_value_text end,
   'published_award_value_text',s.award_value_text,
   'award_value_type',s.award_value_type,'award_percentage',s.award_percentage,'award_amount',s.award_amount,
   'award_currency_code',s.award_currency_code,'award_applies_to_fee_type',s.award_applies_to_fee_type,
   'award_fee_basis',s.award_fee_basis,'award_duration_basis',s.award_duration_basis,
   'academic_year',s.academic_year,'source_url',s.source_url,'evidence_id',coalesce(m.evidence_id,s.evidence_id),
   'mapping_basis',m.mapping_basis,'mapping_state',m.mapping_state,'mapped_at',m.mapped_at,
   'calculation',case when fc.id is null then null else jsonb_build_object(
      'status',fc.calculation_status,'course_fee_id',fc.course_fee_id,'fee_amount',fc.fee_amount,
      'fee_type',fc.fee_type,'fee_basis',fc.fee_basis,'fee_year',fc.fee_year,'currency_code',fc.currency_code,
      'scholarship_saving_amount',fc.scholarship_saving_amount,'net_fee_amount',fc.net_fee_amount,
      'formula',fc.calculation_formula,'reason',fc.calculation_reason,'calculated_at',fc.calculated_at,
      'fee_evidence_id',fc.fee_evidence_id,'scholarship_evidence_id',fc.scholarship_evidence_id
   ) end
 ) order by s.name),'[]'::jsonb)
 into v_items
 from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id
 left join scholarship.course_financial_calculations fc on fc.mapping_id=m.id
 where m.course_id=p_course_id and m.mapping_state='mapped';
 select count(*) into v_candidates from scholarship.course_mapping_candidates where course_id=p_course_id and status='needs_review';
 return jsonb_build_object('items',v_items,'mapped_count',jsonb_array_length(v_items),'needs_review_count',v_candidates,
   'state',case when jsonb_array_length(v_items)>0 then 'mapped' when v_candidates>0 then 'needs_review' else 'not_mapped' end);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_state_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'publishing', 'search', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_stable_key text;
  v_lifecycle text;
  v_publication text;
  v_verified timestamptz;
  v_has_registration boolean:=false;
  v_has_structure boolean:=false;
  v_has_fee boolean:=false;
  v_has_intake boolean:=false;
  v_has_english boolean:=false;
  v_has_description boolean:=false;
  v_has_scholarship boolean:=false;
  v_score numeric:=0;
  v_channels jsonb;
  v_search jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select c.stable_key,c.lifecycle_status,c.publication_status,c.last_verified_at,
         exists(select 1 from catalogue.course_registrations r where r.course_id=c.id),
         (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)),
         exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'),
         exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'),
         exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'),
         (c.description is not null and length(trim(c.description))>0),
         exists(
           select 1 from scholarship.scopes ss
           where coalesce(ss.include_exclude,'include')='include'
             and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id))
         )
  into v_stable_key,v_lifecycle,v_publication,v_verified,
       v_has_registration,v_has_structure,v_has_fee,v_has_intake,v_has_english,v_has_description,v_has_scholarship
  from catalogue.courses c
  where c.id=p_course_id;

  if v_stable_key is null then return '{}'::jsonb; end if;

  v_score:=round(((v_has_registration::int+v_has_structure::int+v_has_fee::int+v_has_intake::int+v_has_english::int+v_has_description::int)*100.0/6.0)::numeric,2);

  select coalesce(jsonb_agg(jsonb_build_object(
    'channel_code',es.channel_code,'channel_name',ch.name,'audience',ch.audience,
    'locale',es.locale,'publication_status',es.publication_status,
    'published_at',es.published_at,'unpublished_at',es.unpublished_at,
    'completeness_score',es.completeness_score,'last_checked_at',es.last_checked_at,'updated_at',es.updated_at
  ) order by es.channel_code,es.locale),'[]'::jsonb)
  into v_channels
  from publishing.entity_states es
  left join publishing.channels ch on ch.code=es.channel_code
  where es.entity_id=p_course_id;

  select jsonb_build_object(
    'projected',d.course_id is not null,
    'publication_status',d.publication_status,
    'completeness_score',d.completeness_score,
    'projection_version',d.projection_version,
    'catalogue_generation',d.catalogue_generation,
    'updated_at',d.updated_at,'generated_at',d.generated_at,'source_updated_at',d.source_updated_at,
    'has_fee',d.has_fee,'has_intake',d.has_intake,'has_english',d.has_english,'has_scholarship',d.has_scholarship,
    'global_projection',case when ps.projection_code is null then null else jsonb_build_object(
      'projection_code',ps.projection_code,'generation',ps.generation,'row_count',ps.row_count,
      'rebuilt_at',ps.rebuilt_at,'content_hash',ps.content_hash,'metadata',ps.metadata
    ) end
  )
  into v_search
  from (select 1) x
  left join search.course_documents d on d.course_id=p_course_id
  left join search.projection_state ps on ps.projection_code='courses';

  return jsonb_build_object(
    'canonical',jsonb_build_object(
      'lifecycle_status',v_lifecycle,'publication_status',v_publication,'last_verified_at',v_verified
    ),
    'canonical_presence',jsonb_build_object('scholarship',v_has_scholarship),
    'admin_readiness',jsonb_build_object(
      'score',v_score,
      'signals',jsonb_build_object(
        'registration',v_has_registration,'structure',v_has_structure,'fee',v_has_fee,
        'intake',v_has_intake,'english',v_has_english,'description',v_has_description
      ),
      'definition','display-only six-signal canonical presence readiness; not truth, approval, freshness or publication'
    ),
    'consumer_channels',v_channels,
    'search',coalesce(v_search,'{}'::jsonb)
  );
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_taxonomy_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_rank integer;
begin
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'study_level_observations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'scheme', o.scheme,
          'registration_code', o.registration_code,
          'source_value', o.source_value,
          'mapping_status', o.mapping_status,
          'canonical_level', jsonb_build_object(
            'id', sl.id,
            'code', sl.code,
            'name', sl.name
          ),
          'status', o.status,
          'valid_from', o.valid_from,
          'valid_to', o.valid_to,
          'source_snapshot_at', o.source_snapshot_at,
          'observed_at', o.observed_at,
          'last_verified_at', o.last_verified_at,
          'content_hash', o.content_hash,
          'source', jsonb_build_object(
            'source_id', o.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'content_hash', e.content_hash
          ) end
        ) order by o.observed_at desc nulls last
      )
      from catalogue.course_study_level_observations o
      join ref.study_levels sl on sl.id=o.study_level_id
      left join pipeline.sources s on s.id=o.source_id
      left join pipeline.evidence_artifacts e on e.id=o.evidence_id
      where o.course_id=p_course_id
    ), '[]'::jsonb),
    'field_observations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'source_field_code', o.source_field_code,
          'source_field_name', o.source_field_name,
          'canonical_field', jsonb_build_object(
            'id', f.id,
            'code', f.code,
            'name', f.name
          ),
          'is_primary', o.is_primary,
          'status', o.status,
          'observed_at', o.observed_at,
          'source', jsonb_build_object(
            'source_id', o.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'content_hash', e.content_hash
          ) end
        ) order by o.is_primary desc, o.observed_at desc nulls last
      )
      from catalogue.course_field_observations o
      join ref.fields_of_study f on f.id=o.field_id
      left join pipeline.sources s on s.id=o.source_id
      left join pipeline.evidence_artifacts e on e.id=o.evidence_id
      where o.course_id=p_course_id
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION security.admin_dashboard_maturity()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank integer := 0; v_payload jsonb; v_at timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  select payload, computed_at into v_payload, v_at from security.admin_summary_snapshots
  where snapshot_key='dashboard' and computed_at > now() - interval '10 minutes';
  if v_payload is not null then
    return v_payload || jsonb_build_object('snapshot_at', v_at, 'snapshot_source', 'snapshot');
  end if;
  return security.admin_dashboard_maturity_compute() || jsonb_build_object('snapshot_at', now(), 'snapshot_source', 'live');
end $function$;

CREATE OR REPLACE FUNCTION security.admin_data_flags_read_v1(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'security'
AS $function$
declare v_status text:=coalesce(nullif(p_args->>'status',''),'open'); v_limit int:=least(greatest(coalesce((p_args->>'limit')::int,100),1),500);
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return jsonb_build_object(
    'can_edit', security.current_role_rank()>=4,
    'counts', (select jsonb_object_agg(status,n) from (select status,count(*) n from pipeline.data_flags group by 1) x),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'flag',f.flag_code,'status',f.status,'created_at',f.created_at,'resolved_at',f.resolved_at,'resolution',f.resolution,
        'course_id',f.entity_id,'course',coalesce(c.display_title,c.canonical_title),'course_code',c.course_code,
        'provider',coalesce(pv.display_name,pv.canonical_name),'amount',fe.amount,'currency',fe.currency_code,'basis',fe.basis,'fee_status',fe.status,
        'page_url',f.detail->>'page_url','quotes',f.detail->'quotes',
        'schedule',(select jsonb_build_object('amount',fr.amount,'year',fr.fee_year,'url',sr.url) from pipeline.provider_fee_rows fr join pipeline.provider_fact_sources sr on sr.id=fr.source_id
                     where sr.decision='approved' and fr.current and fr.basis='annual' and fr.provider_id=c.provider_id and fr.course_code=upper(btrim(c.course_code))
                     order by fr.fee_year desc nulls last, sr.decided_at desc limit 1)) order by f.created_at desc)
      from (select * from pipeline.data_flags where status=v_status or v_status='all' order by created_at desc limit v_limit) f
      left join catalogue.courses c on c.id=f.entity_id left join catalogue.providers pv on pv.id=c.provider_id
      left join catalogue.course_fees fe on fe.id=f.record_id),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_data_quality_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank int:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if p_operation='data_quality_overview' then return security.data_quality_overview_cached(p_args); end if;
  if p_operation='data_quality_exceptions' then return security.data_quality_exceptions_impl(p_args); end if;
  if p_operation='data_quality_quarantine' then
    if v_rank<3 then raise exception 'curator role required for quarantine details' using errcode='42501'; end if;
    return security.data_quality_quarantine_impl(p_args);
  end if;
  raise exception 'unsupported data quality operation: %',p_operation using errcode='22023';
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_filter_option_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_survey text:=nullif(trim(coalesce(p_args->>'survey_code','')),'');
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),10);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;

  if v_kind='evidence_source' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    with q as (
      select s.id::text value,s.label label,
             concat_ws(' · ',nullif(s.source_type,''),co.iso_alpha2::text) meta,
             count(*)::bigint cnt
      from pipeline.evidence_artifacts e
      join pipeline.sources s on s.id=e.source_id
      left join ref.countries co on co.id=s.country_id
      where (v_country is null or upper(co.iso_alpha2::text)=v_country)
        and (v_query is null or lower(s.label||' '||coalesce(s.source_type,'')||' '||coalesce(co.iso_alpha2::text,'')) like '%'||v_query||'%')
      group by s.id,s.label,s.source_type,co.iso_alpha2
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='qilt_provider' then
    if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
    with q as (
      select p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po
      join catalogue.providers p on p.id=po.provider_id
      join ref.outcome_surveys os on os.id=po.survey_id
      where os.code like 'qilt_%'
        and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
      group by p.id,p.display_name,p.canonical_name,p.stable_key
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='qilt_metric' then
    if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
    with q as (
      select om.code value,om.name label,concat_ws(' · ',om.unit,om.code) meta,count(*)::bigint cnt
      from catalogue.provider_outcomes po
      join ref.outcome_surveys os on os.id=po.survey_id
      join ref.outcome_metrics om on om.id=po.metric_id
      where os.code like 'qilt_%'
        and (v_survey is null or os.code=v_survey)
        and (v_query is null or lower(om.name||' '||om.code||' '||coalesce(om.unit,'')) like '%'||v_query||'%')
      group by om.code,om.name,om.unit
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='prisms_study_area' then
    if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
    with q as (
      select sfo.source_study_area_code value,sfo.source_study_area_name label,sfo.source_study_area_code meta,count(*)::bigint cnt
      from catalogue.student_flow_observations sfo
      join ref.outcome_surveys os on os.id=sfo.survey_id
      where os.code='prisms_international_students'
        and sfo.source_study_area_code is not null
        and (v_query is null or lower(coalesce(sfo.source_study_area_name,'')||' '||sfo.source_study_area_code) like '%'||v_query||'%')
      group by sfo.source_study_area_code,sfo.source_study_area_name
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'count',cnt) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  else
    raise exception 'unsupported filter option kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  );
end $function$;

CREATE OR REPLACE FUNCTION security.admin_insights_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_limit integer := least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer := greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_provider_id uuid;
  v_year integer;
  v_suppressed boolean;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  v_provider_id := nullif(p_args->>'provider_id','')::uuid;
  v_year := nullif(p_args->>'year','')::integer;
  v_suppressed := case
    when nullif(p_args->>'suppressed','') is null then null
    else (p_args->>'suppressed')::boolean
  end;

  if p_operation='qilt_outcomes' then
    return public.ui_qilt_outcomes_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'survey_code',''),
      nullif(p_args->>'metric_code',''),
      v_provider_id,
      nullif(p_args->>'status',''),
      v_year,
      coalesce(nullif(p_args->>'sort',''),'provider'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='qilt_filters' then
    return public.ui_qilt_filter_options(nullif(p_args->>'survey_code',''));
  elsif p_operation='prisms_student_flow' then
    return public.ui_prisms_student_flow_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'subdivision_code',''),
      nullif(p_args->>'study_area_code',''),
      nullif(p_args->>'sector_code',''),
      nullif(p_args->>'remoteness_area',''),
      v_suppressed,
      coalesce(nullif(p_args->>'sort',''),'geography'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='prisms_filters' then
    return public.ui_prisms_filter_options();
  else
    raise exception 'unsupported insights read operation: %',p_operation using errcode='22023';
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_layer3_control_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'generated_at', now(),
    'can_control', security.current_role_rank()>=5,
    'credit', (select jsonb_build_object('remaining_usd',round(remaining_usd,2),'observed_at',observed_at) from pipeline.layer3_openrouter_observations where kind='credits' order by observed_at desc limit 1),
    'tasks', (select jsonb_agg(jsonb_build_object(
        'task_class', b.task_class,
        'label', case b.task_class when 'provider_intake_validation' then 'Intakes' when 'provider_english_validation' then 'English requirements' else 'Tuition' end,
        'running', coalesce((select j.active from cron.job j where j.jobname=security.layer3_task_job(b.task_class)),false),
        'cascade', b.route_mode='ladder',
        'daily_usd', b.daily_usd_max,
        'spent_today_usd', round(coalesce((select sum(i.estimated_cost_usd) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0),4),
        'last_24h', (select jsonb_build_object('admitted',count(*) filter (where w.status='admitted'),'to_review',count(*) filter (where w.status='layer4_required'),
                       'not_stated',count(*) filter (where w.status='no_candidate'),'retrying',count(*) filter (where w.status in ('failed','pending')))
                       from pipeline.layer3_work_items w where w.task_class=b.task_class and w.updated_at>=now()-interval '24 hours'),
        'in_review', (select count(*) from pipeline.layer4_review_items l where l.status='pending' and l.layer3_interpretation_id is not null
                        and l.field_code=case b.task_class when 'provider_intake_validation' then 'course_intake' when 'provider_english_validation' then 'course_english' else 'provider_current_tuition_validation' end),
        'tiers', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object(
              'tier', t.tier_no, 'active', t.active, 'final', t.is_final, 'profile', p.code, 'model', p.model_identifier,
              'cost_per_1000_usd', round(t.cost_per_call_usd*1000,2), 'test_right_pct', round(t.h1_success_rate*100,1), 'test_wrong', t.h1_wrong_admitted,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status in ('validated','no_candidate')),
              'passed_up_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours' and i.status='escalated'),
              'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=t.profile_id and i.created_at>=now()-interval '24 hours'),
              'audits', (select jsonb_build_object('checked',count(*),'disagreed',count(*) filter (where not a.agree)) from pipeline.layer3_tier_audits a where a.profile_id=t.profile_id and a.task_class=b.task_class)
            ) order by t.tier_no),'[]'::jsonb) from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class=b.task_class and p.enabled and not p.paused and p.retired_at is null)
          else (select coalesce(jsonb_agg(jsonb_build_object('tier',1,'active',true,'final',true,'profile',p.code,'model',p.model_identifier,
              'cost_per_1000_usd', round(coalesce((security.layer3_tier_evidence(b.task_class,p.id)->>'cost_per_call_usd')::numeric,0)*1000,2),
              'test_right_pct', (security.layer3_tier_evidence(b.task_class,p.id)->>'right_pct')::numeric, 'test_wrong', (security.layer3_tier_evidence(b.task_class,p.id)->>'wrong')::int,
              'answered_24h', (select count(*) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'),
              'passed_up_24h', 0, 'cost_24h_usd', (select round(coalesce(sum(i.estimated_cost_usd),0),4) from pipeline.layer3_interpretations i where i.task_class=b.task_class and i.profile_id=p.id and i.created_at>=now()-interval '24 hours'))),'[]'::jsonb)
              from pipeline.layer3_model_profiles p where b.task_class=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
               and coalesce((p.quality_benchmark->>'pass')::boolean,false)) end,
        'addable', case when b.route_mode='ladder' then (select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,
              'test_right_pct',(e->>'right_pct')::numeric,'test_wrong',(e->>'wrong')::int,'cost_per_1000_usd',round((e->>'cost_per_call_usd')::numeric*1000,2)) order by (e->>'cost_per_call_usd')::numeric),'[]'::jsonb)
            from pipeline.layer3_model_profiles p cross join lateral (select security.layer3_tier_evidence(b.task_class,p.id) e) x
           where b.task_class=any(p.allowed_task_classes) and coalesce((e->>'eligible')::boolean,false)
             and not exists (select 1 from pipeline.layer3_route_tiers t where t.task_class=b.task_class and t.profile_id=p.id)) else '[]'::jsonb end
      ) order by case b.task_class when 'provider_intake_validation' then 1 when 'provider_english_validation' then 2 else 3 end)
      from pipeline.layer3_route_budget b),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'kind',e.kind,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                 from (select * from pipeline.layer3_route_events order by created_at desc limit 12) e)
  ) into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_layer_status_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank integer; v_payload jsonb; v_at timestamptz;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
 select payload, computed_at into v_payload, v_at from security.admin_summary_snapshots
 where snapshot_key='layer_status_summary' and computed_at > now() - interval '10 minutes';
 if v_payload is not null then
   return v_payload || jsonb_build_object('snapshot_at', v_at, 'snapshot_source', 'snapshot');
 end if;
 return security.admin_layer_status_summary_compute() || jsonb_build_object('snapshot_at', now(), 'snapshot_source', 'live');
end $function$;

CREATE OR REPLACE FUNCTION security.admin_live_activity_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  with runs as (
    select d.jobid, d.start_time, d.end_time, d.status, d.return_message,
           row_number() over (partition by d.jobid order by d.start_time desc) rn
      from cron.job_run_details d where d.start_time > now() - interval '2 days'),
  agg as (
    select jobid,
           count(*) filter (where start_time > now() - interval '24 hours') runs_24h,
           count(*) filter (where start_time > now() - interval '24 hours' and status = 'failed') failed_24h,
           bool_or(status in ('running','starting')) running
      from runs group by jobid),
  -- work left and done in 24 hours, for jobs that work through a queue
  q(jobname, unit, work_left, done_24h) as (
    select 'scholarship-discover', 'providers',
           (select count(*) from pipeline.scholarship_discovery_providers where status = 'pending' and attempts < 3),
           (select count(*) from pipeline.scholarship_discovery_providers where discovered_at > now() - interval '24 hours')
    union all select 'scholarship-read', 'pages',
           (select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id and s.lifecycle_status = 'active'
             where p.next_read_at <= now() and p.attempts < 5),
           (select count(*) from pipeline.scholarship_pages where read_at > now() - interval '24 hours')
    union all select 'provider-facts', 'searches and documents',
           (select count(*) from pipeline.provider_fact_search where state = 'queued') + (select count(*) from pipeline.provider_fact_sources where status = 'found' and attempts < 3),
           (select count(*) from pipeline.provider_fact_search where done_at > now() - interval '24 hours') + (select count(*) from pipeline.provider_fact_sources where read_at > now() - interval '24 hours')
    union all select 'course-link-search-worker', 'courses',
           (select count(*) from pipeline.course_link_search where state = 'queued'),
           (select count(*) from pipeline.course_link_search where done_at > now() - interval '24 hours')
    union all select 'coverage-read', 'course pages',
           (select count(*) from pipeline.coverage_course_pages where status in ('bound','ambiguous') and coalesce(next_read_at, now()) <= now() and read_attempts < 3),
           (select count(*) from pipeline.coverage_course_pages where read_at > now() - interval '24 hours')
    union all select 'layer3-intake-route', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_intake_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_intake_validation' and completed_at > now() - interval '24 hours')
    union all select 'layer3-english-route', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_english_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_english_validation' and completed_at > now() - interval '24 hours')
    union all select 'layer3-tuition-dispatch', 'AI checks',
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' and status in ('pending','retry','reserved')),
           (select count(*) from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' and completed_at > now() - interval '24 hours')
    union all select 'evidence-link-index', 'pages',
           (select count(*) from pipeline.evidence_artifacts e left join pipeline.evidence_link_index_state st on st.evidence_id = e.id
              join pipeline.sources s on s.id = e.source_id join pipeline.layer2_onboarding_snapshot o on o.provider_id = s.provider_id
             where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
               and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
               and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
               and (st.evidence_id is null or (st.status = 'error' and st.indexed_at < now() - interval '6 hours'))),
           (select count(*) from pipeline.evidence_link_index_state where status in ('indexed','no_links') and indexed_at > now() - interval '24 hours')),
  jobs as (
    select a.jobname, a.area, a.sort, a.label, a.description, j.schedule, j.active,
           coalesce(g.running, false) running, coalesce(g.runs_24h, 0) runs_24h, coalesce(g.failed_24h, 0) failed_24h,
           r.start_time last_start, r.end_time last_end, r.status last_status, left(r.return_message, 240) last_message,
           q.unit, q.work_left, q.done_24h,
           coalesce(substring(j.command from '"mode":"([a-z_]+)"'), case a.jobname when 'evidence-link-index' then 'evidence_link_index' end) worker_mode, substring(j.command from '"task":"([a-z_]+)"') worker_task
      from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
      left join agg g on g.jobid = j.jobid
      left join runs r on r.jobid = j.jobid and r.rn = 1
      left join q on q.jobname = a.jobname),
  -- the latest summary each coverage-sweep worker mode returned (kept a few hours by pg_net)
  worker as (
    select m.mode, m.task, x.content, x.created at
      from (select distinct worker_mode mode, worker_task task from jobs where worker_mode is not null) m
      left join lateral (select h.content, h.created from net._http_response h
                          where h.status_code = 200 and (case when m.mode = 'evidence_link_index' then h.content like '%"processed":%"summary":{"indexed"%' else h.content like '%"mode":"' || m.mode || '"%' end)
                            and (m.task is null or h.content like '%"task":"' || m.task || '"%')
                          order by h.created desc limit 1) x on true),
  pub as (select p.publishable, p.missing, s.publication_status, s.lifecycle_status
            from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id)
  select jsonb_build_object(
    'now', now(),
    'jobs', (select jsonb_agg(jsonb_build_object(
        'job', j.jobname, 'area', j.area, 'label', j.label, 'description', j.description, 'schedule', j.schedule, 'active', j.active,
        'running', j.running, 'runs_24h', j.runs_24h, 'failed_24h', j.failed_24h,
        'last', jsonb_build_object('start', j.last_start, 'end', j.last_end, 'status', j.last_status, 'message', j.last_message),
        'queue', case when j.unit is null then null else jsonb_build_object('unit', j.unit, 'left', j.work_left, 'done_24h', j.done_24h) end,
        'worker', case when j.worker_mode is null then null else (select jsonb_build_object('mode', w.mode, 'at', w.at,
                   'result', security.live_worker_summary(w.content)) from worker w where w.mode = j.worker_mode and w.task is not distinct from j.worker_task) end)
        order by j.area, j.sort, j.jobname) from jobs j),
    'needs_person', jsonb_build_object(
        'fee_schedules', (select count(*) from pipeline.provider_fact_sources where kind = 'fee_schedule' and status = 'parsed' and decision is null),
        'layer4_reviews', (select count(*) from pipeline.layer4_review_items where status = 'pending'),
        'flagged_values', (select count(*) from pipeline.data_flags where status = 'open'),
        'ranking_links', (select count(*) from ranking.provider_mappings where status = 'candidate'),
        'scholarships_ready', (select count(*) from pub where publishable and coalesce(publication_status, 'unpublished') <> 'published'),
        'scholarships_domestic', (select count(*) from pub where lifecycle_status = 'active' and 'eligibility lists domestic students only' = any(missing))),
    'in_flight', (select count(*) from net.http_request_queue),
    -- Decision 215: replies from workers with an error status (pg_net keeps them a few hours)
    'worker_errors', (select coalesce(jsonb_agg(jsonb_build_object('function', x.fn, 'job', x.job, 'status', x.status_code, 'timed_out', x.timed_out, 'message', x.message, 'count', x.n, 'last', x.last) order by x.last desc), '[]'::jsonb)
                        from (select e.*, (select a.label from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
                                            where e.fn <> '' and j.command like '%''' || e.fn || '''%' and (e.mode is null or j.command like '%"mode":"' || e.mode || '"%')
                                            order by a.sort limit 1) job
                                from (select coalesce(l.function_name, '') fn, l.mode, h.status_code, h.timed_out, left(coalesce(h.error_msg, h.content), 200) message, count(*) n, max(h.created) last
                                        from net._http_response h left join pipeline.edge_request_log l on l.slot = (h.id % 50000)::int and l.request_id = h.id
                                       where h.status_code >= 400 or h.status_code is null
                                       group by 1, 2, 3, 4, 5) e
                               where not exists (select 1 from pipeline.live_error_acks k where k.function_name = e.fn and k.status_code = coalesce(e.status_code, -1)
                                                    and k.message_md5 = md5(e.message) and k.acked_at >= e.last)
                               order by e.last desc limit 10) x)
  ) into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_priority_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'pins',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'target_id',x.target_id,'sort',x.sort,'note',x.note,'at',x.created_at)||coalesce(security.priority_pin_label(x.kind,x.target_id),'{}'::jsonb) order by x.sort),'[]'::jsonb) from pipeline.priority_pins x),
    'ranking',(select coalesce(jsonb_agg(r order by (r->>'rank')::int),'[]'::jsonb) from (
       select jsonb_build_object('rank',pp.rank,'provider_id',pp.provider_id,'name',coalesce(pr.display_name,pr.canonical_name),'state',s.name,'country',k.iso_alpha2,
         'courses',pp.active_courses,'pinned_by',pp.pinned_by,
         'pages_matched',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.read_status='read' and g.identity_basis is not null),
         'pages_waiting',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.status in ('bound','ambiguous') and coalesce(g.read_status,'')<>'read' and g.read_attempts<3)) r
         from pipeline.provider_priority pp join catalogue.providers pr on pr.id=pp.provider_id left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
        where pp.rank<=60) y),
    'states',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'country',k.name) order by k.name,s.name),'[]'::jsonb)
                from ref.subdivisions s join ref.countries k on k.id=s.country_id where exists (select 1 from catalogue.providers pr where pr.subdivision_id=s.id)),
    'countries',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'name',k.name) order by k.name),'[]'::jsonb)
                from ref.countries k where exists (select 1 from catalogue.providers pr where pr.country_id=k.id)),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='priority' order by created_at desc limit 12) e));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_priority_search_v1(p_kind text, p_q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare q text:='%'||btrim(coalesce(p_q,''))||'%';
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_q,'')))<2 then return '[]'::jsonb; end if;
  if p_kind='provider' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',pr.id,'label',coalesce(pr.display_name,pr.canonical_name),'detail',concat_ws(' · ',s.name,k.name)) x
      from catalogue.providers pr left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
     where pr.display_name ilike q or pr.canonical_name ilike q or pr.short_name ilike q order by (select count(*) from catalogue.courses c where c.provider_id=pr.id and c.lifecycle_status='active') desc, length(coalesce(pr.display_name,pr.canonical_name)) limit 20) y);
  elsif p_kind='course' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',c.id,'label',coalesce(c.display_title,c.canonical_title),'detail',concat_ws(' · ',c.course_code,coalesce(pr.display_name,pr.canonical_name))) x
      from catalogue.courses c left join catalogue.providers pr on pr.id=c.provider_id
     where c.lifecycle_status='active' and (c.course_code ilike q or c.canonical_title ilike q or c.display_title ilike q) limit 20) y);
  end if;
  raise exception 'search by provider or course';
end $function$;

CREATE OR REPLACE FUNCTION security.admin_provider_asset_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'ranking', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_country text:=upper(nullif(btrim(p_args->>'country_code'),''));
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_state text:=nullif(btrim(p_args->>'state'),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if p_operation='provider_asset_summary' then
    return (
      with university_scope as (
        select distinct p.id,p.canonical_name,p.display_name,p.stable_key,c.iso_alpha2 country_code
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2 in('AU','NZ')
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%') discovered,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_backed,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate,
          exists(select 1 from catalogue.provider_assets pa where pa.provider_id=u.id and pa.is_primary and pa.status='approved' and pa.asset_type in ('logo','logo_dark','logo_light')) approved_primary,
          exists(select 1 from pipeline.sources s where s.provider_id=u.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad') hotcourses_matched
        from university_scope u
      )
      select jsonb_build_object(
        'scope_basis','AU/NZ canonical university cohort defined by accepted ranking Provider mappings; Hotcourses is discovery/reconciliation only',
        'country_code',v_country,'expected',count(*),'discovered',count(*) filter(where discovered),
        'acquired',count(*) filter(where evidence_backed or approved_primary),'approved',count(*) filter(where approved_primary),
        'blocked',count(*) filter(where accepted_candidate and not approved_primary),'missing',count(*) filter(where not discovered),
        'needs_review',count(*) filter(where discovered and not accepted_candidate and not approved_primary),
        'hotcourses_matched',count(*) filter(where hotcourses_matched),
        'refresh_cadence','quarterly','authority','first_party_provider',
        'third_party_discovery_policy','Exact university-logo copies from Hotcourses may be promoted as operator-approved fallbacks; canonical ownership remains the Provider and Hotcourses provenance is retained'
      ) from base
    );
  elsif p_operation='provider_asset_coverage' then
    return (
      with university_scope as (
        select distinct p.id provider_id,p.stable_key,coalesce(p.display_name,p.canonical_name) provider_name,p.website,p.lifecycle_status,
          c.iso_alpha2 country_code,c.name country_name
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2 in('AU','NZ')
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='rejected') rejected_candidate_count,
          (select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') latest_candidate_at,
          (select s.url from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_url,
          (select s.metadata->>'directory_id' from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_id,
          pa.id primary_asset_id,pa.source_url primary_source_url,pa.evidence_id primary_evidence_id,pa.storage_path primary_storage_path,
          pa.mime_type primary_mime_type,pa.content_hash primary_content_hash,pa.verified_at primary_verified_at,
          case when pa.id is not null then 'approved'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') then 'needs_review'
            else 'missing' end coverage_state
        from university_scope u
        left join lateral (
          select x.* from catalogue.provider_assets x where x.provider_id=u.provider_id and x.is_primary and x.status='approved'
            and x.asset_type in ('logo','logo_dark','logo_light')
          order by x.verified_at desc nulls last,x.id limit 1
        ) pa on true
      ), filtered as (select * from base where v_state is null or coverage_state=v_state),
      page as (
        select * from filtered order by case coverage_state when 'blocked' then 1 when 'needs_review' then 2 when 'missing' then 3 else 4 end,
          lower(provider_name),provider_id limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb))
    );
  elsif p_operation='provider_asset_context' then
    return (
      select jsonb_build_object(
        'provider_id',p.id,
        'state',case when pa.id is not null then 'approved'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') then 'needs_review'
          else 'missing' end,
        'primary_asset',case when pa.id is null then null else jsonb_build_object('id',pa.id,'source_url',pa.source_url,'evidence_id',pa.evidence_id,'storage_path',pa.storage_path,'mime_type',pa.mime_type,'content_hash',pa.content_hash,'verified_at',pa.verified_at) end,
        'candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'accepted_candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted'),
        'hotcourses_reference',(select jsonb_build_object('id',s.metadata->>'directory_id','url',s.url,'fallback_reuse_approved',coalesce((s.metadata->>'operator_fallback_reuse_approved')::boolean,false),'rights_owner_basis',s.metadata->>'rights_owner_basis') from pipeline.sources s where s.provider_id=p.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1),
        'latest_candidate_at',(select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'authority','first_party_provider','refresh_cadence','quarterly')
      from catalogue.providers p
      left join lateral (
        select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved'
          and x.asset_type in ('logo','logo_dark','logo_light')
        order by x.verified_at desc nulls last,x.id limit 1
      ) pa on true
      where p.id=nullif(p_args->>'provider_id','')::uuid
    );
  end if;
  raise exception 'unsupported provider asset read operation: %',p_operation using errcode='22023';
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_provider_contact_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'auth'
AS $function$
declare
 v_rank int:=0;v_limit int:=least(greatest(coalesce(nullif(p_args->>'limit','')::int,50),1),200);v_offset int:=greatest(coalesce(nullif(p_args->>'offset','')::int,0),0);
 v_query text:=nullif(btrim(coalesce(p_args->>'query','')),'');v_country text:=nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'');
 v_provider uuid:=nullif(p_args->>'provider_id','')::uuid;v_lifecycle text:=nullif(lower(btrim(coalesce(p_args->>'lifecycle_status',''))),'');
 v_record_type text:=nullif(lower(btrim(coalesce(p_args->>'record_type',''))),'');v_source text:=nullif(lower(btrim(coalesce(p_args->>'source_authority',''))),'');
 v_verify text:=nullif(lower(btrim(coalesce(p_args->>'verification_state',''))),'');v_has_email text:=nullif(lower(btrim(coalesce(p_args->>'has_email',''))),'');
 v_has_phone text:=nullif(lower(btrim(coalesce(p_args->>'has_phone',''))),'');v_freshness text:=nullif(lower(btrim(coalesce(p_args->>'freshness',''))),'');
 v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'provider'));v_direction text:=case when lower(coalesce(p_args->>'direction','asc'))='desc' then 'desc' else 'asc' end;
 v_id uuid;v_items jsonb;v_total bigint:=0;v_result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

 if p_operation='provider_contacts_page' then
  with base as (
   select c.id,c.provider_id,p.canonical_name provider_name,p.stable_key provider_stable_key,co.iso_alpha2 country_code,
    c.record_type,c.lifecycle_status,c.identity_key,c.updated_at,c.deleted_at,v.id version_id,v.version_no,v.full_name,v.team_name,
    v.job_title,v.functional_area,v.region_scope,v.countries_or_markets,v.work_email,v.work_phone,v.staff_location,v.verification_state,
    v.verified_on,v.source_class,v.source_authority,v.source_url,v.source_page_title,v.evidence_id,v.source_observation_id,v.created_at version_created_at
   from pipeline.provider_contacts c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   left join pipeline.provider_contact_versions v on v.id=c.current_version_id
   where (v_country is null or upper(co.iso_alpha2)=v_country) and (v_provider is null or c.provider_id=v_provider)
    and (v_lifecycle is null or c.lifecycle_status=v_lifecycle) and (v_record_type is null or c.record_type=v_record_type)
    and (v_source is null or lower(coalesce(v.source_authority,''))=v_source) and (v_verify is null or lower(coalesce(v.verification_state,''))=v_verify)
    and (v_has_email is null or (v_has_email='true')=(nullif(btrim(coalesce(v.work_email,'')),'') is not null))
    and (v_has_phone is null or (v_has_phone='true')=(nullif(btrim(coalesce(v.work_phone,'')),'') is not null))
    and (v_freshness is null or (v_freshness='stale' and (v.verified_on is null or v.verified_on<current_date-365))
      or (v_freshness='current' and v.verified_on is not null and v.verified_on>=current_date-365) or (v_freshness='unverified' and v.verified_on is null))
    and (v_query is null or position(lower(v_query) in lower(concat_ws(' ',p.canonical_name,p.stable_key,v.full_name,v.team_name,v.job_title,
      v.functional_area,v.region_scope,v.countries_or_markets,v.work_email,v.work_phone,v.staff_location,v.source_page_title,v.source_url)))>0)
  ), numbered as (select base.*,count(*) over() total_count from base), ordered as (
   select * from numbered order by
    case when v_direction='asc' and v_sort='provider' then lower(provider_name) end asc,
    case when v_direction='desc' and v_sort='provider' then lower(provider_name) end desc,
    case when v_direction='asc' and v_sort='contact' then lower(coalesce(full_name,team_name,'')) end asc,
    case when v_direction='desc' and v_sort='contact' then lower(coalesce(full_name,team_name,'')) end desc,
    case when v_direction='asc' and v_sort='title' then lower(coalesce(job_title,'')) end asc,
    case when v_direction='desc' and v_sort='title' then lower(coalesce(job_title,'')) end desc,
    case when v_direction='asc' and v_sort='region' then lower(coalesce(region_scope,'')) end asc,
    case when v_direction='desc' and v_sort='region' then lower(coalesce(region_scope,'')) end desc,
    case when v_direction='asc' and v_sort='verified' then verified_on end asc nulls last,
    case when v_direction='desc' and v_sort='verified' then verified_on end desc nulls last,
    case when v_direction='asc' and v_sort='status' then lifecycle_status end asc,
    case when v_direction='desc' and v_sort='status' then lifecycle_status end desc,
    lower(provider_name),lower(coalesce(full_name,team_name,'')),id limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),coalesce(max(total_count),0) into v_items,v_total from ordered o;
  return jsonb_build_object('items',coalesce(v_items,'[]'::jsonb),'total',v_total,'limit',v_limit,'offset',v_offset,'summary',jsonb_build_object(
   'active',(select count(*) from pipeline.provider_contacts where lifecycle_status='active'),
   'inactive',(select count(*) from pipeline.provider_contacts where lifecycle_status='inactive'),
   'deleted',(select count(*) from pipeline.provider_contacts where lifecycle_status='deleted'),
   'stale',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where v.verified_on is null or v.verified_on<current_date-365),
   'providers',(select count(distinct provider_id) from pipeline.provider_contacts)));
 end if;

 if p_operation='provider_contact_detail' then
  v_id:=nullif(p_args->>'id','')::uuid;if v_id is null then raise exception 'contact id required' using errcode='22023'; end if;
  select jsonb_build_object(
   'contact',jsonb_build_object('id',c.id,'provider_id',c.provider_id,'provider_name',p.canonical_name,'provider_stable_key',p.stable_key,'country_code',co.iso_alpha2,
    'record_type',c.record_type,'lifecycle_status',c.lifecycle_status,'identity_key',c.identity_key,'created_at',c.created_at,'updated_at',c.updated_at,
    'deleted_at',c.deleted_at,'deleted_by',c.deleted_by,'delete_reason',c.delete_reason,'restored_at',c.restored_at,'restored_by',c.restored_by),
   'current',case when v.id is null then '{}'::jsonb else to_jsonb(v) end,
   'versions',coalesce((select jsonb_agg(to_jsonb(h) order by h.version_no desc) from (
    select vv.id,vv.version_no,vv.full_name,vv.team_name,vv.job_title,vv.functional_area,vv.region_scope,vv.countries_or_markets,vv.work_email,vv.work_phone,
     vv.staff_location,vv.verification_state,vv.verified_on,vv.source_class,vv.source_authority,vv.source_url,vv.source_page_title,vv.source_notes,
     vv.source_observation_id,vv.evidence_id,vv.import_batch_id,vv.import_row_id,vv.content_hash,vv.effective_from,vv.effective_to,vv.change_reason,vv.created_at,vv.created_by
    from pipeline.provider_contact_versions vv where vv.contact_id=c.id order by vv.version_no desc limit 100) h),'[]'::jsonb),
   'audit',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (
    select aa.id,aa.event_type,aa.actor_id,aa.reason,aa.before_version_id,aa.after_version_id,aa.metadata,aa.created_at
    from pipeline.provider_contact_audit_events aa where aa.contact_id=c.id order by aa.created_at desc limit 100) a),'[]'::jsonb),
   'source_observations',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'source_class',o.source_class,'source_provider',o.source_provider,'source_url',o.source_url,
    'full_name',o.full_name,'job_title',o.job_title,'team_name',o.team_name,'territory_text',o.territory_text,'territory_codes',o.territory_codes,
    'work_email',o.work_email,'work_phone',o.work_phone,'professional_profile_url',o.professional_profile_url,'evidence_id',o.evidence_id,
    'verification_state',o.verification_state,'observed_at',o.observed_at,'last_verified_at',o.last_verified_at,'is_current',o.is_current,'confidence',o.confidence)
    order by o.last_verified_at desc) from pipeline.provider_contact_observations o where o.managed_contact_id=c.id),'[]'::jsonb)
  ) into v_result from pipeline.provider_contacts c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
  left join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.id=v_id;
  return coalesce(v_result,'{}'::jsonb);
 end if;

 if p_operation='provider_contact_imports' then
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  with numbered as (select b.*,count(*) over() total_count from pipeline.provider_contact_import_batches b where v_country is null or upper(b.country_code)=v_country),
  ordered as (select * from numbered order by uploaded_at desc,id desc limit v_limit offset v_offset)
  select coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),coalesce(max(total_count),0) into v_items,v_total from ordered o;
  return jsonb_build_object('items',coalesce(v_items,'[]'::jsonb),'total',v_total,'limit',v_limit,'offset',v_offset);
 end if;

 if p_operation='provider_contact_import_detail' then
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  v_id:=nullif(p_args->>'id','')::uuid;if v_id is null then raise exception 'import id required' using errcode='22023'; end if;
  select jsonb_build_object('batch',to_jsonb(b),'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.row_number) from (
   select rr.id,rr.row_number,rr.row_hash,rr.logical_key,rr.source_institution_name,rr.current_institution_name,rr.mapped_provider_id,p.canonical_name mapped_provider_name,
    rr.mapping_state,rr.matched_contact_id,rr.proposed_action,rr.applied_action,rr.validation_errors,rr.conflict_detail,rr.normalized_payload,rr.created_at,rr.applied_at
   from pipeline.provider_contact_import_rows rr left join catalogue.providers p on p.id=rr.mapped_provider_id where rr.batch_id=b.id order by rr.row_number limit 2000) r),'[]'::jsonb))
  into v_result from pipeline.provider_contact_import_batches b where b.id=v_id;
  return coalesce(v_result,'{}'::jsonb);
 end if;

 raise exception 'unsupported provider contact read operation: %',p_operation using errcode='22023';
end $function$;

CREATE OR REPLACE FUNCTION security.admin_provider_contacts(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'public', 'auth'
AS $function$
declare v_rank integer:=0;v_profile jsonb;v_items jsonb;v_events jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
 select jsonb_build_object('profile_id',p.id,'enabled',p.enabled,'paused',p.paused,'base_url',p.base_url,'domain',p.domain,'last_run_at',p.last_run_at,'last_success_at',p.last_success_at,'last_error',p.last_error)
 into v_profile from pipeline.provider_contact_profiles p where p.provider_id=p_provider_id;
 select coalesce(jsonb_agg(row_json order by source_priority,lower(coalesce(row_json->>'territory_text','')),lower(coalesce(row_json->>'job_title','')),lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb)
 into v_items from (
  select case v.source_authority when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
  jsonb_build_object('id',c.id,'managed_contact_id',c.id,'source_class',v.source_authority,'managed_source_class',v.source_class,'source_authority',v.source_authority,
   'source_provider',coalesce(v.metadata->>'source_provider',v.source_authority),'full_name',v.full_name,'job_title',v.job_title,'team_name',coalesce(v.team_name,v.functional_area),
   'territory_text',coalesce(v.countries_or_markets,v.region_scope),'territory_codes',coalesce(v.metadata->'territory_codes','[]'::jsonb),'work_email',v.work_email,'work_phone',v.work_phone,
   'professional_profile_url',v.metadata->>'professional_profile_url','source_url',v.source_url,'evidence_id',v.evidence_id,'verification_state',v.verification_state,
   'confidence',v.metadata->'confidence','observed_at',v.effective_from,'last_verified_at',v.verified_on,
   'source_priority',case v.source_authority when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end,
   'record_type',c.record_type,'lifecycle_status',c.lifecycle_status) row_json
  from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id
  where c.provider_id=p_provider_id and c.lifecycle_status in ('active','inactive') order by 1,v.verified_on desc nulls last limit 100
 ) q;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'source_class',e.source_class,'before_state',e.before_state,'after_state',e.after_state,'detected_at',e.detected_at,'acknowledged',e.acknowledged) order by e.detected_at desc),'[]'::jsonb)
 into v_events from (select * from pipeline.provider_contact_watch_events where provider_id=p_provider_id order by detected_at desc limit 20)e;
 return jsonb_build_object('profile',coalesce(v_profile,'{}'::jsonb),'items',coalesce(v_items,'[]'::jsonb),'events',coalesce(v_events,'[]'::jsonb),'summary',jsonb_build_object(
  'current_contacts',(select count(*) from pipeline.provider_contacts where provider_id=p_provider_id and lifecycle_status='active'),
  'first_party_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='first_party'),
  'manual_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='manual'),
  'enriched_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='licensed_enrichment'),
  'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events where provider_id=p_provider_id and acknowledged=false)));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_provider_detail(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'public', 'catalogue', 'pipeline', 'ref', 'search', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_base jsonb;
  v_courses jsonb;
  v_evidence jsonb;
  v_campuses jsonb;
  v_contacts jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  v_base:=public.ui_provider_detail(p_provider_id);
  if v_base is null then return '{}'::jsonb; end if;
  v_courses:=public.ui_provider_related_courses(p_provider_id,25,0,null,null,null);
  v_evidence:=public.ui_provider_related_evidence(p_provider_id,25,0,null,null);
  v_contacts:=security.admin_provider_contacts(p_provider_id);

  with base as (
    select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.city,ca.postcode,ca.status,ca.publication_status,
           sd.code subdivision_code,sd.name subdivision_name,
           (select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
    from catalogue.campuses ca left join ref.subdivisions sd on sd.id=ca.subdivision_id
    where ca.provider_id=p_provider_id
  ), numbered as (select *,count(*) over() total_count from base), ordered as (
    select * from numbered order by lower(name),id limit 25
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0)
    into v_campuses from ordered o;

  return v_base || jsonb_build_object(
    'courses_page',coalesce(v_courses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'evidence_page',coalesce(v_evidence,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'campuses_page',coalesce(v_campuses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'courses',coalesce(v_courses->'items','[]'::jsonb),
    'evidence',coalesce(v_evidence->'items','[]'::jsonb),
    'international_contacts',coalesce(v_contacts,jsonb_build_object('items','[]'::jsonb,'events','[]'::jsonb,'summary','{}'::jsonb)),
    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
    'university_groups',security.provider_university_groups(p_provider_id),
    'history',jsonb_build_object('created_at',v_base->'created_at','updated_at',v_base->'updated_at','last_verified_at',v_base->'last_verified_at')
  );
end $function$;

CREATE OR REPLACE FUNCTION security.admin_provider_identity_quality_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'security', 'auth'
AS $function$
declare v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return (select jsonb_build_object(
    'providers',count(*),
    'missing_canonical_name',count(*) filter(where canonical_name is null or btrim(canonical_name)=''),
    'missing_display_name',count(*) filter(where display_name is null or btrim(display_name)=''),
    'generic_name_placeholder',count(*) filter(where lower(btrim(coalesce(display_name,canonical_name,''))) in ('location','campus','city','state','region','country','provider','university')),
    'institution_like_city',count(*) filter(where nullif(primary_city,'') is not null and primary_city ~* '(university|institute|college|school|academy|pty|limited|ltd|education|tafe)'),
    'display_matches_city',count(*) filter(where nullif(primary_city,'') is not null and lower(btrim(coalesce(display_name,'')))=lower(btrim(primary_city))),
    'canonical_matches_city',count(*) filter(where nullif(primary_city,'') is not null and lower(btrim(coalesce(canonical_name,'')))=lower(btrim(primary_city))),
    'display_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(display_name,''))))),
    'canonical_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(canonical_name,''))))),
    'display_matches_country',count(*) filter(where exists(select 1 from ref.countries c where lower(btrim(c.name))=lower(btrim(coalesce(display_name,''))) or lower(btrim(c.iso_alpha2::text))=lower(btrim(coalesce(display_name,''))))),
    'canonical_matches_country',count(*) filter(where exists(select 1 from ref.countries c where lower(btrim(c.name))=lower(btrim(coalesce(canonical_name,''))) or lower(btrim(c.iso_alpha2::text))=lower(btrim(coalesce(canonical_name,''))))),
    'display_differs_from_canonical',count(*) filter(where nullif(btrim(display_name),'') is not null and lower(btrim(display_name))<>lower(btrim(canonical_name)))
  ) from catalogue.providers);
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_provider_rankings(p_provider_id uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'ranking', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_result jsonb;
  v_obs uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  -- Find this provider's observations once (direct and linked), each via an index.
  v_obs := array(select o.id from ranking.observations o where o.provider_id=p_provider_id union select opl.observation_id from ranking.observation_provider_links opl where opl.provider_id=p_provider_id);

  select coalesce(jsonb_object_agg(code,payload),'{}'::jsonb)
  into v_result
  from (
    select s.code,
      jsonb_build_object(
        'system_code',s.code,
        'publisher_name',s.publisher_name,
        'ranking_name',s.ranking_name,
        'latest',(
          select jsonb_strip_nulls(jsonb_build_object(
            'edition_year',e.edition_year,
            'rank_display',o.rank_display,
            'rank_exact',o.rank_exact,
            'rank_low',o.rank_low,
            'rank_high',o.rank_high,
            'rank_status',o.rank_status,
            'is_tied',o.is_tied,
            'overall_score',o.overall_score,
            'source_url',e.source_url,
            'methodology_url',e.methodology_url,
            'evidence_artifact_id',o.evidence_artifact_id
          ))
          from ranking.observations o
          join ranking.editions e on e.id=o.edition_id
          where o.id = any(v_obs) and e.system_id=s.id and e.status='accepted'
          order by e.edition_year desc,e.updated_at desc
          limit 1
        ),
        'history',coalesce((
          select jsonb_agg(x order by (x->>'edition_year')::integer desc)
          from (
            select jsonb_strip_nulls(jsonb_build_object(
              'edition_year',e.edition_year,
              'rank_display',o.rank_display,
              'rank_exact',o.rank_exact,
              'rank_low',o.rank_low,
              'rank_high',o.rank_high,
              'rank_status',o.rank_status,
              'is_tied',o.is_tied,
              'overall_score',o.overall_score,
              'methodology_version',e.methodology_version
            )) x
            from ranking.observations o
            join ranking.editions e on e.id=o.edition_id
            where o.id = any(v_obs) and e.system_id=s.id and e.status='accepted'
            order by e.edition_year desc,e.updated_at desc
            limit v_limit
          ) h
        ),'[]'::jsonb)
      ) payload
    from ranking.systems s
    where s.active
  ) z;

  return coalesce(v_result,'{}'::jsonb);
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_provider_scholarships(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'auth'
AS $function$
declare v_rank integer; v_items jsonb; v_total integer; v_mapped_courses integer; v_review integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'scholarship_id',s.id,'name',s.name,'scholarship_type',s.scholarship_type,'audience',s.audience,
   'award_value_text',s.award_value_text,'award_value_type',s.award_value_type,'award_percentage',s.award_percentage,
   'award_amount',s.award_amount,'award_currency_code',s.award_currency_code,'academic_year',s.academic_year,
   'application_close_date',s.application_close_date,'lifecycle_status',s.lifecycle_status,'publication_status',s.publication_status,
   'source_url',s.source_url,'evidence_id',s.evidence_id,
   'mapped_course_count',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')
 ) order by s.name),'[]'::jsonb),count(*)::int
 into v_items,v_total from scholarship.scholarships s where s.provider_id=p_provider_id;
 select count(distinct m.course_id)::int into v_mapped_courses from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id where s.provider_id=p_provider_id and m.mapping_state='mapped';
 select count(*)::int into v_review from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id=c.scholarship_id where s.provider_id=p_provider_id and c.status='needs_review';
 return jsonb_build_object('items',v_items,'scholarship_count',coalesce(v_total,0),'mapped_course_count',coalesce(v_mapped_courses,0),'needs_review_count',coalesce(v_review,0));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_providers_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_lifecycle_status text DEFAULT NULL::text, p_publication_status text DEFAULT NULL::text, p_sort text DEFAULT 'provider'::text, p_direction text DEFAULT 'asc'::text, p_university_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  return (
    with base as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count
      from catalogue.providers p
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      where
        (
          nullif(trim(coalesce(p_query,'')),'') is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.stable_key,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.primary_city,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.code,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.name,'') ilike '%'||trim(p_query)||'%'
        )
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or p.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or p.id in (select security.university_group_provider_ids(p_university_group)))
    ), numbered as (
      select *,count(*) over()::bigint total_count from base
    ), ordered as (
      select * from numbered
      order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(display_name,canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(display_name,canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then country_code end asc,
        case when v_sort='country' and v_dir='desc' then country_code end desc,
        case when v_sort='currency' and v_dir='asc' then currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then currency_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,
        case when v_sort='courses' and v_dir='desc' then course_count end desc,
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
        lower(coalesce(display_name,canonical_name)),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg((to_jsonb(o)-'total_count')||jsonb_build_object('university_groups',security.provider_university_groups(o.id))),'[]'::jsonb),
      'total',coalesce(max(total_count),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir
    ) from ordered o
  );
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_publication_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'search', 'publishing', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'course_documents',jsonb_build_object(
      'total',count(*),
      'published',count(*) filter(where publication_status='published'),
      'unpublished',count(*) filter(where publication_status='unpublished'),
      'has_fee',count(*) filter(where has_fee),
      'has_intake',count(*) filter(where has_intake),
      'has_english',count(*) filter(where has_english),
      'has_scholarship',count(*) filter(where has_scholarship),
      'latest_generated_at',max(generated_at)
    ),
    'projection',coalesce((select jsonb_build_object(
      'projection_code',ps.projection_code,'generation',ps.generation,'rebuilt_at',ps.rebuilt_at,'row_count',ps.row_count,
      'content_hash',ps.content_hash,'projection_version',ps.metadata->>'projection_version','enrichment_gate',ps.metadata->>'enrichment_gate'
    ) from search.projection_state ps where ps.projection_code='courses'),'{}'::jsonb),
    'channels',coalesce((select jsonb_agg(jsonb_build_object(
      'code',ch.code,'name',ch.name,'audience',ch.audience,'status',ch.status,
      'entity_state_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code),
      'published_count',(select count(*) from publishing.entity_states es where es.channel_code=ch.code and es.publication_status='published')
    ) order by ch.code) from publishing.channels ch),'[]'::jsonb)
  ) into v_result
  from search.course_documents;
  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_ranking_links_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_system text := nullif(p_args->>'system_code', ''); v_year int := nullif(p_args->>'edition_year', '')::int;
        v_country text := nullif(p_args->>'country', ''); v_provider uuid := nullif(p_args->>'provider_id', '')::uuid; v_query text := nullif(btrim(p_args->>'query'), '');
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if p_operation = 'ranking_filter_options' then
    return (with base as (
        select pi.country_text, o.provider_id, coalesce(p.display_name, p.canonical_name) provider_name, sd.code state_code, sd.name state_name
          from ranking.observations o join ranking.editions e on e.id = o.edition_id join ranking.systems s on s.id = e.system_id
          join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
          left join catalogue.providers p on p.id = o.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
         where e.status = 'accepted' and (v_system is null or s.code = v_system) and (v_year is null or e.edition_year = v_year))
      select jsonb_build_object(
        'can_link', v_rank >= 3,
        'countries', coalesce((select jsonb_agg(jsonb_build_object('value', country_text, 'count', n,
                        'in_catalogue', exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(q.country_text) and p2.lifecycle_status = 'active')) order by n desc, country_text)
                        from (select country_text, count(*) n from base where country_text is not null group by 1) q), '[]'::jsonb),
        'states', coalesce((select jsonb_agg(jsonb_build_object('value', state_code, 'label', state_name, 'count', n) order by state_name)
                        from (select state_code, state_name, count(*) n from base where state_code is not null and (v_country is null or country_text = v_country) group by 1, 2) q), '[]'::jsonb),
        'providers', coalesce((select jsonb_agg(jsonb_build_object('value', provider_id, 'label', provider_name) order by provider_name)
                        from (select distinct provider_id, provider_name from base where provider_id is not null and (v_country is null or country_text = v_country)) q), '[]'::jsonb),
        'linked', (select count(*) from base where provider_id is not null and (v_country is null or country_text = v_country)),
        'not_linked', (select count(*) from base where provider_id is null and (v_country is null or country_text = v_country)),
        'not_linked_in_catalogue_countries', (select count(*) from base b where b.provider_id is null and (v_country is null or b.country_text = v_country)
                        and exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(b.country_text) and p2.lifecycle_status = 'active'))));
  elsif p_operation = 'ranking_link_candidates' then
    return jsonb_build_object('can_link', v_rank >= 3, 'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', m.provider_id,
             'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code, 'confidence', m.confidence) order by m.confidence desc)
             from ranking.provider_mappings m join catalogue.providers p on p.id = m.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
            where m.publisher_institution_id = nullif(p_args->>'publisher_institution_id', '')::uuid and m.status = 'candidate'), '[]'::jsonb));
  elsif p_operation = 'ranking_provider_search' then
    if v_query is null or length(v_query) < 3 then return jsonb_build_object('items', '[]'::jsonb); end if;
    return jsonb_build_object('items', coalesce((select jsonb_agg(x) from (
             select jsonb_build_object('provider_id', p.id, 'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code) x
               from catalogue.providers p left join ref.subdivisions sd on sd.id = p.subdivision_id
              where p.lifecycle_status = 'active' and (v_country is null or p.country_id = security.ranking_country_id(v_country))
                and (coalesce(p.display_name, p.canonical_name) ilike '%' || v_query || '%'
                     or exists (select 1 from catalogue.provider_aliases a where a.provider_id = p.id and a.valid_to is null and a.alias ilike '%' || v_query || '%'))
              order by length(coalesce(p.display_name, p.canonical_name)) limit 20) q), '[]'::jsonb));
  elsif p_operation = 'provider_ranking_history' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('system_code', s.code, 'ranking_name', s.ranking_name, 'edition_year', e.edition_year,
             'rank_display', o.rank_display, 'rank_exact', o.rank_exact, 'overall_score', o.overall_score, 'publisher_name', pi.institution_name,
             'evidence_artifact_id', o.evidence_artifact_id) order by s.code, e.edition_year desc)
             from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id
             join ranking.editions e on e.id = o.edition_id and e.status = 'accepted' join ranking.systems s on s.id = e.system_id
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
            where l.provider_id = v_provider), '[]'::jsonb));
  end if;
  raise exception 'unsupported ranking link read: %', p_operation using errcode = '22023';
end $function$;

CREATE OR REPLACE FUNCTION security.admin_ranking_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'ranking', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_system text:=nullif(p_args->>'system_code','');
  v_year integer:=nullif(p_args->>'edition_year','')::integer;
  v_provider uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_country text:=nullif(p_args->>'country','');
  v_state text:=nullif(p_args->>'state','');
  v_link text:=nullif(p_args->>'link','');
  v_sort text:=case when lower(coalesce(nullif(p_args->>'sort',''),'rank')) in ('institution','provider','rank','score','country','status','edition','system') then lower(coalesce(nullif(p_args->>'sort',''),'rank')) else 'rank' end;
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if p_operation='ranking_summary' then
    return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',s.code,'publisher_name',s.publisher_name,'ranking_name',s.ranking_name,'official_url',s.official_url,'latest_edition',(select max(e.edition_year) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'accepted_editions',(select count(*) from ranking.editions e where e.system_id=s.id and e.status='accepted'),'observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted')),'mapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is not null),'unmapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and e.edition_year=(select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted') and o.provider_id is null),'total_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted')) order by s.code) from ranking.systems s where s.active),'[]'::jsonb),'manual_imports',case when v_rank>=4 then (select jsonb_build_object('total',count(*),'uploaded',count(*) filter(where status='uploaded'),'needs_review',count(*) filter(where status='needs_review'),'applied',count(*) filter(where status='applied')) from ranking.manual_imports) else null end);
  elsif p_operation='ranking_filters' then
    return jsonb_build_object('systems',coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',ranking_name) order by code) from ranking.systems where active and (v_system is null or code=v_system)),'[]'::jsonb),'years',coalesce((select jsonb_agg(y order by y desc) from (select distinct e.edition_year y from ranking.editions e join ranking.systems s on s.id=e.system_id where e.status='accepted' and (v_system is null or s.code=v_system)) q),'[]'::jsonb),'editions',coalesce((select jsonb_agg(jsonb_build_object('year',q.edition_year,'observations',q.observations,'mapped_observations',q.mapped_observations) order by q.edition_year desc) from (select e.edition_year,count(o.id)::integer observations,count(o.id) filter(where o.provider_id is not null)::integer mapped_observations from ranking.editions e join ranking.systems s on s.id=e.system_id left join ranking.observations o on o.edition_id=e.id where e.status='accepted' and (v_system is null or s.code=v_system) group by e.id,e.edition_year) q),'[]'::jsonb),'statuses',jsonb_build_array('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown'));
  elsif p_operation='ranking_observations' then
    return (
      with filtered as (
        select o.id,s.code system_code,s.publisher_name,s.ranking_name,e.edition_year,e.methodology_version,e.methodology_url,e.source_url,pi.institution_name publisher_institution_name,pi.country_text,o.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,o.rank_display,o.rank_exact,o.rank_low,o.rank_high,o.is_tied,o.rank_status,o.overall_score,o.evidence_artifact_id,o.publisher_institution_id,sd.code state_code,sd.name state_name
        from ranking.observations o
        join ranking.editions e on e.id=o.edition_id
        join ranking.systems s on s.id=e.system_id
        join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
        left join catalogue.providers p on p.id=o.provider_id
        left join ref.subdivisions sd on sd.id=p.subdivision_id
        where e.status='accepted'
          and (v_system is null or s.code=v_system)
          and (v_year is null or e.edition_year=v_year)
          and (v_provider is null or o.provider_id=v_provider or exists(select 1 from ranking.observation_provider_links opl where opl.observation_id=o.id and opl.provider_id=v_provider))
          and (v_query is null or pi.institution_name ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_query||'%')
          and (v_country is null or pi.country_text=v_country)
          and (v_state is null or sd.code=v_state)
          and (v_link is null or (v_link='linked' and o.provider_id is not null) or (v_link='not_linked' and o.provider_id is null))
      ), ordered as (
        select * from filtered order by
          case when v_sort='institution' and v_dir='asc' then lower(publisher_institution_name) end asc,
          case when v_sort='institution' and v_dir='desc' then lower(publisher_institution_name) end desc,
          case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,
          case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
          case when v_sort='rank' and v_dir='asc' then coalesce(rank_exact,rank_low,999999) end asc,
          case when v_sort='rank' and v_dir='desc' then coalesce(rank_exact,rank_low,-1) end desc,
          case when v_sort='score' and v_dir='asc' then overall_score end asc nulls last,
          case when v_sort='score' and v_dir='desc' then overall_score end desc nulls last,
          case when v_sort='country' and v_dir='asc' then lower(coalesce(country_text,'')) end asc,
          case when v_sort='country' and v_dir='desc' then lower(coalesce(country_text,'')) end desc,
          case when v_sort='status' and v_dir='asc' then lower(coalesce(rank_status,'')) end asc,
          case when v_sort='status' and v_dir='desc' then lower(coalesce(rank_status,'')) end desc,
          case when v_sort='edition' and v_dir='asc' then edition_year end asc,
          case when v_sort='edition' and v_dir='desc' then edition_year end desc,
          case when v_sort='system' and v_dir='asc' then system_code end asc,
          case when v_sort='system' and v_dir='desc' then system_code end desc,
          system_code,edition_year desc,coalesce(rank_exact,rank_low,999999),publisher_institution_name,id
        limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,'items',coalesce((select jsonb_agg(to_jsonb(x)) from ordered x),'[]'::jsonb))
    );
  elsif p_operation='ranking_imports' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    return (select jsonb_build_object('total',(select count(*) from ranking.manual_imports),'limit',v_limit,'offset',v_offset,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.uploaded_at desc) from (select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,mi.uploaded_at from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id order by mi.uploaded_at desc limit v_limit offset v_offset) x),'[]'::jsonb)));
  else
    raise exception 'unsupported ranking read operation: %',p_operation using errcode='22023';
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_read_impl(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'catalogue', 'ref', 'pim', 'scholarship', 'pipeline', 'workflow', 'integration', 'search', 'publishing', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_result jsonb;
  v_id uuid;
  v_limit integer := least(greatest(coalesce((p_args->>'limit')::integer,500),1),2000);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if p_operation='context' then return public.ui_context();
  elsif p_operation='dashboard' then return public.ui_dashboard();
  elsif p_operation='providers' then select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_name),'[]'::jsonb) into v_result from public.ui_providers_list(v_limit) x; return v_result;
  elsif p_operation='provider_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_provider_detail(v_id),'{}'::jsonb)||jsonb_build_object('evidence',coalesce(public.ui_provider_related_evidence(v_id,100,0,null,null)->'rows','[]'::jsonb),'courses',coalesce(public.ui_provider_related_courses(v_id,100,0,null,null,null)->'rows','[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='campuses' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_campuses_list(v_limit) x; return v_result;
  elsif p_operation='campus_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select jsonb_build_object('id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'country_code',co.iso_alpha2,'subdivision_code',sd.code,'subdivision_name',sd.name,'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.canonical_title,'delivery_mode',cc.delivery_mode,'is_primary',cc.is_primary) order by c.canonical_title) from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id where cc.campus_id=ca.id),'[]'::jsonb)) into v_result from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=ca.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id left join pipeline.sources s on s.id=ca.source_id left join pipeline.evidence_artifacts e on e.id=ca.evidence_id where ca.id=v_id; return coalesce(v_result,'{}'::jsonb);
  elsif p_operation='courses' or p_operation='completeness' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.canonical_title),'[]'::jsonb) into v_result from public.ui_course_completeness_list(v_limit) x; return v_result;
  elsif p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_course_detail(v_id),'{}'::jsonb)||jsonb_build_object(
      'fee_summary',jsonb_build_object(
        'cricos_registered',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'evidence_id',cf.evidence_id) order by cf.fee_type) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb),
        'provider_current',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'source_id',cf.source_id,'evidence_id',cf.evidence_id) order by cf.fee_year desc nulls last,cf.created_at desc) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis is distinct from 'registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb)
      ),
      'regulatory_facts',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('scheme',o.scheme,'registration_code',o.registration_code,'status',o.status,'course_language',o.course_language,'work_component',o.work_component,'work_component_total_hours',o.work_component_total_hours,'foundation_studies',o.foundation_studies,'dual_qualification',o.dual_qualification,'source_snapshot_at',o.source_snapshot_at,'evidence_id',o.evidence_id)) order by o.source_snapshot_at desc) from catalogue.course_regulatory_observations o where o.course_id=v_id and o.valid_to is null),'[]'::jsonb),
      'campuses',coalesce(public.ui_course_related_campuses(v_id),'[]'::jsonb),
      'evidence',coalesce((select jsonb_agg(distinct jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at,'valid_from',e.valid_from,'valid_to',e.valid_to)) from pipeline.evidence_artifacts e where e.id in (
        select evidence_id from catalogue.course_fees where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_registrations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_regulatory_observations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_links where course_id=v_id and evidence_id is not null
        union select av.evidence_id from pim.attribute_values av join pim.entity_registry er on er.id=av.entity_id where er.entity_type='course' and er.stable_key=(select stable_key from catalogue.courses where id=v_id) and av.evidence_id is not null
      ) or e.entity_id=v_id),'[]'::jsonb)
    ) into v_result;
    return v_result;
  elsif p_operation='scholarships' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_scholarships_list(v_limit) x; return v_result;
  elsif p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid; return coalesce(public.ui_scholarship_detail(v_id),'{}'::jsonb);
  elsif p_operation='evidence' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.captured_at desc),'[]'::jsonb) into v_result from public.ui_evidence_governance_list(v_limit) x; return v_result;
  elsif p_operation='reviews' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.priority desc,x.created_at desc),'[]'::jsonb) into v_result from public.ui_review_queue(v_limit) x; return v_result;
  elsif p_operation='attributes' then if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if; select jsonb_build_object('families',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_families_list() x),'[]'::jsonb),'groups',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_groups_list() x),'[]'::jsonb),'attributes',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attributes_list() x),'[]'::jsonb),'options',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_options_list(v_limit) x),'[]'::jsonb),'completeness_profiles',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_completeness_profiles_list() x),'[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='jobs' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_result from public.ui_jobs_list(v_limit) x; return v_result;
  elsif p_operation='sources' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.country_code,x.source_label),'[]'::jsonb) into v_result from public.ui_regulatory_sources_list() x; return v_result;
  else raise exception 'unsupported admin read operation: %',p_operation using errcode='22023';
  end if;
end$function$;

CREATE OR REPLACE FUNCTION security.admin_requeue_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'groups',(select coalesce(jsonb_agg(jsonb_build_object('field',g.field_code,'reason',g.reason,'items',g.n,'oldest',g.oldest) order by g.n desc),'[]'::jsonb)
      from (select l.field_code, security.review_reason_key(l.escalation_reason) reason, count(*) n, min(l.created_at) oldest from pipeline.layer4_review_items l
             where l.status='pending' and l.layer3_interpretation_id is not null and l.before_value is null
               and l.field_code in ('course_intake','course_english','provider_current_tuition_validation') group by 1,2) g),
    'stays_with_person',(select jsonb_object_agg(field_code,n) from (select field_code,count(*) n from pipeline.layer4_review_items where status='pending' and (layer3_interpretation_id is null or before_value is not null) group by 1) x),
    'layer3_failed',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from pipeline.layer3_work_items where status in ('failed','parked') and coalesce(last_error,'') not like 'released:%' group by 1) y),
    'layer3_waiting',(select jsonb_object_agg(task_class,n) from (select task_class,count(*) n from (
         select task_class from pipeline.layer3_fact_handoffs where work_item_id is null
         union all select task_class from pipeline.layer3_work_items where status='pending') z group by 1) y),
    'models',jsonb_build_object(
       'course_intake',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',t.active,'cost_per_1000_usd',round(t.cost_per_call_usd*1000,2)) order by t.tier_no),'[]'::jsonb)
          from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class='provider_intake_validation' and p.enabled and not p.paused and p.retired_at is null),
       'course_english',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',t.active,'cost_per_1000_usd',round(t.cost_per_call_usd*1000,2)) order by t.tier_no),'[]'::jsonb)
          from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id where t.task_class='provider_english_validation' and p.enabled and not p.paused and p.retired_at is null),
       'provider_current_tuition_validation',(select coalesce(jsonb_agg(jsonb_build_object('profile',p.code,'model',p.model_identifier,'in_cascade',true,'cost_per_1000_usd',null)),'[]'::jsonb)
          from pipeline.layer3_model_profiles p where 'provider_current_tuition_validation'=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
           and coalesce((p.quality_benchmark->>'pass')::boolean,false))),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='requeue' order by created_at desc limit 10) e));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_scholarship_publishing_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'catalogue', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  return (with p as (select * from security.scholarship_publishability_v1())
  select jsonb_build_object('can_control',security.current_role_rank()>=5,
    'counts',jsonb_build_object('published',(select count(*) from scholarship.scholarships where publication_status='published'),
       'eligible',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
         and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id)),
       'held',(select count(*) from pipeline.scholarship_publication_holds where released_at is null),
       'domestic_only',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),
       'active',(select count(*) from scholarship.scholarships where lifecycle_status='active'),
       'published_failing',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.publication_status='published' and not p.publishable)),
    'published_failing',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,'reason',array_to_string(p.missing,'; ')) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published' and not p.publishable),
    'not_publishable_reasons',(select jsonb_object_agg(m,n) from (select unnest(p.missing) m,count(*) n from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' group by 1) x),
    'eligible',(select coalesce(jsonb_agg(x order by x->>'provider',x->>'name'),'[]'::jsonb) from (select jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),
         'value',scholarship.value_label(s.id),
         'page',s.source_url,'courses',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')) x
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
        and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id) limit 300) y),
    'domestic_only',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,
         'published',s.publication_status='published',
         'words',(select left(cr.human_text,240) from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type' and cr.value_json->>'by'='scholarship_sweep' limit 1))
         order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),
    'held',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'reason',h.reason,'at',h.held_at) order by h.held_at desc),'[]'::jsonb)
       from pipeline.scholarship_publication_holds h join scholarship.scholarships s on s.id=h.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where h.released_at is null),
    'published',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from scholarship.scholarships s left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published'),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='scholarships' order by created_at desc limit 10) e)));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_scholarship_semantic_summary(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_rank integer;
begin
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'record_provenance', coalesce((
      select jsonb_build_object(
        'source', case when ps.id is null then null else jsonb_build_object(
          'id',ps.id,'label',ps.label,'type',ps.source_type,'url',ps.url
        ) end,
        'evidence', case when pe.id is null then null else jsonb_build_object(
          'id',pe.id,'type',pe.evidence_type,'source_url',pe.source_url,
          'captured_at',pe.captured_at,'content_hash',pe.content_hash,
          'valid_from',pe.valid_from,'valid_to',pe.valid_to
        ) end
      )
      from scholarship.scholarships s
      left join pipeline.sources ps on ps.id=s.source_id
      left join pipeline.evidence_artifacts pe on pe.id=s.evidence_id
      where s.id=p_scholarship_id
    ), '{}'::jsonb),
    'cycles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',cy.id,
          'cycle_code',cy.cycle_code,
          'academic_year',cy.academic_year,
          'intake_label',cy.intake_label,
          'valid_from',cy.valid_from,
          'valid_to',cy.valid_to,
          'status',cy.status,
          'metadata',cy.metadata,
          'source',case when cys.id is null then null else jsonb_build_object('id',cys.id,'label',cys.label,'type',cys.source_type,'url',cys.url) end,
          'evidence',case when cye.id is null then null else jsonb_build_object('id',cye.id,'type',cye.evidence_type,'source_url',cye.source_url,'captured_at',cye.captured_at,'content_hash',cye.content_hash) end,
          'application_windows',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',w.id,'round_code',w.round_code,'label',w.label,'opens_at',w.opens_at,'closes_at',w.closes_at,
              'application_method',w.application_method,'application_url',w.application_url,'status',w.status,'metadata',w.metadata,
              'source',case when ws.id is null then null else jsonb_build_object('id',ws.id,'label',ws.label,'type',ws.source_type,'url',ws.url) end,
              'evidence',case when we.id is null then null else jsonb_build_object('id',we.id,'type',we.evidence_type,'source_url',we.source_url,'captured_at',we.captured_at,'content_hash',we.content_hash) end
            ) order by w.opens_at nulls last,w.closes_at nulls last,w.label)
            from scholarship.application_windows w
            left join pipeline.sources ws on ws.id=w.source_id
            left join pipeline.evidence_artifacts we on we.id=w.evidence_id
            where w.scholarship_id=p_scholarship_id and w.cycle_id=cy.id
          ),'[]'::jsonb),
          'scopes',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',sc.id,'scope_type',sc.scope_type,'include_exclude',sc.include_exclude,
              'target',jsonb_strip_nulls(jsonb_build_object(
                'provider',case when p.id is null then null else jsonb_build_object('id',p.id,'stable_key',p.stable_key,'name',p.canonical_name) end,
                'course',case when c.id is null then null else jsonb_build_object('id',c.id,'stable_key',c.stable_key,'name',c.canonical_title) end,
                'course_collection',case when cc.id is null then null else jsonb_build_object('id',cc.id,'stable_key',cc.stable_key,'code',cc.code,'name',cc.name) end,
                'study_level',case when sl.id is null then null else jsonb_build_object('id',sl.id,'code',sl.code,'name',sl.name) end,
                'field',case when f.id is null then null else jsonb_build_object('id',f.id,'code',f.code,'name',f.name) end,
                'country',case when co.id is null then null else jsonb_build_object('id',co.id,'code',co.iso_alpha2,'name',co.name) end,
                'campus',case when ca.id is null then null else jsonb_build_object('id',ca.id,'stable_key',ca.stable_key,'name',ca.name) end
              )),
              'source',case when ss.id is null then null else jsonb_build_object('id',ss.id,'label',ss.label,'type',ss.source_type,'url',ss.url) end,
              'evidence',case when se.id is null then null else jsonb_build_object('id',se.id,'type',se.evidence_type,'source_url',se.source_url,'captured_at',se.captured_at,'content_hash',se.content_hash) end
            ) order by sc.scope_type,sc.include_exclude)
            from scholarship.scopes sc
            left join catalogue.providers p on p.id=sc.provider_id
            left join catalogue.courses c on c.id=sc.course_id
            left join catalogue.course_collections cc on cc.id=sc.course_collection_id
            left join ref.study_levels sl on sl.id=sc.study_level_id
            left join ref.fields_of_study f on f.id=sc.field_id
            left join ref.countries co on co.id=sc.country_id
            left join catalogue.campuses ca on ca.id=sc.campus_id
            left join pipeline.sources ss on ss.id=sc.source_id
            left join pipeline.evidence_artifacts se on se.id=sc.evidence_id
            where sc.scholarship_id=p_scholarship_id and sc.cycle_id=cy.id
          ),'[]'::jsonb),
          'eligibility_groups',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',g.id,'group_code',g.group_code,'label',g.label,'parent_group_id',g.parent_group_id,
              'conjunction',g.conjunction,'is_mandatory',g.is_mandatory,'display_order',g.display_order,
              'source',case when gs.id is null then null else jsonb_build_object('id',gs.id,'label',gs.label,'type',gs.source_type,'url',gs.url) end,
              'evidence',case when ge.id is null then null else jsonb_build_object('id',ge.id,'type',ge.evidence_type,'source_url',ge.source_url,'captured_at',ge.captured_at,'content_hash',ge.content_hash) end,
              'criteria',coalesce((
                select jsonb_agg(jsonb_build_object(
                  'id',cr.id,'criterion_type',cr.criterion_type,'operator',cr.operator,'value_text',cr.value_text,
                  'value_number',cr.value_number,'value_codes',cr.value_codes,'value_json',cr.value_json,'human_text',cr.human_text,
                  'is_mandatory',cr.is_mandatory,'machine_evaluable',cr.machine_evaluable,'status',cr.status,'confidence',cr.confidence,
                  'source',case when crs.id is null then null else jsonb_build_object('id',crs.id,'label',crs.label,'type',crs.source_type,'url',crs.url) end,
                  'evidence',case when cre.id is null then null else jsonb_build_object('id',cre.id,'type',cre.evidence_type,'source_url',cre.source_url,'captured_at',cre.captured_at,'content_hash',cre.content_hash) end
                ) order by cr.criterion_type,cr.id)
                from scholarship.criteria cr
                left join pipeline.sources crs on crs.id=cr.source_id
                left join pipeline.evidence_artifacts cre on cre.id=cr.evidence_id
                where cr.scholarship_id=p_scholarship_id and cr.criterion_group_id=g.id
              ),'[]'::jsonb)
            ) order by g.display_order,g.group_code)
            from scholarship.criterion_groups g
            left join pipeline.sources gs on gs.id=g.source_id
            left join pipeline.evidence_artifacts ge on ge.id=g.evidence_id
            where g.scholarship_id=p_scholarship_id and g.cycle_id=cy.id
          ),'[]'::jsonb),
          'award_tiers',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',a.id,'tier_code',a.tier_code,'label',a.label,'amount',a.amount,'currency_code',a.currency_code,
              'percentage',a.percentage,'basis',a.basis,'maximum_amount',a.maximum_amount,'notes',a.notes,'display_order',a.display_order,
              'source',case when axs.id is null then null else jsonb_build_object('id',axs.id,'label',axs.label,'type',axs.source_type,'url',axs.url) end,
              'evidence',case when axe.id is null then null else jsonb_build_object('id',axe.id,'type',axe.evidence_type,'source_url',axe.source_url,'captured_at',axe.captured_at,'content_hash',axe.content_hash) end
            ) order by a.display_order,a.label)
            from scholarship.award_tiers a
            left join pipeline.sources axs on axs.id=a.source_id
            left join pipeline.evidence_artifacts axe on axe.id=a.evidence_id
            where a.scholarship_id=p_scholarship_id and a.cycle_id=cy.id
          ),'[]'::jsonb),
          'coverage',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',cv.id,'coverage_type',cv.coverage_type,'percentage',cv.percentage,'amount',cv.amount,'currency_code',cv.currency_code,
              'duration_value',cv.duration_value,'duration_unit',cv.duration_unit,'notes',cv.notes,
              'source',case when cvs.id is null then null else jsonb_build_object('id',cvs.id,'label',cvs.label,'type',cvs.source_type,'url',cvs.url) end,
              'evidence',case when cve.id is null then null else jsonb_build_object('id',cve.id,'type',cve.evidence_type,'source_url',cve.source_url,'captured_at',cve.captured_at,'content_hash',cve.content_hash) end
            ) order by cv.coverage_type)
            from scholarship.coverage cv
            left join pipeline.sources cvs on cvs.id=cv.source_id
            left join pipeline.evidence_artifacts cve on cve.id=cv.evidence_id
            where cv.scholarship_id=p_scholarship_id and cv.cycle_id=cy.id
          ),'[]'::jsonb)
        ) order by cy.academic_year desc nulls last,cy.cycle_code
      )
      from scholarship.offering_cycles cy
      left join pipeline.sources cys on cys.id=cy.source_id
      left join pipeline.evidence_artifacts cye on cye.id=cy.evidence_id
      where cy.scholarship_id=p_scholarship_id
    ),'[]'::jsonb),
    'unscoped', jsonb_build_object(
      'application_windows',coalesce((select jsonb_agg(to_jsonb(w) order by w.opens_at nulls last,w.label) from scholarship.application_windows w where w.scholarship_id=p_scholarship_id and w.cycle_id is null),'[]'::jsonb),
      'scopes',coalesce((select jsonb_agg(to_jsonb(sc) order by sc.scope_type) from scholarship.scopes sc where sc.scholarship_id=p_scholarship_id and sc.cycle_id is null),'[]'::jsonb),
      'eligibility_groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.display_order,g.group_code) from scholarship.criterion_groups g where g.scholarship_id=p_scholarship_id and g.cycle_id is null),'[]'::jsonb),
      'criteria',coalesce((select jsonb_agg(to_jsonb(cr) order by cr.criterion_type) from scholarship.criteria cr where cr.scholarship_id=p_scholarship_id and cr.cycle_id is null),'[]'::jsonb),
      'award_tiers',coalesce((select jsonb_agg(to_jsonb(a) order by a.display_order,a.label) from scholarship.award_tiers a where a.scholarship_id=p_scholarship_id and a.cycle_id is null),'[]'::jsonb),
      'coverage',coalesce((select jsonb_agg(to_jsonb(cv) order by cv.coverage_type) from scholarship.coverage cv where cv.scholarship_id=p_scholarship_id and cv.cycle_id is null),'[]'::jsonb)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION security.admin_scholarships_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'scholarship'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  return (
    with pub as materialized (select scholarship_id, publishable, missing from security.scholarship_publishability_v1()),
    base as (
      select s.id,s.stable_key,s.name,s.scholarship_type,s.description,s.audience,s.nationalities,scholarship.value_label(s.id) value_label,
        case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce(pb.publishable, false) then 'ready' else 'held' end status,
        coalesce(pb.missing, '{}'::text[]) held_reasons,s.award_value_text,s.award_value_type,s.award_percentage,s.award_amount,s.award_currency_code,s.academic_year,s.application_required,s.application_open_date,s.application_close_date,s.lifecycle_status,s.publication_status,s.source_url,s.created_at,s.updated_at,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
        (select count(*)::int from scholarship.offering_cycles oc where oc.scholarship_id=s.id) cycle_count,
        (select count(*)::int from scholarship.application_windows aw where aw.scholarship_id=s.id) window_count,
        (select count(*)::int from pipeline.evidence_artifacts e where e.entity_id=s.id)+case when s.evidence_id is not null then 1 else 0 end evidence_count,
        (select count(*)::int from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped') mapped_course_count,
        (select count(*)::int from scholarship.course_mapping_candidates mc where mc.scholarship_id=s.id and mc.status='needs_review') review_course_count,
        left(regexp_replace(coalesce(s.description,''),'\s+',' ','g'),220) description_excerpt
      from scholarship.scholarships s
      left join catalogue.providers p on p.id=s.provider_id
      left join ref.countries co on co.id=p.country_id
      left join pub pb on pb.scholarship_id=s.id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null
          or s.name ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.description,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.award_value_text,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.scholarship_type,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.academic_year::text,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (v_provider_id is null or s.provider_id=v_provider_id)
        and (nullif(p_args->>'lifecycle_status','') is null or s.lifecycle_status=p_args->>'lifecycle_status')
        and (nullif(p_args->>'publication_status','') is null or s.publication_status=p_args->>'publication_status')
        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')
        and (nullif(trim(coalesce(p_args->>'course','')),'') is null or exists (
              select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
               where cm.scholarship_id=s.id and cm.mapping_state='mapped'
                 and (c.canonical_title ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.course_code,'') ilike trim(p_args->>'course')||'%')))
    ), numbered as (
      select *,count(*) over() total_count from base
       where case when coalesce(p_args->>'status','') = '' then status <> 'inactive' else status = p_args->>'status' end
    ), ordered as (
      select * from numbered order by
        case when v_sort='scholarship' and v_dir='asc' then lower(name) end asc,
        case when v_sort='scholarship' and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(scholarship_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(scholarship_type,'')) end desc,
        case when v_sort='audience' and v_dir='asc' then lower(coalesce(audience::text,'')) end asc,
        case when v_sort='audience' and v_dir='desc' then lower(coalesce(audience::text,'')) end desc,
        case when v_sort='award' and v_dir='asc' then coalesce(award_percentage,award_amount) end asc nulls last,
        case when v_sort='award' and v_dir='desc' then coalesce(award_percentage,award_amount) end desc nulls last,
        case when v_sort='year' and v_dir='asc' then academic_year end asc nulls last,
        case when v_sort='year' and v_dir='desc' then academic_year end desc nulls last,
        case when v_sort='close' and v_dir='asc' then application_close_date end asc nulls last,
        case when v_sort='close' and v_dir='desc' then application_close_date end desc nulls last,
        case when v_sort='courses' and v_dir='asc' then mapped_course_count end asc,
        case when v_sort='courses' and v_dir='desc' then mapped_course_count end desc,
        case when v_sort='evidence' and v_dir='asc' then evidence_count end asc,
        case when v_sort='evidence' and v_dir='desc' then evidence_count end desc,
        case when v_sort='publication' and v_dir='asc' then lower(coalesce(publication_status,'')) end asc,
        case when v_sort='publication' and v_dir='desc' then lower(coalesce(publication_status,'')) end desc,
        case when v_sort='updated' and v_dir='asc' then updated_at end asc,
        case when v_sort='updated' and v_dir='desc' then updated_at end desc,
        lower(name),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,'status_counts',(select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select b.status, count(*) n from base b group by 1) z))
    from ordered o
  );
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_source_comparison_read_v1(p_entity_type text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'scholarship', 'security', 'auth'
AS $function$
declare
  v_provider jsonb; v_gov jsonb; v_current jsonb; v_weeks numeric; v_reg jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  if p_entity_type = 'scholarship' then
    if not exists (select 1 from scholarship.scholarships where id = p_id) then return null; end if;

    select jsonb_build_object(
             'url', coalesce(sp.final_url, sp.url), 'read_at', sp.read_at, 'read_status', sp.read_status,
             'url_source', sp.url_source, 'evidence_id', sp.evidence_id, 'heading', sp.facts->>'h1',
             'value', sp.facts->'value', 'deadline', sp.facts->'deadline', 'levels', sp.facts->'levels',
             'international', sp.facts->'international')
      into v_provider
      from pipeline.scholarship_pages sp
     where sp.scholarship_id = p_id
     order by (sp.facts is not null) desc, sp.read_at desc nulls last
     limit 1;
    if v_provider is null then
      select jsonb_build_object('url', i.identifier_value, 'evidence_id', i.evidence_id)
        into v_provider from scholarship.identifiers i
       where i.scholarship_id = p_id and i.scheme = 'first_party_detail_url' and coalesce(i.status,'active') = 'active'
       order by i.is_primary desc, i.created_at desc limit 1;
    end if;

    with urls as (
      select s.source_url u from scholarship.scholarships s where s.id = p_id and security.reference_url_has_use(s.source_url, 'scholarship_placeholder')
      union select c.before_value->>'source_url' from pipeline.scholarship_sweep_changes c
        where c.scholarship_id = p_id and security.reference_url_has_use(c.before_value->>'source_url', 'scholarship_placeholder')
    ), ids as (
      select i.identifier_value v from scholarship.identifiers i where i.scholarship_id = p_id and i.scheme = 'study_australia_scholarship_id'
    ), rec as (
      select r.* from pipeline.scholarship_source_records r
       where r.source_record_id in (select v from ids) or r.source_record_url in (select u from urls)
       order by r.observed_at desc nulls last limit 1
    )
    select jsonb_build_object(
             'url', coalesce(rec.source_record_url, (select u from urls limit 1)),
             'observed_at', rec.observed_at, 'evidence_id', rec.evidence_id,
             'value_text', rec.payload->>'award_value_text',
             'amount', rec.payload->'cycles'->0->'award_tiers'->0->'amount',
             'currency', rec.payload->'cycles'->0->'award_tiers'->0->>'currency_code',
             'closing_date', coalesce(rec.payload->>'application_close_date', rec.payload->>'close_date', rec.payload->'cycles'->0->'windows'->0->>'closes_at'),
             'closing_text', coalesce(rec.payload->>'application_close_text', rec.payload->'cycles'->0->'metadata'->>'source_closing_text'),
             'levels_text', coalesce(rec.payload->>'level_of_study_text', rec.payload->'cycles'->0->'metadata'->>'source_level_of_study'),
             'study_levels', rec.payload->'study_levels')
      into v_gov
      from (select 1) one left join rec on true
     where rec.id is not null or exists (select 1 from urls);

    select jsonb_build_object('value_text', s.award_value_text, 'source_url', s.source_url,
             'closing_date', (select min(w.closes_at) from scholarship.application_windows w where w.scholarship_id = s.id))
      into v_current from scholarship.scholarships s where s.id = p_id;

    return jsonb_build_object('entity_type','scholarship','id',p_id,
      'provider', v_provider, 'government', v_gov, 'current', v_current);
  end if;

  if p_entity_type = 'course' then
    if not exists (select 1 from catalogue.courses where id = p_id) then return null; end if;
    select case when c.duration_unit = 'weeks' then c.duration_value end into v_weeks from catalogue.courses c where c.id = p_id;

    select jsonb_build_object(
             'cricos_code', (select o.registration_code from catalogue.course_regulatory_observations o
                               where o.course_id = p_id and o.scheme = 'cricos' order by (o.valid_to is null) desc, o.observed_at desc nulls last limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at,
                                   'per_year_estimate', case when v_weeks > 0 and f.basis = 'registered_total_course' then round(f.amount / (v_weeks / 52.0)) end)
                           from catalogue.course_fees f
                          where f.course_id = p_id and f.fee_type = 'tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', (select jsonb_build_object('value', c.duration_value, 'unit', c.duration_unit) from catalogue.courses c where c.id = p_id and c.duration_value is not null),
             'campuses', (select coalesce(jsonb_agg(distinct cp.name order by cp.name), '[]'::jsonb)
                            from catalogue.course_campuses cc join catalogue.campuses cp on cp.id = cc.campus_id where cc.course_id = p_id))
      into v_reg;

    select jsonb_build_object(
             'url', coalesce((select g.url from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
                             (select l.url from catalogue.course_links l where l.course_id = p_id and l.link_type = 'official_course' and coalesce(l.status,'active') = 'active'
                               order by (l.audience = 'international') desc, l.last_verified_at desc nulls last limit 1)),
             'read_at', (select g.read_at from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at, 'source_type', s.source_type)
                           from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
                          where f.course_id = p_id and f.fee_type = 'provider_current_tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', null, 'campuses', null)
      into v_provider;

    return jsonb_build_object('entity_type','course','id',p_id,'provider', v_provider, 'regulator', v_reg);
  end if;

  raise exception 'unsupported entity type %', p_entity_type using errcode='22023';
end
$function$;

CREATE OR REPLACE FUNCTION security.course_link_reverse_tick_v1(p_batch integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n_done int := 0; n_bound int := 0; n_sent int := 0;
begin
  -- 1. Store the CRICOS codes printed on each page read.
  for r in select x.url, h.status_code, h.content from pipeline.course_link_reverse x join net._http_response h on h.id = x.req_id where x.state = 'sent' loop
    n_done := n_done + 1;
    if r.status_code = 200 and r.content is not null then
      update pipeline.course_link_reverse set state = 'done', done_at = now(),
             codes = array(select distinct m[1] from regexp_matches(upper(r.content), '(?:^|[^0-9A-Z])([0-9]{6}[0-9A-Z])(?![0-9A-Z])', 'g') m)
       where url = r.url;
    else
      update pipeline.course_link_reverse set state = 'error', done_at = now() where url = r.url;
    end if;
  end loop;
  update pipeline.course_link_reverse set state = 'queued'
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. For universities whose pages are all read: bind a course still being searched for when its code is on exactly
  --    one page, and that page shows no more than three of the university's codes.
  for r in with done_prov as (select provider_id from pipeline.course_link_reverse group by provider_id
                               having bool_and(state in ('done','error')) and bool_or(state = 'done')),
                pc as (select x.provider_id, x.url, co.id course_id, co.course_code
                         from pipeline.course_link_reverse x join done_prov using (provider_id)
                         join catalogue.courses co on co.provider_id = x.provider_id and co.lifecycle_status = 'active' and co.course_code = any(x.codes)
                        where x.state = 'done'),
                per_page as (select url, count(*) n from pc group by url),
                per_code as (select course_id, count(distinct url) n from pc group by course_id)
           select pc.provider_id, pc.url, pc.course_id from pc join per_page pp using (url) join per_code pk using (course_id)
             join pipeline.course_link_search s on s.course_id = pc.course_id and s.state in ('queued','none','error')
            where pp.n <= 3 and pk.n = 1 loop
    update pipeline.course_link_search set state = 'found', candidates = to_jsonb(array[r.url]), cand_idx = 1, bound_url = r.url, done_at = now()
     where course_id = r.course_id;
    perform security.course_link_bind_v1(r.course_id, r.provider_id, r.url, 'cricos_search');
    update pipeline.course_link_reverse set bound = bound + 1 where url = r.url;
    n_bound := n_bound + 1;
  end loop;

  -- 3. Read the next pages, universities in turn.
  for r in select x.url from pipeline.course_link_reverse x where x.state = 'queued'
            order by row_number() over (partition by x.provider_id order by x.url) limit greatest(1, least(coalesce(p_batch, 30), 60)) loop
    update pipeline.course_link_reverse set state = 'sent', sent_at = now(),
           req_id = net.http_get(r.url, headers := jsonb_build_object('user-agent', 'Mozilla/5.0 (compatible; StudySearchBot/1.0)'), timeout_milliseconds := 30000)
     where url = r.url;
    n_sent := n_sent + 1;
  end loop;
  return jsonb_build_object('read', n_done, 'bound', n_bound, 'sent', n_sent);
end $function$;

CREATE OR REPLACE FUNCTION security.layer3_provider_credential_set_impl(p_actor uuid, p_profile_id uuid, p_secret text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'vault'
AS $function$
declare
  v_rank smallint := 0;
  v_profile pipeline.layer3_model_profiles%rowtype;
  v_name text;
  v_secret_id uuid;
  v_action text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0)::smallint into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform admin role required' using errcode='42501'; end if;
  if p_secret is null or length(btrim(p_secret)) < 20 then raise exception 'provider credential is required' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason)) < 4 then raise exception 'reason is required' using errcode='22023'; end if;
  select * into v_profile from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'layer3 model profile not found' using errcode='22023'; end if;
  v_name := security.layer3_provider_credential_name(p_profile_id);
  select id into v_secret_id from vault.secrets where name=v_name limit 1;
  if v_secret_id is null then
    v_secret_id := vault.create_secret(btrim(p_secret), v_name, 'StudySearch Layer 3 provider credential for ' || v_profile.code);
    v_action := 'set';
  else
    perform vault.update_secret(v_secret_id, btrim(p_secret), v_name, 'StudySearch Layer 3 provider credential for ' || v_profile.code);
    v_action := 'replace';
  end if;
  update pipeline.layer3_model_profiles
  set paused=true,
      last_validation_result=jsonb_build_object(
        'state','credential_configured_pending_benchmark',
        'validated',false,
        'credential_configured',true,
        'credential_configured_at',now(),
        'provider',aggregator_provider
      ),
      updated_at=now()
  where id=p_profile_id;
  insert into pipeline.layer3_provider_credential_audit(profile_id,action,actor_id,reason)
  values(p_profile_id,v_action,p_actor,btrim(p_reason));
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'credential_configured',true,'state','credential_configured_pending_benchmark');
end $function$;

CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- OpenRouter refused calls (Layer 3)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:3:refused:' || z.code, 'layer', 3, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s work items in the last %s hours were released and will be retried.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance, then the released items are picked up again.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there; the items retry by themselves.'
                          when 'rate' then 'Usually clears by itself; the items retry.'
                          else 'Check the key on Platform settings › Environment & integrations.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when i.last_error ilike '%key limit exceeded%' or i.last_error ilike '%key weekly limit%' then 'key_limit'
                      when i.last_error ~ 'provider_402' then 'credit' when i.last_error ~ 'provider_429' then 'rate' else 'key' end code,
                 count(*) n, min(i.updated_at) first_at, max(i.updated_at) last_at
          from pipeline.layer3_work_items i
          where i.updated_at > now() - make_interval(hours => w_or)
            and (i.last_error ~ 'provider_(40[123]|429)' or i.last_error ilike '%key weekly limit%')
          group by 1) z where z.code is not null), '[]'::jsonb);

  -- OpenRouter balance (Layer 3)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:3:low_balance', 'layer', 3, 'toolset', 'openrouter', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', format('Below the warning level of US$%s. Layer 3 is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                       case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits' end),
      'hint', 'Top up when you are ready; nothing is stopped by this notice.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0)
    union all
    select jsonb_build_object('key', 'openrouter:3:not_observed', 'layer', 3, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(o.observed_at::text, 'never')),
      'hint', 'The balance is read by the route guard job on Layer 3; check it is running.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- Spend past a daily guard today (Layer 3)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:3:over_guard:' || z.task_class || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 3, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', replace(z.task_class, '_', ' '), round(z.spent, 2), z.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: the task keeps running. This is recorded for the top-up review.' else 'The task has stopped until the UTC day changes.' end,
      'hint', 'Change the guard on Platform settings › Environment & integrations, or the mode on Models & services › Toolsets and limits.',
      'count', 1, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select b.task_class, b.daily_usd_max guard, sum(i.estimated_cost_usd) spent, min(i.created_at) first_at, max(i.created_at) last_at
          from pipeline.layer3_route_budget b join pipeline.layer3_interpretations i on i.task_class = b.task_class
          where i.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'
          group by 1, 2 having sum(i.estimated_cost_usd) >= b.daily_usd_max) z), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 (select count(*) from cron.job_run_details d2 where d2.jobid = j.jobid and d2.end_time > now() - make_interval(hours => w_job)) runs
          from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          where d.status = 'failed' and d.end_time > now() - make_interval(hours => w_job)
            and not (select coalesce(bool_and(r.status = 'succeeded'), false) and count(*) = 3
                       from (select d3.status from cron.job_run_details d3 where d3.jobid = j.jobid and d3.status in ('succeeded', 'failed')
                             order by d3.start_time desc limit 3) r)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_contact_disposition_current(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare v_rank int; v pipeline.provider_contact_dispositions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  select * into v from pipeline.provider_contact_dispositions where provider_id=p_provider_id order by created_at desc,id desc limit 1;
  if not found then return jsonb_build_object('disposition','pending_acquisition'); end if;
  return jsonb_build_object(
    'id',v.id,'disposition',v.disposition,'international_students_url',v.international_students_url,
    'contact_team_url',v.contact_team_url,'general_email',v.general_email,
    'named_contact_count',v.named_contact_count,'territory_contact_count',v.territory_contact_count,
    'source_urls',v.source_urls,'evidence_ids',v.evidence_ids,'layer3_interpretation_id',v.layer3_interpretation_id,
    'interpretation_source',v.interpretation_source,'observed_at',v.observed_at,'last_verified_at',v.last_verified_at
  );
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_selection_for_course_browser_bridge(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
begin
  if auth.uid() is not null and security.current_role_rank()<3 then
    raise exception 'StudySearch reviewer/operator role required' using errcode='42501';
  end if;
  return security.scholarship_selection_for_course_impl(p_course_id);
end
$function$;

CREATE OR REPLACE FUNCTION security.scholarship_selection_for_provider_browser_bridge(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
begin
  if auth.uid() is not null and security.current_role_rank()<3 then
    raise exception 'StudySearch reviewer/operator role required' using errcode='42501';
  end if;
  return security.scholarship_selection_for_provider_impl(p_provider_id);
end
$function$;

do $post$
declare v_expected jsonb := jsonb_build_object('pipeline.svc_layer2_provider_probe_start(text, text, text)', '10cc7a0870f99ca3df965a10f6ff8e3b', 'public.admin_catalogue_edit_rows(text, uuid[])', 'cb10f13ea0bc0b387a972e6ed5abb33b', 'public.admin_course_edit_read(uuid)', '17a50d1ddd51808976758893b0fb8f60', 'public.admin_course_links_read(uuid)', '4741a90e46a49b99375faca6b01d27a7', 'public.admin_fee_rule_preview(uuid, text, text)', '03b88939b214f7f7353234f6e3e13828', 'public.admin_fee_rules_read()', '4492d81b8265d06132612fb816935af6', 'public.admin_key_dates_read()', '098ffa6a63aaf37134d24727f7dfbfb5', 'public.admin_link_refresh_read()', '2f64b89c70401f944856a6d37a503150', 'public.admin_platform_notices_read(integer)', 'afe21315ffa1abb4ca7339cf5d4e356c', 'public.admin_provider_applicants_read(uuid)', '412d777b6671b12a914440c3d1cc766f', 'public.admin_provider_edit_read(uuid)', '65205d6cc2fbd5833510c80551c711cc', 'public.admin_reference_source_save(uuid, jsonb, text)', 'ea00f07f6245fdae915f61e4350493cd', 'public.admin_reference_sources_read()', 'e804fa7930b458911e51649003c5a713', 'public.admin_scholarship_layer_read(integer)', '37fe14a21b72ced0be006b612c1b21d4', 'public.admin_scholarship_links_detail(uuid, text, jsonb)', '981f000a5f655f8758fa2783359ef008', 'public.admin_scholarship_links_read(text, text)', '68c18e35541ea3201470232bf29fa83c', 'public.admin_scholarship_record_read(uuid)', '8e23b487daea103dd7130612c1091a4c', 'public.admin_search_pass_read()', '7adb94dc7b14d509c439ba07726ae1e5', 'public.admin_toolset_samples_read(uuid)', 'e08061116bc15037c098ae80e30bda15', 'public.admin_toolsets_read()', 'ba108d9abcac0af663f31869e776fcd0', 'public.admin_value_note_add(uuid, text, text)', 'bf8064f88c6bff59756d638866353823', 'public.admin_waiting_read()', '586b7e0a36395d2d10216bf4d3433a86', 'public.layer2_provider_control(uuid, text, jsonb)', 'a3769b048d06b30a9126a28869d4079b', 'public.layer2_scale_qualification_prepare(uuid)', 'f1531cfa24da87c843dd31e911333092', 'public.platform_environment_control_service(uuid, text, jsonb)', 'b768b46cfe1723702a9d5bba8876c68f', 'public.svc_admin_access_replace_roles(uuid, uuid, text[], timestamp with time zone)', '61b45bd159c2cd070da1ecb0af28f96e', 'public.ui_courses_decision_page(integer, integer, text, text, text, uuid, text, text, text, text, text, boolean, boolean, boolean, boolean, numeric, text, text, text, boolean, boolean, text)', '5e8e9f86c3e590f30fddb6b4ef118635', 'public.ui_prisms_student_flow_page(integer, integer, text, text, text, text, text, boolean, text, text)', '3c37775f39d20d31a75a5ac1c3ff408c', 'public.ui_qilt_outcomes_page(integer, integer, text, text, text, uuid, text, integer, text, text)', '35c697842376077a663c208abafe734d', 'public.ui_scholarships_page(integer, integer, text, text, text, text, text, text)', '8c2dcb7d440f6c0ad3302f0b9d84cdf3', 'security.admin_a15_acceptance_status()', 'd4c27bfaa318b41d198500a56a9f998b', 'security.admin_automations_read_v1()', '351b3d2f2f87b6ec304897c0e74559fc', 'security.admin_campus_detail(uuid)', '19ac4bd108726ff7f64b9f183e4394c3', 'security.admin_campus_page_fast(jsonb)', 'ea657cd6f8ef347e522e53e853712303', 'security.admin_catalogue_filter_options(text, jsonb)', '98c15bb68473f715cbbf845cb8fdb0d8', 'security.admin_catalogue_filter_page(jsonb)', '41fccde4b9bf53aaf9866769897557e1', 'security.admin_catalogue_page(text, jsonb)', 'e3aa4969b87e63b661e460e828d0cb1a', 'security.admin_course_coverage_read(text, jsonb)', '9bbee980e58adbbd6f71a81121ce69f5', 'security.admin_course_entry_summary(uuid)', '4850dd19fef842a9210260d027c78c3f', 'security.admin_course_fee_summary(uuid)', 'a8e9ac608e1edb7b8653d3494e0ae376', 'security.admin_course_field_states(uuid)', '840a4460e546c5dc9ef0d0c8e22d213e', 'security.admin_course_page_fast(jsonb)', '2dc6ee8ba523afeec04d862f3a2ced8a', 'security.admin_course_page_fast_base(jsonb)', '520c6f535e5d7c5c43dea7068b21ae66', 'security.admin_course_page_search_state(jsonb)', 'e49924a6a4930ce4837cd5c61d3af53a', 'security.admin_course_page_unfiltered_fast(jsonb)', '0d95e3df806173bde46ac9319bcf282a', 'security.admin_course_rankings(uuid, integer)', '13049536737a1d9aa709f07e26f4bd57', 'security.admin_course_scholarships(uuid)', '981cd9415cf5fd76ce93804e21921320', 'security.admin_course_state_summary(uuid)', '948b2af5c5545a7bf1180f096b2cd177', 'security.admin_course_taxonomy_summary(uuid)', '46416661e7a6895bd834f32f5c371608', 'security.admin_dashboard_maturity()', 'd87a739396f47e717c7d9336c35ff248', 'security.admin_data_flags_read_v1(jsonb)', '8cb8b563e8e38014c7cac5aac74b2162', 'security.admin_data_quality_read(text, jsonb)', '355a09fc4260174163d0e7e3c776b04d', 'security.admin_filter_option_page(jsonb)', 'df772c5a49b65a2f6936b3e7f6318474', 'security.admin_insights_read(text, jsonb)', '0fe0936af884b89b3dfa72ccc49a1953', 'security.admin_layer3_control_read_v1()', '4caf1facf2d408d049f2f57da76f9faf', 'security.admin_layer_status_summary()', '83feb37894fd84b189b9508fa33d68f1', 'security.admin_live_activity_v1()', 'bb02b729324db20302d0b2d70543c091', 'security.admin_priority_read_v1()', '4103e58c0fbe27f134d7d52d1fd5070b', 'security.admin_priority_search_v1(text, text)', '4d2fff0bc433e9ed2e01ad2e3d2d4c10', 'security.admin_provider_asset_read(text, jsonb)', 'ccfc43758d0372057cd7fe0486aef5fe', 'security.admin_provider_contact_read(text, jsonb)', '8a793b7d7c7acdaa4792a825125e9770', 'security.admin_provider_contacts(uuid)', '0942bd705ec4264ee33805a1d4de2fa6', 'security.admin_provider_detail(uuid)', '450dfd3fba62f6181a890a9dfa9683db', 'security.admin_provider_identity_quality_summary()', '4bde77b98ea711107e6a50913905fb99', 'security.admin_provider_rankings(uuid, integer)', '57171999cde457fc83c1ca75aa87f191', 'security.admin_provider_scholarships(uuid)', '07cbe99ef7ad515fabaeb7315ad89346', 'security.admin_providers_page(integer, integer, text, text, text, text, text, text, text, text)', '4d07ec592074c421890c82c0552c52f2', 'security.admin_publication_overview()', '9df5fe7926cd42f9a7854111d33735ac', 'security.admin_ranking_links_read(text, jsonb)', 'fcdbb4ee194d8575bdc43186ca098d08', 'security.admin_ranking_read(text, jsonb)', '84b9b429fcebe6d2c85a46c48cb5c4e0', 'security.admin_read_impl(text, jsonb)', '056bef9a8a2b0290cd3939403af5eef6', 'security.admin_requeue_read_v1()', '520913cd3f07ed6cab4ca14859977e87', 'security.admin_scholarship_publishing_read_v1()', '01e4e340b26e1fb5e6c37f09a5f99f65', 'security.admin_scholarship_semantic_summary(uuid)', 'b314e0410ba3aa0e6c19ae518392dbe1', 'security.admin_scholarships_page(jsonb)', '1e0e5ca08c099dcc4f14e3515997b76b', 'security.admin_source_comparison_read_v1(text, uuid)', '111c9297f8dd71e7d7ad8c7cb2f9c4b6', 'security.course_link_reverse_tick_v1(integer)', '49d27bf3fc458e0f732206ce894ca851', 'security.layer3_provider_credential_set_impl(uuid, uuid, text, text)', 'b6b7b9f1c5ed450ee3c57a3e81ab38b0', 'security.platform_notices_v1()', '1d2cda19e6d10644203c2dea23376aa9', 'security.provider_contact_disposition_current(uuid)', '21088a425d7115e11dd72d1b7daf5a48', 'security.scholarship_selection_for_course_browser_bridge(uuid)', '130fd0822670e0d8696f40728031354d', 'security.scholarship_selection_for_provider_browser_bridge(uuid)', '49c3a59eff66c24bc07cb68acd770a9a');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.241 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname not in ('pg_catalog','information_schema') and p.prokind = 'f' and pg_get_functiondef(p.oid) ~ 'CourseFinder') then
    raise exception 'CF-247 v2.15.241 post-check: a function still says CourseFinder';
  end if;
end $post2$;
