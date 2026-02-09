{...}: {
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    secrets = {
      tailscalePreauthKey = {
        reference = "op://Homelab/Tailscale/preauthKey";
        services = ["tailscaled"];
      };
      cloudflareCredsEnv = {
        reference = "op://Homelab/Cloudflare/credsEnv";
        services = ["acme-turn.cramt.dk"];
      };
      postgresPassword = {
        reference = "op://Homelab/Postgres/password";
        owner = "postgres";
        group = "postgres";
        services = ["postgresql"];
      };
      homelabControllerEnv = {
        reference = "op://Homelab/HomelabController/envFile";
        services = ["homelab_system_controller"];
      };
      valheimEnv = {
        reference = "op://Homelab/Valheim/envFile";
      };
      curseForgeEnv = {
        reference = "op://Homelab/CurseForge/envFile";
      };
      minioCredsEnv = {
        reference = "op://Homelab/Minio/credsEnv";
        services = ["minio"];
      };
      titanFrontendEnv = {
        reference = "op://Homelab/TitanFrontend/envFile";
        services = ["titan-frontend"];
      };
      jellyfinCramtPassword = {
        reference = "op://Homelab/JellyfinUsers/cramtPassword";
      };
      jellyfinHannahPassword = {
        reference = "op://Homelab/JellyfinUsers/hannahPassword";
      };
      cockatricePassword = {
        reference = "op://Homelab/Cockatrice/password";
      };
      cockatriceEnv = {
        reference = "op://Homelab/Cockatrice/envFile";
      };
      matrixSharedSecret = {
        reference = "op://Homelab/Matrix/sharedSecret";
        services = ["coturn"];
      };
      conduitSecretEnv = {
        reference = "op://Homelab/Matrix/conduitEnv";
        services = ["conduit"];
      };
      synapseExtraConfig = {
        reference = "op://Homelab/Matrix/synapseExtraConfig";
        services = ["matrix-synapse"];
      };
      ollamaBearerEnv = {
        reference = "op://Homelab/Ollama/bearerEnv";
        services = ["caddy"];
      };
      nixAccessTokensConf = {
        reference = "op://Homelab/GitHub/nixAccessTokensConf";
      };
      terraformRemotePassword = {
        reference = "op://Homelab/TerraformRemoteState/password";
        services = ["postgresql"];
      };
    };
  };
}
