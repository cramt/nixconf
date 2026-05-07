# Steam Link client for Raspberry Pi 4/5 (arm64).
#
# Valve never packaged Steam Link as a self-contained binary: the apt deb is a
# bootstrap shell script that downloads the actual Qt5/SDL3 runtime from
# media.steampowered.com on first launch. We skip that path entirely — fetch
# the runtime tarball at build time, autoPatchelf against nixpkgs deps mapped
# from the upstream steamlinkdeps.txt, and ship the udev rules so NixOS can
# install them via services.udev.packages.
#
# libavcodec.so.59 / libavutil.so.57 are ABI-locked (ffmpeg 5.x); nixpkgs only
# ships ffmpeg 6+, so we vendor those two .so files from Debian bookworm.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, dpkg
, glibc
, libdrm
, libglvnd
, libepoxy
, libGL
, libxkbcommon
, libinput
, libpng
, libjpeg
, libjpeg_turbo
, freetype
, fontconfig
, harfbuzz
, dbus
, glib
, double-conversion
, md4c
, mtdev
, icu72
, krb5
, zstd
, zlib
, wayland
, mesa
, ffmpeg_6
, libraspberrypi
, libX11
, libxcb
, libxkbfile
, libICE
, libSM
, libxcursor
, libxrandr
, libxrender
, libxfixes
, libxi
, libxext
, libxau
, libxdmcp
, libxcb-util
, libxcb-image
, libxcb-keysyms
, libxcb-render-util
, libxcb-wm
, libxshmfence
, openxr-loader
, sndio
, xorg
, libva
, librsvg
, cairo
, snappy
, libtheora
, gsm
, twolame
, rav1e
, shine
}:

let
  version = "1.3.25.302";
  codename = "bookworm";
  arch = "arm64";

  runtime = fetchurl {
    url = "https://media.steampowered.com/steamlink/rpi/${codename}/${arch}/steamlink-rpi-${codename}-${arch}-${version}.tar.gz";
    hash = "sha256-YOy0zU5ZbbLAtAgeMij1se2EGjaMT+L7gcEyhNEuxOw=";
  };

  # ffmpeg 5 .so files vendored from Debian bookworm — Steam Link's binaries
  # are ABI-locked to libavcodec.so.59 / libavutil.so.57 and nixpkgs only ships
  # ffmpeg 6+ (libavcodec.so.60+). Tracked separately so updating the upstream
  # ffmpeg in nixpkgs doesn't break the patchelf step.
  libavcodec59 = fetchurl {
    url = "http://deb.debian.org/debian/pool/main/f/ffmpeg/libavcodec59_5.1.8-0+deb12u1_arm64.deb";
    hash = "sha256-O1+QTKIC3KV6HTigZg8Ip0l3iIFE+1rFV7W2KLF4skE=";
  };
  libavutil57 = fetchurl {
    url = "http://deb.debian.org/debian/pool/main/f/ffmpeg/libavutil57_5.1.8-0+deb12u1_arm64.deb";
    hash = "sha256-KYdMGJXRNTWWgzUUBVIkueOC1FnDIsZxLSi+ibJ+iwo=";
  };
