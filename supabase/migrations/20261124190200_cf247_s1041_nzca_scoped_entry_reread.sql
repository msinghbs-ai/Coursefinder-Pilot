-- s1041 F-AER.08: after deterministic NZ HTML-table and Auckland identity fix is deployed,
-- requeue existing stored official copies without touching AU, human-claimed or approved Layer 4 decisions.
-- Replaces: no functions. Retires: none. Does not alter G3 or manual locks.
-- This migration must be applied only with s1041 coverage-sweep worker release; all re-read attempts
-- use the existing audited admin_entry_matrix_reread and preserve previous_results.
do $s1041$
declare
  v_ids uuid[];
  v_out jsonb;
begin
  select array_agg(s.id order by s.id) into v_ids
  from pipeline.entry_matrix_sources s
  join catalogue.providers p on p.id=s.provider_id
  join ref.countries c on c.id=p.country_id and c.iso_alpha2='NZ'
  join lateral (
    select r.id,r.state,r.review_item_id
    from pipeline.entry_matrix_runs r where r.source_id=s.id
    order by (r.content_hash is not distinct from s.content_hash) desc,r.created_at desc,r.id desc
    limit 1
  ) r on true
  left join pipeline.layer4_review_items i on i.id=r.review_item_id
  where s.id in (
    'd74fcba4-a492-4cde-a1f0-70a398e6bfda'::uuid, -- Otago Polytechnic
    'f06a01dd-d77e-48bc-b646-e669e22daffd'::uuid, -- Wintec
    '7cd70eba-dbf9-424f-b1d7-6024fc0266c4'::uuid, -- Auckland A-I only (J-Z approved; do not supersede)
    '8b020b17-cb26-4d91-90c1-498062465a4a'::uuid  -- Wellington
  )
  and r.state in ('done','failed')
  and (i.id is null or (i.status='pending' and i.claimed_at is null and i.assigned_to is null))
  and not exists (select 1 from pipeline.layer4_review_items other
                  join pipeline.entry_matrix_runs other_run on other_run.review_item_id=other.id
                 where other_run.source_id=s.id
                   and (other.status='approved' or other.claimed_at is not null or other.assigned_to is not null));

  if coalesce(cardinality(v_ids),0)>0 then
    v_out := public.admin_entry_matrix_reread(
      v_ids,'s1041 NZ country-heading HTML parser and Auckland/VUW guarded course identity rerun; approved or claimed Layer 4 items excluded'
    );
    if not coalesce((v_out->>'ok')::boolean,false) then
      raise exception 's1041 reread audit did not succeed: %',v_out;
    end if;
    raise notice 's1041 NZ AER reread: %',v_out;
  else
    raise notice 's1041 NZ AER reread: no safely eligible stored runs';
  end if;
end $s1041$;
