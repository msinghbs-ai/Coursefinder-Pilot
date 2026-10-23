-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 1 (Platform Admin decisions 20:42, conditions C1 and 20:56 F1):
-- the NZ polytechnic transition is recorded per provider from the Government's published pages, each row with its source, and a
-- daily job re-checks each flagged provider's website and asks the source finder to look again, because domains and brands move
-- during the transition. C1 closed 23 Oct 2026 20:52 (Beehive release 31 Mar 2026, TEC NZIST page 20 Jul 2026, Ministry of
-- Education VET redesign page): the seed ships as the next migration (20261023024000), every row with its Government source.
-- Replaces: nothing
-- Retires: nothing

create table pipeline.provider_transitions (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  -- standalone_from_2027 and operations_transfer_2027 added at 20:52 (addendum): the three 2027 standalones are not federation members
  risk text not null check (risk in ('none', 're_established_2026', 'standalone_from_2027', 'operations_transfer_2027', 'nzist_federation_until_2027', 'nzist_entity')),
  note text,
  recheck_days int check (recheck_days between 7 and 180),  -- per-provider override of transition.recheck_days (Tai Poutini 14)
  source_url text not null check (source_url ~* '^https://'),
  source_quote text,
  as_at date not null,
  decided_by uuid,
  last_checked_at timestamptz,
  last_check jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.provider_transitions is 'CF-247 23 Oct 2026 (NZ brief C1): NZ providers in the polytechnic transition, each with the Government page it comes from (source_url, source_quote, as_at). risk is set by a person with a source; the daily transition-recheck job only records last_check and queues the website check and source finder.';
alter table pipeline.provider_transitions enable row level security;
revoke all on pipeline.provider_transitions from public, anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'transition.recheck_days', 'Transition: re-check every',
        'How often a provider in the NZ polytechnic transition has its website checked and its course source found again (a provider row may set its own shorter interval).',
        'number', '30'::jsonb, '7', '180', 'days', 150, 'Job sizes', 'job transition-recheck', 'Platform Admin 23 Oct 2026 20:42: NZ brief Release 1')
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'batch.transition_recheck', 'Transition: providers re-checked a run', 'Providers the daily transition re-check handles in one run.', 'number', '5'::jsonb, '1', '50', 'providers', 151, 'Job sizes', 'job transition-recheck', 'Platform Admin 23 Oct 2026 20:42: NZ brief Release 1')
on conflict (toolset_key, key) do nothing;

-- the website check and the source finder already exist; this queues them for providers whose interval has passed
create or replace function security.transition_recheck_v1() returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare v_n int := 0; r record; v_site text;
begin
  for r in select t.provider_id, t.risk, coalesce(t.recheck_days, security.pipeline_num_v1('transition.recheck_days', 30)::int) every
             from pipeline.provider_transitions t
            where t.risk <> 'none'
              and coalesce(t.last_checked_at, '-infinity'::timestamptz) < now() - make_interval(days => coalesce(t.recheck_days, security.pipeline_num_v1('transition.recheck_days', 30)::int))
            order by t.last_checked_at nulls first
            limit security.pipeline_num_v1('batch.transition_recheck', 5)::int loop
    select (security.provider_website_list_v1(p.website))[1] into v_site from catalogue.providers p where p.id = r.provider_id;
    if v_site is not null and not exists (select 1 from pipeline.provider_website_checks w where w.provider_id = r.provider_id and w.state in ('queued', 'leased')) then
      -- requested_by: the job runs as the platform; the row carries the Platform Admin who decided the transition (decided_by)
      insert into pipeline.provider_website_checks(provider_id, url, action, reason, requested_by)
      select r.provider_id, v_site, 'check', 'NZ transition re-check (' || r.risk || ', every ' || r.every || ' days)', t.decided_by
        from pipeline.provider_transitions t where t.provider_id = r.provider_id and t.decided_by is not null;
    end if;
    -- the same "find again" as Course sources › Find again (admin_course_sources): a run row asked to look again
    update pipeline.source_find_runs set next_try_at = now(), step = null, leased_until = null, work = jsonb_build_object('again', true, 'reason', 'NZ transition re-check')
     where provider_id = r.provider_id;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at, work)
    values (r.provider_id, 'none', now(), jsonb_build_object('again', true, 'reason', 'NZ transition re-check')) on conflict (provider_id) do nothing;
    update pipeline.provider_transitions set last_checked_at = now(), last_check = jsonb_build_object('at', now(), 'website', v_site, 'queued', true), updated_at = now()
     where provider_id = r.provider_id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('rechecked', v_n);
