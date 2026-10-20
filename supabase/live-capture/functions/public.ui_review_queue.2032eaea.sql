CREATE OR REPLACE FUNCTION public.ui_review_queue(p_limit integer DEFAULT 500)
 RETURNS TABLE(id uuid, entity_id uuid, domain text, field_code text, priority smallint, status text, previous_review_id uuid, reopen_reason text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'workflow', 'auth'
AS $function$
select r.id,r.entity_id,r.domain,r.field_code,r.priority,r.status,r.previous_review_id,r.reopen_reason,r.created_at,r.updated_at
from workflow.review_queue r where auth.uid() is not null order by r.priority desc,r.created_at desc limit least(greatest(coalesce(p_limit,500),1),1000)
$function$
