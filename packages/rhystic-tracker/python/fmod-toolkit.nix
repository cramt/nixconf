# FSB audio extraction. Nothing in the avatar path touches it, but UnityPy's
# export package imports it eagerly, so `import UnityPy` fails without it.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  pyfmodex,
  autoPatchelfHook,
  stdenv,
}:
buildPythonPackage rec {
  pname = "fmod_toolkit";
  version = "0.1.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-58FskMI7E3JreO2lYlY7x0YwmLqngg3DP66UQRouHH8=";
  };

  build-system = [setuptools];

  # The wheel bundles a prebuilt libfmod.so with no RPATH, and pyfmodex dlopens
  # it at import time — so `import UnityPy` dies on libstdc++ unless it's patched.
  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  dependencies = [pyfmodex];

  pythonImportsCheck = ["fmod_toolkit"];

  meta = {
    description = "FMOD sound bank tooling";
    homepage = "https://github.com/K0lb3/fmod_toolkit";
    license = lib.licenses.mit;
  };
}
