{
  harbor-meta,
  harbor-rs,
}: _: {
  imports = [
    harbor-meta.treefmtModules.nix
    harbor-meta.treefmtModules.toml
    harbor-rs.treefmtModules.rust
  ];
  projectRootFile = "flake.nix";
  settings.global.excludes = ["templates/**" ".github/workflows/*.yaml"];
}
