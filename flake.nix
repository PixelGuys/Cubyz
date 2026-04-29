{
  description = "Cubyz voxel game";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig_overlay.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
  };

  outputs = { self, nixpkgs, flake-utils, zig_overlay, zls, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        zig_version = "0.16.0";
        zig = zig_overlay.packages.${system}.${zig_version};

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
        ldLibraryPath = "${libPath}\${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}";
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ zig zls.packages.${system}.default ] ++ runtimeLibs;

          shellHook = ''
            export LD_LIBRARY_PATH="${ldLibraryPath}"
          '';
        };

        # Run the built project
        packages.default = pkgs.writeShellScriptBin "cubyz" ''
          export LD_LIBRARY_PATH="${ldLibraryPath}"
          exec "$PWD/zig-out/bin/Cubyz" "$@"
        '';
      }
    );
}
