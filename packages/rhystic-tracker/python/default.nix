# UnityPy plus the handful of codec/format packages it depends on, none of which
# are in nixpkgs. Kept as a local scope instead of pythonPackagesExtensions so
# the rest of the python set isn't re-evaluated for one leaf consumer.
{python3Packages}: let
  self = {
    texture2ddecoder = python3Packages.callPackage ./texture2ddecoder.nix {};
    etcpak = python3Packages.callPackage ./etcpak.nix {};
    astc-encoder-py = python3Packages.callPackage ./astc-encoder-py.nix {};
    tpk-ar = python3Packages.callPackage ./tpk-ar.nix {};
    pyfmodex = python3Packages.callPackage ./pyfmodex.nix {};
    fmod-toolkit = python3Packages.callPackage ./fmod-toolkit.nix {
      inherit (self) pyfmodex;
    };

    unitypy = python3Packages.callPackage ./unitypy.nix {
      inherit (self) astc-encoder-py etcpak fmod-toolkit texture2ddecoder tpk-ar;
    };
  };
in
  self
