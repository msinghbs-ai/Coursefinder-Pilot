-- CF-247 (Decision 205, continued): fee schedules become proposals a Platform Admin approves.
-- Found on 1 Oct 2026: universities' fee pages usually link the real schedule as a PDF (ACU's 2027 schedule lists
-- about 150 courses, each with its CRICOS code and annual fee), so the worker now follows those links:
--   * pipeline.provider_fact_sources.linked_from: a document found through a link on another source;
--   * public.svc_provider_facts_read_record_v2(...): as before, plus p_links ([{url, year}]) from a fee page; each link
--     on the provider's own site becomes a fee_schedule source to read (newest year first).
-- Reading English policies and academic calendars waits until a qualified extractor exists (they are found, not read),
-- so Firecrawl credit goes to fee schedules first; fee schedule searches are also sent first.
-- The proposal: each current fee row is matched to the provider's active course with the same CRICOS code. On approval
-- (Platform Admin, per document) a fee is written only where the course has no current provider tuition, no pending
-- Layer 4 tuition review, one amount for the basis, and the basis is annual (or a total when no annual is given).
-- Courses whose current fee differs are listed, not changed. Nothing is written without the approval.

alter table pipeline.provider_fact_sources add column if not exists linked_from uuid references pipeline.provider_fact_sources(id);
alter table pipeline.provider_fact_sources add column if not exists decision text check (decision in ('approved','rejected'));
alter table pipeline.provider_fact_sources add column if not exists decided_by uuid;
alter table pipeline.provider_fact_sources add column if not exists decided_at timestamptz;
alter table pipeline.provider_fact_sources add column if not exists decision_note text;
alter table pipeline.provider_fact_sources add column if not exists apply_summary jsonb;
create index if not exists provider_fee_rows_source_idx on pipeline.provider_fee_rows(source_id) where current;

-- guards: the three worker functions below are replaced from the definitions in 20261001178000
do $g$
declare v text;
begin
  select md5(prosrc) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_provider_facts_read_next';
  if v is distinct from 'cf3018a6b0acf8e3ca4377b230240de7' then raise exception 'svc_provider_facts_read_next changed (md5 %)', v; end if;
  select md5(prosrc) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'svc_provider_facts_search_next';
  if v is distinct from 'd686812054e7e8faeb2098e62f4f833c' then raise exception 'svc_provider_facts_search_next changed (md5 %)', v; end if;
end $g$;

create or replace function public.svc_provider_facts_search_next(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, r.search_domain
      from pipeline.provider_fact_search s join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
     where s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3)
     order by (s.kind <> 'fee_schedule'), s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $fn$;
revoke all on function public.svc_provider_facts_search_next(int) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_search_next(int) to service_role;

