import { Hono } from "hono";
import * as QRCode from "qrcode";

const app = new Hono();

const DEFAULT_COUNT = 12;
const MAX_COUNT = 250;

type Code = {
  value: string;
  svg: string;
};

const escapeHtml = (value: string): string =>
  value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      case "'":
        return "&#39;";
      default:
        return char;
    }
  });

const parseCount = (url: URL): number => {
  const raw = url.searchParams.get("n") ?? url.searchParams.get("N") ?? url.searchParams.get("count");

  if (raw === null || raw.trim() === "") {
    return DEFAULT_COUNT;
  }

  const count = Number.parseInt(raw, 10);

  if (!Number.isFinite(count) || count < 1) {
    return DEFAULT_COUNT;
  }

  return Math.min(count, MAX_COUNT);
};

const randomValue = (): string => {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);

  return `REZIP-${Array.from(bytes, (byte) => byte.toString(36).padStart(2, "0")).join("").toUpperCase()}`;
};

const makeCode = async (): Promise<Code> => {
  const value = randomValue();
  const svg = await QRCode.toString(value, {
    type: "svg",
    margin: 1,
    width: 256,
    errorCorrectionLevel: "M"
  });

  return { value, svg };
};

const renderPage = (codes: Code[], count: number): string => {
  const cards = codes
    .map(
      ({ value, svg }, index) => `<article class="card">
        <div class="index">${index + 1}</div>
        <div class="qr">${svg}</div>
        <code>${escapeHtml(value)}</code>
      </article>`
    )
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${count} random QR codes</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: Canvas;
      color: CanvasText;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      padding: 2rem;
    }

    main {
      max-width: 72rem;
      margin: 0 auto;
    }

    header {
      display: flex;
      flex-wrap: wrap;
      gap: 1rem;
      align-items: end;
      justify-content: space-between;
      margin-bottom: 1.5rem;
    }

    h1 {
      margin: 0;
      font-size: clamp(1.5rem, 4vw, 2.5rem);
    }

    p {
      margin: 0.25rem 0 0;
      color: color-mix(in oklab, CanvasText 70%, Canvas);
    }

    form {
      display: flex;
      gap: 0.5rem;
      align-items: center;
    }

    input {
      width: 6rem;
      padding: 0.55rem 0.7rem;
      border: 1px solid color-mix(in oklab, CanvasText 25%, Canvas);
      border-radius: 0.6rem;
      background: Canvas;
      color: CanvasText;
      font: inherit;
    }

    button, a.button {
      border: 0;
      border-radius: 0.6rem;
      padding: 0.6rem 0.85rem;
      background: #dc2626;
      color: white;
      font: inherit;
      font-weight: 700;
      text-decoration: none;
      cursor: pointer;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
      gap: 1rem;
    }

    .card {
      position: relative;
      display: grid;
      gap: 0.75rem;
      justify-items: center;
      padding: 1rem;
      border: 1px solid color-mix(in oklab, CanvasText 12%, Canvas);
      border-radius: 1rem;
      background: color-mix(in oklab, Canvas 96%, CanvasText);
      break-inside: avoid;
      box-shadow: 0 0.5rem 1.5rem color-mix(in oklab, CanvasText 8%, transparent);
    }

    .index {
      position: absolute;
      top: 0.75rem;
      left: 0.75rem;
      min-width: 1.5rem;
      height: 1.5rem;
      border-radius: 999px;
      display: grid;
      place-items: center;
      background: color-mix(in oklab, CanvasText 12%, Canvas);
      font-size: 0.75rem;
      font-weight: 700;
    }

    .qr {
      width: min(100%, 14rem);
      aspect-ratio: 1;
    }

    .qr svg {
      display: block;
      width: 100%;
      height: auto;
      background: white;
      border-radius: 0.5rem;
    }

    code {
      max-width: 100%;
      overflow-wrap: anywhere;
      font-size: 0.8rem;
      text-align: center;
    }

    @media print {
      body {
        padding: 0;
      }

      header {
        display: none;
      }

      main {
        max-width: none;
      }

      .grid {
        grid-template-columns: repeat(3, 1fr);
        gap: 0.4cm;
      }

      .card {
        box-shadow: none;
        border-color: #ddd;
      }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>${count} random QR codes</h1>
        <p>Use <code>?n=24</code> to choose how many to generate. Refresh for a fresh batch.</p>
      </div>
      <form method="get">
        <label for="n">Count</label>
        <input id="n" name="n" type="number" min="1" max="${MAX_COUNT}" value="${count}">
        <button type="submit">Generate</button>
        <a class="button" href="?n=${count}">Refresh</a>
      </form>
    </header>
    <section class="grid">${cards}</section>
  </main>
</body>
</html>`;
};

app.get("/", async (c) => {
  const url = new URL(c.req.url);
  const count = parseCount(url);
  const codes = await Promise.all(Array.from({ length: count }, makeCode));

  return c.html(renderPage(codes, count));
});

export default app;
