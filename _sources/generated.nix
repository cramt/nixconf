# This file was generated by nvfetcher, please do not modify it manually.
{ fetchgit, fetchurl, fetchFromGitHub, dockerTools }:
{
  adguard = {
    pname = "adguard";
    version = "v0.108.0-b.65";
    src = dockerTools.pullImage {
      imageName = "adguard/adguardhome";
      imageDigest = "sha256:56b07ee1cf5a7cdfc0137b4d544666f2df7784b41c30589b4c8232ba8eddd500";
      sha256 = "sha256-HvJxyijfUqrJkZHqylYU3hSAOTqroxGjgXSOnsid98I=";
      finalImageTag = "v0.108.0-b.65";
    };
  };
  bazarr = {
    pname = "bazarr";
    version = "1.5.1";
    src = dockerTools.pullImage {
      imageName = "linuxserver/bazarr";
      imageDigest = "sha256:ac9fe56bee9133bcb9e27fe48faaf83c57b83d75bacc277d9b2619136632b1fe";
      sha256 = "sha256-xSr7YKWSHB1Ma7o1eEInGF4yD8g097kqRUUCNVxVCvc=";
      finalImageTag = "1.5.1";
    };
  };
  caddy = {
    pname = "caddy";
    version = "2.9.1";
    src = dockerTools.pullImage {
      imageName = "library/caddy";
      imageDigest = "sha256:2c136eb7e4daa97deed8738aab21994ea88dc0ced06aa44e30a949ba3d60e213";
      sha256 = "sha256-BjLwNrXPZFwZs7Fau/pxhUPSImBT8ms+nUVBs1PO4H8=";
      finalImageTag = "2.9.1";
    };
  };
  jellyfin = {
    pname = "jellyfin";
    version = "2025032405";
    src = dockerTools.pullImage {
      imageName = "jellyfin/jellyfin";
      imageDigest = "sha256:38b09f245ffdd6b8ef2024134b6c66a530e115bb02692e1433a5a3649e7f541b";
      sha256 = "sha256-DZ/bbxcZ8cQgKXt9G42YGpc7X0/YPXqlBPwgfT4+YN4=";
      finalImageTag = "2025032405";
    };
  };
  minecraft-server = {
    pname = "minecraft-server";
    version = "java8";
    src = dockerTools.pullImage {
      imageName = "itzg/minecraft-server";
      imageDigest = "sha256:40083af30bd9d75358ba14a825f3c1d3620875be0c055b212c9aed76420a9d54";
      sha256 = "sha256-ve8kNL+OKdwuONuN+SWRha6T4G5g5amjg+idFi4+2Wo=";
      finalImageTag = "java8";
    };
  };
  odin = {
    pname = "odin";
    version = "3.1.0";
    src = dockerTools.pullImage {
      imageName = "mbround18/valheim";
      imageDigest = "sha256:70bd4da591cd50290454a9cc1511e640700c2e2f82ea4d5a8b2ee44629988936";
      sha256 = "sha256-MOcnbV1juj9UBsg9haORH9X9DzoutGrp99kfFRe6IfE=";
      finalImageTag = "3.1.0";
    };
  };
  prowlarr = {
    pname = "prowlarr";
    version = "1.32.2";
    src = dockerTools.pullImage {
      imageName = "linuxserver/prowlarr";
      imageDigest = "sha256:18e9801e4509e45873c1adb03adf0bf718743ff5147e19b4cdf7626f8bd2f752";
      sha256 = "sha256-pgHkerlaKRSjfrni9xIGgIKlXIoi2swESjKXP1DkVPc=";
      finalImageTag = "1.32.2";
    };
  };
  qbittorrent = {
    pname = "qbittorrent";
    version = "20.04.1";
    src = dockerTools.pullImage {
      imageName = "linuxserver/qbittorrent";
      imageDigest = "sha256:fc98c8af048936d0070dc5e5992feab08664f8a61a860d91be02f782f8721485";
      sha256 = "sha256-GZAC1cA7pShhKQB92d8JMbsUUYICplel+Mp2GqkFH/w=";
      finalImageTag = "20.04.1";
    };
  };
  radarr = {
    pname = "radarr";
    version = "5.20.2";
    src = dockerTools.pullImage {
      imageName = "linuxserver/radarr";
      imageDigest = "sha256:23677e1cb09bd957796f4521748f0eff9eb65d883949c10442635eabe64b750a";
      sha256 = "sha256-hg5ncUrAuPdXQh1W3Omz3wTrFeVaJOSJlCVVzGLdqIg=";
      finalImageTag = "5.20.2";
    };
  };
  sonarr = {
    pname = "sonarr";
    version = "4.0.14";
    src = dockerTools.pullImage {
      imageName = "linuxserver/sonarr";
      imageDigest = "sha256:7fe49f99201de94a277c577dcce5ef8f1789ead1056c8cf758fac7bf4e601d16";
      sha256 = "sha256-tZu4doZN7CZUQo7qeu2Kl4jMGrkvy/52ZNHimFu83f0=";
      finalImageTag = "4.0.14";
    };
  };
  tor-privoxy = {
    pname = "tor-privoxy";
    version = "latest";
    src = dockerTools.pullImage {
      imageName = "dockage/tor-privoxy";
      imageDigest = "sha256:7688b62223e1107adcda1418c2f9f95f9173abec7118431d776a0793135844f0";
      sha256 = "sha256-pWk0Ci7gSSfzUaY2bOtOaMlFnBjO0gBtwIU7nuq8ZMQ=";
      finalImageTag = "latest";
    };
  };
}
