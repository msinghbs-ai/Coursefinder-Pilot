-- CF-247 worker v1.0.2: defects found in admitted production records (audit of 15 Nov 2026 10:18; Platform Admin 15 Nov 2026 11:22, expired
-- scholarships: "Withdraw all closed ones").
--   5. Job scholarship-coverage-classify failed every run ("record r is not assigned yet"): the provider query names scholarship_ai_reviews "r",
--      the name of the function's record variable, so r.provider_id read the unassigned record. The alias is renamed (md5-guarded edit).
--   1. Scholarships: a closed one (its closing date has passed) is not publishable, nor one on a test or sandbox address or a winners or news page
--      (security.scholarship_publishability_for_v1, two checks added). Job scholarship-auto-publish first withdraws every published scholarship that
--      has closed (security.scholarship_expire_v1, no Layer 4 hold: once a recheck finds a current closing date, the existing publish step publishes
--      it again). A withdrawn scholarship is served by neither website_v2_scholarships nor website_v2_scholarship, which return published ones only,
--      so no consumer API object changes (G3).
--   2-4. Worker v1.0.2 (fees.ts one-off charges; field-checks.ts delivery and title level).
-- Records cleaned up here: every published scholarship that has closed (586 when measured) is withdrawn; any still published that fails the page
-- check is withdrawn; the three Layer 4 fee reviews raised from one-off charges (CNA: an Academic Audit Fee twice, a Confirmation Fee) are rejected;
-- the delivery mode of Bachelor of Global Studies (Victoria University of Wellington) is cleared (its quote states distance or online study, which
-- does not support on_campus) and Te Hono ki Toi (Poutiriao) (EIT) is set to Masters (its own page is the Master of Professional Creative Practice).
-- Lock rule (#1149): no ALTER of any table; nothing written to pipeline.platform_toolset_settings; no switch or mode changes (post-check).
-- G1: no new job. G2: no new value (the checks are rules, not limits). G3: no consumer API object is changed.
-- Replaces: security.scholarship_coverage_classify_v1(uuid[]), security.scholarship_publishability_for_v1(uuid[]) and
--   security.scholarship_auto_publish_v1() (same names and signatures; md5-guarded edits of the live text).
-- Retires: nothing.

set local lock_timeout = '3s';

select set_config('cf247.v102_before', jsonb_build_object(
  'drain', security.pipeline_num_v1('layer4.drain_on', 0), 'md', security.pipeline_num_v1('reading.markdown_input', 0),
  'reorder', security.pipeline_num_v1('health.ai_reorder_on', 0), 'shadow', security.pipeline_num_v1('aer.v2_shadow_on', 0),
  'openrouter', (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'))::text, false);

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

-- 1. Defect 5: the classify job's alias
select pg_temp.edit_once('security.scholarship_coverage_classify_v1(uuid[])', '370ef8409b5046533ad6a393d919f63f',
  $o$or exists (select 1 from pipeline.scholarship_ai_reviews r where r.provider_id = l.provider_id and r.status = 'pending') then 1$o$,
  $n$or exists (select 1 from pipeline.scholarship_ai_reviews ar where ar.provider_id = l.provider_id and ar.status = 'pending') then 1  -- v1.0.2: not "r", the record variable$n$);

-- 2. Defect 1: when a scholarship has closed, and pages that are not the scholarship's own live page
create or replace function security.scholarship_closed_v1(p_close date, p_precision text) returns boolean
language sql stable set search_path to '' as $function$
  -- a closing date stated as a month or a year has passed only once that month or year has ended
  select p_close is not null and case coalesce(p_precision, 'day')
    when 'month' then (date_trunc('month', p_close) + make_interval(months => 1))::date <= current_date  -- fixed: calendar arithmetic (end of the stated month)
    when 'year' then (date_trunc('year', p_close) + make_interval(years => 1))::date <= current_date  -- fixed: calendar arithmetic (end of the stated year)
    else p_close < current_date end
$function$;
comment on function security.scholarship_closed_v1(date, text) is 'CF-247 worker v1.0.2: true when a scholarship''s closing date has passed (a month or a year as stated: once it has ended).';

create or replace function security.scholarship_page_kind_v1(p_url text) returns text
language sql immutable set search_path to '' as $function$
  -- the reason the page is not the scholarship's own live page, or null
  select case
    when lower(regexp_replace(coalesce(p_url, ''), '^https?://([^/?#]+).*$', '\1')) ~ '(^|[.-])(sb[0-9]*|sandbox|staging|stage|uat|test|dev|preview)([.-]|$)'
      then 'not the provider''s live site (a test or sandbox address)'
    when lower(regexp_replace(coalesce(p_url, ''), '^https?://[^/]+', '')) ~ '(scholarships?|awards?|prizes?|bursar(y|ies))[-_](winners|recipients)(\.[a-z]+)?/?$'
      or lower(regexp_replace(coalesce(p_url, ''), '^https?://[^/]+', '')) ~ '/(congratulations|felicitations)[-_/]'
      then 'a winners or recipients page, not the scholarship'
    when lower(regexp_replace(coalesce(p_url, ''), '^https?://[^/]+', '')) ~ '(^|[/_-])(news|newsletters?|nouvelles|actualites|media-releases?|press-releases?)([/._-]|$)'
      then 'a news item or newsletter, not the scholarship page'
  end
$function$;
comment on function security.scholarship_page_kind_v1(text) is 'CF-247 worker v1.0.2: why a scholarship''s page is not its own live page (test or sandbox address, winners list, news item), or null.';

select pg_temp.edit_once('security.scholarship_publishability_for_v1(uuid[])', 'd8123efd7e6e0d36fb6ebe9c8d38fdf7',
  $o$        case when s.evidence_id is null then 'no evidence' end,$o$,
  $n$        -- v1.0.2 (Platform Admin 15 Nov 2026 11:22): a closed scholarship is not listed; nor a page that is not the scholarship's own live page
        case when security.scholarship_closed_v1(s.application_close_date, s.application_close_precision) then 'applications have closed' end,
        security.scholarship_page_kind_v1(s.source_url),
        case when s.evidence_id is null then 'no evidence' end,$n$);

create or replace function security.scholarship_expire_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_ids uuid[]; v_ref text := to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI');
begin
  select coalesce(array_agg(s.id), '{}') into v_ids from scholarship.scholarships s
   where s.publication_status = 'published' and security.scholarship_closed_v1(s.application_close_date, s.application_close_precision);
  if cardinality(v_ids) > 0 then
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = any (v_ids);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('withdraw', 'auto-expire ' || v_ref, v_ids);
    insert into search.refresh_requests(requested_by) values ('auto-expire ' || v_ref || ': ' || cardinality(v_ids) || ' closed');
  end if;
  return jsonb_build_object('withdrawn', cardinality(v_ids));
end $function$;
comment on function security.scholarship_expire_v1() is 'CF-247 worker v1.0.2: withdraws every published scholarship whose closing date has passed (batch auto-expire, no hold), first step of job scholarship-auto-publish; a recheck that finds a current closing date makes it publishable again.';
revoke all on function security.scholarship_expire_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.scholarship_auto_publish_v1()', 'c5e0a77f3de9d9b68993275f18c37c56',
  $o$begin
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;$o$,
  $n$begin
  -- v1.0.2 (Platform Admin 15 Nov 2026 11:22): a closed scholarship is not served, whether or not automatic publishing is on
  perform security.scholarship_expire_v1();
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;$n$);

-- 3. Records
do $d$
declare v_exp jsonb; v_page uuid[]; v_l4 int; v_c1 int; v_c2 int;
begin
  v_exp := security.scholarship_expire_v1();
  select coalesce(array_agg(s.id), '{}') into v_page from scholarship.scholarships s
   where s.publication_status = 'published' and security.scholarship_page_kind_v1(s.source_url) is not null;
  if cardinality(v_page) > 0 then
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = any (v_page);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('withdraw', 'v1.0.2 page check', v_page);
    insert into search.refresh_requests(requested_by) values ('v1.0.2 page check: ' || cardinality(v_page) || ' withdrawn');
  end if;

  update pipeline.layer4_review_items
     set status = 'rejected', decided_at = now(),
         escalation_reason = 'Rejected (worker v1.0.2 data fix, 15 Nov 2026): a one-off charge, not tuition. ' || coalesce(escalation_reason, '')
   where status = 'pending' and id in ('5f2dbde9-4ac6-4034-8f06-e5817b98aae2', 'c5e8480c-5bc2-4057-9ad1-dec6a17810c5', 'a7af27b6-5822-4bef-9dcb-5968e17082fc')
     and field_code = 'provider_current_tuition_validation';
  get diagnostics v_l4 = row_count;

  update catalogue.courses set delivery_mode = null, updated_at = now()
   where id = '32a08c35-dc69-4a95-b644-309db615f37f' and delivery_mode = 'on_campus';
  get diagnostics v_c1 = row_count;
  update catalogue.courses set study_level_id = 'ea7901ca-2375-49ae-8b49-4188cd9c1140', updated_at = now()
   where id = '8ff55b05-4042-4e11-a155-3b20beef35f7' and study_level_id = '89f84b24-daeb-489a-a6d8-8db9a1f34f12';
  get diagnostics v_c2 = row_count;
  update pipeline.field_enrich_items set state = 'skipped', reason = 'Withdrawn by the worker v1.0.2 data fix (15 Nov 2026): the quote does not state this value', updated_at = now()
   where id in (349081, 347804) and state = 'filled';

  insert into pipeline.admin_control_events(area, action, target, detail, actor) values
   ('data_fix', 'v1.0.2 scholarships withdrawn', 'scholarship.scholarships', jsonb_build_object('closed', v_exp->'withdrawn', 'page_check', cardinality(v_page), 'page_ids', to_jsonb(v_page)), null),
   ('data_fix', 'v1.0.2 one-off fee reviews rejected', 'pipeline.layer4_review_items', jsonb_build_object('rejected', v_l4), null),
   ('data_fix', 'v1.0.2 course fields corrected', 'catalogue.courses', jsonb_build_object(
      'Bachelor of Global Studies (Level 7) delivery cleared', v_c1, 'Te Hono ki Toi (Poutiriao) set to Masters', v_c2,
      'why', 'quotes did not state the values (audit 15 Nov 2026)'), null);
end $d$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.scholarship_closed_v1', 'Layer 2', 'Scholarships', 'Whether a scholarship''s closing date has passed', 'active', '{}', '20261115120000'),
 ('function', 'security.scholarship_page_kind_v1', 'Layer 2', 'Scholarships', 'Why a scholarship page is not its own live page', 'active', '{}', '20261115120000'),
 ('function', 'security.scholarship_expire_v1', 'Layer 2', 'Scholarships', 'Withdraws closed scholarships (job scholarship-auto-publish)', 'active', '{}', '20261115120000')
on conflict do nothing;

-- 4. Post-checks: nothing closed or off-page is published; no switch or mode moved
do $c$
declare v_before jsonb := current_setting('cf247.v102_before')::jsonb;
begin
  if exists (select 1 from scholarship.scholarships s where s.publication_status = 'published'
              and (security.scholarship_closed_v1(s.application_close_date, s.application_close_precision) or security.scholarship_page_kind_v1(s.source_url) is not null)) then
    raise exception 'post-check: no closed or off-page scholarship stays published';
  end if;
  if (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter') is distinct from v_before->>'openrouter'
     or security.pipeline_num_v1('layer4.drain_on', 0) <> (v_before->>'drain')::numeric or security.pipeline_num_v1('reading.markdown_input', 0) <> (v_before->>'md')::numeric
     or security.pipeline_num_v1('health.ai_reorder_on', 0) <> (v_before->>'reorder')::numeric or security.pipeline_num_v1('aer.v2_shadow_on', 0) <> (v_before->>'shadow')::numeric then
    raise exception 'post-check: switches and the OpenRouter mode are unchanged';
  end if;
end $c$;
