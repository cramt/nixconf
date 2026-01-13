{
  stdenv,
  swift,
  version,
  src,
  lib,
  ...
}:
stdenv.mkDerivation {
  pname = "codexbar-cli";
  inherit version src;

  buildInputs = [ swift ];

  unpackPhase = ''
    echo "CUSTOM UNPACKPHASE: src=$src"
    echo "ISDIR: $( [ -d \"$src\" ] && echo yes || echo no )"
    echo "ISFILE: $( [ -f \"$src\" ] && echo yes || echo no )"
    mkdir -p source
    if [ -d "$src" ]; then
      echo "Copying directory contents from $src to source"
      cp -r "$src"/. source/
    elif [ -f "$src" ]; then
      echo "Extracting tarball $src"
      tar -xzf "$src" -C source || true
    else
      echo "No source found at $src" >&2
    fi
    echo "Contents of source:"
    ls -la source || true
  '';

  buildPhase = ''
    set -e
    cd source
    swift build -c release --product CodexBarCLI --static-swift-stdlib || swift build -c release --product CodexBarCLI
  '';

  installPhase = ''
    mkdir -p "$out/bin"

    if [ -x "$source/.build/release/CodexBarCLI" ]; then
      cp "$source/.build/release/CodexBarCLI" "$out/bin/codexbar"
    elif [ -x "$source/.build/x86_64-unknown-linux-gnu/release/CodexBarCLI" ]; then
      cp "$source/.build/x86_64-unknown-linux-gnu/release/CodexBarCLI" "$out/bin/codexbar"
    elif [ -x "$source/.build/aarch64-unknown-linux/release/CodexBarCLI" ]; then
      cp "$source/.build/aarch64-unknown-linux/release/CodexBarCLI" "$out/bin/codexbar"
    else
      cp -v "$source"/bin/* "$out/bin/" || true
      if [ -f "$out/bin/CodexBarCLI" ]; then
        mv "$out/bin/CodexBarCLI" "$out/bin/codexbar" || true
      fi
      if [ ! -f "$out/bin/codexbar" ]; then
        exe=$(find "$source" -maxdepth 3 -type f -executable -print -quit || true)
        if [ -n "$exe" ]; then
          cp "$exe" "$out/bin/codexbar" || true
        fi
      fi
    fi

    chmod +x "$out/bin/codexbar" || true
  '';

  meta = with lib; {
    description = "CodexBarCLI (Linux CLI for tracking AI tool usage limits)";
    homepage = "https://github.com/steipete/CodexBar";
    platforms = platforms.linux;
  };
}
