# The whole point of this directory: reads Unity asset bundles, which is how
# rhystic-tracker's extractor gets avatar art out of MTGA's own game files.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  attrs,
  brotli,
  fsspec,
  lz4,
  pillow,
  astc-encoder-py,
  etcpak,
  fmod-toolkit,
  texture2ddecoder,
  tpk-ar,
}:
buildPythonPackage rec {
  pname = "unitypy";
  version = "1.25.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-kdYWnXPbjrXxH9ZTG05emA9T2uANXjy6uCe79HZd5tM=";
  };

  build-system = [setuptools];

  dependencies = [
    astc-encoder-py
    attrs
    brotli
    etcpak
    fmod-toolkit
    fsspec
    lz4
    pillow
    texture2ddecoder
    tpk-ar
  ];

  pythonImportsCheck = ["UnityPy"];

  meta = {
    description = "Unity asset extraction and patching package";
    homepage = "https://github.com/K0lb3/UnityPy";
    license = lib.licenses.mit;
  };
}
