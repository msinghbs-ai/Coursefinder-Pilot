-- CF-247 v2.15.232 (R1): Platform Admin bug list of 10 Oct 2026 (Fix 3, Fix 4, Fix 5, Feature 2).
-- Fix 3: a course finder address entered by hand is marked manual and locked (admin_provider_edit set_course_finder), and the
--        site search no longer replaces it (svc_coverage_site_record keeps the search result as evidence only).
-- Fix 4: adding a Firecrawl target returns the domain page-finding will search; a find run can be started for one provider.
-- Feature 2: admin_adapter_builder 'add_page' takes a course page entered by hand. The page must be on the provider's own
--        website; it becomes the course's official page (entered by hand, locked) and a sample. 'read' lists the courses.
-- Fix 5 is in the UI: the builder sends a standard log line instead of asking for a reason (servers still require one).
-- Live definitions are md5-checked before and after. Nothing is dropped.
do $guard$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit(uuid,text,jsonb)', 'fae8f49a62ca00a358d2e7370fea501a', 'public.svc_coverage_site_record(uuid,text,jsonb)', 'f1deed17172207ea537784f2d8d4d121', 'public.admin_firecrawl_write(text,jsonb)', 'd0ee636ef9b5926f9382dda57b096751', 'public.admin_adapter_builder(text,jsonb)', 'db29a9baa824f836c79830d258470a10');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.admin_provider_edit(p_provider_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_field text; v_before jsonb; v_after jsonb; v_val jsonb; v_url text;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = p_provider_id;
  if v_p.id is null then raise exception 'provider not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_name','short_name','website','phone','email','description','primary_city','address_line1','postcode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if v_field = 'email' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email address'; end if;
    v_before := to_jsonb(v_p)->v_field;
    update catalogue.providers p set display_name = r.display_name, short_name = r.short_name, website = r.website, phone = r.phone, email = r.email,
           description = r.description, primary_city = r.primary_city, address_line1 = r.address_line1, postcode = r.postcode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.providers x0 where x0.id = p_provider_id) r
     where p.id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_course_finder' then
    v_field := 'course_finder'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    select to_jsonb(d.website) into v_before from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id;
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
    values (p_provider_id, v_url, 'pending', 0, now(), now())
    on conflict (provider_id) do update set website = excluded.website, status = 'pending', attempts = 0, next_due_at = now(), leased_until = null,
           last_error = null, updated_at = now();
    -- v2.15.232 (Fix 3): an address entered by hand is marked manual and locked, so automation never replaces it
    update pipeline.coverage_provider_discovery set site_source = 'manual', site_searched_at = now() where provider_id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'course_finder', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    -- v2.15.232: handing the course finder address back to automation lets the site search replace it again
    if v_field = 'course_finder' then update pipeline.coverage_provider_discovery set site_source = null where provider_id = p_provider_id and site_source = 'manual'; end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_p.lifecycle_status);
    update catalogue.providers set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  return public.admin_provider_edit_read(p_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_dom text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.232 (Fix 3): a course finder address entered by hand is kept; the search result is stored as evidence only
  if exists (select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p_provider_id and l.field='course_finder')
     or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id=p_provider_id and d.site_source='manual') then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         updated_at=now()
   where provider_id=p_provider_id;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_firecrawl_write(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_uc text := p_args->>'use_case';
        v_run uuid; v_n int; v_settings jsonb; v_cap numeric; v_budget jsonb; v_pid uuid; v_inc boolean; v_r pipeline.firecrawl_runs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'target' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if p_args->'included' is null or jsonb_typeof(p_args->'included') = 'null' then
      update pipeline.firecrawl_targets set included = (select t.rule_match from security.firecrawl_targets_v1() t where t.provider_id = v_pid), reason = 'back to the rule: ' || v_reason, set_by = auth.uid(), set_at = now() where provider_id = v_pid;
    else
      v_inc := (p_args->>'included')::boolean;
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (v_pid, v_inc, v_reason, auth.uid(), now())
        on conflict (provider_id) do update set included = excluded.included, reason = excluded.reason, set_by = excluded.set_by, set_at = now() where pipeline.firecrawl_targets.provider_id = excluded.provider_id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_target', v_pid::text, jsonb_build_object('included', p_args->'included', 'reason', v_reason), auth.uid());
    -- v2.15.232 (Fix 4): say which domain page-finding will search (none when the provider has no website and no read page yet)
    return jsonb_build_object('ok', true, 'domain', (select t.domain from security.firecrawl_targets_v1() t where t.provider_id = v_pid));
  elsif p_action = 'start' then
    if v_uc not in ('read_page', 'find_page') then raise exception 'use case must be read_page or find_page'; end if;
    if exists (select 1 from pipeline.firecrawl_runs r where r.use_case = v_uc and r.status = 'running') then raise exception 'a run of this use case is still open. Let it finish or stop it first'; end if;
    v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 1);
    if not coalesce((v_budget->>'allowed')::boolean, false) then raise exception 'Firecrawl is at its reserve. Check the plan on this page first'; end if;
    select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl';
    v_cap := (v_settings->>(case when v_uc = 'read_page' then 'read_credits_per_run' else 'find_credits_per_run' end))::numeric;
    insert into pipeline.firecrawl_runs(use_case, settings, reason, requested_by, credits_cap) values (v_uc, v_settings, v_reason, auth.uid(), v_cap) returning id into v_run;
    insert into pipeline.firecrawl_run_items(run_id, course_id, provider_id, country, url, input)
      select v_run, b.course_id, b.provider_id, b.country, b.url, b.input from (select distinct on (b0.course_id) b0.* from security.firecrawl_backlog_v1(v_uc) b0
             where nullif(p_args->>'provider_id', '') is null or b0.provider_id = (p_args->>'provider_id')::uuid  -- v2.15.232: one provider only, from the adapter builder
             order by b0.course_id) b
      order by b.provider_id, b.course_id;
    get diagnostics v_n = row_count;
    update pipeline.firecrawl_runs set items = v_n, status = case when v_n = 0 then 'done' else 'running' end, finished_at = case when v_n = 0 then now() end where id = v_run;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_start', v_uc, jsonb_build_object('run_id', v_run, 'items', v_n, 'credits_cap', v_cap, 'provider_id', p_args->'provider_id', 'reason', v_reason), auth.uid());
    if v_n > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_run)); end if;
    return jsonb_build_object('ok', true, 'run_id', v_run, 'items', v_n, 'credits_cap', v_cap);
  elsif p_action in ('stop', 'continue') then
    select * into v_r from pipeline.firecrawl_runs where id = (p_args->>'run_id')::uuid;
    if v_r.id is null then raise exception 'unknown run'; end if;
    if p_action = 'stop' then
      update pipeline.firecrawl_runs set status = 'stopped', finished_at = now() where id = v_r.id and status = 'running';
    else
      if v_r.status not in ('running', 'stopped_credit_cap', 'stopped_plan_reserve', 'stopped') then raise exception 'only an open or stopped run can be continued'; end if;
      if p_args ? 'add_credits' then update pipeline.firecrawl_runs set credits_cap = credits_cap + greatest((p_args->>'add_credits')::numeric, 0) where id = v_r.id; end if;
      update pipeline.firecrawl_runs set status = 'running', finished_at = null where id = v_r.id;
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_r.id));
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_' || p_action, v_r.id::text, jsonb_build_object('add_credits', p_args->'add_credits', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$;

