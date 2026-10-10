alter table ranking.systems drop constraint systems_code_check;
alter table ranking.systems add constraint systems_code_check
  check (code = any (array['qs_wur'::text,'the_wur'::text,'arwu'::text]));

insert into ranking.systems(code,publisher_name,ranking_name,official_url,active)
select 'arwu','ShanghaiRanking Consultancy','Academic Ranking of World Universities','https://www.shanghairanking.com/rankings/arwu/2026',true
where not exists (select 1 from ranking.systems where code='arwu');

update ranking.systems
set publisher_name='ShanghaiRanking Consultancy',
    ranking_name='Academic Ranking of World Universities',
    official_url='https://www.shanghairanking.com/rankings/arwu/2026',
    active=true,
    updated_at=now()
where code='arwu';
