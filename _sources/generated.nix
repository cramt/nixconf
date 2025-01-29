# This file was generated by nvfetcher, please do not modify it manually.
{ fetchgit, fetchurl, fetchFromGitHub, dockerTools }:
{
  adguard = {
    pname = "adguard";
    version = "v0.108.0-b.62";
    src = dockerTools.pullImage {
      imageName = "adguard/adguardhome";
      imageDigest = "sha256:1c0025ab891508e0945b2d050f4a4d696e1ad8910452e5bd9b6caab744c6e033";
      sha256 = "sha256-Hu1DHGUTaC97/EqTd2+Wha9zzWwiQMw3tvjOwGFhmSc=";
      finalImageTag = "v0.108.0-b.62";
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
    version = "2025012005";
    src = dockerTools.pullImage {
      imageName = "jellyfin/jellyfin";
      imageDigest = "sha256:ab357c368e9038156793a9dea11707c55fd375e775418753ae6fe11cf2e99a59";
      sha256 = "sha256-S4g65I645J+rA8TYNOsNoF10nUFdELqXVDTHXFfVV44=";
      finalImageTag = "2025012005";
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
  prowlarr = {
    pname = "prowlarr";
    version = "1.30.2";
    src = dockerTools.pullImage {
      imageName = "linuxserver/prowlarr";
      imageDigest = "sha256:5c9d62af19a810f7799c1d5fbf686cc6c28690c00f916c029699ae3d1c75e8ef";
      sha256 = "sha256-KsVLg/m+WNduLRhvAwZZ0NAUlPSoJyfMqHL5bOKjYBM=";
      finalImageTag = "1.30.2";
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
    version = "5.17.2";
    src = dockerTools.pullImage {
      imageName = "linuxserver/radarr";
      imageDigest = "sha256:e633fc93b9e2cea959853d27c6acc1d0b2d1ed7db4a800f6f46fe5b217f13102";
      sha256 = "sha256-s7LVbtOUeDcfamvuRumWOvLGx8aR4M4PqNN8S8YqLvA=";
      finalImageTag = "5.17.2";
    };
  };
  sonarr = {
    pname = "sonarr";
    version = "4.0.12";
    src = dockerTools.pullImage {
      imageName = "linuxserver/sonarr";
      imageDigest = "sha256:23f6911b2b81cb69aa03166b53c15081d5c3a5ed58f5b183c5900c2d8fc9759a";
      sha256 = "sha256-BRAMd1mjH622xY5/w/xR1D0GnS/TUSrebZVo9paCKmo=";
      finalImageTag = "4.0.12";
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
