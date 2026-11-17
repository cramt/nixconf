{
  nodejs,
  openssh,
  rsync,
  unzip,
  writeShellApplication,
}:
# No dependencies and node runs .ts natively (type stripping), so there is
# nothing to build: the script is the package.
writeShellApplication {
  name = "bs-sync";
  runtimeInputs = [nodejs openssh rsync unzip];
  text = ''
    exec node ${./main.ts} "$@"
  '';
  meta.description = "Match a Spotify (Exportify CSV) or .bplist playlist to BeatSaver maps and rsync them to a standalone Beat Saber install";
}
