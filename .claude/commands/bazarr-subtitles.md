---
description: Manage Bazarr subtitles - providers, languages, wanted subtitles, and manual search via the Bazarr API
allowed-tools: Bash, Read, Write, Grep, Glob, WebSearch
---

# Bazarr Subtitle Management

You are managing Bazarr for a media server stack (nixarr) that serves TV shows, movies, and anime.

## Connection Details

- **API Base**: https://bazarr.cramt.dk/api
- **API Key**: Retrieve from the user. Do NOT hardcode it. Ask if not provided: "What's your Bazarr API key? (Settings > General in the Bazarr UI)"
- **Authentication**: Header `X-API-KEY: <key>` on all requests

## User's Content Profile

Based on their library (Jellyfin): mainstream TV/movies + anime. Configured languages are English (`en`) and Danish (`da`). Prioritize:
- English subtitles (primary)
- Danish subtitles (secondary)
- Anime-capable providers (for `.ass`/styled subs)

## API Reference

All requests need header: `X-API-KEY: <key>`

### System Status
```
GET /api/system/status
```
Returns environment info, version, start time.

### System Health
```
GET /api/system/health
```
Returns list of health issues (empty array = healthy).

### Get All Settings
```
GET /api/system/settings
```
Returns the full settings blob including provider configuration, language settings, and profiles.

### Update Settings
```
POST /api/system/settings
Content-Type: application/x-www-form-urlencoded
```
Settings are sent as form fields. Key fields:
- `settings-general-*` — general settings
- `settings-providers-*` — provider enable/disable and credentials
- `settings-subtitles-*` — subtitle behavior settings
- `settings-languages-enabled` — list of enabled language code2 values
- `settings-languages-profiles` — JSON array of language profile objects

### List Available Languages
```
GET /api/system/languages
```
Returns all languages Bazarr knows about (code2, code3, name).

### Language Profiles
```
GET /api/system/languages/profiles
```
Returns configured language profiles (which languages to download, in what order).

### Provider Status
```
GET /api/providers
```
Returns runtime status of each provider (active, throttled, retry timers). This is NOT the configuration — config lives in `/api/system/settings`.

### Reset Providers
```
POST /api/providers
Body: action=reset
```
Resets all throttled/errored providers back to active.

### Wanted Episodes (Missing Subtitles)
```
GET /api/episodes/wanted?start=0&length=50
```
Returns episodes with missing subtitles. Params:
- `start` — offset (default 0)
- `length` — page size (default 50)
- `episodeid[]` — filter to specific episode IDs

### Wanted Movies (Missing Subtitles)
```
GET /api/movies/wanted?start=0&length=50
```
Returns movies with missing subtitles. Same pagination params.

### Manual Subtitle Search — Episode
```
GET /api/providers/episodes?episodeid=<id>
```
Searches all active providers for subtitles for a specific episode. Returns list of available subtitle results.

### Manual Subtitle Search — Movie
```
GET /api/providers/movies?radarrid=<id>
```
Searches all active providers for subtitles for a specific movie.

### Download Subtitle — Episode
```
POST /api/providers/episodes
Content-Type: application/x-www-form-urlencoded
```
Download a specific subtitle result for an episode. Fields from the search result.

### Download Subtitle — Movie
```
POST /api/providers/movies
Content-Type: application/x-www-form-urlencoded
```
Download a specific subtitle result for a movie.

## Workflow

### Default (no args): Audit & Status
1. **Check system health** — report any issues
2. **List provider status** — show which providers are active, throttled, or errored
3. **Get settings** — show enabled providers and language profiles
4. **Show wanted counts** — how many episodes/movies are missing subtitles
5. **Recommend actions** — suggest provider resets, missing providers to enable, or manual searches

### Provider Management
1. **Get current settings** to see which providers are enabled
2. **Recommend providers** based on the user's content profile
3. **Enable/disable providers** by POSTing updated settings

### Missing Subtitles
1. **List wanted** episodes and movies
2. **Manual search** for specific items if automatic hasn't found them
3. **Download** best matches

## Recommended Subtitle Providers

Good set for English + Danish, TV/movies/anime:

| Provider | Notes |
|----------|-------|
| OpenSubtitles.com | Best general coverage, requires free account |
| Addic7ed | Good for TV shows, may need account |
| Podnapisi | Good multilingual coverage including Danish |
| Subscene | Large catalog, community-driven |
| SubDivX | Backup general provider |
| Zimuku | Backup, good Asian content coverage |
| Supersubtitles | Good for Danish subtitles |
| Gestdown (formerly Addic7ed proxy) | Alternative access to Addic7ed content |
| Animetosho | Anime subtitles (`.ass` styled subs) |
| Embeddedsubtitles | Extracts embedded subs from MKV files |

### Anime-Specific Notes
- **Animetosho** and **Embeddedsubtitles** are most useful for anime
- Many anime releases already have embedded `.ass` subs — Embeddedsubtitles provider can extract these
- For simulcast anime (SubsPlease, Erai-raws), subs are usually embedded

## Important Notes

- Use `nix-shell -p jq` or find jq path first — this is NixOS, no global jq
- Settings responses can be large. Save to a temp file, don't store in shell variables
- Provider config is inside the settings blob, NOT at `/api/providers`
- The `/api/providers` endpoint only shows runtime status (throttled/active)
- Some providers require accounts (OpenSubtitles.com, Addic7ed) — ask the user for credentials before enabling
- Provider throttling is normal — Bazarr auto-manages retry timers
- Use `POST /api/providers` with `action=reset` to clear throttled states

## Arguments

If the user provides arguments like "status", "wanted", "providers", "search <title>", "reset providers", handle accordingly. Default behavior (no args) is to audit system health, provider status, and wanted subtitles.
