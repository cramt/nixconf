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

    # YouTube and Reddit with Morphe's patches, rebuilt by j-hc's CI every few
    # days. The non-root APKs, not the Magisk modules: Nixup can't install a
    # module, and Reddit only ships as an APK. Both are signed with j-hc's key,
    # pinned here, so a swapped build is refused.
    {
      # Installs beside stock YouTube under its own name; it logs in through
      # MicroG-RE below instead of Play Services.
      id = "app.morphe.android.youtube";
      url = "https://github.com/j-hc/revanced-magisk-module";
      apkFilter = "^youtube-morphe-v.*\\.apk$";
      signer = "637c226c67aec0cdbc6f49cd476d5247f999122606286273e16233a913a088b4";
    }
    {
      # Keeps Reddit's own package name, so stock Reddit has to be uninstalled
      # first: Android won't update it with a differently signed APK.
      id = "com.reddit.frontpage";
      url = "https://github.com/j-hc/revanced-magisk-module";
      apkFilter = "^reddit-morphe-.*\\.apk$";
      signer = "637c226c67aec0cdbc6f49cd476d5247f999122606286273e16233a913a088b4";
    }
    {
      # Morphe's microG build. The patched YouTube looks for it as
      # app.revanced.android.gms, the name ReVanced's GmsCore also uses.
      id = "app.revanced.android.gms";
      url = "https://github.com/MorpheApp/MicroG-RE";
      apkFilter = "^microg-.*-noicon";
      signer = "0b6c9515afb195fac59601696ba0a7907a0b217ccf720b43148427ccf64343e7";
    }
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
  ];
}