CREATE OR REPLACE FUNCTION public.admin_adapter_builder(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_id uuid; v_d pipeline.uni_adapter_drafts%rowtype; v_n int; v_b jsonb; v_samples jsonb; v_m jsonb; v_s jsonb; v_cid uuid; v_code text; v_host text; v_dom text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object('budget', security.adapter_builder_budget(), 'can_manage', v_rank >= 6,
      'model', security.adapter_builder_model_for_v1(v_pid), 'models', case when v_rank >= 6 then security.adapter_builder_models_v1() else '[]'::jsonb end,
      'max_samples', 10,
      -- v2.15.232 (Feature 2): the provider's courses, to attach a course page entered by hand as a sample
      'courses', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'course', coalesce(c.display_title, c.canonical_title),
                   'code', (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = c.id and lower(cr.scheme) = 'cricos' limit 1)) order by coalesce(c.display_title, c.canonical_title))
                   from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'), '[]'::jsonb) else '[]'::jsonb end,
      'website', (select p.website from catalogue.providers p where p.id = v_pid),
      'pages', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('course', x.title, 'code', x.code, 'url', x.url, 'read', x.read_status = 'read') order by x.title) from (
                 select distinct on (pg.url) coalesce(c.display_title, c.canonical_title) title, pg.url, pg.read_status,
                        (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code
                   from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
                  where pg.provider_id = v_pid and pg.url is not null limit 600) x), '[]'::jsonb) else '[]'::jsonb end,
      'drafts', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from (select * from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 3) d), '[]'::jsonb));
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'model' then
    if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
    v_code := nullif(btrim(coalesce(p_args->>'profile_code', '')), '');
    if v_code is null then
      delete from pipeline.uni_adapter_models where provider_id = v_pid;
    else
      if not exists (select 1 from jsonb_array_elements(security.adapter_builder_models_v1()) x where x->>'code' = v_code) then
        raise exception 'that model is not enabled and qualified for intake work (Models & services)';
      end if;
      insert into pipeline.uni_adapter_models(provider_id, profile_code, set_by, reason) values (v_pid, v_code, auth.uid(), v_reason)
        on conflict (provider_id) do update set profile_code = excluded.profile_code, set_by = excluded.set_by, set_at = now(), reason = excluded.reason;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_model', v_pid::text, jsonb_build_object('profile_code', v_code, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'model', security.adapter_builder_model_for_v1(v_pid));
  end if;
  if p_action = 'start' then
    v_n := least(greatest(coalesce((security.firecrawl_setting('builder_samples') #>> '{}')::int, 6), 1), 10);
    select coalesce(jsonb_agg(jsonb_build_object('course_id', x.course_id, 'course', x.title, 'code', x.code, 'url', x.url, 'kind', x.kind) order by x.kr, x.kind), '[]'::jsonb) into v_samples from (
      select q.*, row_number() over (partition by q.kind order by random()) kr from (
        select distinct on (pg.url) pg.course_id, coalesce(c.display_title, c.canonical_title) title, (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code, pg.url,
               case when coalesce(c.display_title, c.canonical_title) ~* '/|, bachelor|and bachelor|double' then 'double'
                    when coalesce(c.display_title, c.canonical_title) ~* 'master|graduate|doctor|postgrad' then 'postgraduate'
                    when coalesce(c.display_title, c.canonical_title) ~* 'certificate|diploma' then 'certificate or diploma'
                    else 'undergraduate' end kind
          from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status in ('active', 'inactive')
         where pg.provider_id = v_pid and pg.read_status = 'read' and pg.url is not null) q
      order by kr, kind limit v_n) x;
    if jsonb_array_length(coalesce(v_samples, '[]'::jsonb)) = 0 then raise exception 'no confirmed course page for this university yet - find pages first'; end if;
    insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, v_samples, v_reason, auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_start', v_pid::text, jsonb_build_object('draft_id', v_id, 'samples', v_samples, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  -- v2.15.232 (Feature 2): a course page entered by hand. It must be on the provider's own website; it is saved as the course's
  -- official page (entered by hand, locked) through admin_course_edit, then added as a sample exactly as add_sample does.
  if p_action = 'add_page' then
    v_cid := nullif(p_args->>'course_id', '')::uuid;
    select c.provider_id into v_pid from catalogue.courses c where c.id = v_cid;
    if v_pid is null then raise exception 'pick one of this provider''s courses'; end if;
    if nullif(p_args->>'provider_id', '') is not null and v_pid <> (p_args->>'provider_id')::uuid then raise exception 'that course belongs to another provider'; end if;
    v_code := btrim(coalesce(p_args->>'url', ''));
    if v_code !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    v_host := lower(regexp_replace(substring(v_code from '^https?://([^/:?#]+)'), '^www\.', ''));
    select lower(regexp_replace(substring(coalesce(p.website, '') from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) into v_dom from catalogue.providers p where p.id = v_pid;
    if coalesce(v_dom, '') = '' then raise exception 'record the provider''s own website first (step 1), then add its course pages'; end if;
    if not (v_host = v_dom or v_host like '%.' || v_dom) then raise exception 'this page is not on the provider''s own website (%)', v_dom; end if;
    perform public.admin_course_edit(v_cid, 'set_official_url', jsonb_build_object('url', v_code, 'reason', v_reason));
    return public.admin_adapter_builder('add_sample', jsonb_build_object('course_id', v_cid, 'reason', v_reason));
  end if;
  if p_action = 'add_sample' then
    v_cid := nullif(p_args->>'course_id', '')::uuid;
    select jsonb_build_object('course_id', pg.course_id, 'course', coalesce(c.display_title, c.canonical_title),
             'code', (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1),
             'url', pg.url, 'kind', 'chosen'), pg.provider_id
      into v_s, v_pid
      from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
     where pg.url is not null and (pg.course_id = v_cid or (v_cid is null and pg.provider_id = v_pid and pg.url = nullif(p_args->>'url', '')))
     order by (pg.read_status = 'read') desc limit 1;
    if v_s is null then raise exception 'this course has no stored page to sample'; end if;
    select * into v_d from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 1;
    if v_d.id is not null and v_d.status in ('capturing', 'proposing') then raise exception 'the current samples are still being captured or proposed; try again in a minute'; end if;
    if v_d.id is null then
      insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, jsonb_build_array(v_s), v_reason, auth.uid()) returning id into v_id;
    else
      if exists (select 1 from jsonb_array_elements(v_d.samples) x where x->>'url' = v_s->>'url') then raise exception 'this page is already a sample'; end if;
      if jsonb_array_length(v_d.samples) >= 10 then raise exception 'a draft holds at most 10 samples: capture new samples to start again'; end if;
      update pipeline.uni_adapter_drafts set samples = samples || jsonb_build_array(v_s), status = 'capturing', updated_at = now() where id = v_d.id;
      v_id := v_d.id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_add_sample', v_pid::text, jsonb_build_object('draft_id', v_id, 'sample', v_s, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  select * into v_d from pipeline.uni_adapter_drafts where id = (p_args->>'draft_id')::uuid;
  if v_d.id is null then raise exception 'unknown draft'; end if;
  if p_action = 'marks' then
    if jsonb_typeof(coalesce(p_args->'marks', '[]'::jsonb)) <> 'array' then raise exception 'marks must be a list'; end if;
    update pipeline.uni_adapter_drafts set marks = coalesce(p_args->'marks', '[]'::jsonb), comments = left(coalesce(p_args->>'comments', ''), 4000), updated_at = now() where id = v_d.id;
    return jsonb_build_object('ok', true);
  elsif p_action = 'propose' then
    if jsonb_array_length(v_d.captures) = 0 then raise exception 'capture the sample pages first'; end if;
    v_b := security.adapter_builder_budget();
    if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric then raise exception 'the AI allowance for today is used (US$ % of %). It is a setting under Adapter builder', v_b->>'used_usd', v_b->>'limit_usd'; end if;
    if (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then raise exception 'the proposals for today are used (% of %). It is a setting under Adapter builder', v_b->>'proposals', v_b->>'limit_proposals'; end if;
    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);
    update pipeline.uni_adapter_drafts set status = 'proposing', marks = coalesce(p_args->'marks', marks), comments = coalesce(left(p_args->>'comments', 4000), comments), model = v_m->>'model', model_profile = v_m->>'code', updated_at = now() where id = v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_propose', v_d.provider_id::text, jsonb_build_object('draft_id', v_d.id, 'budget', v_b, 'model', v_m), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_propose', 'draft_id', v_d.id));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$;

do $post$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit(uuid,text,jsonb)', '21b1ff3858ad64d52e4ff36bcce85e23', 'public.svc_coverage_site_record(uuid,text,jsonb)', '153b3bd42d3c751deb5d37231feec9b8', 'public.admin_firecrawl_write(text,jsonb)', 'd4a359d649a0347ebd399815845bd410', 'public.admin_adapter_builder(text,jsonb)', '08bcda47fabc0afc42e47f410face7ea');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.232 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
