-- CF-247 (Decision 219, 2 Oct 2026). Platform Admin, 11:24: "No state filter for nz, also check it for Canada. Make sure
-- state or province is available as filter. Also make mass bulk action for layer 4, flagged values".
--  1. New Zealand's 16 regions and the Chatham Islands (ISO 3166-2:NZ) are added to the reference list, and every NZ
--     provider without a region gets one from its town. Towns that name two places (Frankton is in Hamilton and in
--     Queenstown), overseas addresses and towns not listed are left for a person; a region set by hand is never changed.
--     Canada already holds a province or territory for all 1,130 providers.
--  2. Flagged values: one call settles many flags at once (confirm per year, mark as whole course, or remove), each
--     through the same checks as a single decision (Pipeline Operator and above).

insert into ref.subdivisions(country_id, code, name, subdivision_type, status)
select k.id, x.code, x.name, x.t, 'active'
  from ref.countries k cross join (values
    ('NZ-AUK','Auckland','region'),('NZ-BOP','Bay of Plenty','region'),('NZ-CAN','Canterbury','region'),('NZ-GIS','Gisborne','region'),
    ('NZ-HKB','Hawke''s Bay','region'),('NZ-MWT','Manawatū-Whanganui','region'),('NZ-MBH','Marlborough','region'),('NZ-NSN','Nelson','region'),
    ('NZ-NTL','Northland','region'),('NZ-OTA','Otago','region'),('NZ-STL','Southland','region'),('NZ-TKI','Taranaki','region'),
    ('NZ-TAS','Tasman','region'),('NZ-WKO','Waikato','region'),('NZ-WGN','Wellington','region'),('NZ-WTC','West Coast','region'),
    ('NZ-CIT','Chatham Islands Territory','territory')) x(code, name, t)
 where k.iso_alpha2 = 'NZ'
on conflict (code) do nothing;

