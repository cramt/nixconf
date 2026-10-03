# `nix run .#moonlight-pairing -- <outdir> [clients...]`: pre-generates the
# certs that pair ganymede's Moonlight with saturn's Sunshine, so neither
# side ever pairs by PIN. See the script's docstring for what goes where.
{
  writers,
  python3Packages,
}:
writers.writePython3Bin "moonlight-pairing" {
  libraries = [python3Packages.cryptography];
  flakeIgnore = ["E501"];
} (builtins.readFile ./moonlight-pairing.py)
