# Tdarr Auto-Configuration Setup

This document describes the automated Tdarr setup in your NixOS configuration.

## Overview

Tdarr has been configured to automatically:
1. Start with pre-configured GPU and CPU workers
2. Auto-configure libraries via API on first boot
3. Queue your entire media library for H.265 transcoding

## Configuration Details

### Docker Container (nixarr.nix:100-144)
- **Image**: Pinned via npins (`haveagitgat/tdarr`)
- **GPU Access**: Enabled with `--gpus=all`
- **API Key**: Pre-seeded as `tapi_nixos_autoconfig_12345`
- **Workers**:
  - 2 GPU transcode workers
  - 4 CPU transcode workers
  - 1 GPU health check worker
  - 2 CPU health check worker

### Volume Mounts
- Movies: `/storage/media/library/movies` → `/media/movies`
- TV Shows: `/storage/media/library/shows` → `/media/shows`
- Downloads: `/storage/downloads/{movies,tvshows}` → `/downloads/{movies,tvshows}`
- Temp: `/tmp/tdarr` → `/temp`
- State: `/storage/media/.state/nixarr/tdarr/`

### Auto-Configuration Service (nixarr.nix:146-179)

Two systemd services handle automatic configuration:

1. **tdarr-configure.service**
   - Runs after Tdarr container starts
   - Waits for Tdarr to be ready (max 5 minutes)
   - Creates two libraries via API:
     - Movies (`/media/movies`)
     - TV Shows (`/media/shows`)
   - Configures plugin stack for H.265 transcoding
   - Only runs once (checks for marker file)

2. **tdarr-configure-marker.service**
   - Creates marker file at `/storage/media/.state/nixarr/tdarr/.configured`
   - Prevents re-running configuration on subsequent boots

## Plugin Stack

The auto-configuration sets up the following plugins:

1. **Migz-Transcode Using Nvidia GPU & FFMPEG**
   - Codec: `hevc_nvenc` (H.265 with NVIDIA GPU)
   - CRF: 23 (good quality/size balance)

2. **Migz-Remove All Subtitle Streams**
   - Removes embedded subtitles (use Bazarr for external subs)

3. **Migz-Remove Closed Captions**
   - Removes embedded closed captions

4. **Migz-Keep One Audio Stream**
   - Language: English
   - Codec: AAC
   - Channels: Stereo

5. **Migz-Remove Meta-Data If Title Meta Detected**
   - Cleans up metadata

## Usage

### First Boot
After running `sudo nixos-rebuild switch`:

1. Tdarr container starts automatically
2. Wait ~30 seconds for Tdarr to initialize
3. Auto-configuration service runs and sets up libraries
4. Workers automatically start processing your media

### Monitoring

Check service status:
```bash
systemctl status docker-tdarr
systemctl status tdarr-configure
```

View logs:
```bash
journalctl -u docker-tdarr -f
journalctl -u tdarr-configure -f
```

Access Web UI:
```bash
# Local
http://localhost:8265

# Via Caddy reverse proxy
https://tdarr.cramt.dk
```

### Manual Configuration

If you need to reconfigure Tdarr:

1. Remove the marker file:
   ```bash
   sudo rm /storage/media/.state/nixarr/tdarr/.configured
   ```

2. Restart the configuration service:
   ```bash
   sudo systemctl restart tdarr-configure
   ```

Or manually run the configuration script:
```bash
tdarr-configure
```

## API Access

The pre-seeded API key is: `tapi_nixos_autoconfig_12345`

Example API calls:
```bash
# Check status
curl http://localhost:8265/api/v2/status

# List libraries
curl -H "x-api-key: tapi_nixos_autoconfig_12345" \
  http://localhost:8265/api/v2/libraries

# View queue
curl -H "x-api-key: tapi_nixos_autoconfig_12345" \
  http://localhost:8265/api/v2/queue
```

## Customization

### Adjust Worker Counts (nixarr.nix:123-126)
```nix
transcodegpuWorkers = "2";      # Increase for more parallel GPU transcodes
transcodecpuWorkers = "4";      # Increase based on CPU cores
healthcheckgpuWorkers = "1";
healthcheckcpuWorkers = "2";
```

### Change Transcoding Settings
Edit the plugin stack in `scripts/tdarr-configure.sh`:
- Adjust CRF value (lower = better quality, larger files)
- Change codec (hevc_nvenc, hevc_qsv, libx265)
- Modify audio settings

### Add More Libraries
Edit `scripts/tdarr-configure.sh` and add more `create_library` calls.

## Troubleshooting

### Configuration service fails
```bash
# Check logs
journalctl -u tdarr-configure -n 50

# Verify Tdarr is running
curl http://localhost:8265/api/v2/status

# Manually run configuration
tdarr-configure
```

### Workers not starting
- Check GPU access: `docker exec tdarr nvidia-smi`
- Verify worker counts in Web UI (Nodes tab)
- Check container logs: `docker logs tdarr`

### Libraries not processing
- Go to Web UI → Libraries → Options → "Requeue all items (transcode)"
- Check that workers are active in Nodes tab
- Verify file permissions on media directories

## Expected Results

With this configuration:
- **Space Savings**: 40-60% reduction in file size (H.264 → H.265)
- **Processing Speed**: ~2-4x realtime with GPU transcoding
- **Quality**: Visually identical with CRF 23

Example:
- 100GB movie library → ~50GB after transcoding
- 1TB TV show library → ~500GB after transcoding

## References

- [Tdarr Documentation](https://docs.tdarr.io)
- [Tdarr Plugins](https://github.com/HaveAGitGat/Tdarr_Plugins)
- [Configuration Script](../scripts/tdarr-configure.sh)
- [NixOS Module](../nixosModules/services/nixarr.nix)
