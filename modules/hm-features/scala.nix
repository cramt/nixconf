{ ... }: {
  hmModules.features.scala = { config, lib, pkgs, ... }: {
    options.myHomeManager.scala.enable = lib.mkEnableOption "myHomeManager.scala";
    config = lib.mkIf config.myHomeManager.scala.enable {
      # Metals is a JVM app and reads JAVA_HOME, which programs.java sets.
      myHomeManager.java.enable = true;

      home.packages = with pkgs; [
        # The Zed extension resolves metals with `worktree.which("metals")` and
        # ignores lsp.metals.binary.path, so it has to be on the session PATH:
        # https://github.com/scalameta/metals-zed/blob/main/src/lib.rs
        metals
        sbt
        scala-cli
        coursier
      ];
    };
  };
}
