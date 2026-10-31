// Alertmanager webhook receiver that turns each alert into a Discord DM from
// the yelliv bot. Alertmanager's own discord_configs only speaks channel
// webhooks, and a DM is the thing that actually buzzes the phone.
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const listen = new URL(requiredEnv("ALERT_DM_LISTEN"));
const recipient = requiredEnv("ALERT_DM_RECIPIENT");
// systemd LoadCredential, so the token never sits in the environment.
const token = readFileSync(join(requiredEnv("CREDENTIALS_DIRECTORY"), "bot-token"), "utf8").trim();

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

// The slice of Alertmanager's webhook payload (version 4) this reads.
type Alert = {
  status: "firing" | "resolved";
  labels: Record<string, string>;
  annotations: Record<string, string>;
};
type Payload = { alerts: Alert[] };

function render(alert: Alert): string {
  const summary = alert.annotations.summary ?? alert.labels.alertname ?? "unnamed alert";
  if (alert.status === "resolved") return `💚 ${summary} — sorted`;
  const description = alert.annotations.description;
  return description ? `🚨 ${summary}\n${description}` : `🚨 ${summary}`;
}

async function discord(path: string, body: unknown): Promise<unknown> {
  const res = await fetch(`https://discord.com/api/v10${path}`, {
    method: "POST",
    headers: { Authorization: `Bot ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`discord ${path}: ${res.status} ${await res.text()}`);
  return res.json();
}

async function dm(content: string): Promise<void> {
  // Idempotent: Discord hands back the existing DM channel every time.
  const channel = (await discord("/users/@me/channels", { recipient_id: recipient })) as { id: string };
  await discord(`/channels/${channel.id}/messages`, { content });
}

createServer(async (req, res) => {
  try {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const payload = JSON.parse(Buffer.concat(chunks).toString("utf8")) as Payload;
    for (const alert of payload.alerts) await dm(render(alert));
    res.writeHead(200).end();
  } catch (err) {
    console.error(err);
    // A 5xx makes Alertmanager retry, which is what a Discord hiccup wants.
    res.writeHead(502).end(String(err));
  }
}).listen(Number(listen.port), listen.hostname);
