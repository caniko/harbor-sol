{
  harbor-meta,
  harbor-rs,
  solanaSource,
  solanaSourceDarwin,
}: rec {
  timezone = harbor-meta.lib.timezone;
  rustOverlay = import harbor-rs.inputs.rust-overlay;

  # ponytail: Nixpkgs' cargoSetupHook forces system libraries (44cddf9), but
  # anchor 1.2.2 and solana-cli 4.0.3 do not declare the ones their -sys
  # crates now require, so both fail to build (uncached upstream). Drop each
  # override once Nixpkgs declares them.
  withSystemLibs = pkgs: drv: libs:
    drv.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.pkg-config];
      buildInputs = (old.buildInputs or []) ++ libs;
    });
  fixAnchor = pkgs: withSystemLibs pkgs pkgs.anchor [pkgs.zstd pkgs.oniguruma];
  # Its jemalloc crate links unprefixed symbols, which rust-jemalloc-sys does
  # not export; let it build the bundled jemalloc as before the hook change.
  fixSolanaCli = pkgs:
    (withSystemLibs pkgs pkgs.solana-cli [pkgs.zstd pkgs.zlib]).overrideAttrs (old: {
      preBuild = (old.preBuild or "") + "\nunset JEMALLOC_OVERRIDE\n";
    });
  systemLibsOverlay = final: prev: {
    anchor = fixAnchor prev;
    solana-cli = fixSolanaCli prev;
  };

  mkCargoBuildSbf = {
    pkgs,
    solana ? fixSolanaCli pkgs,
    source ?
      if pkgs.stdenv.hostPlatform.system == "x86_64-darwin"
      then solanaSourceDarwin
      else solanaSource,
    src ?
      if builtins.pathExists (source + "/platform-tools-sdk/Cargo.toml")
      then source + "/platform-tools-sdk"
      else source,
  }: let
    toolchain = harbor-rs.lib.mkToolchain {inherit pkgs;};
    manifest = builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));
    commonArgs = {
      inherit src;
      cargoLock = src + "/Cargo.lock";
      pname = "cargo-build-sbf";
      version = assert manifest.workspace.package.version == solana.version; solana.version;
      cargoExtraArgs = "-p solana-cargo-build-sbf";
      rsHarborCargoTomlContents = builtins.readFile (src + "/Cargo.toml");
      doCheck = false;
      strictDeps = true;
      nativeBuildInputs = [pkgs.pkg-config];
      buildInputs = [pkgs.bzip2 pkgs.openssl];
    };
    # Agave 3 patches registry dependencies with real workspace crates; Crane's
    # dependency-only dummy sources cannot satisfy those path patches.
    cargoArtifacts =
      if builtins.pathExists (source + "/platform-tools-sdk/Cargo.toml")
      then toolchain.craneLib.buildDepsOnly commonArgs
      else null;
  in
    toolchain.craneLib.buildPackage (commonArgs // {inherit cargoArtifacts;});

  mkSolanaToolchain = {
    pkgs,
    anchor ? fixAnchor pkgs,
    solana ? fixSolanaCli pkgs,
    cargoBuildSbf ? mkCargoBuildSbf {inherit pkgs solana;},
    rustToolchain ? (harbor-rs.lib.mkToolchain {inherit pkgs;}).rustToolchain,
  }: let
    rustupToolchain = "harbor-sol-${builtins.substring 0 12 (builtins.hashString "sha256" (toString rustToolchain))}";
  in {
    packages = [pkgs.rustup anchor cargoBuildSbf solana rustToolchain];
    env = {
      ANCHOR_VERSION = anchor.version;
      SOLANA_VERSION = solana.version;
    };
    shellHook = ''
      export PATH="${pkgs.rustup}/bin:$PATH"
      export RUSTUP_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}/harbor-sol/rustup"
      mkdir -p "$RUSTUP_HOME"
      if ! ${pkgs.rustup}/bin/rustup toolchain list | grep -F ${rustupToolchain} >/dev/null; then
        ${pkgs.rustup}/bin/rustup toolchain link ${rustupToolchain} ${rustToolchain}
      fi
      ${pkgs.rustup}/bin/rustup default ${rustupToolchain} >/dev/null
    '';
  };

  mkSolanaDevShellFragment = args: let
    toolchain = mkSolanaToolchain args;
  in {
    inherit (toolchain) packages env shellHook;
  };

  mkSolanaDevShell = {
    pkgs,
    timeZone ? "UTC",
    ...
  } @ args:
    harbor-meta.lib.devShell.mkShell {
      inherit pkgs timeZone;
      fragments = [
        (mkSolanaDevShellFragment (builtins.removeAttrs args ["timeZone"]))
      ];
    };
}
