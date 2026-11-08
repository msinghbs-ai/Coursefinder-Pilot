-- CF-247 P-DESC (lane E, Platform Admin directive 8 Nov 2026 14:06 Melbourne: restore independent execution of provider descriptions).
--
-- Finding (live read 8 Nov 2026 03:10 UTC, project fxcwkweaxjtknorudmwp):
--   0 of 3,087 active providers hold a description. The reader is on and healthy (pdesc.enabled 1, job provider-description-read active, 6,16,26,56 past
--   each hour, every run succeeds) but has had nothing to do since 3 Nov 00:06 UTC: pdesc.provider_keys pins the run scope to 5 providers
--   (Wollongong, Queensland, Monash, Charles Darwin, ACU), all 5 already have a read (4 proposed and waiting in Layer 4 since 2-3 Nov, 1 held), the AI
--   spend is US$0.0066 of the US$1 pilot ceiling. Nothing is broken in the reader; the scope and the reviewers' decisions are the limits (Controller / Platform
--   Admin actions, recorded in the lane report).
-- Defect found on the way (new, linked under IQ-00022): a held or rejected read waits pdesc.recheck_days (180) before the provider is selected again, even when a
--   different official About page has since been stored. security.provider_description_selection_v1 only compares the stored copy with the read's hash for
--   'unchanged_unsuitable_evidence'; every other held or rejected read falls to 'retry_wait' for 180 days, so a provider whose first read found no usable page, or a
--   page that the page rule (IQ-00022) now refuses, is never read again on the better page. Live: Wollongong's proposal was built from
--   /about/global-presence/international-linkages/, which security.provider_description_page_v1 now refuses (refused_word); a reviewer's rejection of it would park the
--   provider for 180 days although /about/ passes the rule.
-- Change 1: security.provider_description_selection_v1 stops answering 'retry_wait' when (a) the read has waited at least pdesc.retry_minutes, (b) a stored official
--   copy exists whose content hash differs from the read's, and (c) the read was held by the platform, or it was rejected by a person on a source the page rule now
--   refuses. A rejection by a person on a source that still passes the rule keeps its 180-day wait (a person said no to that evidence). The same hash is still
--   'unchanged_unsuitable_evidence'. Every later check (identity, lifecycle, manual lock, recovery knowledge, cost) still applies; no number is added (existing
--   settings pdesc.retry_minutes and pdesc.recheck_days), no duplicate or support rule is touched, no Layer 4 item is decided.
-- Change 2: public.admin_provider_description_funnel_v1(), read only, the stage counts for the whole catalogue, not only the 5 pinned providers (the existing
--   admin_provider_descriptions('metrics') counts only providers inside the run scope): registry, website, policy scope, run scope, identity clear, stored About
--   page, read, proposed, held (by rule), rejected, admitted, published, plus Layer 4 pending and oldest age, job and last run, spend and the next-run eligibility
--   with its reasons.
-- Consumer API: untouched (no public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* function or table is read or changed).
-- No setting, flag, job or Layer 4 item is changed. Nothing is switched on; scope widening (pdesc.provider_keys) is the Controller's / Platform Admin's setting.
--
-- Live definition this change edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.provider_description_selection_v1(jsonb) 6b43ea62758a2c6fac80affba14b12d5 -> 1fd3fcde2fcafed6fadf4f6337c0482c
-- Called, not edited: security.provider_description_page_v1(uuid,text), security.provider_description_scope_v1(uuid), security.provider_description_stored_v1(uuid),
--   security.provider_description_identity_v1(uuid,text).
-- Replaces: the 180-day 'retry_wait' branch of security.provider_description_selection_v1 for held reads when the stored official copy has changed (edited in place); the 'metrics' scope-only counting is not replaced (kept beside it)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_page_v1(uuid,text)'), ('security.provider_description_scope_v1(uuid)'), ('security.provider_description_stored_v1(uuid)'),
                                 ('security.provider_description_identity_v1(uuid,text)'), ('security.current_role_rank()'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_old text, p_new text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.provider_description_selection_v1(jsonb)', '6b43ea62758a2c6fac80affba14b12d5', '1fd3fcde2fcafed6fadf4f6337c0482c',
$old$  when r.state in ('held','rejected') and r.updated_at>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'retry_wait'
$old$,
$new$  when r.state in ('held','rejected') and r.updated_at>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int)
   and not (r.updated_at<=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int) and a.id is not null
            and coalesce(a.content_hash,a.id::text) is distinct from r.content_hash
            and (r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) then 'retry_wait'
