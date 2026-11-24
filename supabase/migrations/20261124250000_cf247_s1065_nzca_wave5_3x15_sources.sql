-- CF-247 F-AER.08 S3 NZ/CA lane s1065: Wave 5 next 45 pending providers, batches of 15.
-- Platform Admin 24 Nov 2026 16:17 AEDT: reuse verified sources and queue only actual
-- stored evidence, while the 37 unsourced providers remain PENDING rather than false HELD.
-- Replaces: nothing. Retires: nothing. Data-only existing source/settings/run objects.
-- Guard: AU untouched, Consumer G3 (75/48) untouched, manual locks immutable,
-- no machine admission, no global CA schedule, no new crons, no UI/UX changes.
-- Source is a candidate, not a published minima: page must first pass structural,
-- quotation, qualification/level and Level 4 validation.
do $pre$
begin
 if not exists (select 1 from supabase_migrations.schema_migrations where version='20261124210000') then
   raise exception 's1065 requires Wave 4 production release';
 end if;
 if (select count(*) from cron.job where active) > 140 then
   raise exception 's1065: too many active crons';
 end if;
end $pre$;

with sources(provider_id,url,title) as (values
 ('370a325f-6c1e-4624-8a4d-57b111f4501a'::uuid,'https://www.kingsu.ca/admissions/admission-requirements/general-international-admission-requirements','King''s University official international admissions requirements'),
 ('bd10d0cd-daec-40ff-a9e0-200d8db91102'::uuid,'https://www.confederationcollege.ca/international-education/admission-requirements/','Confederation College country and qualification academic minimums'),
 ('e7caf3bf-0dba-49e1-a654-09427531cd26'::uuid,'https://international.niagaracollege.ca/apply-now','Niagara College international diploma and degree academic admission criteria'),
 ('41e457a8-afef-4e09-a91f-5908ef0581dc'::uuid,'https://www.capilanou.ca/admissions/apply-to-capu/admission-requirements/international-students/','Capilano international admission eligibility and secondary equivalencies'),
 ('687ae5b6-756a-4a2f-b4f0-bf85b68b339c'::uuid,'https://www.douglascollege.ca/admissions/requirements-and-assessment-testing/international-students-admission-requirements','Douglas College international admission criteria by degree level')
)
insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
select s.provider_id,s.url,s.title,1,'manual'
from sources s join catalogue.providers p on p.id=s.provider_id
join ref.countries c on c.id=p.country_id and c.iso_alpha2='CA'
on conflict (provider_id,url) do nothing;

-- Only five verified Canadian institutional websites are enabled; Canada-wide
-- AER scheduling is intentionally OFF. Existing AU/NZ IDs are unchanged.
update pipeline.platform_toolset_settings s
 set value = (
   select to_jsonb(array(select distinct v from (
     select jsonb_array_elements_text(s.value) v
     union all
     select unnest(array[
       '370a325f-6c1e-4624-8a4d-57b111f4501a',
       'bd10d0cd-daec-40ff-a9e0-200d8db91102',
       'e7caf3bf-0dba-49e1-a654-09427531cd26',
       '41e457a8-afef-4e09-a91f-5908ef0581dc',
       '687ae5b6-756a-4a2f-b4f0-bf85b68b339c'
     ]::text[])
   ) k order by v))
 ),
 reason='s1065 NZ/CA Wave5 batches B1-B2: 5 official Canada source-backed providers, no CA global schedule'
where toolset_key='pipeline' and key='entry.providers' and jsonb_typeof(value)='array';

-- Zero fabricated hashes: sources still requiring fetching are left at found.
-- The three NZ providers already have stored sources; do not overwrite a run
-- or a person's Layer 4 item when the content hash is unchanged.
with cohort(id) as (values
 ('370a325f-6c1e-4624-8a4d-57b111f4501a'::uuid),
 ('bd10d0cd-daec-40ff-a9e0-200d8db91102'::uuid),
 ('e7caf3bf-0dba-49e1-a654-09427531cd26'::uuid),
 ('41e457a8-afef-4e09-a91f-5908ef0581dc'::uuid),
 ('687ae5b6-756a-4a2f-b4f0-bf85b68b339c'::uuid),
 ('4fdf1c36-59eb-47e8-802d-39aea9f39b37'::uuid),
 ('d5e0d1c6-9f24-4ce2-869e-dec769f4c3a2'::uuid),
 ('51463a53-dd3f-4dfc-a6d8-bce081dacfb0'::uuid)
)
insert into pipeline.entry_matrix_runs(provider_id,source_id,content_hash)
select s.provider_id,s.id,s.content_hash
from cohort c join pipeline.entry_matrix_sources s on s.provider_id=c.id
where s.status='read' and s.evidence_id is not null and s.content_hash is not null
 and security.entry_matrix_enabled_v1(s.provider_id)
