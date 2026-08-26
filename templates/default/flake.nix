{
  description = "Anchor project powered by harbor-sol";

  inputs = {
    harbor-sol.url = "github:caniko/harbor-sol";
    nixpkgs.follows = "harbor-sol/nixpkgs";
  };

  outputs = {
    harbor-sol,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  in {
    devShells = nixpkgs.lib.genAttrs systems (system: {
      default = harbor-sol.lib.mkSolanaDevShell {
        pkgs = import nixpkgs {
          inherit system;
          overlays = [harbor-sol.lib.rustOverlay];
        };
      };
    });

    formatter = nixpkgs.lib.genAttrs systems (system: (import nixpkgs {inherit system;}).alejandra);
  };
}
