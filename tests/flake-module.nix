{ withSystem, inputs, ... }:

{
  flake.checks.x86_64-linux = withSystem "x86_64-linux" ({ pkgs, system, inputs', config, ... }:
    let
      testInputs = {
        inherit pkgs;
        inherit (inputs.disko.nixosModules) disko;
        nixos-remote = config.packages.nixos-remote;
        kexec-installer = "${inputs'.nixos-images.packages.kexec-installer-nixos-unstable}/nixos-kexec-installer-${system}.tar.gz";
      };
    in
    {
      from-nixos = import ./from-nixos.nix testInputs;
      from-nixos-with-sudo = import ./from-nixos-with-sudo.nix testInputs;
    });
}
