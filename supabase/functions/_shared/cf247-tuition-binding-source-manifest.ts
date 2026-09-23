// CF-247 3B2A: source-derived, public (non-secret) binding inputs.
// The required CI contract recomputes these hashes from the actual sources.
// A source/prompt/schema/helper change without manifest regeneration fails CI.
// This manifest alone does not qualify or unpause a model profile.
export const CF247_TUITION_BINDING_SOURCE_MANIFEST = {
  benchmark_prompt_sha256: "8d8d012d2b750076f81cdc3667884284d2ba687ce17618d39a0e9bd5c1ac4d52",
  interpreter_prompt_sha256: "9d10e70fab37a4b0c3eefb8748098c7a615a08d16bf3b2533b557d0ccfff0132",
  benchmark_request_sha256: "387f9650c0495eeeedb809d6b3fa3682f745df2964a14a0e34865f3d4e70295f",
  interpreter_request_sha256: "6690aa9b7c0dae9a09c269858b68f45cfd44a6f6124f00a7ae398b0ed1f9dcc5",
  validator_source_sha256: "4873590885968d4dd070dd08da16e30b6eca112a2af77dc08a44c3570b43765e",
  schema_sha256: "17f3e69647244176a699b953c74cd99f81baf155a0421ef1c9014245b0560a9a",
  binding_helper_sha256: "5965a3622ab9942c79769c62c48f720c17862bede108b17d578e9cb6977b24f8",
} as const;