create or replace function public.svc_provider_facts_read_next(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where f.kind = 'fee_schedule'
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < 3
     order by (f.linked_from is null), f.rank, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $fn$;
revoke all on function public.svc_provider_facts_read_next(int) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_read_next(int) to service_role;

-- v2 = v1 plus linked documents. v1 stays for a worker that has not been redeployed.
create or replace function public.svc_provider_facts_read_record_v2(p_id uuid, p_status text, p_http int, p_storage_path text, p_sha256 text,
                                                                    p_mime text, p_rows jsonb, p_summary jsonb, p_links jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare f pipeline.provider_fact_sources%rowtype; v_dom text; v jsonb; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v := public.svc_provider_facts_read_record(p_id, p_status, p_http, p_storage_path, p_sha256, p_mime, p_rows, p_summary);
  select * into f from pipeline.provider_fact_sources where id = p_id;
  if p_status = 'read' and f.kind = 'fee_schedule' and f.linked_from is null and jsonb_typeof(p_links) = 'array' then
    select r.search_domain into v_dom from pipeline.course_link_recipes r where r.provider_id = f.provider_id;
    insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, linked_from)
    select f.provider_id, 'fee_schedule', left(x.url, 2000), 'Linked from ' || left(f.url, 200), x.rk, f.id
      from (select e->>'url' url, row_number() over (order by coalesce(nullif(e->>'year', '')::int, 0) desc) rk
              from jsonb_array_elements(p_links) e
             where (e->>'url') ~* ('^https?://([a-z0-9-]+\.)*' || regexp_replace(coalesce(v_dom, '#'), '([.-])', '\\\1', 'g') || '(/|$)')) x
     where x.rk <= 4
    on conflict (provider_id, kind, url) do nothing;
    get diagnostics v_n = row_count;
  end if;
  return v || jsonb_build_object('linked', v_n);
end $fn$;
revoke all on function public.svc_provider_facts_read_record_v2(uuid, text, int, text, text, text, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_read_record_v2(uuid, text, int, text, text, text, jsonb, jsonb, jsonb) to service_role;

-- One row per current fee row with its matched course and what approval would do.
create or replace function security.provider_fee_proposal_rows(p_source_id uuid)
returns table(row_id uuid, course_code text, course_id uuid, course_title text, amount numeric, currency_code text, basis text, fee_year int,
              current_amount numeric, current_basis text, outcome text)
language sql stable security definer set search_path = '' as $fn$
  with f as (select * from pipeline.provider_fact_sources where id = p_source_id),
  r as (
    select fr.*, c.id cid, c.canonical_title,
           min(fr.amount) over (partition by fr.course_code, fr.basis) amin, max(fr.amount) over (partition by fr.course_code, fr.basis) amax,
           bool_or(fr.basis = 'annual') over (partition by fr.course_code) has_annual
      from pipeline.provider_fee_rows fr join f on f.id = fr.source_id
      left join catalogue.courses c on c.provider_id = fr.provider_id and upper(btrim(c.course_code)) = fr.course_code and c.lifecycle_status = 'active'
     where fr.current)
  select r.id, r.course_code, r.cid, r.canonical_title, r.amount, r.currency_code, r.basis, r.fee_year, cur.amount, cur.basis,
         case when r.cid is null then 'no_course'
              when r.basis not in ('annual','total_indicative') then 'basis_not_used'
              when r.basis = 'total_indicative' and r.has_annual then 'annual_used'
              when r.amin <> r.amax then 'several_amounts'
              when cur.amount is not null and cur.amount = r.amount then 'same'
              when cur.amount is not null then 'differs'
              when exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = r.cid
                             and l.field_code = 'provider_current_tuition_validation' and l.status = 'pending') then 'in_review'
              else 'new' end
    from r
    left join lateral (select x.amount, x.basis from catalogue.course_fees x where x.course_id = r.cid and x.fee_type = 'provider_current_tuition'
                         and x.status = 'active' order by x.updated_at desc limit 1) cur on true
$fn$;
revoke all on function security.provider_fee_proposal_rows(uuid) from public, anon, authenticated;

-- Read: documents with fee rows (newest first) and, for one document, its rows. Pipeline operator and above.
create or replace function public.admin_provider_fee_schedules_read(p_source_id uuid default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'pipeline operator role required' using errcode = '42501'; end if;
  if p_source_id is not null then
    return jsonb_build_object('can_decide', v_rank >= 6, 'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.outcome, x.course_code)
             from security.provider_fee_proposal_rows(p_source_id) x), '[]'::jsonb));
  end if;
  return jsonb_build_object(
    'can_decide', v_rank >= 6,
    'totals', (select jsonb_build_object(
        'documents_found', count(*) filter (where f.kind = 'fee_schedule'),
        'documents_read', count(*) filter (where f.kind = 'fee_schedule' and f.status in ('parsed','no_values')),
        'with_fee_rows', count(*) filter (where f.status = 'parsed'),
        'awaiting_decision', count(*) filter (where f.status = 'parsed' and f.decision is null),
        'providers_searched', (select count(distinct s.provider_id) from pipeline.provider_fact_search s where s.kind = 'fee_schedule' and s.state <> 'queued'),
        'providers_queued', (select count(*) from pipeline.provider_fact_search s where s.kind = 'fee_schedule' and s.state = 'queued'))
        from pipeline.provider_fact_sources f),
    'documents', coalesce((select jsonb_agg(d order by d->>'decided_at' desc nulls first, (d->>'new')::int desc) from (
        select jsonb_build_object('id', f.id, 'provider_id', f.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'url', f.url, 'fee_year', f.parse_summary->>'fee_year',
               'read_at', f.read_at, 'decision', f.decision, 'decided_at', f.decided_at, 'apply_summary', f.apply_summary,
               'rows', (select count(*) from security.provider_fee_proposal_rows(f.id)),
               'new', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'new'),
               'same', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'same'),
               'differs', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'differs'),
               'no_course', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'no_course')) d
          from pipeline.provider_fact_sources f join catalogue.providers p on p.id = f.provider_id
         where f.status = 'parsed' order by f.read_at desc limit greatest(1, least(coalesce(p_limit, 50), 200))) q), '[]'::jsonb));
