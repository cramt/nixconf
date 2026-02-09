# Migrate secrets from git-crypt to 1Password (opnix)

## Context

Currently, all secrets live in `secrets.json` encrypted with git-crypt. The goal is to make 1Password the single source of truth using a hybrid approach:

1. **`op inject`** — generates `secrets.json` from a template before each rebuild (for values needed at Nix evaluation time)
2. **opnix** — fetches secrets at boot from 1Password, writes to `/var/lib/opnix/secrets/` with restricted permissions (removes secrets from the Nix store)

This is needed because many secrets (domain, email, IPs) are used at Nix eval time (e.g., as Caddy virtualHost attribute keys, ACME cert names) and CANNOT be deferred to runtime. The `op inject` layer handles these. The opnix layer handles runtime secrets that currently leak into the world-readable `/nix/store/` via `pkgs.writeText`.

## Prerequisites (manual, before implementation)

1. Create a 1Password vault called `Homelab`
2. Populate it with all secrets from `secrets.json` (item/field structure detailed in implementation)
3. Create a 1Password Service Account with read-only access to the `Homelab` vault
4. Place the service account token at `/etc/opnix-token` (mode 0640) on luna (the main server)

## Step 1: Infrastructure changes

### 1a. Add opnix flake input
**File:** `flake.nix`
```nix
opnix = {
  url = "github:brizzbuzz/opnix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 1b. Wire opnix NixOS module into mkSystem
**File:** `myLib/default.nix` — add `inputs.opnix.nixosModules.default` to the `modules` list in `mkSystem`

### 1c. Create `secrets.json.tpl`
Template with `op://Homelab/Item/field` references instead of actual values. Safe to commit. Example:
```json
{
  "domain": "op://Homelab/Infrastructure/domain",
  "email": "op://Homelab/Infrastructure/email",
  "cloudflare_api_key": "op://Homelab/Cloudflare/apiKey",
  ...
}
```
Booleans/numbers (like `"admin": true`) stay as literals — `op inject` only replaces `op://` strings.

### 1d. Update `.gitignore`
Add `secrets.json`

### 1e. Update Justfile
Add `inject_secrets` step before builds:
```just
inject_secrets:
    op inject -i secrets.json.tpl -o secrets.json

build_luna: inject_secrets add_foundry_zips
    nh os switch --target-host root@192.168.178.24 -H luna -- --fallback

update: inject_secrets
    ...existing steps...
```

### 1f. Remove git-crypt
After verifying `op inject` works, remove `.gitattributes` git-crypt entries and the dependency.

## Step 2: Add centralized opnix NixOS secrets module

**New file:** `nixosModules/features/opnix-secrets.nix`

This declares all runtime secrets that should be fetched from 1Password at boot. Each secret gets a camelCase name, an `op://` reference, ownership, permissions, and associated services.

Key secrets to declare (all with `owner = "root"`, `mode = "0600"` unless noted):

| opnix name | op:// reference | Notes |
|---|---|---|
| `tailscalePreauthKey` | `op://Homelab/Tailscale/preauthKey` | services: ["tailscaled"] |
| `cloudflareCredsEnv` | `op://Homelab/Cloudflare/credsEnv` | Multi-line env file: `CLOUDFLARE_EMAIL=...\nCLOUDFLARE_API_KEY=...` |
| `postgresPassword` | `op://Homelab/Postgres/password` | owner: "postgres" |
| `homelabControllerEnv` | `op://Homelab/HomelabController/envFile` | `DISCORD_TOKEN=...\nALLOWED_GUILD=...` |
| `valheimEnv` | `op://Homelab/Valheim/envFile` | `PASSWORD=...` |
| `curseForgeEnv` | `op://Homelab/CurseForge/envFile` | `CF_API_KEY=...` |
| `minioCredsEnv` | `op://Homelab/Minio/credsEnv` | `MINIO_ROOT_USER=...\nMINIO_ROOT_PASSWORD=...` |
| `titanFrontendEnv` | `op://Homelab/TitanFrontend/envFile` | `TITAN_API_KEY=...` |
| `jellyfinCramtPassword` | `op://Homelab/JellyfinUsers/cramtPassword` | |
| `jellyfinHannahPassword` | `op://Homelab/JellyfinUsers/hannahPassword` | |
| `cockatricePassword` | `op://Homelab/Cockatrice/password` | |
| `matrixSharedSecret` | `op://Homelab/Matrix/sharedSecret` | |
| `terraformRemotePassword` | `op://Homelab/TerraformRemoteState/password` | |

