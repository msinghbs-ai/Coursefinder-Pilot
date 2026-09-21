// CF-247 3B2A: source-derived, public (non-secret) binding inputs.
// The required CI contract recomputes these hashes from the actual sources.
// A source/prompt/schema/helper change without manifest regeneration fails CI.
// This manifest alone does not qualify or unpause a model profile.
export const CF247_TUITION_BINDING_SOURCE_MANIFEST = {
  benchmark_prompt_sha256: "9cfd13d2a51dabcf35c3b6234515f85aec90a614ba8eafa34ced683c399c130f",
  interpreter_prompt_sha256: "5b16c07b7a2cc8559923239d9bddffc62d6f20b7de688eaef8b94cc63858c280",
  benchmark_request_sha256: "3b3dea40b32d7f661aa47dcc9126ee2427ff2566db14c902d10b3266c13a3fde",
  interpreter_request_sha256: "8bf4f151c970eb0c524e63bdc7b5d233873eb0613da9f0bdf3eed8b7b6bf23a9",
  validator_source_sha256: "4873590885968d4dd070dd08da16e30b6eca112a2af77dc08a44c3570b43765e",
  schema_sha256: "17f3e69647244176a699b953c74cd99f81baf155a0421ef1c9014245b0560a9a",
  binding_helper_sha256: "6fc61a79a69fc4c1d104869662638a3852f7c0efbf0acc2858faa641f62f7d9e",
} as const;