with town(town, code) as (values
  ('auckland','NZ-AUK'),('north shore city','NZ-AUK'),('albany','NZ-AUK'),('penrose','NZ-AUK'),('manukau','NZ-AUK'),('auckland central','NZ-AUK'),
  ('onehunga','NZ-AUK'),('grafton','NZ-AUK'),('newmarket','NZ-AUK'),('new market','NZ-AUK'),('wiri','NZ-AUK'),('auckland cbd','NZ-AUK'),('manurewa','NZ-AUK'),
  ('otara','NZ-AUK'),('east tamaki','NZ-AUK'),('howick','NZ-AUK'),('manukau city','NZ-AUK'),('mangere','NZ-AUK'),('takapuna','NZ-AUK'),
  ('pukekohe','NZ-AUK'),('new lynn','NZ-AUK'),('castor bay','NZ-AUK'),('torbay','NZ-AUK'),('silverdale','NZ-AUK'),('parakai','NZ-AUK'),
  ('newton','NZ-AUK'),('east otahuhu','NZ-AUK'),('meadowbank','NZ-AUK'),('forrest hill','NZ-AUK'),('parnell','NZ-AUK'),('mt albert','NZ-AUK'),
  ('papatoetoe','NZ-AUK'),('milford','NZ-AUK'),('paremoremo','NZ-AUK'),('henderson','NZ-AUK'),('mt roskill','NZ-AUK'),('panmure','NZ-AUK'),
  ('mairangi bay','NZ-AUK'),('papakura','NZ-AUK'),('waitakere city','NZ-AUK'),('takanini','NZ-AUK'),('waikowhai','NZ-AUK'),('ponsonby','NZ-AUK'),
  ('rosedale','NZ-AUK'),('surfdale','NZ-AUK'),('mt wellington','NZ-AUK'),('ellerslie','NZ-AUK'),('st johns','NZ-AUK'),
  ('christchurch','NZ-CAN'),('christchurch1','NZ-CAN'),('papanui','NZ-CAN'),('harewood','NZ-CAN'),('addington','NZ-CAN'),('lincoln','NZ-CAN'),
  ('riccarton','NZ-CAN'),('sydenham','NZ-CAN'),('ilam','NZ-CAN'),('somerfield','NZ-CAN'),('timaru','NZ-CAN'),('rangiora','NZ-CAN'),
  ('prebbleton','NZ-CAN'),('middleton','NZ-CAN'),('kaiapoi','NZ-CAN'),('waltham','NZ-CAN'),('ashburton','NZ-CAN'),
  ('hamilton','NZ-WKO'),('hamilton east','NZ-WKO'),('tokoroa','NZ-WKO'),('cambridge','NZ-WKO'),('taupo','NZ-WKO'),('taupiri','NZ-WKO'),
  ('te kuiti','NZ-WKO'),('turangi','NZ-WKO'),('thames','NZ-WKO'),('paeroa','NZ-WKO'),('nawton','NZ-WKO'),('maeroa','NZ-WKO'),
  ('whitianga','NZ-WKO'),('coromandel peninsula','NZ-WKO'),('pokeno','NZ-WKO'),
  ('palmerston north','NZ-MWT'),('whanganui','NZ-MWT'),('wanganui','NZ-MWT'),('levin','NZ-MWT'),('marton','NZ-MWT'),('ohakune','NZ-MWT'),
  ('tauranga','NZ-BOP'),('rotorua','NZ-BOP'),('mt maunganui','NZ-BOP'),('whakatane','NZ-BOP'),('opotiki','NZ-BOP'),('ohinemutu','NZ-BOP'),
  ('pukehina','NZ-BOP'),('te puke','NZ-BOP'),('ngapuna','NZ-BOP'),('bethlehem','NZ-BOP'),('pongakawa','NZ-BOP'),
  ('wellington','NZ-WGN'),('lower hutt','NZ-WGN'),('newtown','NZ-WGN'),('te aro','NZ-WGN'),('upper hutt','NZ-WGN'),('porirua','NZ-WGN'),
  ('thorndon quay','NZ-WGN'),('lambton quay','NZ-WGN'),('hutt central','NZ-WGN'),('masterton','NZ-WGN'),('thorndon','NZ-WGN'),
  ('paraparaumu','NZ-WGN'),('otaki','NZ-WGN'),
  ('nelson','NZ-NSN'),('nelson airport','NZ-NSN'),('port nelson','NZ-NSN'),('motueka','NZ-TAS'),('lower moutere','NZ-TAS'),
  ('new plymouth','NZ-TKI'),('bell block','NZ-TKI'),('stratford','NZ-TKI'),('opunake','NZ-TKI'),
  ('whangarei','NZ-NTL'),('whang?rei','NZ-NTL'),('whangārei','NZ-NTL'),('kaitaia','NZ-NTL'),('kaikohe','NZ-NTL'),('raumanga','NZ-NTL'),
  ('awanui','NZ-NTL'),('otamatea','NZ-NTL'),('maungaturoto','NZ-NTL'),
  ('dunedin','NZ-OTA'),('queenstown','NZ-OTA'),('central otago','NZ-OTA'),('lower shotover','NZ-OTA'),('waitati','NZ-OTA'),('wanaka','NZ-OTA'),
  ('wanaka airport','NZ-OTA'),('momona','NZ-OTA'),('balclutha','NZ-OTA'),('roslyn','NZ-OTA'),('fernhill','NZ-OTA'),('alexandra','NZ-OTA'),
  ('invercargill','NZ-STL'),('riverton','NZ-STL'),
  ('hastings','NZ-HKB'),('napier','NZ-HKB'),('wairoa','NZ-HKB'),('haumoana','NZ-HKB'),('taradale','NZ-HKB'),('poukawa','NZ-HKB'),
  ('blenheim','NZ-MBH'),('westport','NZ-WTC'),('greymouth','NZ-WTC'))
