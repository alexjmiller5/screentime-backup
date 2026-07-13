{
  description = "Weekly launchd snapshots of macOS Screen Time data stores (knowledgeC, ScreenTimeAgent, Biome streams)";

  # The module only uses the consumer's pkgs/lib — no inputs needed.
  outputs = { self }: {
    darwinModules.default = import ./nix/darwin.nix;
  };
}
