{
  nodejs,
  writeShellApplication,
}:
# No dependencies and node runs .ts natively (type stripping), so there is
# nothing to build: the script is the package.
writeShellApplication {
  name = "whisper-asr-shim";
  runtimeInputs = [nodejs];
  text = ''
    exec node ${./main.ts} "$@"
  '';
  meta.description = "whisper-asr-webservice's /asr API on top of a whisper.cpp server, for Bazarr";
}
