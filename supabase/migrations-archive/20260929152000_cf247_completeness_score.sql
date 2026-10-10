-- CF-247 plan item A6: automated completeness, rebuilt with the hourly coverage build and kept daily.
-- Per course, over the seven tracked attributes (CRICOS: campus, duration, registered tuition; provider: official
-- page, provider tuition, English, intakes):
--   completeness = share of attributes with an admitted value;
--   accounted    = share whose state is settled or in hand: admitted, found and awaiting admission (candidate),
--                  in review / awaiting AI, published-not-on-page, or site blocked. Not accounted: no website yet,
--                  site known but page not found, page found but not read, missing from the register.
-- Rolled up per provider and for the platform; the platform figure is kept per day.
create table if not exists pipeline.course_completeness (
  course_id uuid primary key, provider_id uuid, tier text,
  attributes int not null, admitted int not null, accounted int not null,
  completeness numeric(5,1) not null, accounted_pct numeric(5,1) not null,
  missing text[] not null default '{}', computed_at timestamptz not null default now());
create table if not exists pipeline.completeness_daily (
  snapshot_date date not null, scope text not null, scope_id uuid, courses int not null,
  completeness numeric(5,1) not null, accounted_pct numeric(5,1) not null, fully_complete int not null,
  computed_at timestamptz not null default now());
alter table pipeline.course_completeness enable row level security;
alter table pipeline.completeness_daily enable row level security;
create unique index if not exists completeness_daily_uq on pipeline.completeness_daily(snapshot_date, scope, coalesce(scope_id,'00000000-0000-0000-0000-000000000000'::uuid));

create or replace function security.course_completeness_build_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v jsonb;
begin
  truncate pipeline.course_completeness;
  insert into pipeline.course_completeness(course_id,provider_id,tier,attributes,admitted,accounted,completeness,accounted_pct,missing)
  select course_id, max(provider_id::text)::uuid, max(tier), count(*),
         count(*) filter (where state='admitted'),
         count(*) filter (where state in ('admitted','candidate','in_review','awaiting_l3','not_on_page','blocked')),
         round(100.0*count(*) filter (where state='admitted')/count(*),1),
         round(100.0*count(*) filter (where state in ('admitted','candidate','in_review','awaiting_l3','not_on_page','blocked'))/count(*),1),
         coalesce(array_agg(attribute order by attribute) filter (where state<>'admitted'),'{}')
    from pipeline.course_attribute_coverage group by course_id;
  delete from pipeline.completeness_daily where snapshot_date=current_date;
  insert into pipeline.completeness_daily(snapshot_date,scope,scope_id,courses,completeness,accounted_pct,fully_complete)
  select current_date,'platform',null,count(*),round(avg(completeness),1),round(avg(accounted_pct),1),count(*) filter (where admitted=attributes) from pipeline.course_completeness
  union all
  select current_date,'provider',provider_id,count(*),round(avg(completeness),1),round(avg(accounted_pct),1),count(*) filter (where admitted=attributes) from pipeline.course_completeness where provider_id is not null group by provider_id;
  select to_jsonb(d) - 'scope_id' into v from pipeline.completeness_daily d where snapshot_date=current_date and scope='platform';
  return v;
end $f$;
revoke all on function security.course_completeness_build_v1() from public, anon, authenticated;

select cron.schedule('course-completeness-build','52 * * * *',$$select security.course_completeness_build_v1()$$);
select security.course_completeness_build_v1();
