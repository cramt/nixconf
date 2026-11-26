# The browser extensions every one of Alex's browsers gets, from AMO: Zen on
# Linux (modules/hm-features/zen.nix) installs these packages, and saturn's
# Windows Firefox (modules/flake/windows.nix) force-installs the same addon
# ids from AMO through enterprise policy. Takes rycee's firefox-addons set.
addons:
with addons; [
  ublock-origin
  sponsorblock
  vimium
  refined-github
  onepassword-password-manager
  bitwarden
  multi-account-containers
]
