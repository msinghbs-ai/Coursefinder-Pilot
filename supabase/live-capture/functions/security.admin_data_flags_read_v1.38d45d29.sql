CREATE OR REPLACE FUNCTION security.admin_data_flags_read_v1(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'security'
AS $function$
declare v_status text:=coalesce(nullif(p_args->>'status',''),'open'); v_limit int:=least(greatest(coalesce((p_args->>'limit')::int,100),1),500);
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object(
    'can_edit', security.current_role_rank()>=4,
    'counts', (select jsonb_object_agg(status,n) from (select status,count(*) n from pipeline.data_flags group by 1) x),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'flag',f.flag_code,'status',f.status,'created_at',f.created_at,'resolved_at',f.resolved_at,'resolution',f.resolution,
        'course_id',f.entity_id,'course',coalesce(c.display_title,c.canonical_title),'course_code',c.course_code,
        'provider',coalesce(pv.display_name,pv.canonical_name),'amount',fe.amount,'currency',fe.currency_code,'basis',fe.basis,'fee_status',fe.status,
        'page_url',f.detail->>'page_url','quotes',f.detail->'quotes',
        'schedule',(select jsonb_build_object('amount',fr.amount,'year',fr.fee_year,'url',sr.url) from pipeline.provider_fee_rows fr join pipeline.provider_fact_sources sr on sr.id=fr.source_id
                     where sr.decision='approved' and fr.current and fr.basis='annual' and fr.provider_id=c.provider_id and fr.course_code=upper(btrim(c.course_code))
                     order by fr.fee_year desc nulls last, sr.decided_at desc limit 1)) order by f.created_at desc)
      from (select * from pipeline.data_flags where status=v_status or v_status='all' order by created_at desc limit v_limit) f
      left join catalogue.courses c on c.id=f.entity_id left join catalogue.providers pv on pv.id=c.provider_id
      left join catalogue.course_fees fe on fe.id=f.record_id),'[]'::jsonb));
end $function$
