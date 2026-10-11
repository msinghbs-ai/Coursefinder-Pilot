-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-5): "Manually ran 4 unis scholarship, job completed and scholarship didn't show up.
-- This is exactly the gap I need in UI with the journey that platform admin should know what is happening and how long it's going to
-- take to bring it up as admitted scholarship. Even the layer 2 job doesn't mention the uni selected for run ... this is not complete
-- auditing." Platform Admin decisions: keep a copy of every page read; hold an automatically published scholarship that now fails a
-- check; show the journey on the task and on each university's Coverage panel; skip non-scholarship pages by address rules.
--   Feature 2: pipeline.admin_job_items records what each scholarship task found and read, item by item.
--   Feature 1: security.scholarship_job_journey_v1 (public.admin_scholarship_job_journey, public.admin_scholarship_provider_runs).
--   Fix 1: finished tasks in Jobs carry the university names; the Jobs list shows the task's title and outcome.
--   Fix 2: a stored candidate page that did not become a scholarship is registered as evidence of the decision.
--   Fix 3: pipeline.scholarship_skip_rules (9 rules, none matches a page held or admitted) applied before pages are read.
--   Fix 4: a page that lists scholarships is suggested as the provider's listing page.
--   Fix 5: the hourly publish holds an automatically published scholarship that now fails a check.
-- Nothing is dropped or deleted. Each replaced function is checked against its live definition first.
do $guard$
declare v_expected jsonb := '{"public.svc_scholarship_candidate_next(integer)": "0080ad829614bf699f313e71db77417e", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "70ae63d8f4600ba9e59abcb257c4ef5d", "security.scholarship_auto_publish_v1()": "e6f873541c91a1dae6d5cddcd1b977b0", "security.admin_job_watch_v1(uuid)": "90a14cb34e5383cdb265e7ec4c46a56e", "security.admin_job_close_v1(uuid)": "54edd7ac2ad149f0fefa5d92da88e22f", "security.admin_pipeline_ops_read(text,jsonb)": "b5d89ce1e5b3b7c3de2398d5ef27289d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;
-- 1. What each task did, item by item (Feature 2). One row per site map, listing page, candidate page or known scholarship page a
--    task found or read, written while the task runs and once more when it finishes, so the record stays as it was then.
create table if not exists pipeline.admin_job_items (
  job_id uuid not null references pipeline.admin_jobs(id),
  provider_id uuid,
  kind text not null check (kind in ('site_map', 'listing', 'candidate', 'page')),
  ref text not null,
  url text, title text, found_via text, read_status text, outcome text, reasons text[],
  evidence_id uuid, storage_path text, content_hash text, scholarship_id uuid,
  at timestamptz, recorded_at timestamptz not null default now(),
  primary key (job_id, kind, ref));
create index if not exists admin_job_items_provider_idx on pipeline.admin_job_items (provider_id, recorded_at desc);
alter table pipeline.admin_job_items enable row level security;

