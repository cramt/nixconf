# ETC/DXT *compressor*. UnityPy only imports it when writing textures back, but
# it's a hard dependency in the dist metadata, so it has to be installed for the
# runtime dependency check to pass.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  wheel,
  archspec,
}:
buildPythonPackage rec {
  pname = "etcpak";
  version = "0.9.15";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-/gnjLYqnW4FjgyQow9bfZaUbK34CNyksEMEiTKVyikM=";
  };

  # Without this setup.py appends -march=native and asks archspec which SIMD
  # level *this* machine has — so the result is unreproducible and only valid on
  # the builder's CPU. The flag is upstream's own "building a redistributable
  # wheel" switch: generic codegen plus every SIMD variant compiled separately,
  # picked at import time.
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

  pythonImportsCheck = ["etcpak"];

  meta = {
    description = "Python wrapper for etcpak";
    homepage = "https://github.com/K0lb3/etcpak";
    license = lib.licenses.mit;
  };
}
