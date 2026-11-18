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