update catalogue.providers p set subdivision_id = s.id, updated_at = now()
  from ref.countries k, town t, ref.subdivisions s
 where k.id = p.country_id and k.iso_alpha2 = 'NZ' and p.subdivision_id is null
   and lower(btrim(p.primary_city)) = t.town and s.code = t.code;

-- 2. bulk decisions on flagged values: the same changes as a single decision (security.admin_data_flag_resolve_v1),
--    applied to each open flag chosen; search is refreshed once at the end
create or replace function public.admin_data_flag_resolve_bulk(p_flag_ids uuid[], p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare f pipeline.data_flags%rowtype; fe catalogue.course_fees%rowtype; v_id uuid; v_ok int := 0; v_skipped int := 0; v_ids uuid[] := '{}';
        v_note text := coalesce(nullif(p_args->>'note', ''), 'Bulk decision');
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline operator or admin role required' using errcode = '42501'; end if;
  if p_action not in ('confirm', 'whole_course', 'remove') then raise exception 'action must be confirm, whole_course or remove'; end if;
  if coalesce(cardinality(p_flag_ids), 0) = 0 then raise exception 'choose at least one flagged value'; end if;
  if cardinality(p_flag_ids) > 500 then raise exception 'at most 500 at a time'; end if;
  foreach v_id in array p_flag_ids loop
    select * into f from pipeline.data_flags where id = v_id for update;
    if f.id is null or f.status <> 'open' then v_skipped := v_skipped + 1; continue; end if;
    select * into fe from catalogue.course_fees where id = f.record_id for update;
    if fe.id is null then v_skipped := v_skipped + 1; continue; end if;
    if p_action = 'confirm' then
      update catalogue.course_fees set notes = coalesce(notes, '') || format(' | period confirmed per year by an operator %s', to_char(now(), 'DD Mon YYYY')),
             last_verified_at = now(), updated_at = now() where id = fe.id;
      update pipeline.data_flags set status = 'confirmed', resolved_at = now(), resolved_by = auth.uid(),
             resolution = jsonb_build_object('action', 'confirm', 'note', v_note, 'bulk', true) where id = f.id;
    elsif p_action = 'whole_course' then
      update catalogue.course_fees set basis = 'total_indicative', updated_at = now(), last_verified_at = now(),
             notes = coalesce(notes, '') || format(' | corrected by an operator %s: was %s %s', to_char(now(), 'DD Mon YYYY'), fe.amount, fe.basis) where id = fe.id;
      update pipeline.data_flags set status = 'corrected', resolved_at = now(), resolved_by = auth.uid(),
             resolution = jsonb_build_object('action', 'correct', 'before', jsonb_build_object('amount', fe.amount, 'basis', fe.basis),
                                             'after', jsonb_build_object('amount', fe.amount, 'basis', 'total_indicative'), 'note', v_note, 'bulk', true) where id = f.id;
    else
      update catalogue.course_fees set status = 'inactive', updated_at = now(), notes = coalesce(notes, '') || format(' | removed by an operator %s', to_char(now(), 'DD Mon YYYY')) where id = fe.id;
      update pipeline.data_flags set status = 'removed', resolved_at = now(), resolved_by = auth.uid(),
             resolution = jsonb_build_object('action', 'remove', 'note', v_note, 'bulk', true) where id = f.id;
    end if;
    v_ok := v_ok + 1; v_ids := v_ids || f.entity_id;
  end loop;
  if cardinality(v_ids) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_ids, true); end if;
  return jsonb_build_object('done', v_ok, 'skipped', v_skipped, 'read', security.admin_data_flags_read_v1('{}'::jsonb));
end $fn$;
revoke all on function public.admin_data_flag_resolve_bulk(uuid[], text, jsonb) from public, anon;
grant execute on function public.admin_data_flag_resolve_bulk(uuid[], text, jsonb) to authenticated;
