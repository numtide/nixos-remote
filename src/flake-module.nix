{
  perSystem = { pkgs, ... }: {
    packages = rec {
      nixos-remote = pkgs.callPackage ./. { };
      default = nixos-remote;
    };
  };
}
