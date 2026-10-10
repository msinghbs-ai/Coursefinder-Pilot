-- CF-247 Decision 254 (6 Oct 2026, night run wave 5). In track D (small providers) an adapter was saved almost only
-- where at least two of the provider's course pages were already read: 108 adapters from 300 providers, and most of the
-- rest had no course page of their own stored (schools, aggregator listings only, nothing found). The rest of track D is
-- batched again: providers with at least two read course pages go to track E (12 a batch) for the adapter agents, the
-- others go to track H (held for page discovery, not worked by the night agents). Track D batches already worked are
-- left as they are. A read-only snapshot like the night run queue. No text value in this file contains a semicolon.

create table if not exists pipeline.night_run_rebatch (
  provider_id uuid primary key references catalogue.providers(id),
  track text not null check (track in ('E', 'H')),
  batch integer not null,
  ord integer not null,
  read_pages integer not null,
  courses integer not null,
  snapshot_at timestamptz not null default now()
);
alter table pipeline.night_run_rebatch enable row level security;
revoke all on table pipeline.night_run_rebatch from anon, authenticated;

insert into pipeline.night_run_rebatch(provider_id, track, batch, ord, read_pages, courses)
  select s.provider_id, s.track, case when s.track = 'E' then (s.rn - 1) / 12 + 1 else 0 end, s.rn, s.rd, s.courses
    from (select x.*, row_number() over (partition by x.track order by x.rd desc, x.courses desc, x.provider_id) rn
            from (select q.provider_id, q.courses,
                         (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = q.provider_id and pg.read_status = 'read')::int rd,
                         case when (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = q.provider_id and pg.read_status = 'read') >= 2 then 'E' else 'H' end track
                    from pipeline.night_run_queue q
                   where q.track = 'D' and q.batch > 20
                     and not exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id)) x) s
  on conflict (provider_id) do nothing;