-- 2. Pages that are never scholarships, skipped before they are read (Fix 3). Address rules, editable in Scholarships › Coverage ›
--    Settings and jobs (Platform Admin, with a reason). A rule never skips an address that mentions a scholarship, bursary, stipend
--    or grant. Tested against every page held or admitted: no rule matches one.
create table if not exists pipeline.scholarship_skip_rules (
  id bigserial primary key, pattern text not null unique, label text not null, active boolean not null default true,
  unless_pattern text not null default '(scholarship|bursar|stipend|grant)', reason text, added_by uuid, added_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table pipeline.scholarship_skip_rules enable row level security;
insert into pipeline.scholarship_skip_rules(pattern, label, reason) values
  ('/study/courses?/', 'Course page', 'bugs 11/10-5: CDU short-course pages'),
  ('/(publications?|research-outputs?)/', 'Research publication', 'bugs 11/10-5: Bond research papers'),
  ('^https?://(research|researchers|pure|eprints|espace|figshare)\.', 'Research portal', 'bugs 11/10-5'),
  ('^https?://(ask|help|support|answers)\.', 'Help or FAQ page', 'bugs 11/10-5: CDU help page'),
  ('/(faqs?|answers)(/|$)', 'Help or FAQ page', 'bugs 11/10-5'),
  ('/(news|events?|media-releases?|stories|blog)/', 'News or event', 'bugs 11/10-5'),
  ('/alumni(-awards)?/', 'Alumni page', 'bugs 11/10-5: CDU alumni awards'),
  ('/handbook/', 'Handbook entry', 'bugs 11/10-5'),
  ('/(staff|people|profiles?|our-people)/', 'Staff profile', 'bugs 11/10-5')
on conflict (pattern) do nothing;

-- 3. Every candidate page read keeps a stored copy as evidence (Fix 2)
alter table pipeline.scholarship_page_candidates add column if not exists evidence_id uuid;

-- Plain words for the reasons a page was not admitted
create or replace function security.scholarship_reason_label_v1(p text)
returns text language sql immutable set search_path to '' as $f$
  select case
    when p in ('no_named_title', 'no named scholarship title', 'stored_name_not_a_title') then 'No scholarship name on the page'
    when p in ('international_not_stated', 'not explicitly open to international students') then 'Does not say international students can apply'
    when p = 'domestic_only' then 'For domestic students only'
    when p = 'past_year_only' then 'Only a past year is mentioned'
    when p = 'not_a_scholarship' then 'Not a scholarship page'
    when p = 'not_offered' then 'Not currently offered'
    when p = 'not_provider_domain' then 'Not on the university''s own website'
    when p = 'listing_page' then 'A list of scholarships, not one scholarship'
    when p = 'too_thin' then 'Too little text to read'
    when p = 'evidence_upload_failed' then 'The copy could not be stored'
    when p in ('already held', 'same stable key') then 'Already held'
    when p = 'register_retired' then 'From a retired register'
    when p like 'skipped: %' then 'Skipped: ' || substr(p, 10)
    else coalesce(p, '') end
$f$;

-- Write (or refresh) what a scholarship task found and read, from the pages of its providers touched while it ran
create or replace function security.scholarship_job_items_sync_v1(p_job uuid)
returns integer language plpgsql security definer set search_path to '' as $f$
declare v_j pipeline.admin_jobs%rowtype; v_ids uuid[]; v_sch uuid[]; v_since timestamptz; v_until timestamptz; v_n int := 0; v_k int;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_job;
  if v_j.id is null or v_j.kind not in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then return 0; end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
  v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
  v_since := v_j.created_at - interval '1 minute';
  v_until := coalesce(v_j.finished_at, now()) + interval '1 minute';
  if v_j.kind = 'scholarship_provider_scan' then
    insert into pipeline.admin_job_items(job_id, provider_id, kind, ref, url, title, found_via, read_status, outcome, reasons, at)
    select p_job, d.provider_id, 'site_map', d.provider_id::text, coalesce(d.site_origin, d.website), d.method, 'site map and search', d.status,
           case when d.status = 'pending' then 'waiting' when d.status = 'failed' then 'failed' else 'mapped' end,
           array_remove(array[coalesce(d.kept_count, 0) || ' page(s) kept of ' || coalesce(d.url_count, 0) || ' address(es)', d.last_error], null), d.updated_at
      from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.updated_at between v_since and v_until
    on conflict (job_id, kind, ref) do update set title = excluded.title, read_status = excluded.read_status, outcome = excluded.outcome, reasons = excluded.reasons, at = excluded.at, recorded_at = now();
    get diagnostics v_k = row_count; v_n := v_n + v_k;
    insert into pipeline.admin_job_items(job_id, provider_id, kind, ref, url, title, found_via, read_status, outcome, reasons, at)
    select p_job, l.provider_id, 'listing', l.id::text, l.url, 'Listing page', l.source, l.status,
           case when l.status = 'read' then 'read' when l.status = 'failed' then 'failed' else 'waiting' end,
           array_remove(array[jsonb_array_length(coalesce(l.items, '[]'::jsonb)) || ' scholarship(s) listed', l.error], null), l.read_at
      from pipeline.scholarship_listing_pages l where l.provider_id = any (v_ids) and l.active and l.read_at between v_since and v_until
    on conflict (job_id, kind, ref) do update set read_status = excluded.read_status, outcome = excluded.outcome, reasons = excluded.reasons, at = excluded.at, recorded_at = now();
    get diagnostics v_k = row_count; v_n := v_n + v_k;
    insert into pipeline.admin_job_items(job_id, provider_id, kind, ref, url, title, found_via, read_status, outcome, reasons, evidence_id, storage_path, content_hash, scholarship_id, at)
    select p_job, c.provider_id, 'candidate', c.id::text, c.url, coalesce(nullif(c.facts->>'h1', ''), nullif(c.title, ''), nullif(c.facts->>'page_title', '')),
           case c.source when 'sitemap' then 'site map' when 'map' then 'site search' when 'search' then 'web search' else c.source end, c.read_status,
           case when c.admit_status = 'admitted' then 'became_scholarship'
                when c.admit_status = 'duplicate' or c.matched_scholarship_id is not null then 'already_held'
                when c.admit_status = 'skipped' then 'skipped'
                when c.admit_status = 'rejected' then 'refused'
                when c.read_status = 'too_thin' and c.read_at >= v_since then 'too_thin'
                when c.read_at >= v_since then 'not_read'
                else 'waiting' end,
           case when c.read_status = 'too_thin' and c.admit_status is null then array['too_thin'] else c.admit_reasons end,
           coalesce(c.evidence_id, (select s.evidence_id from scholarship.scholarships s where s.id = c.admitted_scholarship_id)),
           c.storage_path, c.content_hash, coalesce(c.admitted_scholarship_id, c.matched_scholarship_id), coalesce(c.read_at, c.found_at)
      from pipeline.scholarship_page_candidates c
     where c.provider_id = any (v_ids) and c.source <> 'register'
       and (c.found_at between v_since and v_until or c.read_at between v_since and v_until or c.requested_at between v_since and v_until)
    on conflict (job_id, kind, ref) do update set title = excluded.title, read_status = excluded.read_status, outcome = excluded.outcome, reasons = excluded.reasons,
       evidence_id = excluded.evidence_id, storage_path = excluded.storage_path, content_hash = excluded.content_hash, scholarship_id = excluded.scholarship_id, at = excluded.at, recorded_at = now();
    get diagnostics v_k = row_count; v_n := v_n + v_k;
  end if;
  insert into pipeline.admin_job_items(job_id, provider_id, kind, ref, url, title, found_via, read_status, outcome, reasons, evidence_id, scholarship_id, at)
  select p_job, s.provider_id, 'page', s.id::text, sp.url, s.name, 'known scholarship page', sp.read_status,
         case when s.created_at >= v_since then 'new_record'
              when sp.read_at is null or sp.read_at < v_since then 'waiting'
              when exists (select 1 from pipeline.scholarship_sweep_changes ch where ch.scholarship_id = s.id and ch.changed_at between v_since and v_until and ch.field <> 'admitted') then 'updated'
              when sp.read_status in ('read', 'unchanged') then 'unchanged' else 'not_read' end,
         array(select distinct ch.field from pipeline.scholarship_sweep_changes ch where ch.scholarship_id = s.id and ch.changed_at between v_since and v_until and ch.field <> 'admitted' order by 1),
         sp.evidence_id, s.id, sp.read_at
    from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
   where s.lifecycle_status = 'active'
     and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
     and (sp.read_at between v_since and v_until or sp.requested_at between v_since and v_until or s.created_at between v_since and v_until)
  on conflict (job_id, kind, ref) do update set read_status = excluded.read_status, outcome = excluded.outcome, reasons = excluded.reasons, evidence_id = excluded.evidence_id, at = excluded.at, recorded_at = now();
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  return v_n;
end $f$;
revoke all on function security.scholarship_job_items_sync_v1(uuid) from public, anon, authenticated;

-- The journey of one scholarship task (Feature 1): per university, what was found, read and decided, the records it made or
-- changed, and where each scholarship stands for publishing (published, goes live at the next hourly publish, or what blocks it),
-- with a time estimate while it runs. p_provider limits it to one university (its Coverage panel).
create or replace function security.scholarship_job_journey_v1(p_job uuid, p_provider uuid default null)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_j pipeline.admin_jobs%rowtype; v_ids uuid[]; v_next timestamptz; v_auto boolean; v_left int; v_done int; v_rate numeric; v_out jsonb;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_job;
  if v_j.id is null then return null; end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
  if p_provider is not null then v_ids := array(select x from unnest(v_ids) x where x = p_provider); end if;
  v_auto := security.scholarship_setting('auto_publish', 0) >= 1;
  v_next := date_trunc('hour', now()) + interval '29 minutes'; if v_next <= now() then v_next := v_next + interval '1 hour'; end if;
  select count(*) filter (where i.outcome = 'waiting'), count(*) filter (where i.outcome <> 'waiting' and i.kind in ('candidate', 'page')) into v_left, v_done
    from pipeline.admin_job_items i where i.job_id = p_job;
  v_rate := case when v_j.started_at is not null and v_done > 0 and now() > v_j.started_at + interval '30 seconds'
                 then v_done / greatest(extract(epoch from (coalesce(v_j.finished_at, now()) - v_j.started_at)) / 60.0, 0.5) end;
  with it as (select i.* from pipeline.admin_job_items i where i.job_id = p_job and (p_provider is null or i.provider_id = p_provider)),
  sch as (select distinct i.provider_id, i.scholarship_id from it i where i.scholarship_id is not null and i.outcome in ('became_scholarship', 'new_record', 'updated', 'unchanged', 'already_held')),
  pub as (select x.provider_id, s.id, s.name, s.publication_status, p.publishable, p.missing,
                 exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null) held
            from sch x join scholarship.scholarships s on s.id = x.scholarship_id
            cross join lateral security.scholarship_publishability_for_v1(array[s.id]) p),
  prov as (select pr.id, coalesce(pr.display_name, pr.canonical_name) name, upper(substring(pr.stable_key from '^provider:cricos:(.+)$')) code
             from catalogue.providers pr where pr.id = any (v_ids))
  select jsonb_build_object(
    'job', jsonb_build_object('id', v_j.id, 'kind', v_j.kind, 'title', v_j.title, 'state', v_j.state, 'reason', v_j.reason, 'created_at', v_j.created_at, 'started_at', v_j.started_at, 'finished_at', v_j.finished_at,
                              'requested_by', (select u.email from auth.users u where u.id = v_j.requested_by), 'credits', v_j.result->'credits'),
    'auto_publish', v_auto, 'next_publish_at', case when v_auto then v_next end,
    'eta_minutes', case when v_j.state in ('queued', 'running') and v_left > 0 then ceil(v_left / coalesce(v_rate, 8))::int end,
    'left', v_left,
    'providers', coalesce((select jsonb_agg(jsonb_build_object(
        'provider_id', pr.id, 'name', pr.name, 'code', pr.code,
        'found', jsonb_build_object('candidates', (select count(*) from it where it.provider_id = pr.id and it.kind = 'candidate'),
                                    'by', (select coalesce(jsonb_object_agg(z.v, z.n), '{}'::jsonb) from (select it.found_via v, count(*) n from it where it.provider_id = pr.id and it.kind = 'candidate' group by 1) z),
                                    'site_map', (select jsonb_build_object('outcome', it.outcome, 'method', it.title, 'note', it.reasons, 'at', it.at) from it where it.provider_id = pr.id and it.kind = 'site_map' limit 1),
                                    'listing', (select jsonb_agg(jsonb_build_object('url', it.url, 'outcome', it.outcome, 'note', it.reasons)) from it where it.provider_id = pr.id and it.kind = 'listing')),
        'read', jsonb_build_object('candidates', (select count(*) from it where it.provider_id = pr.id and it.kind = 'candidate' and it.outcome not in ('waiting', 'skipped')),
                                   'known_pages', (select count(*) from it where it.provider_id = pr.id and it.kind = 'page' and it.outcome <> 'waiting'),
                                   'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = pr.id and u.purpose like 'sch\_%' and u.at between v_j.created_at and coalesce(v_j.finished_at, now()))),
        'decided', (select jsonb_build_object('became', count(*) filter (where it.outcome = 'became_scholarship'), 'already_held', count(*) filter (where it.outcome = 'already_held'),
                                              'refused', count(*) filter (where it.outcome = 'refused'), 'too_thin', count(*) filter (where it.outcome = 'too_thin'),
                                              'skipped', count(*) filter (where it.outcome = 'skipped'), 'waiting', count(*) filter (where it.outcome = 'waiting'),
                                              'not_read', count(*) filter (where it.outcome = 'not_read'))
                      from it where it.provider_id = pr.id and it.kind = 'candidate'),
        'reasons', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.r, 'n', z.n) order by z.n desc, z.r), '[]'::jsonb)
                      from (select security.scholarship_reason_label_v1(r) r, count(*) n from it, unnest(it.reasons) r where it.provider_id = pr.id and it.kind = 'candidate' and it.outcome in ('refused', 'skipped', 'too_thin') group by 1) z),
        'records', (select jsonb_build_object('new', count(*) filter (where it.outcome in ('became_scholarship', 'new_record')), 'updated', count(*) filter (where it.outcome = 'updated'), 'unchanged', count(*) filter (where it.outcome = 'unchanged'))
                      from it where it.provider_id = pr.id and it.kind in ('candidate', 'page') and (it.kind = 'page' or it.outcome = 'became_scholarship')),
        'publish', jsonb_build_object(
            'published', (select count(*) from pub where pub.provider_id = pr.id and pub.publication_status = 'published' and pub.publishable),
            'next_publish', (select coalesce(jsonb_agg(jsonb_build_object('id', pub.id, 'name', pub.name) order by pub.name), '[]'::jsonb) from pub where pub.provider_id = pr.id and pub.publication_status is distinct from 'published' and pub.publishable),
            'blocked', (select coalesce(jsonb_agg(jsonb_build_object('id', pub.id, 'name', pub.name, 'held', pub.held, 'missing', pub.missing, 'status', pub.publication_status) order by pub.name), '[]'::jsonb) from pub where pub.provider_id = pr.id and not pub.publishable and pub.publication_status is distinct from 'published'),
            'failing', (select coalesce(jsonb_agg(jsonb_build_object('id', pub.id, 'name', pub.name, 'missing', pub.missing) order by pub.name), '[]'::jsonb) from pub where pub.provider_id = pr.id and pub.publication_status = 'published' and not pub.publishable)),
        'items', (select coalesce(jsonb_agg(jsonb_build_object('kind', it.kind, 'url', it.url, 'title', it.title, 'found_via', it.found_via, 'outcome', it.outcome, 'read_status', it.read_status,
                                                            'reasons', (select coalesce(jsonb_agg(security.scholarship_reason_label_v1(r)), '[]'::jsonb) from unnest(it.reasons) r),
                                                            'evidence_id', it.evidence_id, 'stored', it.storage_path is not null or it.evidence_id is not null, 'scholarship_id', it.scholarship_id, 'at', it.at)
                                         order by case it.kind when 'site_map' then 0 when 'listing' then 1 when 'candidate' then 2 else 3 end,
                                                  case it.outcome when 'became_scholarship' then 0 when 'new_record' then 0 when 'updated' then 1 when 'refused' then 2 when 'too_thin' then 3 when 'skipped' then 4 else 5 end, it.url), '[]'::jsonb)
                    from it where it.provider_id = pr.id))
      order by pr.name) from prov pr), '[]'::jsonb))
  into v_out;
  return v_out;
