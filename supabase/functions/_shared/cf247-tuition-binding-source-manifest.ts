// CF-247 3B2A: source-derived, public (non-secret) binding inputs.
// The required CI contract recomputes these hashes from the actual sources.
// A source/prompt/schema/helper change without manifest regeneration fails CI.
// This manifest alone does not qualify or unpause a model profile.
export const CF247_TUITION_BINDING_SOURCE_MANIFEST = {
  benchmark_prompt_sha256: "44b6ae821715eb11daf63d955503139e156c43385c10f2482641003021a683d0",
  interpreter_prompt_sha256: "5b16c07b7a2cc8559923239d9bddffc62d6f20b7de688eaef8b94cc63858c280",
  benchmark_request_sha256: "67018723373ea1d029269973d81336d89f050a85a4720d393b67249987bdb2c7",
  interpreter_request_sha256: "8bf4f151c970eb0c524e63bdc7b5d233873eb0613da9f0bdf3eed8b7b6bf23a9",
  validator_source_sha256: "4873590885968d4dd070dd08da16e30b6eca112a2af77dc08a44c3570b43765e",
  schema_sha256: "17f3e69647244176a699b953c74cd99f81baf155a0421ef1c9014245b0560a9a",
  binding_helper_sha256: "ec02442e4c787bdd3617bc87ad4764d0ddacc2b6b89b7f51c3c876f24293c757",
} as const;
