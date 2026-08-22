'use strict';
// Replaces upstream's lib/update.js, which self-updates by running git pull and
// npm install inside the install directory. Under nix that directory is an
// immutable store path, so the freshness check and the update both have to go.
function checkInBackground() {}

function cachedBehind() {
  return false;
}

function runUpdate() {
  process.stderr.write(
    'manycode: installed from nix — update the manycode source pin in your nixconf and rebuild.\n'
  );
  process.exit(1);
}

module.exports = { checkInBackground, cachedBehind, runUpdate };