in
stdenv.mkDerivation {
  pname = "steamlink";
  inherit version;

  src = runtime;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper dpkg ];

  buildInputs = [
    stdenv.cc.cc.lib    # libstdc++.so.6, libgcc_s.so.1, libatomic.so.1
    glibc               # libc.so.6, libm.so.6
    libdrm              # libdrm.so.2
    libglvnd            # libEGL.so.1, libGLESv2.so.2, libOpenGL
    libepoxy            # libepoxy.so.0
    libGL               # libGL.so.1 (via libglvnd)
    libxkbcommon        # libxkbcommon.so.0, libxkbcommon-x11.so.0
    libinput            # libinput.so.10
    libpng              # libpng16.so.16
    libjpeg_turbo       # libjpeg.so.62
    freetype            # libfreetype.so.6
    fontconfig.lib      # libfontconfig.so.1
    harfbuzz            # libharfbuzz.so.0
    dbus.lib            # libdbus-1.so.3
    glib                # libglib-2.0.so.0, libgobject-2.0.so.0
    double-conversion   # libdouble-conversion.so.3
    md4c                # libmd4c.so.0
    mtdev               # libmtdev.so.1
    icu72               # libicui18n.so.72, libicuuc.so.72, libicudata.so.72
    krb5.lib            # libgssapi_krb5.so.2
    zstd.out            # libzstd.so.1
    zlib                # libz.so.1
    wayland             # libwayland-client.so.0, libwayland-egl.so.1
    mesa                # libgbm.so.1
    ffmpeg_6            # avcodec/avutil aliases — vendored .so.59/.57 take precedence
    libraspberrypi      # libbcm_host etc., for hw decode paths
    libX11
    libxcb
    libxkbfile
    libICE
    libSM
    libxcursor
    libxrandr
    libxrender
    libxfixes
    libxi
    libxext
    libxau
    libxdmcp
    libxcb-util
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-wm
    libxshmfence
    openxr-loader
    sndio
    xorg.libXtst
    libva
    librsvg
    cairo
    snappy
    libtheora
    gsm
    twolame
    rav1e
    shine
  ];

  # Vendored Debian bookworm ffmpeg 5 .so files link against codec sonames that
  # don't exist in nixpkgs (version-locked to bookworm's ABI). These are optional
  # codec paths — steamlink only needs h264/hevc for game streaming.
  autoPatchelfIgnoreMissingDeps = [
    "libvpx.so.7"
    "libdav1d.so.6"
    "libjxl.so.0.7"
    "libjxl_threads.so.0.7"
    "libx265.so.199"
    "libSvtAv1Enc.so.1"
    "libcodec2.so.1.0"
    "libsteam_api.so"
    "libGLES_CM.so.1"
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xzf $src
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild

    # Vendor libavcodec.so.59 and libavutil.so.57 from Debian bookworm.
    # autoPatchelfHook will pick them up via addAutoPatchelfSearchPath.
    mkdir -p vendored-ffmpeg5
    dpkg-deb -x ${libavcodec59} ffmpeg5-extract
    dpkg-deb -x ${libavutil57} ffmpeg5-extract
    cp -P ffmpeg5-extract/usr/lib/aarch64-linux-gnu/libav*.so* vendored-ffmpeg5/

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share $out/bin $out/lib/udev/rules.d $out/lib/modules-load.d

    cp -r steamlink $out/share/steamlink

    # Bypass the script's Debian arch check — we are arm64 but `dpkg` won't be
    # on PATH and even if it were, /etc/os-release won't say "bookworm".
    touch $out/share/steamlink/.ignore_arch

    # Drop in vendored ffmpeg5 libs alongside the bundled libs so the launcher's
    # LD_LIBRARY_PATH ($TOP/lib) picks them up.
    cp -P vendored-ffmpeg5/libav*.so* $out/share/steamlink/lib/

    # Neutralize the in-script apt-based dep installer and the udev-rules
    # bootstrap (we install udev rules via NixOS instead).
    substituteInPlace $out/share/steamlink/steamlink.sh \
      --replace-fail '"$STEAMDEPS" "$TOP/steamlinkdeps-$VERSION_CODENAME.txt"' 'true' \
      --replace-fail '"$STEAMDEPS" "$TOP/steamlinkdeps.txt"' 'true' \
      --replace-fail 'UDEV_RULES_DIR=/lib/udev/rules.d' 'UDEV_RULES_DIR=/run/current-system/sw/lib/udev/rules.d'

    # Ship udev rules + uinput modules-load fragment for NixOS to consume.
    cp $out/share/steamlink/udev/rules.d/56-steamlink.rules $out/lib/udev/rules.d/
    cp $out/share/steamlink/udev/modules-load.d/uinput.conf $out/lib/modules-load.d/

    # Wrapper that points Qt at the bundled plugins, exports the bundled Qt/SDL
    # library path, and forwards to the upstream launcher with --skip-update so
    # it never reaches out to media.steampowered.com behind our backs.
    makeWrapper $out/share/steamlink/steamlink.sh $out/bin/steamlink \
      --add-flags "--skip-update" \
      --set-default QT_QPA_PLATFORM xcb \
      --prefix LD_LIBRARY_PATH : "$out/share/steamlink/lib:$out/share/steamlink/Qt-5.14.1/lib"

    runHook postInstall
  '';

  # autoPatchelfHook scans buildInputs for SONAMEs but won't find the bundled
  # SDL3/Qt/libsteamwebrtc or the vendored ffmpeg 5 .so files unless we point
  # it at them explicitly. preFixup runs before autoPatchelfHook's hook in
  # fixupPhase, so the search path is in place when patching happens.
  preFixup = ''
    addAutoPatchelfSearchPath $out/share/steamlink/lib
    addAutoPatchelfSearchPath $out/share/steamlink/Qt-5.14.1/lib
  '';

  dontStrip = true;

  meta = with lib; {
    description = "Valve Steam Link client (Raspberry Pi 4/5 arm64 build)";
    homepage = "https://store.steampowered.com/app/353380";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "steamlink";
  };
}
