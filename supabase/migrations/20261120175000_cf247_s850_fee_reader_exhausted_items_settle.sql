-- CF-247 s850 (Platform Admin 20 Nov 2026 15:11 AEDT, chat S1-Fees-Intakes): the Fee reader (AI) no longer shows as stuck behind an item that has used its three tries.
-- Found live (rolled-back probes, 20 Nov 2026 15:15 to 15:25 AEDT, branch cf247-s850-fees-probe): Platform health said "1 waiting and nothing finished since 20 Nov 01:41".
--   pipeline.fee_reader_queue held 6,290 done pages and one course-page item (940bdc00-…, created 17 Nov 08:52 UTC) in state queued with attempts = 3 and no error.
--   public.svc_fee_ai_next only hands out items with attempts < 3 (fixed: three tries), but the watchdog's pending count (pipeline.queue_watch fee_reader.pending_sql)
--   counted every queued item, so one item that can never be claimed kept the queue "stuck" with nothing to do. The AI route was open (not held, US$0 spent today).
--   How it got there: an item given back after its third lease (a lease that ran out, or a key-limit release) keeps state queued without passing through the
--   record step that turns a third failure into failed.
-- What changes: (a) the watchdog counts only items a worker can take (attempts < 3) as waiting, and items that used their three tries as exhausted; (b, c)
--   security.fee_reader_queue_settle_v1() turns any item that used its three tries (still queued, or a third lease that ran out) into failed, with the reason in words
--   and a read_failed finding, every minute (called by job fid-det-sweep, s852), so it can never hold the queue again; (d) the one item found is given one more full
--   try (attempts back to 0, first in line), because it never recorded an error, so the queue moves on now. No DDL touches pipeline.fee_reader_queue: the fee-reader
--   job writes it every minute, and the first dry run of a trigger on it waited on that lock (lock timeout).
-- Objects (no new public function, table or view): function security.fee_reader_queue_settle_v1(); data: pipeline.queue_watch row fee_reader (pending_sql, exhausted_sql); the one queue item.
-- G1: no new job (the settle is called by s851's job fid-det-sweep). G2: no new operational value (three tries is the claim step's fixed value, marked fixed).
-- G3: no consumer API object; the consumer API check is read before and after (75 functions, 48 relations, no drift).
-- Parity: live head 20261120143000 (2,219 rows) read 20 Nov 2026 15:16 AEDT; lane block s850 to s859 (migrations 20261120153000 to 155900). Renumbered twice
--   (16:05 and 17:20 AEDT) as other lanes merged above that slot (S1-AER 20261120163000, S1-Structure 20261120163500 and 20261120172000, S1-ELR 20261120170000):
--   now 20261120175000 and 20261120175100, above the newest migration on main (repo-first parity, merge check).
-- Replaces: the fee_reader watchdog's pending count of every queued item.
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: set the two watchdog queries back (the old text is in this file's comment block below).
--   old pending_sql: select count(*) from pipeline.fee_reader_queue q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

-- (b) and (c) items that used their three tries and are still queued, or whose third lease ran out, are settled to failed with the reason kept
--   (no trigger on pipeline.fee_reader_queue: the fee-reader job writes that table every minute, and a trigger would need a table lock it holds)
create or replace function security.fee_reader_queue_settle_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare n int := 0; r record;
begin
  for r in
    update pipeline.fee_reader_queue q set state = 'failed', leased_until = null, finished_at = now(),
           error = left(coalesce(nullif(q.error, ''), case when q.state = 'leased' then 'the third lease ran out with no answer' else 'no answer recorded' end)
                        || ' (gave up after three tries; s850)', 500)
     where q.attempts >= 3  -- fixed: three tries, as public.svc_fee_ai_next
       and (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))
    returning q.provider_id, q.fact_source_id, q.course_id
  loop
    n := n + 1;
    perform security.fee_reader_finding_v1(r.provider_id, r.fact_source_id, 'read_failed', r.fact_source_id::text,
                                           jsonb_build_object('error', 'gave up after three tries', 'course_id', r.course_id));
  end loop;
  return jsonb_build_object('settled', n);
end $function$;
comment on function security.fee_reader_queue_settle_v1() is 'CF-247 s850: settles AI fee reader items that used their three tries (still queued, or a third lease that ran out) to failed, with a read_failed finding. Called every minute by job fid-det-sweep (s852).';

-- (a) the watchdog counts only what a worker can take
update pipeline.queue_watch
   set pending_sql = 'select count(*) from pipeline.fee_reader_queue q where q.attempts < 3 and (q.state = ''queued'' or (q.state = ''leased'' and q.leased_until < now()))',
       exhausted_sql = 'select count(*) from pipeline.fee_reader_queue q where q.state = ''failed'' or (q.attempts >= 3 and q.state in (''queued'', ''leased''))'
 where key = 'fee_reader';

-- (d) the one item found: never recorded an error, so it gets one more full try, first in line
update pipeline.fee_reader_queue
   set attempts = 0, leased_until = null, priority = greatest(priority, 1),
       error = 'given one more try after three leases with no answer (s850, 20 Nov 2026)'
 where state = 'queued' and attempts >= 3 and error is null;
update pipeline.fee_reader_queue set state = 'failed', finished_at = now(), leased_until = null,
       error = left(coalesce(error, '') || ' (gave up after three tries; s850)', 500)
 where state = 'queued' and attempts >= 3;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.fee_reader_queue_settle_v1', 'Layer 2', 'Fees', 'Settles AI fee reader items that used their three tries', 'active', '{}', '20261120175000')
on conflict do nothing;

-- post-checks
do $c$
declare v_n bigint; v_api jsonb := security.consumer_api_check_v1(); v_t timestamptz; v_ms numeric;
begin
  if exists (select 1 from pipeline.fee_reader_queue where state = 'queued' and attempts >= 3) then
    raise exception 'post-check: an item that used its three tries is still queued';
  end if;
  if exists (select 1 from pipeline.queue_watch where key = 'fee_reader') then
    v_t := clock_timestamp();
    execute (select pending_sql from pipeline.queue_watch where key = 'fee_reader') into v_n;
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    if v_ms > 300 then raise exception 'post-check: the fee reader waiting count took % ms (limit 300)', round(v_ms); end if;
    if v_n <> (select count(*) from pipeline.fee_reader_queue q where q.attempts < 3 and (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))) then
      raise exception 'post-check: the waiting count does not match the claimable items';
    end if;
  end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
