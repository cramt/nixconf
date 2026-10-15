# Dictation: whisper-server on luna's GPU (modules/services/whisper.nix) and the
# clients that talk to it (voxtype on the desktops, modules/hm-features/dictation.nix).
#
# The vocabulary is Whisper's initial prompt, which biases spelling towards
# these words: "nix" stops coming out as "Knicks", "Lasombra" as "Lassam Bra".
# Whisper keeps only ~224 tokens of it (this list is ~206), so it holds the
# words actually said out loud, not every card or clan ever printed, nor words
# Whisper already spells right on its own (Rust, Claude, Wayland). Words it still mangles go in `replacements`,
# grown from real mishears rather than guessed.
#
# Lives in myLib/ because import-tree would turn it into a flake-parts module.
let
  vocabulary = {
    tech = [
      "Nix" "NixOS" "nixpkgs" "nixconf" "flake" "home-manager" "cachix" "devshell"
      "mkIf" "systemd" "journalctl" "deploy-rs" "opnix" "1Password" "Authelia"
      "Zed" "niri" "COSMIC" "t3code" "luna" "saturn" "ganymede" "mercury" "eros"
    ];
    ttrpg = [
      "Kindred" "Camarilla" "Sabbat" "Anarch" "Tzimisce" "Tremere" "Ventrue"
      "Toreador" "Brujah" "Gangrel" "Malkavian" "Nosferatu" "Lasombra" "Hecata"
      "Ravnos" "Banu Haqim" "Salubri" "Caitiff" "ghoul" "vitae" "diablerie"
      "Vicissitude" "Daggerheart"
    ];
    mtg = [
      "Commander" "cEDH" "EDHREC" "ETB" "Scryfall" "Sol Ring" "Rhystic Study"
      "Atraxa" "proliferate" "Ephemerate"
    ];
  };
in {
  host = "luna";
  port = 10300;
  prompt = "Glossary: " + builtins.concatStringsSep ", " (builtins.concatLists (builtins.attrValues vocabulary)) + ".";

  # Lowercase spoken form -> written form, whole-word and case-insensitive
  # (voxtype's [text] replacements).
  replacements = {
    "knicks" = "Nix";
    "make if" = "mkIf";
    "make-if" = "mkIf";
    "journal control" = "journalctl";
    "op nix" = "opnix";
  };
}
