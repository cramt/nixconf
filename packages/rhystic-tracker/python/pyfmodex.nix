# ctypes bindings to FMOD, pulled in by fmod-toolkit. Pure python — the FMOD
# shared library itself ships inside fmod-toolkit, which points
# PYFMODEX_DLL_PATH at it before importing this.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  poetry-core,
}:
buildPythonPackage rec {
  pname = "pyfmodex";
  version = "0.7.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-2a09eEGhxM9HM8vtxpOJ+ExYpkDSPQ/6CDrWCA81EDw=";
  };

  # The sdist carries poetry metadata but no [build-system] table at all, so
  # every frontend falls back to setuptools and fails to find a setup.py. It
  # also names a README.md it ships lowercase, which poetry-core treats as fatal.
  postPatch = ''
    substituteInPlace pyproject.toml --replace-fail 'readme = "README.md"' 'readme = "readme.md"'
    cat >> pyproject.toml <<'EOT'

    [build-system]
    requires = ["poetry-core"]
    build-backend = "poetry.core.masonry.api"
    EOT
  '';

  build-system = [poetry-core];

  # Deliberately no pythonImportsCheck: importing the module dlopens the FMOD
  # library, which needs PYFMODEX_DLL_PATH pointed at it, and only fmod-toolkit
  # knows where that is. fmod-toolkit's own import check covers this one.

  meta = {
    description = "Python ctypes bindings for the FMOD Ex library";
    homepage = "https://github.com/tyrylu/pyfmodex";
    license = lib.licenses.mit;
  };
}
