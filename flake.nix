{
  description = "vibe — parallel feature worktrees for any git repo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };

      vibe = pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "vibe";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 vibe "$out/bin/vibe"
            # Guarantee the basics exist, but as a PATH *suffix* so the user's own
            # git/gh/docker/nix/$SHELL still take precedence (vibe drives the ambient env).
            wrapProgram "$out/bin/vibe" \
              --set-default VIBE_PROG vibe \
              --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.gnused ]}
            runHook postInstall
          '';
          meta = {
            description = "Parallel feature worktrees for any git repo (new/ls/cd/pull/finish)";
            homepage = "https://github.com/guilhermeprokisch/vibe";
            license = pkgs.lib.licenses.mit;
            mainProgram = "vibe";
            platforms = pkgs.lib.platforms.unix;
          };
        };
    in
    {
      packages = forAll (system:
        let pkgs = pkgsFor system; in {
          vibe = vibe pkgs;
          default = vibe pkgs;
        });

      # For consumers who prefer an overlay: final.vibe
      overlays.default = _final: prev: { vibe = vibe prev; };
    };
}