end $f$;
revoke all on function security.scholarship_job_journey_v1(uuid, uuid) from public, anon, authenticated;

create or replace function public.admin_scholarship_job_journey(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return security.scholarship_job_journey_v1(p_job, null);
end $f$;
revoke all on function public.admin_scholarship_job_journey(uuid) from public, anon;
grant execute on function public.admin_scholarship_job_journey(uuid) to authenticated;

-- A university's Coverage panel: its last five on-demand runs, each with what it found for that university
create or replace function public.admin_scholarship_provider_runs(p_provider_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(security.scholarship_job_journey_v1(j.id, p_provider_id) order by j.created_at desc), '[]'::jsonb)
            from (select j.id, j.created_at from pipeline.admin_jobs j
                   where j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') and j.args->'providers' ? p_provider_id::text
                   order by j.created_at desc limit 5) j);
end $f$;
revoke all on function public.admin_scholarship_provider_runs(uuid) from public, anon;
grant execute on function public.admin_scholarship_provider_runs(uuid) to authenticated;

-- Skip rules: read (Curator and above); add, switch on or off (Platform Admin, with a reason, logged)
create or replace function public.admin_scholarship_skip_rules(p_action text default 'read', p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pat text := btrim(coalesce(p_args->>'pattern', ''));
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action <> 'read' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'add' then
      if length(v_pat) < 3 then raise exception 'enter the address pattern'; end if;
      perform regexp_match('x', v_pat);
      insert into pipeline.scholarship_skip_rules(pattern, label, reason, added_by) values (v_pat, coalesce(nullif(btrim(p_args->>'label'), ''), 'Not a scholarship page'), v_reason, auth.uid())
      on conflict (pattern) do update set active = true, label = excluded.label, reason = excluded.reason, updated_at = now();
    elsif p_action = 'set_active' then
      update pipeline.scholarship_skip_rules set active = coalesce((p_args->>'active')::boolean, true), reason = v_reason, updated_at = now() where id = (p_args->>'id')::bigint;
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('scholarships', 'skip_rule_' || p_action, coalesce(p_args->>'id', v_pat), p_args, auth.uid());
  end if;
  return jsonb_build_object('can_manage', v_rank >= 6, 'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'pattern', r.pattern, 'label', r.label, 'active', r.active, 'unless', r.unless_pattern, 'reason', r.reason, 'added_at', r.added_at,
      'skipped', (select count(*) from pipeline.scholarship_page_candidates c where c.admit_status = 'skipped' and c.admit_reasons @> array['skipped: ' || r.label])) order by r.id), '[]'::jsonb) from pipeline.scholarship_skip_rules r));
