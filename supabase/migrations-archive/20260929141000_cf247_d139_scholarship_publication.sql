-- CF-247 Decision 139 (Platform Admin approval 29 Sep 2026 09:56 IST: publish the scholarships that meet every
-- Decision 139 condition, then sweep for more). A scholarship is publishable when it is active and has:
--   own_page   the provider's own page (not a Study Australia listing),
--   intl       an international audience,
--   value      a stated award value (percentage or fixed amount),
--   evidence   captured evidence,
--   course     at least one linked course (a confirmed course mapping),
--   recent     verification within the last 12 months (record or evidence).
-- Publication is in batches under a recorded approval; a daily review withdraws published scholarships that stop
-- qualifying (never re-publishes on its own). Consumer snapshots are recorded before and after each batch.
create table if not exists pipeline.scholarship_publication_batches (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('publish','withdraw')),
  approval_ref text not null,
  scholarship_ids uuid[] not null,
  created_at timestamptz not null default now()
);
alter table pipeline.scholarship_publication_batches enable row level security;

create or replace function security.scholarship_publishability_v1()
returns table(scholarship_id uuid, publishable boolean, missing text[])
language sql stable security definer set search_path to 'pg_catalog','scholarship','pipeline' as $f$
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' or s.source_url ~* 'studyaustralia\.gov\.au' then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then 'no stated award value' end,
        case when s.evidence_id is null then 'no evidence' end,
        case when not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped') then 'no linked course' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
$f$;
revoke all on function security.scholarship_publishability_v1() from public, anon, authenticated;

create or replace function security.scholarship_publish_batch_v1(p_approval_ref text, p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline','security' as $f$
declare v_ids uuid[]; v_before jsonb; v_after jsonb;
begin
  if coalesce(btrim(p_approval_ref),'')='' then raise exception 'approval reference required'; end if;
  select coalesce(array_agg(p.scholarship_id),'{}') into v_ids
    from security.scholarship_publishability_v1() p join scholarship.scholarships s on s.id=p.scholarship_id
   where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id);
  if not p_apply or cardinality(v_ids)=0 then return jsonb_build_object('apply',p_apply,'eligible',cardinality(v_ids),'ids',to_jsonb(v_ids)); end if;
  v_before:=security.consumer_api_snapshot_v1();
  update scholarship.scholarships set publication_status='published', updated_at=now() where id=any(v_ids);
  insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('publish',p_approval_ref,v_ids);
  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before scholarship publication batch ('||cardinality(v_ids)||', Decision 139)',v_before),
    ('after scholarship publication batch ('||cardinality(v_ids)||', Decision 139)',v_after);
  return jsonb_build_object('apply',true,'published',cardinality(v_ids),'ids',to_jsonb(v_ids));
end $f$;
revoke all on function security.scholarship_publish_batch_v1(text,boolean) from public, anon, authenticated;

create or replace function security.scholarship_publication_review_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline','security' as $f$
declare v_ids uuid[];
begin
  select coalesce(array_agg(s.id),'{}') into v_ids
    from scholarship.scholarships s join security.scholarship_publishability_v1() p on p.scholarship_id=s.id
   where s.publication_status='published' and not p.publishable;
  if cardinality(v_ids)>0 then
    update scholarship.scholarships set publication_status='withdrawn', updated_at=now() where id=any(v_ids);
    insert into pipeline.scholarship_publication_batches(kind,approval_ref,scholarship_ids) values ('withdraw','Decision 139 automatic withdrawal',v_ids);
  end if;
  return jsonb_build_object('withdrawn',cardinality(v_ids));
end $f$;
revoke all on function security.scholarship_publication_review_v1() from public, anon, authenticated;

select cron.schedule('scholarship-publication-review','17 20 * * *',$$select security.scholarship_publication_review_v1()$$);

-- First batch under the 29 Sep 2026 approval.
select security.scholarship_publish_batch_v1('CF-CHG-20260915-247; Decision 139; Platform Admin approval 29 Sep 2026 09:56 IST', true);
