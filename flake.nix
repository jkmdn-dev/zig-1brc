{
  description = "A Nix-flake-based Zig development environment";

  inputs = {
    nixpkgs = { url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz"; };
    zig-overlay = { url = "github:mitchellh/zig-overlay"; };
    zls-overlay = { url = "github:zigtools/zls"; };
  };

  outputs = { self, nixpkgs, zig-overlay, zls-overlay }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f:
        nixpkgs.lib.genAttrs supportedSystems (system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [
                (final: prev:
                  let
                    zig = zig-overlay.packages.${system}.master;
                    zls = zls-overlay.packages.${system}.zls.overrideAttrs {
                      nativeBuildInputs = [ zig ];
                    };
                  in { inherit zig zls; })
              ];
            };
          });
    in {
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell { packages = with pkgs; [ zig zls ]; };
      });
    };
}
