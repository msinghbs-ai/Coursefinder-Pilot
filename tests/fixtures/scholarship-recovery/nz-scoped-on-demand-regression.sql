-- Run after the candidate migration in the same explicit rolled-back transaction.
-- Requires production-shaped cap state; no vendor calls are made.
do $test$
declare
 target uuid := 'e096aba7-e1eb-4903-9a63-2bfb71e9a8b8';
 ca uuid := 'b509ab5c-87b2-4040-8385-d1ce610c7263';
 req uuid;
 r jsonb;
begin
 if not security.fc_sch_held_v1(target,true) then raise exception 'ordinary scheduled cap not held'; end if;
 if not security.fc_sch_held_v1(ca,true) then raise exception 'Canadian scheduled cap not held'; end if;
 r := security.on_demand_open_v1('claude_session','Admin #937: S3-Scholarship-ChatGPT NZQA listing recovery',array[target,ca],jsonb_build_object('cap_firecrawl_units',1));
 req := (r->>'id')::uuid;
 perform security.on_demand_scope_v1(req,array['central']);
 if not security.fc_sch_held_v1(target,true) then raise exception 'incorrect purpose allowed'; end if;
 perform security.on_demand_scope_v1(req,array['scholarships']);
 if security.fc_sch_held_v1(target,true) then raise exception 'authorised NZ request held'; end if;
 if not security.fc_sch_held_v1(ca,true) then raise exception 'Canadian exemption incorrectly expanded'; end if;
 if not security.fc_sch_held_v1(target,false) then raise exception 'non-discovery scheduled path changed'; end if;
 if not security.fc_sch_held_v1('db910e88-67d1-4d2b-a65c-cea290aa0692',true) then raise exception 'unauthorised NZ provider allowed'; end if;
 update pipeline.on_demand_requests set expires_at=now()-interval '1 second' where id=req;
 if not security.fc_sch_held_v1(target,true) then raise exception 'expired request allowed'; end if;
end $test$;
