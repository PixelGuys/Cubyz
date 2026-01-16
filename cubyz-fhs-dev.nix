{ pkgs ? import <nixpkgs> {} }:
pkgs.buildFHSEnv {
  name = "cubyz-fhs-dev";
  
  targetPkgs = p: with p; [
    xorg.libX11
    xorg.libXcursor
    xorg_sys_opengl
    libGL
    alsa-lib
    vulkan-loader
    vulkan-validation-layers
    vulkan-tools
    bash
  ];

  runScript = ''
    bash "$@"
  '';
}
