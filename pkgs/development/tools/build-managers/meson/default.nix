{ lib
, python3Packages
, stdenv
, writeTextDir
, substituteAll
, targetPackages
}:

let
  # See https://mesonbuild.com/Reference-tables.html#cpu-families
  cpuFamilies = {
    aarch64  = "aarch64";
    armv5tel = "arm";
    armv6l   = "arm";
    armv7l   = "arm";
    i686     = "x86";
    x86_64   = "x86_64";
  };
in
python3Packages.buildPythonApplication rec {
  pname = "meson";
  version = "0.53.2";

  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "Po+DDzMYQ5fC6wtlHsUCrbY97LKJeL3ISzVY1xKEwh8=";
  };

  postFixup = ''
    pushd $out/bin
    # undo shell wrapper as meson tools are called with python
    for i in *; do
      mv ".$i-wrapped" "$i"
    done
    popd

    # Do not propagate Python
    rm $out/nix-support/propagated-build-inputs
  '';

  patches = [
    # Upstream insists on not allowing bindir and other dir options
    # outside of prefix for some reason:
    # https://github.com/mesonbuild/meson/issues/2561
    # We remove the check so multiple outputs can work sanely.
    ./allow-dirs-outside-of-prefix.patch

    # Unlike libtool, vanilla Meson does not pass any information
    # about the path library will be installed to to g-ir-scanner,
    # breaking the GIR when path other than ${!outputLib}/lib is used.
    # We patch Meson to add a --fallback-library-path argument with
    # library install_dir to g-ir-scanner.
    ./gir-fallback-path.patch

    # In common distributions, RPATH is only needed for internal libraries so
    # meson removes everything else. With Nix, the locations of libraries
    # are not as predictable, therefore we need to keep them in the RPATH.
    # At the moment we are keeping the paths starting with /nix/store.
    # https://github.com/NixOS/nixpkgs/issues/31222#issuecomment-365811634
    (substituteAll {
      src = ./fix-rpath.patch;
      inherit (builtins) storeDir;
    })
  ];

  setupHook = ./setup-hook.sh;

  crossFile = writeTextDir "cross-file.conf" ''
    [binaries]
    c = '${targetPackages.stdenv.cc.targetPrefix}cc'
    cpp = '${targetPackages.stdenv.cc.targetPrefix}c++'
    ar = '${targetPackages.stdenv.cc.bintools.targetPrefix}ar'
    strip = '${targetPackages.stdenv.cc.bintools.targetPrefix}strip'
    pkgconfig = 'pkg-config'
    ld = '${targetPackages.stdenv.cc.targetPrefix}ld'
    objcopy = '${targetPackages.stdenv.cc.targetPrefix}objcopy'

    [properties]
    needs_exe_wrapper = true

    [host_machine]
    system = '${targetPackages.stdenv.targetPlatform.parsed.kernel.name}'
    cpu_family = '${cpuFamilies.${targetPackages.stdenv.targetPlatform.parsed.cpu.name}}'
    cpu = '${targetPackages.stdenv.targetPlatform.parsed.cpu.name}'
    endian = ${if targetPackages.stdenv.targetPlatform.isLittleEndian then "'little'" else "'big'"}
  '';

  # 0.45 update enabled tests but they are failing
  doCheck = false;
  # checkInputs = [ ninja pkgconfig ];
  # checkPhase = "python ./run_project_tests.py";

  inherit (stdenv) cc;

  isCross = stdenv.targetPlatform != stdenv.hostPlatform;

  meta = with lib; {
    homepage = https://mesonbuild.com;
    description = "SCons-like build system that use python as a front-end language and Ninja as a building backend";
    license = licenses.asl20;
    maintainers = with maintainers; [ mbe rasendubi ];
    platforms = platforms.all;
  };
}
