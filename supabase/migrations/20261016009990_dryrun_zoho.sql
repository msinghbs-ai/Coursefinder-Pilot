-- noop
-- PASTE FILE — CF-247 target_only audit write-back (throughput record section 3.2; standing order: audit → O10 → R2)
-- Applied by: the Platform Admin, Supabase SQL editor, project fxcwkweaxjtknorudmwp. Audit: PASTE-20261024-target-only-audit.csv (same folder).
-- What it does: records the derived reason on each of the 87 group-A rows of pipeline.firecrawl_target_cache (included = false, no reason today)
-- in the existing override_reason column. It RELEASES NOTHING: included stays false. Releases (rule_false_no_reason after the domain rule is
-- re-run) and the firecrawl-targets run for never_evaluated providers follow the Platform Admin's O10 sign-off, in a separate paste file.
-- Group B (455 providers not in the cache) has no cache row to annotate: 334 are unpublished or archived (held), 1 robots, 120 never evaluated.
-- Count guards: exactly 87 rows, all included = false, none already carrying a reason.

do $p$
declare v_n int; v_upd int;
begin
  create temp table _audit(provider_id uuid primary key, reason text) on commit drop;
  insert into _audit values
    ('73c4ae05-4b36-4175-ac30-31fe1c7b6335'::uuid, 'audit 2026-10-24: deliberate_list — unpublished or archived'),
    ('99a4e951-3320-4751-8805-115debb300bd'::uuid, 'audit 2026-10-24: deliberate_list — unpublished or archived'),
    ('1b8db821-3b4c-4c17-a7d7-6819923352d6'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('0f5373c8-d724-4303-9267-739530a5ce53'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('141c895b-9fd5-4c10-9427-bf457593de37'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('c53d394b-bd68-4437-85c8-b9d78f2f83e8'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('95a1f220-4617-4ea1-81e5-b50debd72404'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('c537423d-028a-4b06-b135-003f2c6c393d'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('ac672bf2-086b-4d9f-8aa6-6f3057f58a51'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('bd473ff9-d45a-4447-9b84-cead3c11c01c'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('fd815678-46ec-49f1-bcc4-ac9b5880d76c'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('551383f9-7732-4588-a843-dd2b97c13f6f'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('e3735418-63b0-480a-83e0-ecb309c9cebb'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('68341895-092b-480c-962d-57ec0fb152fc'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('a00e0e6d-02da-426b-9fdd-8c7f1afe75c0'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('8d6c74b2-75fa-41e1-b0f1-af1cfb216361'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('f897e2d8-6624-4417-b546-e0343f617dff'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('4e8aae65-7740-4597-b158-4dba41cba82e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('7cc10c4d-eb36-43bc-9230-6d43c31d45e0'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('2fb4d947-843b-4f8a-bc09-c20cb230cb61'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('7586774d-d712-42b4-9049-495b0cc9676e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('e547d207-c3e7-454b-85f2-bf542571f021'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('40abe289-b458-47dd-a035-96d339bd1248'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('037ccfe3-cc93-43d1-a30a-283a979b2a28'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('ed3cf118-13fa-4538-b1e0-689228770ed3'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('a787be65-254e-4fed-91d5-8aec5908d226'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('76c9d431-e678-4412-a36d-b42818672f70'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('ca2dacb0-297a-4067-a899-59eb7b381ae6'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('26d98667-66fa-47e9-8829-5cacde1c951e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('6e83a7d7-27d5-476f-a6d9-bc03a04c42d2'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('c9d6e8c8-a988-4f90-94c4-944a5bf2aec0'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('3edbcd34-cd3e-4765-bf89-fa84cfe43dbd'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('2bf782c5-e2df-477f-959d-fcec254c2d7b'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('cdeb0e83-3c79-4d0f-bd35-9fcdecf9946e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('ede06b09-1e9a-4594-96d3-24e769cb4f91'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('681f7e51-e130-4e53-aa09-81e4b717d69d'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('d6efb7f6-123d-4734-bef6-c5af2da44ce7'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('cffb854b-5d63-43b1-96fe-23bcd0c1917e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('fbb89e0c-5f9a-4451-954d-e4e679ae85d0'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('8a06f802-dacc-447c-a6bc-f97e3521cc77'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('bd1dd317-f9d8-484b-9639-c632e92c2503'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('03d30857-b575-4952-b311-4d7fa5ecfa29'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('05b70e2c-e1f3-407a-accf-8596ef56ecfb'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('30b81368-9003-4775-81af-60439fc3b109'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('23d19ef5-f4b0-4a99-bb9a-16bdaf7eb6be'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('ebd96fd9-b4b8-474c-8729-6fb01c3c0b57'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('54ed4846-cc4c-4195-879e-2e1dacfd1b87'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('a1198033-11d5-4ecb-979f-84991ae99fbe'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('123f53b3-490b-4dbf-a386-a0247b340e60'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('fbe47347-71a7-418a-83a0-42a313c6c95d'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('aa87f50d-f732-4e80-9ca4-66779e715f41'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('eaa7991e-0718-4058-84bc-e8db75766b42'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('6c2c7f9e-5904-4871-94f9-694700176cd2'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('d9fabbd4-8cce-4b04-a2ee-5d2d90502402'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('6bf9e89d-e86c-494f-b022-405250d3ff57'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('772bc2bf-5c08-452c-9ec6-0c618e65362a'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('fe106405-7f73-4ff4-978f-3c0162b1739b'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('5fa2e75e-c8d8-4e7f-b020-7aa6587554ec'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('d7508425-0ecb-4ae0-8f47-064399362fe9'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('c347b48f-02a5-4344-aacc-efe6ce320e63'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('cec09f0c-2426-419d-8c9b-d16b983eb0fa'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('631508b9-67c8-460d-9d98-6734cbc5db95'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('b4379618-97ad-4390-b2d0-e730e2443b85'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('57e9dac2-c4ce-467d-bb2a-881ed59377c8'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('f4ed3151-b81e-46d9-8a6c-d7e302ab63ae'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('9e94a92a-fd26-4aa5-82c9-77b481f7682d'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('20620df0-360d-4218-ae89-f210c37798ce'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('97433acd-91da-4e21-ab9f-427ed2d39e33'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('c549263b-6de6-41b0-b6fc-a2d6e9db9b51'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('b90e9815-38cc-460c-88f2-ac2d17ad2fc3'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('99044b9f-270a-413e-a70d-00e651ab2c9b'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('62faed4f-185c-4d78-9397-3ab02de9123c'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('3accd132-9073-446d-b539-f8c7f0e1cd6a'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('758e7d2b-f419-49bf-9e69-34f1454bc6ec'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('11e427cd-da7a-4f6f-b18a-99426b4d3b25'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('0173b650-92ae-4683-907e-f258bb7bda40'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('d4150646-46b4-4a83-b89b-2a4de22b2f4d'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('7fb75529-a914-4a28-ad38-1ba7aac5f2a6'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('3dfbe754-fa4e-4b08-bb53-be547d543b23'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('881a0ebc-9e8c-4e7e-8172-6c1e6f149e67'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('7457267e-d70e-4855-86a9-d4c8f377332a'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('1e006385-fd4a-431d-b63a-5b29c09f1fea'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('8045d740-6a60-452e-9b24-d5e18841b06f'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('2b8c5d60-ad9f-4ea6-b540-1d84f663488e'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('fa9fb404-21ea-4f52-8caf-351dc3b55a83'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('d960d5a3-813f-493f-b95c-d2d6a1a43dbc'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason'),
    ('75397f2c-1101-4fc5-a5d4-afe4c800f98b'::uuid, 'audit 2026-10-24: rule_false_no_reason — cache rule_match=false, no override_reason');
  select count(*) into v_n from pipeline.firecrawl_target_cache tc join _audit a using (provider_id) where not tc.included and tc.override_reason is null;
  if v_n <> 87 then raise exception 'count guard: expected 87 excluded rows without a reason, found %', v_n; end if;
  update pipeline.firecrawl_target_cache tc set override_reason = a.reason from _audit a where tc.provider_id = a.provider_id and not tc.included and tc.override_reason is null;
  get diagnostics v_upd = row_count;
  if v_upd <> 87 then raise exception 'count guard: updated % rows, expected 87 (rolled back)', v_upd; end if;
  raise exception 'DRYRUN OK target_only audit: reason recorded on % excluded cache rows; nothing released', v_upd;
end $p$;

