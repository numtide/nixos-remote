{
  perSystem = { pkgs, lib, ... }: {
    packages.docs = pkgs.runCommand "nixos-remote-docs"
      {
        passthru.serve = pkgs.writeShellScriptBin "serve" ''
          cd docs
          ${lib.getExe pkgs.mdbook} serve --dest-dir $(${pkgs.coreutils}/bin/mktemp -d)
        '';
      }
      ''
        cp -r ${lib.cleanSource ./.}/* .
        ${lib.getExe pkgs.mdbook} build --dest-dir "$out"
      '';
  };
}
