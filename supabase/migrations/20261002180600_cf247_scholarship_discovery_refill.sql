-- CF-247 (Decision 214, 2 Oct 2026). Platform Admin, 07:31: "Schedule them asap" (the next scholarship discovery
-- providers) and the UI must show what is running at each layer instead of a person asking for the next round.
-- Found: scholarship discovery had nothing queued since 29 Sep 2026 (93 providers, all done); 1,453 Australian providers
-- with active courses were never searched (847 with a website).
-- 1. The 100 largest unsearched Australian providers with a website are queued now (priority 4, read like universities).
-- 2. security.scholarship_discovery_refill_v1 keeps 30 waiting, adding the next largest; job scholarship-discover-refill
--    runs hourly, so discovery never stops for lack of a list. Spending stays inside the existing scholarship Firecrawl cap.

create or replace function security.scholarship_discovery_refill_v1(p_keep int default 30) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_pending int; v_added int := 0;
begin
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status = 'pending';
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, 4, 'largest_unsearched', 'pending'
      from (select p.id provider_id, btrim(p.website) website, count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.iso_alpha2 = 'AU' and nullif(btrim(p.website), '') is not null
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website order by count(*) desc, p.id limit greatest(0, p_keep - v_pending)) q
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  return jsonb_build_object('pending_before', v_pending, 'added', v_added);
end $fn$;
revoke all on function security.scholarship_discovery_refill_v1(int) from public, anon, authenticated;

select security.scholarship_discovery_refill_v1(100);
select cron.schedule('scholarship-discover-refill', '23 * * * *', $$select security.scholarship_discovery_refill_v1(30)$$);
