// Pi extension: a `generate_image` tool backed by the M365 Copilot proxy's
// /v1/images/generations. Copilot only draws on tool-less chat turns, and an
// agent always sends tools, so the drawing has to be its own call.
// @endpoint@ is filled in by nix (modules/services/m365-copilot-proxy.nix).

import { StringEnum, Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

const ENDPOINT = "@endpoint@";

const generateImage = defineTool({
  name: "generate_image",
  label: "Generate image",
  description:
    "Draw an image with Microsoft 365 Copilot's image generator and save it as a PNG. " +
    "Takes about a minute. Returns the saved file's absolute path and shows you the image. " +
    "One image per call; there is a daily image quota, so don't generate variations nobody asked for.",
  parameters: Type.Object({
    prompt: Type.String({ description: "What to draw. Describe subject, style, composition and colours." }),
    path: Type.Optional(
      Type.String({ description: "Where to save the PNG, relative to the working directory. Defaults to a timestamped name in it." }),
    ),
    orientation: Type.Optional(StringEnum(["landscape", "portrait", "square"] as const)),
    style: Type.Optional(
      StringEnum(["natural", "icon", "story", "designer"] as const, {
        description: "natural: as described (default); icon: app icon; story: multi-panel illustration; designer: graphic-design composition.",
      }),
    ),
  }),

  async execute(_toolCallId, params, signal, onUpdate, ctx) {
    onUpdate?.({ content: [{ type: "text", text: "Drawing (about a minute)..." }], details: {} });
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt: params.prompt, orientation: params.orientation, style: params.style }),
      signal,
    });
    const body: any = await res.json().catch(() => null);
    const b64: string | undefined = body?.data?.[0]?.b64_json;
    if (!res.ok || !b64) {
      throw new Error(`Image generation failed (HTTP ${res.status}): ${body?.error?.message ?? "no image in the response"}`);
    }

    const name = params.path ?? `m365-image-${new Date().toISOString().replace(/[:.]/g, "-")}.png`;
    const file = isAbsolute(name) ? name : resolve(join(ctx.cwd, name));
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, Buffer.from(b64, "base64"));

    return {
      content: [
        { type: "text", text: `Saved to ${file}` },
        { type: "image", data: b64, mimeType: "image/png" },
      ],
      details: { path: file },
    };
  },
});

// T3 Code's Pi bridge activates every one of its ~80 MCP tools up front for
// openai-completions models (its mcpExtensionSource.ts, reconcileDiscovery),
// because some gateways drop calls to undeclared tools. M365 Copilot can't
// carry that: with them declared, gpt-5.5-think-deeper answered "no tool is
// available" 3/3 times, against reliable tool calls with Pi's own five. So on
// the m365 provider, drop them again. This handler runs after T3's because
// CLI extensions (T3 passes its bridge with -e) load before discovered ones.
const T3_TOOL_PREFIXES = ["mcp__t3-code__", "mcp__t3_code__"];

function dropT3ToolsOnM365(pi: ExtensionAPI, ctx: { model?: { provider?: string } }) {
  if (ctx.model?.provider !== "m365") return;
  const active = pi.getActiveTools();
  const kept = active.filter((name) => !T3_TOOL_PREFIXES.some((p) => name.startsWith(p)));
  if (kept.length !== active.length) pi.setActiveTools(kept);
}

export default function (pi: ExtensionAPI) {
  pi.registerTool(generateImage);
  pi.on("session_start", (_event, ctx) => dropT3ToolsOnM365(pi, ctx));
  pi.on("model_select", (_event, ctx) => dropT3ToolsOnM365(pi, ctx));
  pi.on("before_agent_start", (_event, ctx) => dropT3ToolsOnM365(pi, ctx));
}
