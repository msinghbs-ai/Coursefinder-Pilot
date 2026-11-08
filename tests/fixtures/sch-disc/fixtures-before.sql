-- The defects on the live definitions (8 Nov 2026), each read only or rolled back. Every case prints a NOTICE "before ..." and raises if the live behaviour is not what
-- this change replaces.
create or replace function pg_temp.pst(p uuid) returns text language sql as $$ select state from security.scholarship_coverage_items_v1(array[p]) where item_key = 'provider' $$;
do $$
begin
  -- D1: four different facts read as one word
  if pg_temp.pst('20000000-0000-0000-0000-000000000001') is distinct from 'source_not_discovered' then raise exception 'before D1: expected Alpha (searched, nothing found) to read source_not_discovered, got %', pg_temp.pst('20000000-0000-0000-0000-000000000001'); end if;
  if pg_temp.pst('20000000-0000-0000-0000-000000000011') is distinct from 'source_not_discovered' then raise exception 'before D1: expected Lambda (provider type not admitted) to read source_not_discovered'; end if;
  if pg_temp.pst('20000000-0000-0000-0000-000000000004') is distinct from 'source_not_discovered' then raise exception 'before D1: expected Delta (no website) to read source_not_discovered'; end if;
  if pg_temp.pst('20000000-0000-0000-0000-000000000007') is distinct from 'source_not_discovered' then raise exception 'before D1: expected Eta (discovery not eligible) to read source_not_discovered'; end if;
  raise notice 'before D1: searched-and-empty, type not admitted, no website and not-eligible providers all read source_not_discovered';
end $$;
-- D4: an unchanged complete catalogue is read again in 7 days
savepoint d4;
do $$
declare v_days numeric;
begin
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, '[{"name": "Alpha Award"}, {"name": "Beta Award"}]'::jsonb, null, '{"state": "complete", "pages_read": 2, "total_stated": 2}'::jsonb);
  perform public.svc_scholarship_listing_record_v2(9, 'read', 200, '[{"name": "Alpha Award"}, {"name": "Beta Award"}]'::jsonb, null, '{"state": "complete", "pages_read": 2, "total_stated": 2}'::jsonb);
  select extract(epoch from (next_read_at - now())) / 86400 into v_days from pipeline.scholarship_listing_pages where id = 9;
  if round(v_days) <> 7 then raise exception 'before D4: expected an unchanged catalogue to wait 7 days, got %', v_days; end if;
  raise notice 'before D4: an unchanged complete catalogue is read again in % days', round(v_days);
end $$;
rollback to savepoint d4;
-- D2/D3/D5: no way for a suggested listing, nothing to park a transient failure (the objects do not exist yet)
do $$
begin
  if to_regprocedure('security.scholarship_listing_accept_v1()') is not null or to_regprocedure('security.scholarship_transient_recover_v1()') is not null
     or to_regclass('pipeline.scholarship_read_retry_cycles') is not null then raise exception 'before D2/D5: the recovery objects already exist'; end if;
  if (select count(*) from pipeline.scholarship_listing_pages where source = 'suggested' and not active) <> 8 then raise exception 'before D2: expected 8 suggested listings waiting'; end if;
  if (select count(*) from pipeline.scholarship_page_candidates where read_status = 'scrape_failed' and attempts >= 3) <> 9 then raise exception 'before D5: expected 9 failed candidates at the cap, got %', (select count(*) from pipeline.scholarship_page_candidates where read_status = 'scrape_failed' and attempts >= 3); end if;
  raise notice 'before D2/D5: 8 suggested listings wait with no way to be accepted; 9 failed candidate pages sit at the cap with no way back';
end $$;
