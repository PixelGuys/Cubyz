{
  description = "Cubyz voxel game";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Libraries GLFW dynamically loads (dlopen) at runtime on Linux.
        runtimeLibs = with pkgs; [
          libX11
          libXcursor
          libXrandr
          libXi
          libXinerama
          libXxf86vm
          vulkan-loader
          libGL
        ];

        libPath = pkgs.lib.makeLibraryPath runtimeLibs;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ zig ] ++ runtimeLibs;

          shellHook = ''
            export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          '';
        };

        # Run after `zig build` from the project root: `nix run .#`
        packages.default = pkgs.writeShellScriptBin "cubyz" ''
          export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          exec "$PWD/zig-out/bin/Cubyz" "$@"
        '';
      }
    );
}