Note: For secrets used as env files (suffix `Env`), the 1Password field stores the complete env file content (e.g., `DISCORD_TOKEN=xxx\nALLOWED_GUILD=yyy`).

## Step 3: Module-by-module migration

Migrate each module to use opnix secret paths instead of `pkgs.writeText`/inline values. Reference paths via `config.services.onepassword-secrets.secretPaths.<name>`.

### 3a. `nixosModules/services/tailscale.nix`
- Remove `pkgs.writeText "tailscale-auth-key"`
- Use `authKeyFile = config.services.onepassword-secrets.secretPaths.tailscalePreauthKey;`

### 3b. `nixosModules/services/conduit.nix`
- Remove `cloudflareCredentials = pkgs.writeText "cloudflare_creds.env" ...`
- Use `environmentFile = config.services.onepassword-secrets.secretPaths.cloudflareCredsEnv;`

### 3c. `nixosModules/services/synapse.nix`
- Same change as conduit.nix

### 3d. `nixosModules/services/homelab_system_controller.nix`
- Remove `DISCORD_TOKEN` and `ALLOWED_GUILD` from `environment`
- Add `serviceConfig.EnvironmentFile = config.services.onepassword-secrets.secretPaths.homelabControllerEnv;`

### 3e. `nixosModules/services/nixarr.nix`
- Replace `pkgs.writeText "password" value.password` with opnix paths
- Inline the user list (no longer dynamic from secrets.json):
  ```nix
  users = [
    { name = "cramt"; passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinCramtPassword; isAdministrator = true; }
    { name = "hannah"; passwordFile = config.services.onepassword-secrets.secretPaths.jellyfinHannahPassword; isAdministrator = true; }
  ];
  ```

### 3f. `nixosModules/services/minio.nix`
- Replace `secretKey`/`accessKey` with `rootCredentialsFile = config.services.onepassword-secrets.secretPaths.minioCredsEnv;`

### 3g. `nixosModules/services/valheim.nix`
- Remove `PASSWORD` from Docker `environment`
- Add `environmentFiles = [config.services.onepassword-secrets.secretPaths.valheimEnv];`

### 3h. `nixosModules/services/minecraft-forge.nix`
- Remove `CF_API_KEY` from Docker `environment`
- Add `environmentFiles = [config.services.onepassword-secrets.secretPaths.curseForgeEnv];`

### 3i. `nixosModules/services/titan-vm.nix`
- Remove `TITAN_API_KEY` from `environment`
- Add `serviceConfig.EnvironmentFile = config.services.onepassword-secrets.secretPaths.titanFrontendEnv;`

### 3j. `nixosModules/services/postgres.nix`
- Remove password from `pkgs.writeText "init.sql"`
- Read password at runtime in `postStart` script:
  ```bash
  PG_PASS=$(cat ${config.services.onepassword-secrets.secretPaths.postgresPassword})
  psql -c "ALTER USER \"postgres\" WITH PASSWORD '$PG_PASS'" -d postgres
  ```
- Change `applicationUsers` option from `password: str` to `passwordFile: path`
- Update `upsertScript` generation to read from files at runtime

### 3k. `nixosModules/services/terraform_remote_backend.nix`
- Change `password = ...` to `passwordFile = config.services.onepassword-secrets.secretPaths.terraformRemotePassword;`
- (Depends on postgres.nix option type change in 3j)

### Deferred (kept as eval-time only, not worth the refactoring complexity):
- `caddy.nix` — ollama_secret in Caddy config (would require Caddy snippet file generation)
- `servatrice.nix` — password in INI config (would require envsubst templating)
- `conduit.nix`/`synapse.nix` — `shared_matrix_secret` in module options (no `*File` variant exists)
- `general.nix` — github_read_token in nix access-tokens (no file variant)
- `ssh.nix` — luna_internal_address/ip used in SSH config (eval-time only)

These still get their values from `secrets.json` at eval time, which is fine — `secrets.json` is gitignored and generated by `op inject`.

## Verification

1. `op inject -i secrets.json.tpl -o secrets.json` — verify output matches current secrets.json
2. `nix flake check` — verify the flake evaluates
3. `nixos-rebuild build` — verify full system build
4. Deploy to luna, verify:
   - `systemctl status opnix-secrets` — service succeeded
   - `ls -la /var/lib/opnix/secrets/` — files exist with correct permissions
   - Services start and function (caddy, postgres, tailscale, homelab_system_controller, etc.)
5. Verify services that depend on opnix secrets all start correctly
