import {test,expect} from '@playwright/test'
import fs from 'node:fs/promises'

const MIGRATION_PATH='supabase/migrations/20260921040446_cf247_task_profile_scoped_reservation.sql'

test('CF-247 slice 2A: scoped reservation RPC requires exact task class/profile and revalidates in-transaction',async()=>{
  const sql=await fs.readFile(MIGRATION_PATH,'utf8')
  for(const token of [
    'layer3_reserve_scoped_work_service(',
    'p_worker text',
    'p_task_class text',
    'p_profile_id uuid',
    'p_limit integer default 10',
    "if nullif(trim(p_task_class),'') is null then raise exception 'task class required'",
    'if p_profile_id is null then raise exception \'profile id required\'',
    'select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id for update',
    'if not v_p.enabled or v_p.paused then raise exception \'model profile not executable\'',
    "quality_benchmark->>'pass')::boolean,false) is not true then",
    'if not (trim(p_task_class)=any(v_p.allowed_task_classes)) then',
    'raise exception \'task class not allowed by profile\'',
    "reserved_at < now()-interval '15 minutes'",
    'and task_class=trim(p_task_class) and profile_id=p_profile_id',
    "w.status in ('pending','failed')",
    'w.task_class=trim(p_task_class) and w.profile_id=p_profile_id',
    'for update of w skip locked',
    "w.attempt_count<5 or (w.corrective_retry_count=1 and w.corrective_retry_authorized_at is not null)",
    "service_role required",
    "current_setting('request.jwt.claim.role',true)",
  ]) expect(sql).toContain(token)

  // Lease recovery and selection must both be scoped to the exact task/profile pair.
  const leaseRecoveryScoped=/where status='reserved' and reserved_at < now\(\)-interval '15 minutes'\s*\n\s*and task_class=trim\(p_task_class\) and profile_id=p_profile_id/
  expect(sql).toMatch(leaseRecoveryScoped)

  // The legacy two-argument RPC must fail closed, not globally reserve arbitrary work.
  expect(sql).toMatch(/create or replace function public\.layer3_reserve_work_service\(p_worker text, p_limit integer default 10\)/)
  expect(sql).toMatch(/layer3_reserve_work_service is retired; use layer3_reserve_scoped_work_service\(worker,task_class,profile_id,limit\)/)
  expect(sql).not.toMatch(/create or replace function public\.layer3_reserve_work_service\([^)]*\)[\s\S]{0,400}for update of w skip locked/)

  // No default-argument/overload ambiguity: exactly one declaration per distinct arity/signature.
  const scopedDeclarations=[...sql.matchAll(/create or replace function public\.layer3_reserve_scoped_work_service\(/g)]
  expect(scopedDeclarations.length).toBe(1)
  const legacyDeclarations=[...sql.matchAll(/create or replace function public\.layer3_reserve_work_service\(/g)]
  expect(legacyDeclarations.length).toBe(1)

  // Access control: revoke public/anon/authenticated, grant only service_role, for both RPCs.
  expect(sql).toMatch(/revoke all on function public\.layer3_reserve_scoped_work_service\(text,text,uuid,integer\) from public,anon,authenticated/)
  expect(sql).toMatch(/grant execute on function public\.layer3_reserve_scoped_work_service\(text,text,uuid,integer\) to service_role/)
  expect(sql).toMatch(/revoke all on function public\.layer3_reserve_work_service\(text,integer\) from public,anon,authenticated/)
  expect(sql).toMatch(/grant execute on function public\.layer3_reserve_work_service\(text,integer\) to service_role/)
  expect(sql).not.toMatch(/grant .*layer3_reserve_scoped_work_service.*authenticated/i)
  expect(sql).not.toMatch(/grant .*layer3_reserve_work_service.*authenticated/i)
})
