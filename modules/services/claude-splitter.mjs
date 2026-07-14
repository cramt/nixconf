// Model-based splitter in front of Claude Code's single ANTHROPIC_BASE_URL.
// Branches on the request body's `model`:
//   * M365 slugs (env M365_SLUGS) -> LiteLLM (LITELLM_URL), which translates to
//     the M365 Copilot proxy.
//   * everything else -> Anthropic (ANTHROPIC_URL) verbatim, forwarding the
//     client's Authorization header untouched so subscription OAuth is preserved.
// Zero deps on purpose: it only routes bytes, never transforms them.
import http from 'node:http';
import https from 'node:https';

const PORT = Number(process.env.SPLIT_PORT);
const M365 = new Set((process.env.M365_SLUGS || '').split(',').filter(Boolean));
const LITELLM = process.env.LITELLM_URL;
const ANTHROPIC = process.env.ANTHROPIC_URL;

http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    let model = '';
    try { model = JSON.parse(body.toString() || '{}').model || ''; } catch { /* non-JSON: falls through to Anthropic */ }
    const toM365 = M365.has(model);
    const u = new URL((toM365 ? LITELLM : ANTHROPIC) + req.url);
    const mod = u.protocol === 'https:' ? https : http;
    // Forward client headers verbatim; Authorization stays intact for Anthropic.
    const headers = { ...req.headers, host: u.host };
    delete headers['content-length'];
    const up = mod.request(u, { method: req.method, headers }, (r) => {
      res.writeHead(r.statusCode, r.headers);
      r.pipe(res);
    });
    up.on('error', (e) => {
      if (!res.headersSent) res.writeHead(502);
      res.end('claude-splitter upstream error: ' + e.message);
    });
    up.end(body);
  });
}).listen(PORT, '127.0.0.1', () => console.error('claude-splitter listening on ' + PORT));
