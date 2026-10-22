-- CF-247 (22 Oct 2026). Platform Admin 15:57 (Bug/Fix, University of Otago): "this is right one to show fees for international, how to change
-- the existing non-producing URL in UI and replace them with correct them. can we add manually in UI by ourselves, how will it start admitting
-- data to the courses field?"
-- Found: Otago's right pages already give fees (business school 32 admitted, health sciences 64, humanities 40, sciences 39), but every page
-- showed the older page reader's status ("no_values"), and seven pages that give no fee rows (the old /international/fees/ addresses and the
-- overview page) are read by the AI every time Read again is pressed.
-- Change, all on Enrich fields › Fee reader (AI), a provider's fee pages (Pipeline Operator and above, each with a reason, logged):
--   page_add    a fee page entered by hand; it is fetched by the provider-facts job (about 10 minutes, about 1 Firecrawl credit), then the
--               fee reader reads it (next 10-minute run) and admits or sends to Layer 4 as for any page. A page read before is fetched again.
--   page_stop   a page that gives no fees is no longer read (status rejected; a waiting read is cancelled); fees it gave stay.
--   page_resume the page is read again from its stored copy (or fetched when it has none).
--   Read again leaves stopped pages out. Each page now says how many fees it gave and how many were admitted.
-- Replaces: public.admin_fee_reader (page actions, page figures). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('public.admin_fee_reader(text,jsonb)', '5a99e8d420aac5e1428bf1c3995d5c32', array[
  [$o$v_reason text := btrim(coalesce(p_args->>'reason', '')); v_n int;$o$,
   $n$v_reason text := btrim(coalesce(p_args->>'reason', '')); v_n int; v_id uuid;$n$],
  [$o$'found_via', f.found_via, 'read_at', f.read_at,$o$,
   $n$'found_via', f.found_via, 'read_at', f.read_at, 'stopped', f.status = 'rejected',
                  -- 22 Oct 2026: what the AI fee reader got from the page (the status above is the page fetch)
                  'fees', (select count(*) from pipeline.fee_reader_rows r where r.fact_source_id = f.id and r.outcome <> 'replaced'),
                  'admitted', (select count(*) from pipeline.fee_reader_rows r where r.fact_source_id = f.id and r.outcome = 'admitted'),
                  'to_review', (select count(*) from pipeline.fee_reader_rows r where r.fact_source_id = f.id and r.outcome = 'review'),
                  'already_held', (select count(*) from pipeline.fee_reader_rows r where r.fact_source_id = f.id and r.outcome = 'same'),$n$],
  [$o$where q.provider_id = v_pid order by q.fact_source_id, q.created_at desc);$o$,
   $n$where q.provider_id = v_pid
                    and not exists (select 1 from pipeline.provider_fact_sources sf where sf.id = q.fact_source_id and sf.status = 'rejected')  -- 22 Oct 2026: stopped pages stay stopped
                  order by q.fact_source_id, q.created_at desc);$n$],
  [$o$  elsif p_action = 'notes_set' then$o$,
   $n$  elsif p_action in ('page_add', 'page_stop', 'page_resume') then
    -- 22 Oct 2026 (Platform Admin 15:57): add the right fee page by hand, stop one that gives no fees, or start it again
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if p_action = 'page_add' then
      if btrim(coalesce(p_args->>'url', '')) !~ '^https?://[^ ]+$' or length(btrim(p_args->>'url')) not between 12 and 500 then
        raise exception 'give the full page address (http or https)';
      end if;
      insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
      values (v_pid, 'fee_schedule', btrim(p_args->>'url'), null, 9, 'manual', 'found')
      on conflict (provider_id, kind, url) do update set status = 'found', attempts = 0, rank = 9, found_via = 'manual', read_at = null, updated_at = now()
      returning id into v_id;
    elsif p_action = 'page_stop' then
      update pipeline.provider_fact_sources set status = 'rejected', updated_at = now()
       where id = nullif(p_args->>'page', '')::uuid and provider_id = v_pid and kind = 'fee_schedule' returning id into v_id;
      if v_id is null then raise exception 'unknown fee page'; end if;
      update pipeline.fee_reader_queue set state = 'failed', error = 'stopped by a person', leased_until = null where fact_source_id = v_id and state = 'queued';
    else
      update pipeline.provider_fact_sources f set status = case when f.evidence_id is not null and f.content_hash is not null then 'read' else 'found' end,
             attempts = 0, read_at = case when f.evidence_id is not null and f.content_hash is not null then f.read_at end, updated_at = now()
       where f.id = nullif(p_args->>'page', '')::uuid and f.provider_id = v_pid and f.kind = 'fee_schedule' and f.status = 'rejected' returning f.id into v_id;
      if v_id is null then raise exception 'unknown or not stopped fee page'; end if;
      update pipeline.fee_reader_queue set state = 'queued', attempts = 0, error = null, leased_until = null
       where id = (select q.id from pipeline.fee_reader_queue q where q.fact_source_id = v_id order by q.created_at desc limit 1);
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('fees', p_action, v_pid::text, jsonb_build_object('page', v_id, 'url', p_args->>'url', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'page', v_id);
  elsif p_action = 'notes_set' then$n$]
]);