end $f$;
revoke execute on function security.transition_recheck_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('transition-recheck', 'Layer 1 register', 9, 'New Zealand: polytechnic transition re-check',
        'Daily at 03:41: for each NZ provider in the polytechnic transition whose interval has passed (Transition: re-check every, or the provider''s own), queues a website check and asks the source finder to look again, so a moved domain or brand is found without a person. Handles Transition: providers re-checked a run providers each run.',
        6, true);
select cron.schedule('transition-recheck', '41 3 * * *', $$select security.transition_recheck_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_transitions', 'Layer 1', 'NZ polytechnic transition per provider, with the Government source', 'active', '{}', '20261023023000'),
 ('function', 'security.transition_recheck_v1', 'Layer 1', 'Daily re-check of transition providers (website check and source finder queued)', 'active', '{}', '20261023023000'),
 ('job', 'transition-recheck', 'Layer 1', 'Runs security.transition_recheck_v1 daily at 03:41', 'active', '{}', '20261023023000')
on conflict (kind, name) do nothing;

select 'NZ provider transitions: table, re-check job and settings' ok;
-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 1 seed (Platform Admin 20:52 addendum: C1 closed). Every row cites the
-- Government page it comes from. The Beehive release could not be read from the build environment (its site redirects the fetch);
-- its quote is the Platform Admin's own summary of the page, marked as such.
-- Replaces: nothing
-- Retires: nothing

create temp table _seed(code text, risk text, note text, recheck int, url text, quote text, as_at date) on commit drop;
insert into _seed values
 ('6006', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Ara Institute of Canterbury (Ara)', '2025-07-14'),
 ('6007', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Eastern Institute of Technology (EIT)', '2025-07-14'),
 ('6011', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Nelson Marlborough Institute of Technology (NMIT)', '2025-07-14'),
 ('6015', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Southern Institute of Technology (SIT)', '2025-07-14'),
 ('6025', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Toi Ohomai Institute of Technology', '2025-07-14'),
 ('6019', 're_established_2026', 'standalone from 1 Jan 2026', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Waikato Institute of Technology (Wintec)', '2025-07-14'),
 ('6004', 're_established_2026', 'merged with MIT into one standalone entity; two register codes until NZQA merges them', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Unitec Institute of Technology and Manukau Institute of Technology (MIT) – to merge and stand-alone', '2025-07-14'),
 ('6010', 're_established_2026', 'merged with Unitec into one standalone entity; two register codes until NZQA merges them', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Unitec Institute of Technology and Manukau Institute of Technology (MIT) – to merge and stand-alone', '2025-07-14'),
 ('6013', 're_established_2026', 'standalone within the federation', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Otago Polytechnic – to stand alone within the federation', '2025-07-14'),
 ('6009', 're_established_2026', 'standalone within the federation', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Universal College of Learning (UCOL) – to stand-alone within the federation', '2025-07-14'),
 ('6022', 're_established_2026', 'anchor of the federation', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'The Open Polytechnic of New Zealand – to serve as the anchor polytechnic of the new federation.', '2025-07-14'),
 ('6012', 'standalone_from_2027', 'stand-alone from 1 Jan 2027; legally established 1 Oct 2026; Federation support; exits NZIST 1 Jan 2027', null, 'https://www.beehive.govt.nz/release/new-chapter-remaining-four-polytechnics-2027', 'Platform Admin summary 23 Oct 2026 of the 31 Mar 2026 release: NorthTec, WITT, Whitireia and WelTec stand-alone from 1 Jan 2027 with Federation support (page not readable from the build environment)', '2026-03-31'),
 ('6017', 'standalone_from_2027', 'stand-alone from 1 Jan 2027; legally established 1 Oct 2026; Federation support; exits NZIST 1 Jan 2027', null, 'https://www.beehive.govt.nz/release/new-chapter-remaining-four-polytechnics-2027', 'Platform Admin summary 23 Oct 2026 of the 31 Mar 2026 release: NorthTec, WITT, Whitireia and WelTec stand-alone from 1 Jan 2027 with Federation support (page not readable from the build environment)', '2026-03-31'),
 ('6014', 'standalone_from_2027', 'stand-alone from 1 Jan 2027; legally established 1 Oct 2026; Federation support; exits NZIST 1 Jan 2027', null, 'https://www.beehive.govt.nz/release/new-chapter-remaining-four-polytechnics-2027', 'Platform Admin summary 23 Oct 2026 of the 31 Mar 2026 release: NorthTec, WITT, Whitireia and WelTec stand-alone from 1 Jan 2027 with Federation support (page not readable from the build environment)', '2026-03-31'),
 ('6024', 'operations_transfer_2027', 'operations transfer to Open Polytechnic from 1 Jan 2027; brand/domain migration expected (also Beehive release 31 Mar 2026: https://www.beehive.govt.nz/release/new-chapter-remaining-four-polytechnics-2027)', 14, 'https://education.govt.nz/our-work/strategies-policies-and-programmes/tertiary-and-further-education/redesign-vocational-education-and-training-system', 'Tai Poutini Polytechnic on the West Coast will be transferred to the Open Polytechnic to manage its operations (from 1 January 2027)', '2026-06-26'),
 ('6683', 'nzist_entity', 'disestablished on or before 31 Mar 2027', null, 'https://education.govt.nz/our-work/strategies-policies-and-programmes/tertiary-and-further-education/redesign-vocational-education-and-training-system', 'until it is disestablished on or before 31 March 2027', '2026-06-26'),
 ('6044', 'nzist_entity', 'transitional entity, not a polytechnic; follows NZIST''s disestablishment', null, 'https://www.education.govt.nz/news/regional-polytechnics-be-re-established-2026', 'Te Pūkenga operates as a transitional entity', '2025-07-14');

insert into pipeline.provider_transitions(provider_id, risk, note, recheck_days, source_url, source_quote, as_at, decided_by)
select i.provider_id, s.risk, s.note, s.recheck, s.url, s.quote, s.as_at, '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid  -- Platform Admin (decisions 20:42 and 20:52), verified in auth.users at build
  from _seed s join catalogue.provider_identifiers i on i.scheme = 'nzqa' and i.identifier = s.code
on conflict (provider_id) do nothing;

do $d$ declare v int; begin
  select count(*) into v from pipeline.provider_transitions;
  if v < 17 then raise exception 'expected 17 transition rows, found %', v; end if;
end $d$;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer1', 'transition_seed', 'NZ', jsonb_build_object('rows', 17, 'reason', 'Platform Admin 23 Oct 2026 20:42 and 20:52: NZ brief C1 closed; sources cited on each row'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select 'NZ provider transitions seeded: 17 rows with sources' ok;
-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 2 (Platform Admin 20:42; N5 at 20:52): when a provider's website moves
-- (the NZ polytechnic transition), its bound course pages and course-list sources move with it, keeping their identity proof and
-- evidence, and are read again first in line. Platform Admin only, logged. The same host is refused (nothing to move, nothing logged).
-- Replaces: nothing
-- Retires: nothing

create or replace function public.admin_provider_domain_moved(p_provider_id uuid, p_new_host text, p_reason text) returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare v_old text; v_new text := lower(btrim(coalesce(p_new_host, ''))); v_pages int := 0; v_lists int := 0; v_reason text := btrim(coalesce(p_reason, '')); v_rx text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if v_new !~ '^[a-z0-9.-]+\.[a-z]{2,}$' then raise exception 'give the new host only, for example www.example.ac.nz'; end if;
  select lower(regexp_replace(website, '^https?://([^/]+).*$', '\1')) into v_old from catalogue.providers where id = p_provider_id and website ~* '^https?://';
  if v_old is null then raise exception 'the provider has no website to move from'; end if;
  if v_old = v_new then raise exception 'the website already is %: nothing to move', v_old; end if;  -- N5: no-op refused, nothing logged
  v_rx := '^(https?://)' || regexp_replace(v_old, '\.', '\\.', 'g') || '(?=/|$)';
  update pipeline.coverage_course_pages g
     set url = regexp_replace(g.url, v_rx, '\1' || v_new, 'i'), next_read_at = now(), read_attempts = 0, leased_until = null
   where g.course_id in (select id from catalogue.courses where provider_id = p_provider_id)
     and g.status in ('bound', 'ambiguous') and g.url ~* v_rx;
  get diagnostics v_pages = row_count;
  update pipeline.provider_course_lists l
     set url = regexp_replace(l.url, v_rx, '\1' || v_new, 'i'), updated_at = now()
   where l.provider_id = p_provider_id and l.url ~* v_rx;
  get diagnostics v_lists = row_count;
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.providers set website = 'https://' || v_new, updated_at = now() where id = p_provider_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'provider_domain_moved', p_provider_id::text, jsonb_build_object('from', v_old, 'to', v_new, 'pages', v_pages, 'lists', v_lists, 'reason', v_reason), auth.uid());
  return jsonb_build_object('from', v_old, 'to', v_new, 'pages_moved', v_pages, 'lists_moved', v_lists);
end $f$;
revoke execute on function public.admin_provider_domain_moved(uuid, text, text) from public, anon;
grant execute on function public.admin_provider_domain_moved(uuid, text, text) to authenticated;
comment on function public.admin_provider_domain_moved(uuid, text, text) is 'CF-247 NZ brief item 2: moves a provider''s bound course pages and list sources to a new host (identity proof and evidence kept, pages read again first in line). Platform Admin, logged; the same host is refused.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_provider_domain_moved', 'Layer 1', 'Move a provider''s course pages to a new host after a website change (NZ transition)', 'active', '{}', '20261023025000')
on conflict (kind, name) do nothing;

select 'provider domain moved action' ok;
-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 4 (Platform Admin decisions C3 and C4 at 20:42; F2 at 20:56).
-- An international fee on an annual basis below the country's floor is quarantined: the row is kept with status unverified (an existing
-- status the website never returns) and a Layer 4
-- item carries the reason; it is not shown until a person decides. Never rejected, never dropped. The floor is a column per country on
-- pipeline.coverage_admission_countries (NZ 8,000 NZD, AU 8,000 AUD, CA 8,000 CAD), shown and changed on Settings › Pipeline settings.
-- The check runs where every fee is admitted (security.coverage_apply_course_v1), so the adapter path, the AI fee reader and the fee
-- schedule actions are all covered; the AI fee reader also records the outcome as review so its figures stay right.
-- C4: the 22 NZ rows below NZ$8,000 (all adapter-read, each the course's only fee row): 20 withdrawn to review, 2 kept live and flagged.
-- F2: NZ-only; the 109 AU and 66 CA rows below the floor stay live until read again (open item O6). Basis check at build: 0 active
-- international fees have a null basis; a null basis is not treated as annual by the floor.
-- Replaces: nothing (security.coverage_apply_course_v1, public.svc_fee_ai_record, public.admin_pipeline_settings_read and
--           public.admin_pipeline_settings_write edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 the floor per country ---------------------------------------------------------------------------------------------------------
alter table pipeline.coverage_admission_countries add column min_annual_international numeric check (min_annual_international > 0);
comment on column pipeline.coverage_admission_countries.min_annual_international is 'Floor for an international fee on an annual basis, in the country''s currency; below it the fee is quarantined to Layer 4 (NZ brief C3, 23 Oct 2026). Null: no floor.';
update pipeline.coverage_admission_countries a set min_annual_international = 8000, updated_at = now()
  from ref.countries k where k.id = a.country_id and k.iso_alpha2 in ('NZ', 'AU', 'CA');
insert into pipeline.admin_control_events(area, action, target, detail, actor) values
 ('settings', 'change', 'fee.floor', jsonb_build_object('NZ', 8000, 'AU', 8000, 'CA', 8000, 'reason', 'Platform Admin 23 Oct 2026 20:42: NZ brief C3, quarantine floors (migration 20261023026000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

create or replace function security.fee_below_floor_v1(p_course_id uuid, p_amount numeric, p_basis text) returns numeric
 language sql stable security definer set search_path to '' as $f$
  -- the floor when the fee is below it (annual or indicative-annual basis only; a null basis is never checked), else null
  select a.min_annual_international
    from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id
   where c.id = p_course_id and p_basis in ('annual', 'indicative_annual') and a.min_annual_international is not null and p_amount < a.min_annual_international
$f$;
revoke execute on function security.fee_below_floor_v1(uuid, numeric, text) from public, anon, authenticated;

-- 2 where every fee is admitted: below the floor, the row is kept as review and a Layer 4 item carries the reason --------------------
select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', '0f3beaac5ed5d4f2ded8a125f569cdfc', array[
  array[$o$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text;$o$,
        $n$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text; v_floor numeric;$n$],
  array[$o$    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    insert into catalogue.course_fees($o$,
        $n$    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    -- 23 Oct 2026 (NZ brief C3): below the country floor the fee is quarantined (status review, Layer 4 item), never admitted silently
    v_floor := security.fee_below_floor_v1(p_course_id, (p_payload->>'fee_amount')::numeric, nullif(btrim(p_payload->>'fee_basis'), ''));
    insert into catalogue.course_fees($n$],
  array[$o$            'active', now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = 'active', last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    v_fees := 1;$o$,
        $n$            case when v_floor is not null then 'unverified' else 'active' end, now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = case when v_floor is not null then 'unverified' else 'active' end, last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    if v_floor is not null then
      if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('page', p_url, 'source', 'fee floor', 'state', 'quarantined'), '{}'::jsonb, 'pending',
                'international fee below the country floor (' || v_cur || ' ' || to_char(v_floor, 'FM999,999,999') || ' a year): ' || v_cur || ' ' || to_char((p_payload->>'fee_amount')::numeric, 'FM999,999,999.00'),
                'CF-CHG-20260915-247 NZ brief C3');
      end if;
      v_fees := 0;
    else
      v_fees := 1;
    end if;$n$],
  array[$o$'english_applied', v_english, 'fees_applied', v_fees);$o$,
        $n$'english_applied', v_english, 'fees_applied', v_fees, 'fee_quarantined', v_floor is not null);$n$]]);

-- 3 the AI fee reader records a below-floor fee as review (the apply above keeps the row quarantined either way)
select pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '87f3a16a63d691b3195ee1ab857fe7c7', array[
  array[$o$        when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim and (v_median is null or c.yearly between v_median / v_ratio and v_median * v_ratio)$o$,
        $n$        when security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')) is not null then 'review'  -- 23 Oct 2026 (NZ brief C3): below the country floor
        when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim and (v_median is null or c.yearly between v_median / v_ratio and v_median * v_ratio)$n$],
  array[$o$        else 'review' end;
      if v_outcome = 'admitted' then$o$,
        $n$        else 'review' end;
      if v_outcome = 'review' and security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')) is not null then
        v_note := v_note || '; international fee below the country floor (' || v_cur || ' ' || to_char(security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')), 'FM999,999,999') || ' a year)';
      end if;
      if v_outcome = 'admitted' then$n$]]);

-- 4 Settings › Pipeline settings: the floor on the country row, changed with a reason (logged) -----------------------------------------
select pg_temp.edit_once('public.admin_pipeline_settings_read()', '6a192ef1a9dda96193847745663c3539', array[
  array[$o$jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref))$o$,
        $n$jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref, 'min_annual_international', c.min_annual_international))$n$]]);
select pg_temp.edit_once('public.admin_pipeline_settings_write(text,jsonb)', '35e8ff42fa934f0e9b46c9a5b0b5e543', array[
  array[$o$    else raise exception 'unknown setting %', p_key;$o$,
        $n$    -- 23 Oct 2026 (NZ brief C3): the international fee floor per country, in its currency; null switches the floor off
    when 'fee.floor' then
      if p_value->>'value' is not null and ((p_value->>'value')::numeric <= 0 or (p_value->>'value')::numeric > 200000) then raise exception 'between 1 and 200,000, or empty for no floor'; end if;
      update pipeline.coverage_admission_countries c
         set min_annual_international = nullif(p_value->>'value', '')::numeric, updated_at = now(),
             approved_ref = c.approved_ref || format('; Settings page, Platform Admin %s (fee floor: %s)', to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), coalesce(p_value->>'value', 'none'))
        from ref.countries k where k.id = c.country_id and k.iso_alpha2 = p_value->>'country';
      if not found then raise exception 'country % not found', p_value->>'country'; end if;
    else raise exception 'unknown setting %', p_key;$n$]]);

-- 5 C4: the 22 NZ rows below NZ$8,000 -----------------------------------------------------------------------------------------------
create temp table _floor on commit drop as
select f.id, f.course_id, p.canonical_name provider, c.canonical_title course, f.amount, f.evidence_id, f.currency_code
  from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id join catalogue.providers p on p.id = c.provider_id
  join ref.countries k on k.id = p.country_id
 where k.iso_alpha2 = 'NZ' and f.audience = 'international' and f.status = 'active' and f.basis = 'annual' and f.amount < 8000;
do $d$ declare v int; begin
  select count(*) into v from _floor; if v <> 22 then raise exception 'expected 22 NZ rows below the floor, found %', v; end if;
end $d$;
-- keep live, flagged (2): short English-language certificates, plausible
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', x.course_id, 'provider_current_tuition', x.evidence_id, jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('source', 'fee floor', 'state', 'flagged'), '{}'::jsonb, 'pending',
       'international fee below the country floor (NZD 8,000 a year); kept live and flagged: short English-language course (Platform Admin 23 Oct 2026 C4)', 'CF-CHG-20260915-247 NZ brief C4'
  from _floor x where x.provider in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
-- withdraw to review (20): off the website until decided; restored on approval
update catalogue.course_fees f set status = 'unverified', updated_at = now()
  from _floor x where f.id = x.id and x.provider not in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', x.course_id, 'provider_current_tuition', x.evidence_id, jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('amount', x.amount, 'status', 'unverified'), jsonb_build_object('source', 'fee floor', 'state', 'withdrawn'), '{}'::jsonb, 'pending',
       'withdrawn to review: international fee below the country floor (NZD 8,000 a year): NZD ' || to_char(x.amount, 'FM999,999,999.00') || ' (Platform Admin 23 Oct 2026 C4)', 'CF-CHG-20260915-247 NZ brief C4'
  from _floor x where x.provider not in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer4', 'fee_floor_pass', 'NZ', jsonb_build_object('withdrawn', 20, 'kept_flagged', 2, 'reason', 'Platform Admin 23 Oct 2026 20:42: NZ brief C4 (migration 20261023026000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
insert into search.refresh_requests(requested_by) select 'Fee floor pass (NZ)'
 where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'Fee floor pass (NZ)');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_below_floor_v1', 'Layer 2', 'The country floor an international annual fee falls below, else null (quarantine)', 'active', '{}', '20261023026000')
on conflict (kind, name) do nothing;

select 'fee floor per country; below-floor fees quarantined; C4 pass applied' ok;
do $d$ declare r jsonb; a jsonb; t record;
begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  r := security.transition_recheck_v1();
  begin perform public.admin_provider_domain_moved('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8', 'www.auckland.ac.nz', 'dry run'); a := '"no exception"'; exception when others then a := to_jsonb(sqlerrm); end;
  r := r || jsonb_build_object('apply', security.coverage_apply_course_v1('de70ae44-8eda-418a-a271-fd82bf5008e2', (select id from pipeline.sources limit 1), '87f8ead6-f126-4ee2-b078-66e8dd673ebf', 'https://x', 'h', jsonb_build_object('fee_amount', 3000, 'fee_year', 2026, 'fee_basis', 'annual', 'currency_code', 'NZD')));
  select status, amount into t from catalogue.course_fees where course_id = 'de70ae44-8eda-418a-a271-fd82bf5008e2' and amount = 3000;
  raise exception 'DRYRUN OK recheck %; noop %; apply % -> row % %; l4 %; transitions %; floors %; c4 quarantined rows %; settings read floor %',
    r->'rechecked', a, r->'apply', t.status, t.amount,
    (select escalation_reason from pipeline.layer4_review_items where entity_id = 'de70ae44-8eda-418a-a271-fd82bf5008e2' and layer2_state->>'state' = 'quarantined' limit 1),
    (select count(*) from pipeline.provider_transitions),
    (select jsonb_object_agg(k.iso_alpha2, c.min_annual_international) from pipeline.coverage_admission_countries c join ref.countries k on k.id = c.country_id),
    (select count(*) from catalogue.course_fees f where f.status = 'unverified' and f.amount < 8000),
    (public.admin_pipeline_settings_read()->'identity'->'NZ'->>'min_annual_international');
end $d$;
