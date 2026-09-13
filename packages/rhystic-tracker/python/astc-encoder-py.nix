# ASTC codec. Same deal as etcpak: UnityPy imports it lazily, the metadata makes
# it mandatory.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  wheel,
  archspec,
}:
buildPythonPackage rec {
  pname = "astc_encoder_py";
  version = "0.1.12";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-A3WawygEyuMrwjjnL5TFuifiKFB98AgWt0H3lh8RhPk=";
  };

  # See etcpak: upstream's redistributable-wheel switch, which is the only way to
  # stop setup.py from baking -march=native and the builder's SIMD level in.
  env.CIBUILDWHEEL = "1";

  # Upstream caps setuptools for a pypy3.8 bug it no longer supports; nixpkgs is
  # well past that cap and the build itself is fine on current setuptools.
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail "setuptools<72.2.0" "setuptools"
  '';

  build-system = [setuptools wheel archspec];

  # Also needed at *runtime*: the package ships one extension module per SIMD
  # level and asks archspec at import which of them this CPU can run. Not
  # declared in the dist metadata, so nothing would pull it in on its own.
  dependencies = [archspec];

  pythonImportsCheck = ["astc_encoder"];

  meta = {
    description = "Python wrapper for ARM's astc-encoder";
    homepage = "https://github.com/K0lb3/astc-encoder-py";
    license = lib.licenses.mit;
  };
}
