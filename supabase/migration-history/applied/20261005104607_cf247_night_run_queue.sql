-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 21:24 and 21:44): the overnight adapter run for every Australian and
-- New Zealand provider with courses and no adapter yet. A fixed snapshot of the providers in three tracks, each cut
-- into batches, so every agent works on its own batch and none overlap:
--   B  more than 30 courses, one provider per batch
--   C  6 to 30 courses, six providers per batch
--   D  1 to 5 courses, fifteen providers per batch
-- Ordered by course count (most first), providers with a website first within a count. Read-only for agents.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.night_run_queue (
  provider_id uuid primary key references catalogue.providers(id),
  track text not null check (track in ('B', 'C', 'D')),
  batch int not null,
  ord int not null,
  country text,
  courses int not null,
  has_website boolean not null,
  snapshot_at timestamptz not null default now()
);
alter table pipeline.night_run_queue enable row level security;
revoke all on table pipeline.night_run_queue from anon, authenticated;

insert into pipeline.night_run_queue(provider_id, track, batch, ord, country, courses, has_website)
select q.id, q.track,
       case q.track when 'B' then q.rn when 'C' then (q.rn - 1) / 6 + 1 else (q.rn - 1) / 15 + 1 end,
       q.rn, q.cc, q.courses, q.web
  from (select s.*, row_number() over (partition by s.track order by s.courses desc, s.web desc, s.id) rn
          from (select p.id, trim(co.iso_alpha2::text) cc, coalesce(p.website, '') <> '' web,
                       (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')::int courses,
                       case when (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') > 30 then 'B'
                            when (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') >= 6 then 'C' else 'D' end track
                  from catalogue.providers p join ref.countries co on co.id = p.country_id
                 where p.lifecycle_status = 'active' and trim(co.iso_alpha2::text) in ('AU', 'NZ')
                   and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = p.id)
                   and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')) s) q
on conflict (provider_id) do nothing;
