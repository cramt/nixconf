# Builds a Zed extension into the exact directory layout Zed keeps under
# ~/.local/share/zed/extensions/installed/<id>, so home-manager can symlink it
# in instead of you running `zed: install dev extension` by hand. For
# extensions that aren't in Zed's registry, this is the only declarative route.
#
# Zed normally does this itself at install time, which on NixOS means shelling
# out to rustup for the wasm32-wasip2 target and downloading a prebuilt
# wasi-sdk to compile the tree-sitter parsers. Here fenix supplies the former
# and pkgsCross.wasi32 the latter, so nothing is fetched at editor runtime.
{
  lib,
  stdenv,
  formats,
  rustPlatform,
  pkgsCross,
  writeText,
  rustToolchain,
}: {
  # Extension repo checkout (the one holding extension.toml).
  src,
  # Grammar name -> { src; rev; }. `rev` is the revision `src` was pinned at;
  # it is checked against what extension.toml declares.
  grammars ? {},
}: let
  manifest = builtins.fromTOML (builtins.readFile "${src}/extension.toml");
  cargoLockPath = "${src}/Cargo.lock";
  isRust = builtins.pathExists cargoLockPath;

  # Zed accepts either spelling for the pinned grammar revision.
  declaredRev = g: g.commit or g.rev;

  # extension.toml names the revision the queries were written against; the
  # npins pin is what actually gets compiled. `npins update` moving one without
  # the other would silently ship queries that don't match the parser, so make
  # the mismatch a build failure rather than a subtly broken editor.
  revMismatches = lib.filterAttrs (name: g: declaredRev manifest.grammars.${name} != g.rev) grammars;

  apiVersion =
    if !isRust
    then null
    else
      (lib.findFirst (p: p.name == "zed_extension_api")
        (throw "${manifest.id}: zed_extension_api missing from Cargo.lock")
        (builtins.fromTOML (builtins.readFile cargoLockPath)).package)
      .version;

  # Zed derives these when it builds an extension. A manifest without them
  # parses fine but loads neither the language nor the wasm, so the extension
  # silently does nothing.
  normalisedManifest =
    manifest
    // {
      languages =
        map (d: "languages/${d}")
        (builtins.attrNames (builtins.readDir "${src}/languages"));
    }
    // lib.optionalAttrs isRust {
      lib = {
        kind = "Rust";
        version = apiVersion;
      };
    };

  # nixpkgs' wasilibc carries thread support that wasi-sdk's does not, so the
  # reactor startup leaves `__wasi_init_tp` as an *import*. Zed's tree-sitter
  # WasmStore only supplies the four dylink symbols and rejects the module with
  # "invalid import '__wasi_init_tp'". Defining a no-op locally keeps the
  # import list identical to a wasi-sdk build; tree-sitter parsers are
  # single-threaded and never touch the thread pointer.
  tpStub = writeText "wasi-init-tp-stub.c" "void __wasi_init_tp(void) {}";

  wasiCc = "${pkgsCross.wasi32.stdenv.cc}/bin/${pkgsCross.wasi32.stdenv.cc.targetPrefix}clang";
  # The cc wrapper shells out to wasm-ld, which lives only in the unwrapped
  # llvm-binutils, not in the bintools wrapper.
  wasiBinPath = lib.makeBinPath [
    pkgsCross.wasi32.stdenv.cc.bintools
    pkgsCross.wasi32.stdenv.cc.bintools.bintools
  ];

  compileGrammar = name: g: let
    root = "${g.src}/${manifest.grammars.${name}.path or "."}";
  in ''
    PATH="${wasiBinPath}:$PATH" ${wasiCc} -fPIC -shared -Os \
      -Wl,--export=tree_sitter_${name} \
      -o $out/grammars/${name}.wasm \
      -I ${root}/src ${root}/src/parser.c ${tpStub} \
      $(test -f ${root}/src/scanner.c && echo ${root}/src/scanner.c || true)
  '';
in
  assert lib.assertMsg (revMismatches == {}) ''
    ${manifest.id}: pinned grammar revision does not match extension.toml:
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: g: "  ${name}: extension.toml wants ${declaredRev manifest.grammars.${name}}, npins pins ${g.rev}") revMismatches)}
    Re-pin the grammar at the revision extension.toml names, or bump both together.
  '';
    stdenv.mkDerivation ({
        inherit src;
        pname = "zed-${manifest.id}";
        inherit (manifest) version;

        buildPhase =
          ''
            runHook preBuild
            mkdir -p $out/grammars
          ''
          + lib.optionalString isRust ''
            cargo build --release --offline --target wasm32-wasip2
          ''
          + lib.concatStrings (lib.mapAttrsToList compileGrammar grammars)
          + ''
            runHook postBuild
          '';

        installPhase = ''
          runHook preInstall
          cp ${(formats.toml {}).generate "extension.toml" normalisedManifest} $out/extension.toml
          cp -r languages $out/languages
          ${lib.optionalString isRust "cp target/wasm32-wasip2/release/*.wasm $out/extension.wasm"}
          for d in themes icon_themes; do
            test -d "$d" && cp -r "$d" "$out/$d" || true
          done
          runHook postInstall
        '';

        passthru.extensionId = manifest.id;

        meta = {
          description = "${manifest.name} extension for Zed, prebuilt into Zed's installed-extension layout";
          homepage = manifest.repository or null;
          platforms = lib.platforms.linux;
        };
      }
      // lib.optionalAttrs isRust {
        cargoDeps = rustPlatform.importCargoLock {lockFile = cargoLockPath;};
        nativeBuildInputs = [rustPlatform.cargoSetupHook rustToolchain];
      })
