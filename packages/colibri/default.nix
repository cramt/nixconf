{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  symlinkJoin,
  writeShellScriptBin,
  python3,
  nix-update-script,
  # --- optional GPU tiers ----------------------------------------------------
  # Both default off. The CPU engine is the portable baseline; the GPU builds
  # are cache misses by construction (nothing upstream builds them), so they get
  # opted into per host and prebuilt into cachix by CI, exactly like the
  # llama-cpp-rocm-rpc / llama-cpp-cuda-rpc overrides in overlays/default.nix.
  rocmSupport ? false,
  rocmPackages,
  # gfx1101 = Navi 32 = saturn's RX 7800 XT. This is NOT optional metadata:
  # backend_gpu_compat.h hard-`#error`s without rocWMMA headers on any gfx11xx
  # target, because RDNA3 has WMMA matrix cores that the HIP backend maps CUDA's
  # nvcuda::wmma onto. Building for a non-WMMA arch needs NO_WMMA_ARCHS instead.
  rocmGpuTarget ? "gfx1101",
  vulkanSupport ? false,
  vulkan-loader,
  vulkan-headers,
  shaderc,
  # -march for the engine kernels. MUST be set explicitly and MUST NOT be
  # "native": the Linux x86_64 branch of upstream's Makefile hardcodes
  # -march=native, nix's cc-wrapper strips it under NIX_ENFORCE_NO_NATIVE, and
  # the build then silently falls back to baseline x86-64 — i.e. no AVX2 at all
  # in a matmul engine, with nothing but a passing build to show for it.
  #
  # x86-64-v3 (AVX2+FMA+BMI, Haswell 2013 and newer) is upstream's own portable
  # default on the platforms where they set one. Bump this to a concrete arch
  # (e.g. "alderlake") to also get the AVX-VNNI VPDPBUSD int8/int4 dot kernels,
  # which the v3 baseline compiles out — worth doing once the target CPU is
  # known, since it only ever runs on hosts we control.
  march ? "x86-64-v3",
}: let
  # The Makefile's Linux HIP contract is a single ROCM_HOME prefix holding
  # bin/hipcc, lib/libamdhip64.so and the hip/ + rocwmma/ headers. nixpkgs
  # splits those across derivations, so join them into the layout it expects
  # rather than patching the Makefile.
  rocmHome = symlinkJoin {
    name = "colibri-rocm-home";
    paths = with rocmPackages; [
      clr
      hipcc
      hip-common
      rocwmma
      rocm-core
      # Not optional and not obvious: hipcc is clang, and clang locates the
      # amdgcn device bitcode by walking up from its own argv[0] to
      # <prefix>/amdgcn/bitcode. Leave this out of the join and every compile
      # dies with "cannot find ROCm device library" even though hipcc, the HIP
      # headers and rocWMMA are all present.
      rocm-device-libs
    ];
  };

  # ...and having the bitcode inside the join still isn't enough: clang finds
  # its ROCm prefix by resolving argv[0], which follows the symlink straight
  # back to clr's own store path, so the join is never consulted. Point it at
  # both explicitly.
  #
  # This wraps the COMPILER (HIPCC ?=) rather than overriding HIPCCFLAGS (also
  # ?=) on purpose: a command-line HIPCCFLAGS would win over the Makefile's own
  # `HIPCCFLAGS +=` lines and silently drop the --offload-arch and
  # -DCOLI_HIP_NO_WMMA logic that decides which kernels get compiled at all.
  # The -I is load-bearing for the same reason: backend_gpu_compat.h gates the
  # matrix-core path on `__has_include(<rocwmma/rocwmma.hpp>)` and hard-#errors
  # when it misses, and --rocm-path does not put the join's include/ on the
  # search path. Without it a gfx1101 build fails outright rather than quietly
  # losing WMMA — which is the good outcome, but only because upstream #errors.
  hipccWrapper = writeShellScriptBin "hipcc" ''
    exec ${rocmHome}/bin/hipcc \
      --rocm-path=${rocmHome} \
      --rocm-device-lib-path=${rocmPackages.rocm-device-libs}/amdgcn/bitcode \
      -I${rocmHome}/include \
      "$@"
  '';
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "colibri";
    version = "1.6.2";

    src = fetchFromGitHub {
      owner = "JustVugg";
      repo = "colibri";
      tag = "v${finalAttrs.version}";
      hash = "sha256-CPmu9e6feNNaukkx1NOJOpc6s5Q/ZkXlOPMaZtwbxjs=";
    };

    # The engine, its Makefile and the `coli` launcher all live in c/.
    sourceRoot = "${finalAttrs.src.name}/c";

    # `coli` finds its engines and python modules at
    # dirname(abspath(__file__))/../libexec/colibri. abspath does NOT resolve
    # symlinks, so when it is invoked as /run/current-system/sw/bin/coli — a
    # symlink into a buildEnv that only links /bin and /share, never /libexec —
    # it looks for /run/current-system/sw/libexec/colibri and dies with
    # "ModuleNotFoundError: No module named 'doctor'". realpath resolves to the
    # store bin/, whose parent really does contain libexec/colibri.
    #
    # Upstream-reportable: any packager using a symlink farm hits this, which is
    # every distro that isn't installing straight into /usr/local.
    postPatch = ''
      substituteInPlace coli \
        --replace-fail 'os.path.dirname(os.path.abspath(__file__))' \
                       'os.path.dirname(os.path.realpath(__file__))'
    '';

    # python3 is deliberately in BOTH lists. The build needs it (tools/clean.py,
    # the deepseek-v4 sub-make), and `coli` is a `#!/usr/bin/env python3` script
    # that spawns openai_server.py via sys.executable — so it must also be a
    # *host* input, or patchShebangs --host silently leaves the env shebang
    # alone and every `coli` invocation dies with "env: python3: not found".
    nativeBuildInputs =
      [makeWrapper python3]
      ++ lib.optionals vulkanSupport [shaderc];

    buildInputs =
      [python3]
      # vulkan-headers is separate from the loader in nixpkgs: without it the
      # link flags resolve fine and backend_vulkan.c still fails on
      # `#include <vulkan/vulkan.h>`.
      ++ lib.optionals vulkanSupport [vulkan-loader vulkan-headers];

    makeFlags =
      [
        "PREFIX=${placeholder "out"}"
        # Threaded through to Makefile.deepseek-v4 too (the parent's
        # deepseek-v4 target forwards ARCH=$(ARCH)), so all three engines get
        # the same ISA baseline.
        "ARCH=${march}"
      ]
      ++ lib.optionals rocmSupport [
        "HIP=1"
        "HIP_ARCH=${rocmGpuTarget}"
        "ROCM_HOME=${rocmHome}"
        "HIPCC=${hipccWrapper}/bin/hipcc"
      ]
      ++ lib.optionals vulkanSupport [
        "VK=1"
        # shaderc is multi-output and glslc lives in its `bin` output, not the
        # default one — ${shaderc}/bin/glslc simply does not exist, and the
        # Makefile's `command -v` guard reports it as "install shaderc".
        "GLSLC=${lib.getBin shaderc}/bin/glslc"
      ];

    # `make install` already depends on colibri, olmoe and (when the toolchain
    # supports it) deepseek-v4, so the install phase drives the whole build and
    # a separate buildPhase would just compile everything twice.
    dontBuild = true;

    # ...which means the compiling happens in installPhase, and that is the one
    # stdenv serialises by default. Without this the whole build is -j1.
    enableParallelBuilding = true;
    enableParallelInstalling = true;

    postInstall =
      ''
        # openai_server.py does a module-level `import v4_dsml`, but the install
        # target never copies v4_dsml.py into LIBEXECDIR — so `coli serve` and
        # `coli web` ImportError on EVERY model, not just DeepSeek V4. Upstream
        # hit the identical gap in their release tarball and fixed only that
        # path, leaving `make install` still broken:
        # https://github.com/JustVugg/colibri/commit/90894cd63cd89c9bdd492430234bdb353cb8228b
        # Remove this line once `grep v4_dsml c/Makefile` matches the install
        # target.
        install -m 644 v4_dsml.py $out/libexec/colibri/v4_dsml.py
      ''
      + lib.optionalString rocmSupport ''
        # resource_plan.py discovers NVIDIA via nvidia-smi and AMD via rocm-smi,
        # in that order. With neither on PATH it silently plans CPU-only and
        # `coli doctor` reports "no supported GPU detected / no NVIDIA device
        # detected" on a machine whose engine is a perfectly good HIP build — so
        # the whole VRAM tier goes unused and the plan under-reports residency.
        #
        # Upstream marks _discover_amd_gpus "hardware-owner-needed ... authored
        # without a ROCm host to test against" (#662), so if this still
        # mis-detects on gfx1101, that is worth reporting back rather than
        # working around.
        wrapProgram $out/bin/coli \
          --prefix PATH : ${lib.makeBinPath [rocmPackages.rocm-smi]}
      ''
      + lib.optionalString vulkanSupport ''
        # backend_vulkan.c loads the compute shaders at runtime from
        # $COLI_VK_SHADERS, defaulting to a shaders/ dir next to the *engine*
        # binary (which lives in libexec, not bin). Install them there and pin
        # the variable anyway so the lookup can't depend on argv[0] resolution.
        install -Dm644 -t $out/libexec/colibri/shaders shaders/*.spv
        wrapProgram $out/bin/coli \
          --set-default COLI_VK_SHADERS $out/libexec/colibri/shaders
      '';

    # Cheap guard against the two ways this package silently ships broken: an
    # unpatched `#!/usr/bin/env python3` shebang, and a libexec that the
    # launcher can't find (it resolves engines as ../libexec/colibri relative to
    # its own path, so any bin/ wrapping has to preserve that layout).
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/coli --help > /dev/null

      # Invoke through a symlink farm that mimics environment.systemPackages:
      # only /bin linked, no /libexec. Calling $out/bin/coli directly cannot
      # catch the abspath-vs-realpath bug postPatch fixes, because in-store the
      # broken lookup happens to land on the right directory anyway. `doctor`
      # specifically, since it imports a module out of libexec rather than just
      # exec'ing an engine.
      mkdir -p "$TMPDIR/farm/bin"
      ln -s "$out/bin/coli" "$TMPDIR/farm/bin/coli"
      "$TMPDIR/farm/bin/coli" --help > /dev/null
      # doctor exits non-zero with no model present, which is fine — we only
      # care that it got far enough to import. Redirect to a file rather than
      # piping into grep, same pipefail/SIGPIPE reason as the AVX2 check below.
      "$TMPDIR/farm/bin/coli" doctor > "$TMPDIR/doctor.log" 2>&1 || true
      if grep -q "ModuleNotFoundError" "$TMPDIR/doctor.log"; then
        echo "colibri: launcher cannot resolve libexec when invoked via a symlink" >&2
        cat "$TMPDIR/doctor.log" >&2
        exit 1
      fi
      rm -rf "$TMPDIR/farm" "$TMPDIR/doctor.log"

      # Assert the vector ISA actually landed. Stripping -march is a *warning*
      # in cc-wrapper, so a baseline-SSE2 build of a matmul engine otherwise
      # succeeds, installs, and just runs several times slower forever. Every
      # supported `march` value here is v3 or better, so AVX2 encodings must be
      # present in all three engines.
      #
      # Disassemble to a FILE rather than piping into `grep -q`. grep -q exits at
      # the first match, which SIGPIPEs objdump mid-write, and stdenv/setup.sh
      # runs with `set -o pipefail` — so the pipeline reports 141 and this
      # assertion fires on a binary that is completely fine. Whether objdump has
      # finished writing before grep bails is a race, so it passed locally and
      # failed in CI on a byte-identical derivation. Against a file there is no
      # pipe, and a genuinely broken objdump now trips `set -e` instead of
      # masquerading as a missing-AVX2 result.
      for engine in colibri deepseek_v4 olmoe; do
        objdump -d "$out/libexec/colibri/$engine" > disasm-check.txt
        if ! grep -qE 'vfmadd|ymm' disasm-check.txt; then
          echo "colibri: $engine has no AVX2 instructions — -march=${march} did not reach the compiler" >&2
          exit 1
        fi
      done
      rm -f disasm-check.txt
      runHook postInstallCheck
    '';

    passthru.updateScript = nix-update-script {};

    meta = {
      homepage = "https://github.com/JustVugg/colibri";
      description = "Streaming inference engine for frontier MoE models on consumer hardware";
      longDescription = ''
        Treats VRAM, RAM and storage as one tiered hierarchy and streams routed
        MoE experts off disk on demand, so a 744B-parameter model needs its
        weights *placed* rather than resident. Pure C with no engine
        dependencies; python is used only by the one-time weight converter and
        the optional OpenAI-compatible gateway.

        Upstream ships a sibling engine per model family, each its own make
        target; this package builds the three that `make install` covers —
        GLM-5.2 (744B/40B), DeepSeek V4 Flash (284B/13B) and OLMoE (7B/1B).
        Inkling and Kimi K3 have their own targets and are not built here.
        The `coli` launcher picks the engine from the model's config.json.

        Throughput is set by disk bandwidth, not compute.
      '';
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
      mainProgram = "coli";
    };
  })