end $f$;
revoke all on function public.admin_scholarship_skip_rules(text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_skip_rules(text, jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 3): pages that are never scholarships are skipped before they are read, by the address
  -- rules in Scholarships › Coverage › Settings and jobs (never an address that mentions a scholarship, bursary, stipend or grant)
  update pipeline.scholarship_page_candidates c set admit_status='skipped', admit_reasons=array['skipped: '||r.label], read_status=coalesce(c.read_status,'skipped'), read_at=now(), leased_until=null
    from pipeline.scholarship_skip_rules r
   where r.active and c.admit_status is null and c.matched_scholarship_id is null and c.source<>'register' and c.url ~* r.pattern and c.url !~* r.unless_pattern;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by (c.requested_at is not null) desc, r.rn, (r.priority not in (0,3)), c.id -- 11 Oct 2026: on-demand candidates first
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb; c pipeline.scholarship_page_candidates%rowtype; v_ev uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+interval '90 days' else now()+interval '6 hours' end,
         admit_status=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 2): a stored page that did not become a scholarship is kept as evidence of the decision
  if c.storage_path is not null and c.evidence_id is null and coalesce(c.admit_status,'')<>'admitted' then
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (security.coverage_sweep_source(c.provider_id),'scholarship_candidate_page',coalesce(c.final_url,c.url),c.storage_path,c.content_hash,'application/gzip',
            jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'read_status',c.read_status,'decision',coalesce(c.admit_status,c.read_status),'reasons',to_jsonb(coalesce(c.admit_reasons,'{}'::text[])),'worker','coverage-sweep scholarship candidates'),1,'scholarship_candidate:'||c.id)
    returning id into v_ev;
    update pipeline.scholarship_page_candidates set evidence_id=v_ev where id=c.id;
  end if;
  -- (Fix 4) a page that lists scholarships is suggested as the provider's listing page, for a person to confirm
  if coalesce(c.admit_status,'')<>'admitted' and c.read_status in ('read','too_thin')
     and (coalesce(c.facts->>'h1','')||' '||coalesce(c.title,'')||' '||coalesce(c.facts->>'page_title','') ~* '(scholarships? (finder|search|list|directory)|grants and scholarships|find (a|your) scholarship|^\s*scholarships\s*$)'
          or coalesce(c.admit_reasons,'{}') && array['listing_page'] or c.url ~* '(scholarship-finder|/scholarships?/?$|/grants-scholarships/?$)') then
    insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)
    values (c.provider_id,coalesce(c.final_url,c.url),security.scholarship_url_norm(coalesce(c.final_url,c.url)),'suggested',false,'suggested')
    on conflict (provider_id,url_norm) do nothing;
  end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_auto_publish_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '300s'
