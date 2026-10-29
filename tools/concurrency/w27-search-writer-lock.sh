#!/usr/bin/env bash
# CF-247 decision W27: local reproduction of the 29 Oct 2026 search.course_documents deadlock and proof of the writer-lock correction.
# Needs a disposable local PostgreSQL (never a shared or live database). Usage: PGHOST=<socket dir> PGPORT=<port> tools/concurrency/w27-search-writer-lock.sh
# Models the real writers: the scoped refresh (stage then UPDATE ... FROM in plan order), the full rebuild (ascending upsert over every
# document, slowed to widen the window) and the scheduled job. 'before' = live definitions as at 29 Oct 2026; 'after' = W27 edits verbatim.
set -u
# guard: a disposable local server only (a Unix socket directory or localhost); never a shared or live database
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refused: PGHOST must be a local socket directory or localhost"; exit 2;; esac
export PGOPTIONS="-c client_min_messages=warning"
PSQL="psql -U postgres -v ON_ERROR_STOP=1 -Atq"
setup() { # $1 = before|after
$PSQL <<SQL
drop schema if exists search cascade; drop schema if exists security cascade;
create schema search; create schema security;
create table search.course_documents(course_id int primary key, v int not null default 0, generated_at timestamptz);
insert into search.course_documents(course_id) select g from generate_series(1,100) g;
create table search.refresh_requests(id bigserial primary key, processed_at timestamptz);
create or replace function search.refresh_course_enrichment_core_scoped_v1(p_course_ids int[], p_apply boolean) returns jsonb language plpgsql as \$f\$
begin
  drop table if exists pg_temp.stage;
  create temp table stage on commit drop as select d.course_id, d.v + 1 nv from search.course_documents d where d.course_id = any(p_course_ids);
  if p_apply then
    -- plan order: the input order (as an unordered join would give it), one row at a time so a competing writer can interleave
    perform pg_sleep(0.02) from unnest(p_course_ids) u(id);
    update search.course_documents d set v = s.nv, generated_at = now() from stage s where d.course_id = s.course_id;
  end if;
  return '{}'::jsonb;
end \$f\$;
create or replace function search.refresh_course_enrichment_scoped_v1(p_course_ids int[], p_apply boolean default false) returns jsonb language plpgsql as \$f\$
declare v_result jsonb;
begin
$( [ "$1" = after ] && cat <<'AFTER'
  if p_apply then
    perform pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer'));  -- fixed: the one writer lock for search.course_documents (W27)
    perform 1 from search.course_documents d where d.course_id = any(p_course_ids) order by d.course_id for update;
  end if;
AFTER
)
  v_result := search.refresh_course_enrichment_core_scoped_v1(p_course_ids, p_apply);
  return v_result;
end \$f\$;
create or replace function search.refresh_course_documents_v3(p_apply boolean default false) returns jsonb language plpgsql as \$f\$
declare i int;
begin
$( [ "$1" = after ] && cat <<'AFTER'
  if p_apply then
    perform pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer'));  -- fixed: the one writer lock for search.course_documents (W27)
  end if;
AFTER
)
  if p_apply then
    for i in 1..100 loop  -- the full upsert visits every document in ascending order (slowed: the live run took 76 s)
      insert into search.course_documents(course_id, v) values (i, 0) on conflict (course_id) do update set v = search.course_documents.v + 1, generated_at = now();
      perform pg_sleep(0.02);
    end loop;
  end if;
  return '{"base":{}}'::jsonb;
end \$f\$;
create or replace function security.search_refresh_requested_v1() returns jsonb language plpgsql as \$f\$
declare v_ids bigint[]; r jsonb;
begin
  select array_agg(id) into v_ids from search.refresh_requests where processed_at is null;
  if v_ids is null then return jsonb_build_object('pending',0); end if;
$( [ "$1" = after ] && cat <<'AFTER'
  if not pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
    return jsonb_build_object('pending', cardinality(v_ids), 'held', 'another search-document writer is running; the requests wait for the next run');
  end if;
AFTER
)
  r := search.refresh_course_documents_v3(true);
  update search.refresh_requests set processed_at = now() where id = any(v_ids);
  return jsonb_build_object('processed', cardinality(v_ids));
end \$f\$;
SQL
}
run() { # $1 label, then two SQL scripts run concurrently (second starts 0.3 s later)
  local a b; a=$(mktemp); b=$(mktemp)
  ($PSQL -c "$2" >"$a" 2>&1; echo "exit=$?" >>"$a") & local pa=$!
  sleep 0.3
  ($PSQL -c "$3" >"$b" 2>&1; echo "exit=$?" >>"$b") & local pb=$!
  wait $pa $pb
  local dl; dl=$(cat "$a" "$b" | grep -c 'deadlock detected')
  echo "$1 | A: $(tr '\n' ' ' <"$a" | cut -c1-150) | B: $(tr '\n' ' ' <"$b" | cut -c1-150) | deadlocks=$dl"
  rm -f "$a" "$b"
}
# S1: a paste-like transaction refreshing a high course set, then a low one, while the scheduled full rebuild runs
PASTE="begin; select search.refresh_course_enrichment_scoped_v1(array(select generate_series(61,80)), true); select pg_sleep(1.5); select search.refresh_course_enrichment_scoped_v1(array(select generate_series(1,20)), true); commit;"
JOB="insert into search.refresh_requests default values; select security.search_refresh_requested_v1();"
FULL="select search.refresh_course_documents_v3(true);"
# S2: two scoped writers, overlapping course sets in opposing orders
SC1="begin; select search.refresh_course_enrichment_scoped_v1(array(select generate_series(1,40)), true); select pg_sleep(1); select search.refresh_course_enrichment_scoped_v1(array(select generate_series(41,80)), true); commit;"
SC2="begin; select search.refresh_course_enrichment_scoped_v1(array(select generate_series(80,41,-1)), true); select pg_sleep(1); select search.refresh_course_enrichment_scoped_v1(array(select generate_series(40,1,-1)), true); commit;"
for v in before after; do
  setup $v
  run "$v S1 paste vs scheduled job" "$PASTE" "$JOB"
  setup $v
  run "$v S1b paste vs full rebuild (other callers)" "$PASTE" "$FULL"
  setup $v
  run "$v S2 scoped vs scoped, opposing orders" "$SC1" "$SC2"
done
