{
  system,
  inputs,
}: let
  config = {
    allowUnfree = true;
    checkMeta = true;
    warnUndeclaredOptions = true;
    # allow NixOS system config cross compilation
    allowUnsupportedSystem = true;
  };
in {
  inherit system config;
  overlays = let
    gimme = title: name: (_final: _prev: {
      ${name} = inputs.${name}.packages.${system}.${title};
    });
  in [
    inputs.nix-detsys.overlays.default
    (gimme "nix" "nix-detsys")
    
    (_: _: {
      _unstable = import inputs.nixpkgs-unstable {inherit system config;};
    })
  ];
}