on conflict(source_id,content_hash) do nothing;

insert into pipeline.admin_control_events(area,action,target,detail,actor)
select 'aer','wave5_nzca_register','pipeline.entry_matrix_sources',
 jsonb_build_object('spec','s1065','lane','S3-AER-ChatGPT','ranked_provider_cohort',45,
 'batches',jsonb_build_array(15,15,15),'source_proven_candidates',8,
 'new_CA_source_urls',5,'reused_NZ_source_urls',3,'unsourced_pending',37,
 'reason','Wave5 NZ/CA only: source-first registration, 3x15; no fabricated academic scores, no Layer 4 override'),
 auth.uid()
where not exists(select 1 from pipeline.admin_control_events e
 where e.area='aer' and e.action='wave5_nzca_register' and e.detail->>'spec'='s1065');

do $post$
declare n int;
begin
 select count(*) into n from (values
 ('370a325f-6c1e-4624-8a4d-57b111f4501a'::uuid),
 ('bd10d0cd-daec-40ff-a9e0-200d8db91102'::uuid),
 ('e7caf3bf-0dba-49e1-a654-09427531cd26'::uuid),
 ('41e457a8-afef-4e09-a91f-5908ef0581dc'::uuid),
 ('687ae5b6-756a-4a2f-b4f0-bf85b68b339c'::uuid)
 ) v(id) where security.entry_matrix_enabled_v1(id);
 if n<>5 then raise exception 's1065: only % of five scoped CA providers enabled',n; end if;
 if (security.aer_schedule_country_v1('CA')->>'on')::boolean then
  raise exception 's1065 must not enable country-wide Canada AER';
 end if;
 if (select count(*) from cron.job where active)>140 then
  raise exception 's1065 active cron ceiling breached';
 end if;
end $post$;


-- s1064 NZ stored-HTML recovery: re-read ONLY the three failed source copies
-- whose held_unparsed reason the existing deterministic reader can now address.
-- Never replay an approved, person-claimed, ambiguous, new-edition, or AU run.
-- Existing public.admin_entry_matrix_reread preserves previous_results and changes
-- proposed rows/pending items only; canonical active rows and manual locks stay put.
do $nz_recovery$
declare v_ids uuid[];
        v_result jsonb;
begin
  select array_agg(s.id order by s.id) into v_ids
  from pipeline.entry_matrix_sources s
  join catalogue.providers p on p.id=s.provider_id
  join ref.countries k on k.id=p.country_id and k.iso_alpha2='NZ'
  join lateral (
    select r.id,r.state,r.error,r.review_item_id
    from pipeline.entry_matrix_runs r where r.source_id=s.id
    order by (r.content_hash is not distinct from s.content_hash) desc,r.created_at desc,r.id desc limit 1
  ) r on true
  left join pipeline.layer4_review_items i on i.id=r.review_item_id
  where s.id in (
    'd74fcba4-a492-4cde-a1f0-70a398e6bfda'::uuid, -- Otago Polytechnic
    'f06a01dd-d77e-48bc-b646-e669e22daffd'::uuid, -- Wintec
    '8b020b17-cb26-4d91-90c1-498062465a4a'::uuid -- VUW
  )
  and s.status='read' and s.evidence_id is not null and s.content_hash is not null
  and r.state='failed' and r.error like 'held_unparsed:%'
  and (i.id is null or (i.status='pending' and i.claimed_at is null and i.assigned_to is null))
  and not exists (
    select 1 from pipeline.entry_matrix_runs r2
    join pipeline.layer4_review_items li on li.id=r2.review_item_id
    where r2.source_id=s.id and (li.status='approved' or li.claimed_at is not null or li.assigned_to is not null)
  );
  if coalesce(cardinality(v_ids),0)>0 then
    v_result := public.admin_entry_matrix_reread(v_ids,'s1064 NZ stored HTML country-section deterministic reader; retry only unparsed Otago, Wintec, VUW');
    if not coalesce((v_result->>'ok')::boolean,false) then
      raise exception 's1064 NZ guarded stored reread failed: %',v_result;
    end if;
    raise notice 's1064 NZ stored-source reread queued: %',v_result;
  else
    raise notice 's1064 NZ stored-source reread: no safely eligible run; existing holds retained';
  end if;
end $nz_recovery$;
