---
description: Manage Prowlarr indexers - list, add, remove, and test indexers via the Prowlarr API
allowed-tools: Bash, Read, Write, Grep, Glob, WebSearch
---

# Prowlarr Indexer Management

You are managing Prowlarr indexers for a media server stack (nixarr) that serves TV shows, movies, and anime.

## Connection Details

- **API Base**: https://prowlarr.cramt.dk/api/v1
- **API Key**: Retrieve from the user. Do NOT hardcode it. Ask if not provided: "What's your Prowlarr API key? (Settings > General in the Prowlarr UI)"
- **FlareSolverr**: Already configured as indexer proxy id=1, tag=1. Used for Cloudflare-protected sites.

## User's Content Profile

Based on their library (Jellyfin): mainstream TV/movies + anime (Attack on Titan, Death Note, Castlevania, Cyberpunk Edgerunners, Delicious in Dungeon, Frieren, etc.). Prioritize indexers with good coverage for:
- English-language TV shows and movies
- Anime (subbed)
- Western animation

## API Reference

All requests need header: `X-Api-Key: <key>`

### List current indexers
```
GET /api/v1/indexer
```

### Get available indexer schemas (all 600+ definitions)
```
GET /api/v1/indexer/schema
```
Returns array of full schema objects. Each has:
- `name`, `definitionName`, `protocol` (torrent/usenet), `privacy` (public/private/semi-private)
- `indexerUrls[]` - available base URLs (try in order if first fails)
- `fields[]` - configuration fields including `baseUrl` (type: select, set to first indexerUrl)

### Create an indexer
```
POST /api/v1/indexer
Content-Type: application/json
Body: <modified schema object>
```
Before posting, modify the schema:
1. Set `.enable = true`
2. Set `.appProfileId = 1`
3. Set `(.fields[] | select(.name == "baseUrl")).value = <url from indexerUrls[0]>`
4. Set `.tags = [1]` if site needs FlareSolverr (Cloudflare-protected), otherwise `[]`
5. `del(.id)` (remove id field)

**Response**: Returns the created indexer object on success, or a JSON **array** of validation errors on failure:
```json
[{"isWarning": false, "errorMessage": "Unable to connect...", "severity": "error"}]
```

### Test an indexer
```
POST /api/v1/indexer/test
Body: <indexer object>
```
Returns HTTP 200 on success, or validation error array on failure.

### Update an indexer
```
PUT /api/v1/indexer/{id}
Body: <full indexer object with changes>
```

### Delete an indexer
```
DELETE /api/v1/indexer/{id}
```

## Workflow

1. **List current indexers** to see what's already configured
2. **Fetch schemas** filtered to `protocol == "torrent" and privacy == "public"` for public torrent indexers
3. **Recommend indexers** based on the user's content profile, excluding already-added ones
4. **For each indexer to add**:
   a. Extract schema from the schemas response
   b. Set baseUrl to `indexerUrls[0]`
   c. POST to create
   d. If creation returns a validation error array (not an object with `.id`):
      - Try each alternate URL from `indexerUrls[]`
      - If all fail and no FlareSolverr tag, retry first URL with `tags: [1]`
      - If still failing, report and skip
   e. Report success/failure

## Recommended Public Torrent Indexers

Good general-purpose set for TV/movies/anime:

| Indexer | Notes |
|---------|-------|
| 1337x | Great general tracker, may need FlareSolverr |
| EZTV | TV-focused, often CF-protected |
| YTS | Movies, small quality encodes |
| The Pirate Bay | Broad fallback |
| kickasstorrents.to | General, often CF-protected |
| SubsPlease | Anime simulcasts |
| Knaben | Meta-search aggregator, catches what others miss |
| showRSS | RSS-based TV tracking |
| Nyaa.si | Primary anime tracker |
| TorrentGalaxyClone | Good general coverage |

## Important Notes

- Use `nix-shell -p jq` or find jq path first - this is NixOS, no global jq
- The schema response is ~600 entries and very large. Save to a temp file, don't store in shell variables
- Cloudflare-protected sites may time out even with FlareSolverr - this is normal, skip them
- The FlareSolverr proxy is tag-based: add tag `[1]` to the indexer to route through it
- Creation validates connectivity - if the site is down, creation itself fails (not just test)

## Arguments

If the user provides arguments like "add 1337x YTS" or "remove BitSearch" or "list", handle accordingly. Default behavior (no args) is to audit current indexers and suggest additions.
