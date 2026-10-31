{
  nodejs,
  writeShellApplication,
}:
# No dependencies and node runs .ts natively (type stripping), so there is
# nothing to build: the script is the package.
writeShellApplication {
  name = "alert-dm";
  runtimeInputs = [nodejs];
  text = ''
    exec node ${./main.ts} "$@"
  '';
  meta.description = "Alertmanager webhook receiver that DMs each alert over Discord";
}
