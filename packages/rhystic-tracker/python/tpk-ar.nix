# Type tree packages — UnityPy needs one to read assets whose serialized type
# trees were stripped, which is every release build of a Unity game.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:
buildPythonPackage rec {
  pname = "tpk_ar";
  version = "0.2.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-1kiX5aC83dWOin1N2SLzctqYSg+YvDtGDshpqrkG7ng=";
  };

  build-system = [setuptools];

  pythonImportsCheck = ["tpk_ar"];

  meta = {
    description = "Parser for Unity type tree packages (TPK)";
    homepage = "https://github.com/K0lb3/tpk_ar";
    license = lib.licenses.mit;
  };
}
