# Pure C++ block-compression decoder (BCn/ETC/ASTC/PVRTC/Crunch). UnityPy calls
# it for every Texture2D it decodes, so avatar extraction is dead without it.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:
buildPythonPackage rec {
  pname = "texture2ddecoder";
  version = "1.0.6";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-iPBNiVEBisE7jazQflfora1Kbxz+VQlkbooQIDRqgco=";
  };

  # Upstream caps setuptools for a pypy3.8 bug it no longer supports; nixpkgs is
  # well past that cap and the build itself is fine on current setuptools.
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail "setuptools<72.2.0" "setuptools"
  '';

  build-system = [setuptools];

  pythonImportsCheck = ["texture2ddecoder"];

  meta = {
    description = "Python wrapper for Perfare's Texture2DDecoder";
    homepage = "https://github.com/K0lb3/texture2ddecoder";
    license = lib.licenses.mit;
  };
}