AS $function$
declare v_ids uuid[]; v_ref text; v_hold uuid[] := '{}';
begin
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;
  select coalesce(array_agg(p.scholarship_id), '{}') into v_ids
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id
   where p.publishable and coalesce(s.publication_status, 'unpublished') <> 'published'
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id);
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 5): a scholarship published automatically that now fails a check is held with the
  -- reason and taken off search; it is listed in Layer 4 to release or fix. One a person published is shown as failing, not held.
  select coalesce(array_agg(p.scholarship_id), '{}') into v_hold
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id = p.scholarship_id
   where not p.publishable and s.publication_status = 'published'
     and not exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)
     and coalesce((select b.approval_ref from pipeline.scholarship_publication_batches b where s.id = any (b.scholarship_ids) and b.kind = 'publish' order by b.created_at desc limit 1), '') like 'auto-publish%';
  v_ref := to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI');
  if cardinality(v_hold) > 0 then
    insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by)
    select p.scholarship_id, 'Failed a check after publishing: ' || array_to_string(p.missing, '; '), 'auto' from security.scholarship_publishability_for_v1(v_hold) p
    on conflict (scholarship_id) do update set reason = excluded.reason, held_by = 'auto', held_at = now(), released_at = null, release_note = null;
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = any (v_hold);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('withdraw', 'auto-hold ' || v_ref, v_hold);
  end if;
  if cardinality(v_ids) > 0 then
    update scholarship.scholarships set publication_status = 'published', updated_at = now() where id = any (v_ids);
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('publish', 'auto-publish ' || v_ref, v_ids);
  end if;
  if cardinality(v_ids) + cardinality(v_hold) > 0 then
    insert into search.refresh_requests(requested_by) values ('auto-publish ' || v_ref || ': ' || cardinality(v_ids) || ' published, ' || cardinality(v_hold) || ' held');
  end if;
  return jsonb_build_object('published', cardinality(v_ids), 'held', cardinality(v_hold), 'batch', case when cardinality(v_ids) > 0 then 'auto-publish ' || v_ref end);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks. The pages in scope were queued first in line when the task
  -- started; each minute this checks progress, sends the scraper worker the next step (map the site, screen candidate pages, read
  -- scholarship pages) when none is already on its way, and finishes when nothing in scope is left to do.
  elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_stall := interval '30 minutes'; v_since := v_j.created_at;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
    v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
    select count(*) filter (where p.requested_at is null and p.read_at >= v_since), count(*) into v_done, v_total
      from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id
     where s.lifecycle_status = 'active'
       and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
       and (p.requested_at is not null or p.read_at >= v_since or s.created_at >= v_since);
    if v_j.kind = 'scholarship_provider_scan' then
      select count(*) into v_n_map from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.status = 'pending' and d.attempts < 3;
      select count(*) into v_n_cand from pipeline.scholarship_page_candidates c
       where c.provider_id = any (v_ids) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.next_read_at <= now() and c.attempts < 3;
    end if;
    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    v_extra := jsonb_build_object('phase_detail', v_phase, 'providers_mapping', v_n_map, 'candidates_waiting', v_n_cand,
      'new_scholarships', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_ids) and s.created_at >= v_since),
      'links_changed', (select count(*) from pipeline.scholarship_sweep_changes c join scholarship.scholarships s on s.id = c.scholarship_id
                         where s.provider_id = any (v_ids) and c.field = 'course_links' and c.changed_at >= v_since),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = any (v_ids) and u.purpose like 'sch\_%' and u.at >= v_since));
    if v_j.kind = 'scholarship_course_check' then
      v_before := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'before', '[]'::jsonb)) x);
      v_extra := v_extra || jsonb_build_object('course_id', v_j.args->>'course_id',
        'linked_now', (select count(*) from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped'),
        'added', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
                   where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped' and not (m.scholarship_id = any (v_before))),
        'removed', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.scholarships s
                     where s.id = any (v_before) and not exists (select 1 from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.scholarship_id = s.id and m.mapping_state = 'mapped')));
    end if;
    if v_n_map = 0 and v_n_cand = 0 and v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' known scholarship page(s) read again through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' scholarship scraper credit(s) used for ' || case when cardinality(v_ids) = 1 then 'this provider' else 'these providers' end || ' while the task ran'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
    -- v2.15.248 (Platform Admin bugs 11/10-5, Feature 2): record what the task found and read, item by item, and count the new
    -- pages it checked in its progress and result
    perform security.scholarship_job_items_sync_v1(v_j.id);
    select v_extra || jsonb_build_object('candidates_found', count(*) filter (where i.kind = 'candidate'), 'became', count(*) filter (where i.outcome = 'became_scholarship'),
             'refused', count(*) filter (where i.outcome = 'refused'), 'too_thin', count(*) filter (where i.outcome = 'too_thin'), 'skipped', count(*) filter (where i.outcome = 'skipped'),
             'known_pages', count(*) filter (where i.kind = 'page')),
           v_done + count(*) filter (where i.kind = 'candidate' and i.outcome <> 'waiting'), v_total + count(*) filter (where i.kind = 'candidate')
      into v_extra, v_done, v_total from pipeline.admin_job_items i where i.job_id = v_j.id;
    if v_fin then
      v_done := v_total;
      v_note := coalesce(nullif((v_extra->>'candidates_found')::int, 0) || ' new page(s) checked (' || (v_extra->>'became') || ' became scholarships, ' || (v_extra->>'refused') || ' refused, '
                || (v_extra->>'too_thin') || ' too thin, ' || (v_extra->>'skipped') || ' skipped); ', 'no new pages found; ') || v_note;
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website (website, then contacts, then central
  -- pages; each step sent to the worker when none is on its way) and Find course pages with Firecrawl (the chosen courses first in
  -- the course page search, finished when each has been searched).
  elsif v_j.kind = 'provider_fill' then
    v_stall := interval '30 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid; v_total := 3;
    select nullif(btrim(p.website), ''), (p.phone is not null and p.email is not null) into v_site, v_cok from catalogue.providers p where p.id = v_pid;
    select * into r from pipeline.coverage_provider_discovery d where d.provider_id = v_pid;
    if v_site is null and r.provider_id is not null and r.status = 'no_website' and (r.site_searched_at is null or r.site_searched_at < v_since) then
      v_phase := 'finding the website'; v_done := 0;
      perform security.provider_task_fire_v1('find_site');
    elsif v_site is null then
      v_fin := true; v_done := 3;
      v_note := 'no website could be verified by search' || coalesce(' (' || (r.site_evidence->>'note') || ')', '') || '; enter it by hand in the Adapter builder, step 1.1';
    else
      v_done := 1;
      if not coalesce(v_cok, false) and exists (select 1 from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active')
         and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = v_pid and k.kind = 'public_general' and k.checked_at >= v_since and k.outcome not in ('leased', 'requested')) then
        v_phase := 'reading contacts';
        perform security.provider_task_fire_v1('contact_page');
      else
        v_done := 2;
        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased')) then
          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');
        else
          v_done := 3; v_fin := true;
        end if;
      end if;
    end if;
    v_extra := jsonb_build_object('phase_detail', coalesce(v_phase, 'finishing'), 'website', v_site, 'website_basis', r.site_evidence->>'basis',
      'phone', (select p.phone from catalogue.providers p where p.id = v_pid), 'email', (select p.email from catalogue.providers p where p.id = v_pid),
      'central_found', (select coalesce(jsonb_array_length(s.found), 0) from pipeline.provider_central_search s where s.provider_id = v_pid),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.at >= v_since));
    if v_fin and v_note is null then
      v_note := 'website ' || coalesce(v_site, 'not found') || '; phone ' || coalesce(v_extra->>'phone', 'not found') || ', email ' || coalesce(v_extra->>'email', 'not found')
             || '; ' || coalesce(v_extra->>'central_found', '0') || ' central page suggestion(s) to attach in the Adapter builder, step 1.3; ' || (v_extra->>'credits') || ' Firecrawl credit(s)';
    end if;
  elsif v_j.kind = 'course_page_find' then
    v_stall := interval '45 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x);
    v_total := coalesce(cardinality(v_ids), 0);
    select count(*) filter (where s.state not in ('queued', 'sent') and s.queued_at >= v_since),
           count(*) filter (where s.state in ('verified', 'found') and s.queued_at >= v_since),
           count(*) filter (where s.state = 'none' and s.queued_at >= v_since)
      into v_done, v_c, v_c2 from pipeline.course_link_search s where s.course_id = any (v_ids);
    v_phase := 'searching course pages';
    v_extra := jsonb_build_object('phase_detail', v_phase, 'found', v_c, 'not_found', v_c2,
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since));
    if v_done >= v_total then
      v_fin := true;
      v_note := v_c || ' of ' || v_total || ' course page(s) found on the provider''s site; ' || v_c2 || ' not found (enter those by hand in the Adapter builder, step 2.1)';
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_close_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_pid uuid;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id;
  if v_j.id is null or v_j.state not in ('done', 'failed', 'cancelled') then return; end if;
  if exists (select 1 from pipeline.jobs x where x.job_type = 'layer2_task' and x.payload->>'admin_job_id' = p_id::text) then return; end if;
  v_pid := case when coalesce(jsonb_array_length(v_j.args->'providers'), 0) = 1 then (v_j.args->'providers'->>0)::uuid else null end;
  insert into pipeline.jobs(job_type, domain, status, provider_id, requested_by, started_at, completed_at, attempt_count, payload, result, error_text)
  values ('layer2_task', v_j.kind, case when v_j.state = 'done' then 'completed' else 'failed' end, v_pid, v_j.requested_by, coalesce(v_j.started_at, v_j.created_at), coalesce(v_j.finished_at, now()), 1,
          jsonb_build_object('admin_job_id', v_j.id, 'kind', v_j.kind, 'title', v_j.title, 'scope', v_j.scope, 'reason', v_j.reason, 'args', v_j.args - 'providers', 'providers', coalesce(jsonb_array_length(v_j.args->'providers'), 0),
                             'provider_names', (select jsonb_agg(coalesce(p.display_name, p.canonical_name) order by coalesce(p.display_name, p.canonical_name)) from catalogue.providers p where p.id::text in (select jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)))),
                             'mode', case when v_j.kind = 'qualify_adapters' then 'qualification' else 'apply' end),
          jsonb_build_object('state', v_j.state, 'progress', v_j.progress) || v_j.result,
          case when v_j.state = 'cancelled' then 'cancelled by a person (work done so far kept)' else v_j.error end);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_pipeline_ops_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'pim', 'ref', 'workflow', 'search', 'publishing', 'integration', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_limit integer := least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer := greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text := lower(coalesce(nullif(p_args->>'sort',''),'created'));
  v_dir text := case when lower(coalesce(nullif(p_args->>'direction',''),'desc'))='asc' then 'asc' else 'desc' end;
  v_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_operation='pipeline_jobs_page' then
    with projected as (
      select j.id,j.job_type,j.domain,j.status,j.source_id,s.label source_label,s.source_type,co.iso_alpha2::text country_code,co.name country_name,j.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,j.entity_id,er.entity_type,er.stable_key entity_stable_key,j.started_at,j.completed_at,j.created_at,j.attempt_count,
        case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end layer_code,
        case when j.payload ? 'apply' then case when coalesce((j.payload->>'apply')::boolean,false) then 'APPLY' else 'DRY_RUN' end when lower(coalesce(j.result->>'mode',j.payload->>'mode',''))='apply' then 'APPLY' when lower(coalesce(j.result->>'mode',j.payload->>'mode','')) ~ '(dry|inventory|validate|qualification)' then 'DRY_RUN' else upper(nullif(coalesce(j.result->>'mode',j.payload->>'mode',''),'')) end run_mode,
        coalesce(j.payload->>'version',j.result->>'workerVersion',j.result->>'worker_version') worker_version,coalesce(j.payload->>'scope',j.result->>'scope',j.domain) run_scope,
        j.payload->>'title' task_title,j.result->>'note' task_note,j.payload->'provider_names' task_providers,(j.payload->>'admin_job_id') task_id,
        case when coalesce(j.payload->>'offset','') ~ '^-?[0-9]+$' then (j.payload->>'offset')::bigint else null end cursor_offset,
        case when coalesce(j.payload->>'batch_size','') ~ '^[0-9]+$' then (j.payload->>'batch_size')::integer when coalesce(j.result->>'batchSize','') ~ '^[0-9]+$' then (j.result->>'batchSize')::integer else null end batch_size,
        case when coalesce(j.result->>'nextOffset','') ~ '^-?[0-9]+$' then (j.result->>'nextOffset')::bigint when coalesce(j.result->>'next_offset','') ~ '^-?[0-9]+$' then (j.result->>'next_offset')::bigint else null end next_cursor,
        case when lower(coalesce(j.result->>'hasMore',j.result->>'has_more','')) in ('true','false') then lower(coalesce(j.result->>'hasMore',j.result->>'has_more'))::boolean else null end has_more,
        case when coalesce(j.result->>'sourceRows','') ~ '^[0-9]+$' then (j.result->>'sourceRows')::bigint when coalesce(j.result->>'source_rows','') ~ '^[0-9]+$' then (j.result->>'source_rows')::bigint when coalesce(j.result->>'discoveredRecords','') ~ '^[0-9]+$' then (j.result->>'discoveredRecords')::bigint else null end discovered_count,
        case when coalesce(j.result->>'selectedRecords','') ~ '^[0-9]+$' then (j.result->>'selectedRecords')::bigint when coalesce(j.result->>'selected_records','') ~ '^[0-9]+$' then (j.result->>'selected_records')::bigint when coalesce(j.result#>>'{reconciliation,records}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,records}')::bigint else null end selected_count,
        case when coalesce(j.result#>>'{reconciliation,records}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,records}')::bigint when coalesce(j.result->>'processedRecords','') ~ '^[0-9]+$' then (j.result->>'processedRecords')::bigint when coalesce(j.result->>'selectedRecords','') ~ '^[0-9]+$' then (j.result->>'selectedRecords')::bigint else null end processed_count,
        case when coalesce(j.result#>>'{reconciliation,mapped}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,mapped}')::bigint when coalesce(j.result->>'acceptedRecords','') ~ '^[0-9]+$' then (j.result->>'acceptedRecords')::bigint when coalesce(j.result->>'accepted_records','') ~ '^[0-9]+$' then (j.result->>'accepted_records')::bigint else null end accepted_count,
        (case when coalesce(j.result#>>'{reconciliation,unmapped}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,unmapped}')::bigint else 0 end + case when coalesce(j.result#>>'{reconciliation,course_missing}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,course_missing}')::bigint else 0 end + case when coalesce(j.result->>'rejectedRecords','') ~ '^[0-9]+$' then (j.result->>'rejectedRecords')::bigint else 0 end) rejected_count,
        case when coalesce(j.result#>>'{reconciliation,review_required}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,review_required}')::bigint else 0 end ambiguity_count,
        case when coalesce(j.result#>>'{reconciliation,observation_created}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_created}')::bigint when coalesce(j.result->>'created','') ~ '^[0-9]+$' then (j.result->>'created')::bigint else null end creates_count,
        case when coalesce(j.result#>>'{reconciliation,observation_updated}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_updated}')::bigint when coalesce(j.result->>'updated','') ~ '^[0-9]+$' then (j.result->>'updated')::bigint else null end updates_count,
        case when coalesce(j.result#>>'{reconciliation,observation_unchanged}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_unchanged}')::bigint when coalesce(j.result->>'unchanged','') ~ '^[0-9]+$' then (j.result->>'unchanged')::bigint else null end unchanged_count,
        case when coalesce(j.result#>>'{reconciliation,conflicts}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,conflicts}')::bigint when coalesce(j.result->>'conflicts','') ~ '^[0-9]+$' then (j.result->>'conflicts')::bigint else 0 end conflicts_count,
        (select count(*)::bigint from pipeline.evidence_artifacts e where e.job_id=j.id) evidence_count,
        case when j.started_at is not null then (extract(epoch from (coalesce(j.completed_at,now())-j.started_at))*1000)::bigint else null end duration_ms,
        case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_running' when j.status='blocked' then 'blocked' when j.status='failed' then 'incomplete_failure' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='true' then 'partial_batch' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='false' then 'source_or_scope_complete' when j.status='completed' then 'completed_scope_unknown' else 'in_progress_or_unknown' end completion_class,
        case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_runtime' when j.status='blocked' then 'governed_blocker' when j.status<>'failed' then null when lower(coalesce(j.error_text,'')) like '%superseded%' then 'historical_superseded' when lower(coalesce(j.error_text,'')) ~ '(inventory unstable|inventory incomplete|coverage blocker|source.*unstable)' then 'source_validation' when lower(coalesce(j.error_text,'')) ~ '(statement timeout|resource limit|compute limit|signal has been aborted|edge worker)' then 'technical_runtime' when lower(coalesce(j.error_text,'')) ~ '(schema cache|not defined|assignment to constant|requires a where clause|cannot insert|does not exist)' then 'technical_defect' when lower(coalesce(j.error_text,'')) like '%rejected%' then 'governed_rejection' else 'technical_failure' end failure_class,
        j.result->>'searchAction' search_action,coalesce(j.payload->>'change_control_ref',j.result->>'change_control_ref') change_control_ref,coalesce(j.payload->>'uat_ref',j.result->>'uat_ref') uat_ref,j.error_text,
        rq.run_id,rq.run_last_job_id,rq.run_summary
      from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=j.provider_id left join pim.entity_registry er on er.id=j.entity_id
      -- v2.15.246 (Fix 1): a register run's batches are one row (the run's last batch carries the run's totals)
      left join lateral (select q.id run_id, q.actual_job_id run_last_job_id, jsonb_build_object('status', q.status, 'started_at', q.started_at, 'completed_at', q.completed_at, 'expected', q.expected_count, 'processed', q.processed_count, 'created', q.created_count, 'updated', q.updated_count, 'unchanged', q.unchanged_count, 'conflicted', q.conflicted_count, 'failed', q.failed_count, 'register', (select jsonb_build_object('total', pl.register_total, 'new', pl.new_count, 'changed', pl.changed_count, 'departed', pl.departed_count) from pipeline.layer1_run_plans pl where pl.run_id = q.id)) run_summary
                           from pipeline.layer1_run_queue q where j.job_type='regulatory_sync' and q.source_id=j.source_id and q.started_at is not null and j.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds' order by q.started_at desc limit 1) rq on true
    ), filtered as (
      select * from projected x where (x.run_id is null or x.run_last_job_id is null or x.id = x.run_last_job_id) and (nullif(trim(coalesce(p_args->>'query','')),'') is null or x.id::text ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.job_type,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.source_label,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.provider_name,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.task_title,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.task_providers::text,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.worker_version,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.error_text,'') ilike '%'||trim(p_args->>'query')||'%') and (nullif(p_args->>'status','') is null or x.status=p_args->>'status') and (nullif(p_args->>'job_type','') is null or x.job_type=p_args->>'job_type') and (nullif(p_args->>'layer','') is null or x.layer_code=upper(p_args->>'layer')) and (nullif(p_args->>'mode','') is null or x.run_mode=upper(p_args->>'mode')) and (nullif(p_args->>'country_code','') is null or x.country_code=upper(p_args->>'country_code')) and (nullif(p_args->>'source_id','') is null or x.source_id=nullif(p_args->>'source_id','')::uuid) and (nullif(p_args->>'failure_class','') is null or x.failure_class=p_args->>'failure_class') and (nullif(p_args->>'completion_class','') is null or x.completion_class=p_args->>'completion_class')
    ), numbered as (select f.*,count(*) over()::bigint total_count from filtered f), ordered as (
      select * from numbered order by case when v_sort='created' and v_dir='asc' then created_at end asc,case when v_sort='created' and v_dir='desc' then created_at end desc,case when v_sort='duration' and v_dir='asc' then duration_ms end asc nulls last,case when v_sort='duration' and v_dir='desc' then duration_ms end desc nulls last,case when v_sort='status' and v_dir='asc' then status end asc,case when v_sort='status' and v_dir='desc' then status end desc,case when v_sort='layer' and v_dir='asc' then layer_code end asc,case when v_sort='layer' and v_dir='desc' then layer_code end desc,created_at desc,id limit v_limit offset v_offset
    ) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o; return v_result;
  elsif p_operation='pipeline_job_detail' then
    v_id:=nullif(p_args->>'id','')::uuid; if v_id is null then raise exception 'job id required' using errcode='22023'; end if;
    select jsonb_build_object('job',jsonb_build_object('id',j.id,'job_type',j.job_type,'domain',j.domain,'status',j.status,'source_id',j.source_id,'source_label',s.label,'source_type',s.source_type,'country_code',co.iso_alpha2,'country_name',co.name,'provider_id',j.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'entity_id',j.entity_id,'entity_type',er.entity_type,'entity_stable_key',er.stable_key,'requested_by',j.requested_by,'started_at',j.started_at,'completed_at',j.completed_at,'duration_ms',case when j.started_at is null then null else (extract(epoch from (coalesce(j.completed_at,now())-j.started_at))*1000)::bigint end,'attempt_count',j.attempt_count,'created_at',j.created_at,'error_text',j.error_text,'payload',j.payload,'result',j.result),'run_semantics',jsonb_build_object('layer',case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end,'authority',case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'regulatory_or_identity_authority' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' then 'deterministic_enrichment_non_identity' when j.job_type ~* '(ai|llm|model|extract)' then 'suggestion_only_no_silent_overwrite' when j.job_type ~* '(review|resolve)' then 'human_resolution_auditable' else 'unclassified' end,'mode',case when j.payload ? 'apply' then case when coalesce((j.payload->>'apply')::boolean,false) then 'APPLY' else 'DRY_RUN' end when lower(coalesce(j.result->>'mode',j.payload->>'mode',''))='apply' then 'APPLY' when lower(coalesce(j.result->>'mode',j.payload->>'mode','')) ~ '(dry|inventory|validate|qualification)' then 'DRY_RUN' else upper(nullif(coalesce(j.result->>'mode',j.payload->>'mode',''),'')) end,'completion_class',case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_running' when j.status='blocked' then 'blocked' when j.status='failed' then 'incomplete_failure' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='true' then 'partial_batch' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='false' then 'source_or_scope_complete' when j.status='completed' then 'completed_scope_unknown' else 'in_progress_or_unknown' end,'search_action',j.result->>'searchAction','change_control_ref',coalesce(j.payload->>'change_control_ref',j.result->>'change_control_ref'),'uat_ref',coalesce(j.payload->>'uat_ref',j.result->>'uat_ref')),'source',case when s.id is null then null else jsonb_build_object('id',s.id,'label',s.label,'source_type',s.source_type,'url',s.url,'status',s.status,'trust_rank',s.trust_rank,'last_checked_at',s.last_checked_at,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,'metadata',s.metadata) end,'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'mime_type',e.mime_type,'captured_at',e.captured_at,'valid_from',e.valid_from,'valid_to',e.valid_to,'supersedes_evidence_id',e.supersedes_evidence_id) order by e.captured_at desc) from pipeline.evidence_artifacts e where e.job_id=j.id),'[]'::jsonb),'entity_impact',jsonb_build_object('direct_entity',case when er.id is null then null else jsonb_build_object('id',er.id,'entity_type',er.entity_type,'stable_key',er.stable_key,'lifecycle_status',er.lifecycle_status) end,'direct_provider',case when p.id is null then null else jsonb_build_object('id',p.id,'stable_key',p.stable_key,'name',coalesce(p.display_name,p.canonical_name)) end,'scope_note',case when j.entity_id is null and j.provider_id is null then 'Batch/source-scoped job: entity-level impact links are not persisted on this job row; use evidence and adapter result counts.' else 'Direct entity/provider reference persisted on the job.' end),'safe_actions',jsonb_build_object('retry',jsonb_build_object('enabled',false,'reason','No generic retry command is exposed. Retry must be adapter-specific and idempotency-governed.'),'replay',jsonb_build_object('enabled',false,'reason','No generic replay command is exposed. Replay requires preserved evidence/hash plus adapter-specific scope validation.'),'reset',jsonb_build_object('enabled',false,'reason','Generic reset is intentionally prohibited. Any destructive reset requires an explicit governed scope and confirmation contract.'))) into v_result from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=j.provider_id left join pim.entity_registry er on er.id=j.entity_id where j.id=v_id; v_result := coalesce(v_result,'{}'::jsonb) || jsonb_build_object('run', security.layer1_run_for_job_v1(v_id)); return v_result;
  elsif p_operation='pipeline_sources_page' then
    with base as (select s.id source_id,s.label source_label,s.source_type,s.url source_url,s.status,s.trust_rank,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,case when lower(coalesce(s.metadata->>'layer','')) like '1%' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when lower(coalesce(s.metadata->>'layer','')) like '3%' then 'L3' when lower(coalesce(s.metadata->>'layer','')) like '4%' then 'L4' else case when s.source_type in ('dataset','regulatory_programme','provincial_regulator','provincial_catalogue','institutional_catalogue','first_party_programme','web_catalogue') then 'L1' else 'UNCLASSIFIED' end end layer_code,s.last_checked_at,s.last_success_at,s.last_failure_at,s.last_error,case when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'unhealthy' when s.last_success_at is not null then 'healthy' else 'untested' end health,case when s.last_success_at is null then null else round((extract(epoch from (now()-s.last_success_at))/86400.0)::numeric,2) end freshness_age_days,case when s.last_success_at is null then 'never_successful' when nullif(s.metadata->>'refresh_cadence','') is null then 'schedule_not_declared' else 'compare_to_declared_cadence' end freshness_class,s.metadata,(select max(j.completed_at) from pipeline.jobs j where j.source_id=s.id and j.status='completed') last_job_success_at,(select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status='running') running_jobs,(select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status in ('failed','blocked')) problem_jobs,(select count(*)::bigint from pipeline.evidence_artifacts e where e.source_id=s.id) evidence_count from pipeline.sources s left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=s.provider_id), filtered as (select * from base b where (nullif(trim(coalesce(p_args->>'query','')),'') is null or coalesce(b.source_label,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.source_type,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.provider_name,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.source_url,'') ilike '%'||trim(p_args->>'query')||'%') and (nullif(p_args->>'country_code','') is null or b.country_code=upper(p_args->>'country_code')) and (nullif(p_args->>'layer','') is null or b.layer_code=upper(p_args->>'layer')) and (nullif(p_args->>'status','') is null or b.status=p_args->>'status') and (nullif(p_args->>'source_type','') is null or b.source_type=p_args->>'source_type') and (nullif(p_args->>'health','') is null or b.health=p_args->>'health')), numbered as (select f.*,count(*) over()::bigint total_count from filtered f), ordered as (select * from numbered order by case when v_sort in ('source','name') and v_dir='asc' then lower(source_label) end asc,case when v_sort in ('source','name') and v_dir='desc' then lower(source_label) end desc,case when v_sort='country' and v_dir='asc' then country_code end asc nulls last,case when v_sort='country' and v_dir='desc' then country_code end desc nulls last,case when v_sort='health' and v_dir='asc' then health end asc,case when v_sort='health' and v_dir='desc' then health end desc,case when v_sort='freshness' and v_dir='asc' then freshness_age_days end asc nulls last,case when v_sort='freshness' and v_dir='desc' then freshness_age_days end desc nulls last,lower(source_label),source_id limit v_limit offset v_offset) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o; return v_result;
  elsif p_operation='pipeline_filters' then
    select jsonb_build_object('countries',coalesce((select jsonb_agg(x order by x->>'code') from (select distinct jsonb_build_object('code',co.iso_alpha2::text,'name',co.name) x from pipeline.sources s join ref.countries co on co.id=s.country_id) q),'[]'::jsonb),'job_types',coalesce((select jsonb_agg(job_type order by job_type) from (select distinct job_type from pipeline.jobs where job_type is not null) q),'[]'::jsonb),'statuses',coalesce((select jsonb_agg(status order by status) from (select distinct status from pipeline.jobs where status is not null) q),'[]'::jsonb),'source_types',coalesce((select jsonb_agg(source_type order by source_type) from (select distinct source_type from pipeline.sources where source_type is not null) q),'[]'::jsonb),'layers',jsonb_build_array('L1','L2','L3','L4','UNCLASSIFIED'),'modes',jsonb_build_array('DRY_RUN','APPLY')) into v_result; return v_result;
  elsif p_operation='pipeline_overview' then
    with job_stage as (select j.*,case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end layer_code from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id),source_stage as (select s.*,case when lower(coalesce(s.metadata->>'layer','')) like '1%' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when lower(coalesce(s.metadata->>'layer','')) like '3%' then 'L3' when lower(coalesce(s.metadata->>'layer','')) like '4%' then 'L4' else case when s.source_type in ('dataset','regulatory_programme','provincial_regulator','provincial_catalogue','institutional_catalogue','first_party_programme','web_catalogue') then 'L1' else 'UNCLASSIFIED' end end layer_code from pipeline.sources s),layers as (select 'L1' code,'Layer 1 Regulatory' name,'regulatory_authority' authority,1 seq union all select 'L2','Layer 2 Deterministic / Structured Enrichment','non_identity_structured_enrichment',2 union all select 'L3','Layer 3 AI Suggestions','suggestion_only_no_silent_overwrite',3 union all select 'L4','Layer 4 Human Resolution','auditable_human_decision',4),layer_cards as (select jsonb_build_object('code',l.code,'name',l.name,'authority',l.authority,'source_count',(select count(*)::bigint from source_stage s where s.layer_code=l.code),'job_count',(select count(*)::bigint from job_stage j where j.layer_code=l.code),'running_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='running'),'stale_running_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes'),'failed_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='failed'),'blocked_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='blocked'),'last_success_at',(select max(j.completed_at) from job_stage j where j.layer_code=l.code and j.status='completed'),'current_job',(select jsonb_build_object('id',j.id,'job_type',j.job_type,'status',j.status,'started_at',j.started_at) from job_stage j where j.layer_code=l.code and j.status='running' order by j.started_at desc nulls last limit 1),'evidence_count',(select count(*)::bigint from pipeline.evidence_artifacts e join source_stage s on s.id=e.source_id where s.layer_code=l.code),'next_allowed_action',case when l.code='L3' then 'AI suggestions may be generated only into governed suggestion/claim surfaces; no silent overwrite of L1/L2.' when l.code='L4' then 'Resolve queued ambiguity/conflict through auditable review actions; direct canonical overwrite is not a review action.' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes') then 'Investigate stale running job before any replay.' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='blocked') then 'Resolve explicit blocker before rerun.' else 'Use adapter-specific dry-run/APPLY runbook; generic replay/reset is not exposed.' end,'blocker',case when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes') then 'STALE_RUNNING_JOB' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='blocked') then 'BLOCKED_JOB_PRESENT' when l.code='L3' and (select count(*) from workflow.suggestions)=0 then 'NOT_OPERATIONAL_NO_SUGGESTIONS' when l.code='L4' and (select count(*) from workflow.review_queue)=0 then null else null end,'governance_ref',null,'uat_ref',null) item,l.seq from layers l) select jsonb_build_object('journey',jsonb_build_array('Layer 1 Regulatory','Layer 2 Deterministic/Structured Enrichment','Layer 3 AI Suggestions','Layer 4 Human Resolution','Search Admission','Publication'),'layers',(select jsonb_agg(item order by seq) from layer_cards),'layer3',jsonb_build_object('suggestions_total',(select count(*)::bigint from workflow.suggestions),'claims_total',(select count(*)::bigint from pipeline.claims where layer=3),'overwrite_policy','Layer 3 is suggestion-only and has no direct authority to overwrite Layer 1/2 facts.'),'layer4',jsonb_build_object('review_queue_total',(select count(*)::bigint from workflow.review_queue),'review_open',(select count(*)::bigint from workflow.review_queue where coalesce(status,'open') not in ('closed','resolved','rejected')),'review_actions_total',(select count(*)::bigint from workflow.review_actions),'audit_policy','Every human resolution must be represented by review_actions with before/after/reason/evidence where applicable.'),'search_admission',jsonb_build_object('documents',(select count(*)::bigint from search.course_documents),'projection',coalesce((select jsonb_build_object('projection_code',ps.projection_code,'generation',ps.generation,'row_count',ps.row_count,'rebuilt_at',ps.rebuilt_at,'content_hash',ps.content_hash,'metadata',ps.metadata) from search.projection_state ps where ps.projection_code='courses' limit 1),'{}'::jsonb),'country_gates',coalesce((select jsonb_agg(jsonb_build_object('projection_code',g.projection_code,'country_code',co.iso_alpha2,'gate_status',g.gate_status,'approval_ref',g.approval_ref,'approved_at',g.approved_at,'updated_at',g.updated_at) order by co.iso_alpha2) from search.projection_country_gates g left join ref.countries co on co.id=g.country_id),'[]'::jsonb),'enrichment_gates',coalesce((select jsonb_agg(to_jsonb(g) order by g.domain_code) from search.enrichment_gates g),'[]'::jsonb),'blocked_enrichment_gates',(select count(*)::bigint from search.enrichment_gates where gate_status<>'approved'),'definition','Ingestion/enrichment completion does not imply Search admission. Search gates are reported independently.'),'publication',jsonb_build_object('entity_states_total',(select count(*)::bigint from publishing.entity_states),'channels',coalesce((select jsonb_agg(to_jsonb(c) order by c.code) from publishing.channels c),'[]'::jsonb),'status_counts',coalesce((select jsonb_object_agg(publication_status,cnt) from (select publication_status,count(*)::bigint cnt from publishing.entity_states group by publication_status) q),'{}'::jsonb),'definition','Publication is a downstream channel state and is not equivalent to successful ingestion or Search projection.'),'guardrails',jsonb_build_object('generic_reset',false,'generic_retry',false,'generic_replay',false,'reason','Destructive/replay operations require adapter-specific governed scope, preserved evidence/hash, explicit confirmation and idempotency semantics.'),'observed_volumes',jsonb_build_object('jobs',(select count(*)::bigint from pipeline.jobs),'sources',(select count(*)::bigint from pipeline.sources),'evidence',(select count(*)::bigint from pipeline.evidence_artifacts),'claims',(select count(*)::bigint from pipeline.claims))) into v_result; return v_result;
  else raise exception 'unsupported pipeline ops read: %',p_operation using errcode='22023'; end if;
end $function$;

-- What today's scholarship tasks found and read, recorded now (they ran before this record existed), and the university names on
-- the finished tasks in Jobs
do $data$
declare v_id uuid;
begin
  for v_id in select j.id from pipeline.admin_jobs j where j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') and j.created_at > now() - interval '3 days' loop
    perform security.scholarship_job_items_sync_v1(v_id);
  end loop;
  update pipeline.jobs x set payload = x.payload || jsonb_build_object('provider_names',
           (select jsonb_agg(coalesce(p.display_name, p.canonical_name) order by coalesce(p.display_name, p.canonical_name)) from catalogue.providers p where p.id::text in (select jsonb_array_elements_text(coalesce(a.args->'providers', '[]'::jsonb)))))
    from pipeline.admin_jobs a where x.job_type = 'layer2_task' and x.payload->>'admin_job_id' = a.id::text and not (x.payload ? 'provider_names');
end $data$;
-- Standing rule G1: the new reads and writes are task parts, not new scheduled jobs (nothing new runs on a schedule)

do $post$
declare v_expected jsonb := '{"public.svc_scholarship_candidate_next(integer)": "e712f443fe298d75a89352cdf19b17f7", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "ae89fd44d52b075254b214de2e03edda", "security.scholarship_auto_publish_v1()": "c5e0a77f3de9d9b68993275f18c37c56", "security.admin_job_watch_v1(uuid)": "f0c7f496ec21728587b46d689d2c628b", "security.admin_job_close_v1(uuid)": "233236ffc66e438edb21c4f51a6c45a1", "security.admin_pipeline_ops_read(text,jsonb)": "898e94c53630aee8e22466b121915e8a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception '20261011010200 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
