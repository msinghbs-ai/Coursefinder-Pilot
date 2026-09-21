// CF-247 3B2A: source-derived, public (non-secret) binding inputs.
// The required CI contract recomputes these hashes from the actual sources.
// A source/prompt/schema/helper change without manifest regeneration fails CI.
// This manifest alone does not qualify or unpause a model profile.
export const CF247_TUITION_BINDING_SOURCE_MANIFEST = {
  benchmark_prompt_sha256: "9cfd13d2a51dabcf35c3b6234515f85aec90a614ba8eafa34ced683c399c130f",
  interpreter_prompt_sha256: "3c77a2c75bf2e32881aceff1e024996142e276de96fd1543cb9f44146f94229f",
  benchmark_request_sha256: "3b3dea40b32d7f661aa47dcc9126ee2427ff2566db14c902d10b3266c13a3fde",
  interpreter_request_sha256: "03cdbc5048002a38b88993f6fe2657ab17fa6fa5a607ec6883a4cb7f757850e2",
  validator_source_sha256: "d61e80faeb7d0099ff310ba04bb8656588ed2006fda8356ffa0dd22905909440",
  schema_sha256: "17f3e69647244176a699b953c74cd99f81baf155a0421ef1c9014245b0560a9a",
  binding_helper_sha256: "6fc61a79a69fc4c1d104869662638a3852f7c0efbf0acc2858faa641f62f7d9e",
} as const;
