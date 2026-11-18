-- CF-247 RM1C / RM1H / RM1I / RM1D page facts: rendered read of the Home Affairs pages and the JSA Table 1 headings (S2-Build; Platform Admin
-- 18 Nov 2026 17:55: "Authorised to use Firecrawl (/v1/scrape with JS rendering, onlyMainContent: true) on the official Home Affairs student
-- visa pages ... Update the JSA workbook parser ... to map Table 1 from its actual column headings").
--
-- What was read live (18 Nov 2026 17:00 AEDT, second load, run a868487a): the Home Affairs pages' static HTML (1.46 MB and 1.30 MB) holds only
-- 3,595 and 1,656 characters of visible text: the content is built in the browser. The JSA OSCA workbook was found and stored, but no sheet's
-- headings matched the reader.
--
-- What it changes
--   * destination.page_facts.read_mode (static or rendered, default static; a Platform Admin changes it per fact). The Home Affairs facts are
--     set to rendered. layer1-destination-geo-loader v1.3.0 reads a rendered page through Firecrawl /v1/scrape (JS rendering, onlyMainContent):
--     the database decides the spend first (svc_fc_spend, purpose destination_page_facts: the "other" daily share, the monthly plan limit and the
--     cost breakers; scheduled work stays held by them), every call is logged (svc_fc_call_log, use case destination_page_facts) and the
--     rendered HTML is stored as the evidence. Two pages a load, one credit each.
--   * public.svc_destination_page_facts_v1 hands each fact's read mode to the loader (md5-guarded edit).
--   * security.destination_page_facts_load_v1 keeps the earnings period the workbook heading states (weekly, annual or hourly) instead of
--     always weekly (md5-guarded edit).
--   * The JSA reader (supabase/functions/_shared/cf247-page-facts.js) reads a heading with the cell above it and recognises a measure by what
--     it is (a median or average of earnings, income or pay; a count of employed persons or workers; never a share, rate, change, age or hours);
--     a sheet that does not load reports the rows around its code heading.
--   * Workflow destination-run-now (workflow_dispatch) asks for Run now of a destination job through the Management API and reads the result
--     back, so a load can be run again without a migration.
-- Fair Work stays restricted and QILT untouched. Nothing is dropped or deleted. G3 untouched.
-- Replaces: the static-only page read of mode facts; the fixed weekly earnings period of the JSA load.
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. read mode
alter table destination.page_facts add column if not exists read_mode text not null default 'static';
do $c$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.page_facts'::regclass and conname = 'page_facts_read_mode_check') then
    alter table destination.page_facts add constraint page_facts_read_mode_check check (read_mode in ('static', 'rendered'));
  end if;
end $c$;
comment on column destination.page_facts.read_mode is 'static: the page is read directly; rendered: through Firecrawl /v1/scrape with JS rendering and onlyMainContent (pages whose content the browser builds). Set by a Platform Admin.';
update destination.page_facts set read_mode = 'rendered', updated_at = now(),
       note = coalesce(note || '; ', '') || 'read rendered from 18 Nov 2026 (20261118220000): the static page holds almost no visible text'
 where status = 'active' and page_url like 'https://immi.homeaffairs.gov.au/%' and read_mode <> 'rendered';

-- 2. the loader is told each fact's read mode
select pg_temp.cf_edit('public.svc_destination_page_facts_v1()'::regprocedure, 'eaa186dda4d71541842a02f431667ded',
  $o$'min', f.min_value, 'max', f.max_value, 'anchor', f.anchor)$o$,
  $n$'min', f.min_value, 'max', f.max_value, 'anchor', f.anchor, 'read_mode', f.read_mode)$n$,
  $m$'read_mode', f.read_mode$m$);

-- 3. the earnings period the workbook states
select pg_temp.cf_edit('security.destination_page_facts_load_v1(jsonb)'::regprocedure, 'fefa5c5a27511fe2ca015e9f3c3992d8',
  $o$'AUD', 'weekly',$o$,
  $n$'AUD', coalesce(nullif(j->'header'->>'earnings_period', ''), 'weekly'),  -- 20261118220000: the period the workbook heading states$n$,
  '20261118220000: the period the workbook heading states');

-- 4. post-checks
do $$
begin
  if (select count(*) from destination.page_facts where status = 'active' and page_url like 'https://immi.homeaffairs.gov.au/%' and read_mode = 'rendered') < 1 then
    raise exception 'post-check: the Home Affairs facts are read rendered';
  end if;
  if exists (select 1 from jsonb_array_elements(public.svc_destination_page_facts_v1()->'facts') f where not (f ? 'read_mode')) then raise exception 'post-check: read mode handed over'; end if;
  if exists (select 1 from jsonb_array_elements(public.svc_destination_page_facts_v1()->'facts') f where f->>'page_url' like '%fairwork.gov.au%') then raise exception 'post-check: Fair Work stays restricted'; end if;
  if exists (select 1 from destination.editions where source_owner ilike '%QILT%' or edition_label ilike '%QILT%') then raise exception 'post-check: QILT stays gated'; end if;
end $$;
