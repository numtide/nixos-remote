{
  description = "A universal nixos installer, just needs ssh access to the target system";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = { url = "github:hercules-ci/flake-parts"; inputs.nixpkgs-lib.follows = "nixpkgs"; };
    disko = { url = "github:nix-community/disko/master"; inputs.nixpkgs.follows = "nixpkgs"; };
    # used for testing
    nixos-images.url = "github:nix-community/nixos-images";
  };


  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      imports = [
        ./src/flake-module.nix
        ./tests/flake-module.nix
        ./docs/flake-module.nix
      ];
    };
}