end $fn$;
revoke all on function public.admin_provider_fee_schedules_read(uuid, int) from public, anon;
grant execute on function public.admin_provider_fee_schedules_read(uuid, int) to authenticated;

-- Decide: Platform Admin approves or rejects one document. Approval writes the "new" rows only.
create or replace function public.admin_provider_fee_schedule_decide(p_source_id uuid, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare f pipeline.provider_fact_sources%rowtype; x record; v_src uuid; v_n int := 0; v_err int := 0; v_sum jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('approve','reject') then raise exception 'action must be approve or reject'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id for update;
  if f.id is null or f.kind <> 'fee_schedule' or f.status <> 'parsed' then raise exception 'not a parsed fee schedule'; end if;
  if f.decision is not null then raise exception 'already decided (%)', f.decision; end if;
  if p_action = 'reject' then
    update pipeline.provider_fact_sources set decision = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 500), updated_at = now() where id = p_source_id;
    return jsonb_build_object('decision', 'rejected');
  end if;
  if f.evidence_id is null or f.content_hash is null then raise exception 'the document has no stored evidence; read it again first'; end if;
  v_src := security.coverage_sweep_source(f.provider_id);
  -- what the document proposed, counted before anything is written
  select jsonb_object_agg(o, n) into v_sum from (select outcome o, count(*) n from security.provider_fee_proposal_rows(p_source_id) group by 1) s;
  for x in select * from security.provider_fee_proposal_rows(p_source_id) where outcome = 'new' loop
    begin
      perform security.coverage_apply_course_v1(x.course_id, v_src, f.evidence_id, f.url, f.content_hash,
        jsonb_build_object('fee_amount', x.amount, 'currency_code', x.currency_code, 'fee_year', x.fee_year, 'fee_basis', x.basis,
                           'fee_notes', 'From the provider''s international fee schedule; approved by a Platform Admin'));
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  v_sum := coalesce(v_sum, '{}'::jsonb) || jsonb_build_object('written', v_n, 'refused', v_err);
  update pipeline.provider_fact_sources set decision = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 500),
         apply_summary = v_sum, updated_at = now() where id = p_source_id;
  return jsonb_build_object('decision', 'approved') || v_sum;
end $fn$;
revoke all on function public.admin_provider_fee_schedule_decide(uuid, text, text) from public, anon;
grant execute on function public.admin_provider_fee_schedule_decide(uuid, text, text) to authenticated;

-- Fee pages already read before links were followed are read again once (1 credit each).
update pipeline.provider_fact_sources set status = 'found', attempts = 0, updated_at = now()
 where kind = 'fee_schedule' and status = 'no_values' and linked_from is null;
