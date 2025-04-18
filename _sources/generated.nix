# This file was generated by nvfetcher, please do not modify it manually.
{ fetchgit, fetchurl, fetchFromGitHub, dockerTools }:
{
  adguard = {
    pname = "adguard";
    version = "v0.108.0-b.67";
    src = dockerTools.pullImage {
      imageName = "adguard/adguardhome";
      imageDigest = "sha256:4cc0f21368838104e7b2bbfee0bb7e9e6ddae6d303e24b2bef36dac6adc6955f";
      sha256 = "sha256-qutB0Ri9VcvXUxgkZPZSy5CHriBe1verd9isLy/Oh7s=";
      finalImageTag = "v0.108.0-b.67";
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
  jellyfin = {
    pname = "jellyfin";
    version = "2025041517";
    src = dockerTools.pullImage {
      imageName = "jellyfin/jellyfin";
      imageDigest = "sha256:b8ce983c7cac30f168a8064a5a1f99fa60b8d131ce0480e8e1b4471039ff1546";
      sha256 = "sha256-vb/rKF0UQNSfA8bG7AWXL7d0OUykduMIzz5mNfJMzaI=";
      finalImageTag = "2025041517";
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
    version = "3.1.2";
    src = dockerTools.pullImage {
      imageName = "mbround18/valheim";
      imageDigest = "sha256:44c2ab93f34c63765b0fbab8f5ec5f67a35f315d995760bf8d4af6ba2f766860";
      sha256 = "sha256-hy818wdfk2bnksBulNhrEUZve+gFRNVczBo/Wr6PL+0=";
      finalImageTag = "3.1.2";
    };
  };
  prowlarr = {
    pname = "prowlarr";
    version = "1.33.3";
    src = dockerTools.pullImage {
      imageName = "linuxserver/prowlarr";
      imageDigest = "sha256:af8eaaa96684a4d83c73684a39ef0abcdc3ee2c0e9ba7b4c90b1523d28327b04";
      sha256 = "sha256-uiJJRziaDjT99fJDTjJ9inhBDD0EfylksQp2xvdvWFs=";
      finalImageTag = "1.33.3";
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
    version = "5.21.1";
    src = dockerTools.pullImage {
      imageName = "linuxserver/radarr";
      imageDigest = "sha256:eccd80c53e55572b91ae205eb572e16b3e012631892e74be7ccedb6d5fafb630";
      sha256 = "sha256-eTtYx4a9QjxueB0vNkiKUw6vSoU9keb0ZJJYQG+gjBo=";
      finalImageTag = "5.21.1";
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