$new$);

-- Change 2: the whole-catalogue funnel (read only) ---------------------------------------------------------------------------------------------
create or replace function public.admin_provider_description_funnel_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_out jsonb; v_job jsonb; v_last jsonb := null; v_sel jsonb; v_elig int; v_pending int; v_pmax numeric := security.pipeline_num_v1('pdesc.pending_max', 10);
        v_size int := least(security.pipeline_num_v1('pdesc.queue_per_run', 10), security.pipeline_num_v1('pdesc.pending_max', 10), security.pipeline_num_v1('run_now.pilot_cap', 20))::int;
        v_stall text; v_policy int; v_run int; v_spent numeric; v_fc numeric;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
  with base as (
    select p.id, p.stable_key, p.website, nullif(btrim(p.description), '') is not null has_desc, nullif(btrim(p.website), '') is not null has_site,
           p.lifecycle_status = 'active' and p.publication_status = 'published' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) live,
           coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text
             and coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(t.code, '') policy_scope
      from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where p.lifecycle_status = 'active'),
  st as (
    select b.*, case when b.live and b.policy_scope then security.provider_description_scope_v1(b.id) end run_scope,
           case when b.live and b.policy_scope then coalesce((security.provider_description_identity_v1(b.id, b.website)->>'ok')::boolean, false) end identity_ok,
           case when b.live and b.policy_scope then security.provider_description_stored_v1(b.id) is not null end stored_page,
           lr.state, lr.rule, lr.published_at, lr.consumer_checked_at, lr.created_at read_created
      from base b left join lateral (select x.state, x.rule, x.published_at, x.consumer_checked_at, x.created_at from pipeline.provider_description_reads x where x.provider_id = b.id order by x.created_at desc, x.id desc limit 1) lr on true)
  select jsonb_build_object(
    'contract', 'provider-description-funnel-v1', 'as_at', now(),
    'stages', jsonb_build_array(
      jsonb_build_object('key', 'registry', 'label', 'Active providers', 'n', count(*)),
      jsonb_build_object('key', 'live', 'label', 'Active, published, not hidden', 'n', count(*) filter (where live)),
      jsonb_build_object('key', 'website', 'label', 'With a website', 'n', count(*) filter (where live and has_site)),
      jsonb_build_object('key', 'policy_scope', 'label', 'In the set countries and institution types', 'n', count(*) filter (where live and policy_scope)),
      jsonb_build_object('key', 'run_scope', 'label', 'In the run scope (pdesc.provider_keys applied)', 'n', count(*) filter (where run_scope)),
      jsonb_build_object('key', 'identity_clear', 'label', 'Identity clear (policy scope)', 'n', count(*) filter (where identity_ok)),
      jsonb_build_object('key', 'stored_page', 'label', 'Official About page already stored (policy scope)', 'n', count(*) filter (where stored_page)),
      jsonb_build_object('key', 'read', 'label', 'Read at least once', 'n', count(*) filter (where state is not null)),
      jsonb_build_object('key', 'queued', 'label', 'Queued or reading', 'n', count(*) filter (where state in ('queued', 'reading'))),
      jsonb_build_object('key', 'proposed', 'label', 'Proposed, waiting for a person in Layer 4', 'n', count(*) filter (where state = 'proposed')),
      jsonb_build_object('key', 'held', 'label', 'Held by a rule', 'n', count(*) filter (where state in ('held', 'dead_letter'))),
      jsonb_build_object('key', 'rejected', 'label', 'Rejected by a person', 'n', count(*) filter (where state = 'rejected')),
      jsonb_build_object('key', 'admitted', 'label', 'Approved and admitted', 'n', count(*) filter (where state in ('admitted', 'verified'))),
      jsonb_build_object('key', 'published', 'label', 'Description held by the catalogue', 'n', count(*) filter (where has_desc and live)),
      jsonb_build_object('key', 'consumer_checked', 'label', 'Checked on the Website read', 'n', count(*) filter (where consumer_checked_at is not null))),
    'held_reasons', coalesce((select jsonb_agg(jsonb_build_object('rule', z.rule, 'state', z.state, 'n', z.n) order by z.n desc, z.rule) from (select s.rule, s.state, count(*) n from st s where s.state in ('held', 'dead_letter', 'rejected') group by 1, 2) z), '[]'::jsonb),
    'policy_scope_outside_run_scope', count(*) filter (where live and policy_scope and not run_scope),
    'oldest_open_read', min(read_created) filter (where state in ('queued', 'reading', 'proposed')))
    into v_out from st;
  v_policy := (select (x->>'n')::int from jsonb_array_elements(v_out->'stages') x where x->>'key' = 'policy_scope');
  v_run := (select (x->>'n')::int from jsonb_array_elements(v_out->'stages') x where x->>'key' = 'run_scope');
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  v_sel := security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', v_size, 'mode', case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then 'approved' else 'stored' end));
  v_elig := (v_sel->>'eligible')::int;
  select jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active) into v_job from cron.job j where j.jobname = 'provider-description-read';
  if to_regclass('cron.job_run_details') is not null then
    execute $q$select jsonb_build_object('status', d.status, 'started', d.start_time, 'finished', d.end_time) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-read' order by d.start_time desc limit 1$q$ into v_last;
  end if;
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc from pipeline.provider_description_reads r;
  v_stall := case when security.pipeline_num_v1('pdesc.enabled', 0) < 1 then 'reader_off'
                  when coalesce((v_job->>'active')::boolean, false) is not true then 'job_paused'
                  when v_pending >= v_pmax then 'review_full'
                  when v_elig > 0 then 'next_run_will_queue'
                  when v_policy > v_run then 'run_scope_limited_by_pdesc_provider_keys'
                  when v_pending > 0 then 'waiting_for_reviewers'
                  else 'no_eligible_provider_in_scope' end;
  return v_out || jsonb_build_object(
    'layer4', jsonb_build_object('pending', v_pending, 'pending_max', v_pmax,
       'oldest_pending', (select min(i.created_at) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending'),
       'decided', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status <> 'pending')),
    'job', coalesce(v_job, '{}'::jsonb), 'last_run', v_last,
    'settings', jsonb_build_object('enabled', security.pipeline_num_v1('pdesc.enabled', 0) >= 1, 'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1,
       'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1, 'queue_per_run', security.pipeline_num_v1('pdesc.queue_per_run', 10),
       'pinned_providers', jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)),
       'countries', coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb), 'provider_types', coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb)),
    'spend', jsonb_build_object('ai_usd', round(v_spent, 4), 'ai_usd_max', security.pipeline_num_v1('pdesc.ai_usd_max', 1), 'firecrawl_reads', v_fc, 'firecrawl_reads_max', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)),
    'next_run', jsonb_build_object('eligible', v_elig, 'size', v_size, 'exclusions', coalesce((select jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n) order by z.n desc, z.reason)
                                                                                                from (select x->>'reason' reason, count(*) n from jsonb_array_elements(coalesce(v_sel->'exclusions', '[]'::jsonb)) x group by 1) z), '[]'::jsonb)),
    'stall', v_stall);
end $function$;
revoke all on function public.admin_provider_description_funnel_v1() from public, anon;
grant execute on function public.admin_provider_description_funnel_v1() to authenticated;
comment on function public.admin_provider_description_funnel_v1() is 'Provider descriptions (lane P-DESC, 8 Nov 2026): read-only whole-catalogue funnel from registry to published, held reasons, Layer 4 waiting and oldest age, job and last run, spend and why the next run will or will not queue. Curator role or above. Reads only; no write, no decision.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_provider_description_funnel_v1', 'Operations', 'Provider descriptions: whole-catalogue funnel and stall reason for Enrich fields', 'active', '{}', '20261108140000')
on conflict do nothing;
