# Home tiles for every app on every Sunshine host ganymede's Moonlight is
# paired with (hosts/ganymede/moonlight.nix runs it). See src/main.rs.
{rustPlatform}:
rustPlatform.buildRustPackage {
  pname = "emrakul-games";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta.mainProgram = "emrakul-games";
}
