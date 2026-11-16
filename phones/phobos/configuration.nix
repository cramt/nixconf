# Alex's phone, managed by Nixup (modules/flake/phones.nix). The fleet bits
# (tailscale on headscale, ssh) come from nixupModules; this file is only what's
# specific to the phone. Anything left unset stays as set by hand on the phone.
#
# Once it's rooted, `nix run --inputs-from . nixup#nixup-config -- create` writes
# a config from what it has now (apps, settings, debloat list); merge the parts
# worth keeping into here. Every option, with comments:
# https://github.com/by-architect/Nixup/blob/main/templates/default/configuration.nix
{ pkgs, ... }:
{
  time.timeZone = "Europe/Copenhagen";

  # Apps by repo, as package-name strings. Not pkgs.fdroid.<name>: those come
  # from the index the phone downloads, so they'd only evaluate under
  # nixup-rebuild. A typo here fails on the phone's build instead, before it
  # changes anything. Play Store apps need android.playstore.tokenFile
  # (nix run .#nixup-play-login).
  # android.packages.fdroid = [ "org.fdroid.fdroid" ];
  # android.packages.playstore = [ ];

  # Straight from GitHub releases, newest one each build.
  android.packages.obtainium = [
    {
      # The Android client only ships in the nightly pre-releases so far.
      id = "com.t3tools.t3code";
      url = "https://github.com/pingdotgg/t3code";
      prerelease = true;
      apkFilter = "^t3code-android-.*\\.apk$";
    }
  ];

  # YouTube and Reddit with Morphe's patches, from j-hc's CI by way of my-nixpkgs
  # (hash-pinned there and bumped by its updater). The non-root APKs: Nixup can't
  # install a Magisk module, and Reddit only ships as an APK.
  myNixup.apks = with pkgs.revanced-magisk-module.apps; {
    # Beside stock YouTube under its own name, signing in through microG.
    "app.morphe.android.youtube" = youtube.apk;
    # Reddit's own package name, so stock Reddit must be uninstalled first:
    # Android won't replace it with a differently signed APK.
    "com.reddit.frontpage" = reddit.apk;
    ${pkgs.microg-re.packageName} = pkgs.microg-re;
  };

  environment.systemPackages = with pkgs; [
    git
    htop
  ];
}
