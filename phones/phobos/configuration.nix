# Alex's phone, managed by Nixup (modules/flake/phones.nix). The fleet bits
# (tailscale on the fleet tailnet, ssh) come from nixupModules; this file is only what's
# specific to the phone. Anything left unset stays as set by hand on the phone.
#
# OnePlus Nord CE5 (CPH2719, EU firmware), rooted with Magisk on init_boot.
# `nix run .#nixup-config -- create` writes a config from what it has now (apps, settings, debloat list); merge the parts
# worth keeping into here. Every option, with comments:
# https://github.com/by-architect/Nixup/blob/main/templates/default/configuration.nix
{ lib, pkgs, ... }:
{
  # OnePlus's system-app preloads, removed for the user with their data kept:
  # drop one from the list and the next build reinstalls it as it was. Only apps
  # nothing else leans on; com.oplus.* services and the Google apps worth using
  # (Maps, Gmail, Photos, Calendar, Messages, Drive, Auto, Wallet) stay. The
  # preloads OnePlus drops onto the user partition at first boot (Amazon,
  # Booking, Facebook, LinkedIn, Netflix, Fitbit, OnePlus Store/Forums, ...)
  # aren't system apps, so debloat refuses them: those were uninstalled by hand.
  android.apps = lib.genAttrs [
    "com.facebook.appmanager"
    "com.facebook.services"
    "com.facebook.system"
    # Link to Windows
    "com.microsoft.appmanager"
    "com.microsoft.deviceintegrationservice"
    "com.microsoftsdk.crossdeviceservicebroker"
    "com.oneplus.membership"
    "com.heytap.browser"
    "com.nearme.instant.platform"
    "com.oplus.games"
    "com.coloros.childrenspace"
    "com.google.android.apps.tachyon"
    # Stock YouTube: Morphe's replaces it
    "com.google.android.youtube"
  ] (_: { debloat = true; });

  time.timeZone = "Europe/Copenhagen";

  android.settings.display.darkMode = true;

  android.settings.sound = {
    touchSounds = false;
    dialpadTones = false;
    screenLockSound = false;
    chargingSound = false;
    keyboardVibration = false;
  };

  # OxygenOS's own key for the back gesture's buzz; touchVibration would kill every haptic.
  android.settings.raw.secure.gesture_side_back_vibrate_enable = 0;

  # nixup-rebuild applies over adb until ssh is up, so a rebuild must never turn it off.
  android.settings.developer = {
    enable = true;
    usbDebugging = true;
  };

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

  # Gboard buzzes on every key whatever the system's keyboardVibration says, and
  # Nixup has no option for an app's own preferences. Gboard keeps them in
  # device-protected storage; a file it hasn't written yet (fresh install, never
  # opened) is left alone, as there's nothing to fix until it exists.
  systemd.services.gboard-no-vibrate = {
    description = "Gboard: no haptic feedback on keypress";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      f=/data/user_de/0/com.google.android.inputmethod.latin/shared_prefs/com.google.android.inputmethod.latin_preferences.xml
      [ -f "$f" ] || { echo "Gboard has no preferences yet"; exit 0; }
      grep -q '<boolean name="enable_vibrate_on_keypress" value="false" />' "$f" && exit 0
      # Its running copy would write the old value back over the edit.
      am force-stop com.google.android.inputmethod.latin
      if grep -q 'name="enable_vibrate_on_keypress"' "$f"; then
        sed 's|<boolean name="enable_vibrate_on_keypress" value="true" />|<boolean name="enable_vibrate_on_keypress" value="false" />|' "$f" > "$f.new"
      else
        sed 's|</map>|    <boolean name="enable_vibrate_on_keypress" value="false" />\n</map>|' "$f" > "$f.new"
      fi
      # cat over the original keeps its owner and SELinux label.
      cat "$f.new" > "$f" && rm "$f.new"
      echo "keypress vibration off"
    '';
  };

  environment.systemPackages = with pkgs; [
    git
    htop
  ];
}
