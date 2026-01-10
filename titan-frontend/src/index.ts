import Fastify from "fastify";
import {
  serializerCompiler,
  validatorCompiler,
  jsonSchemaTransform,
  type ZodTypeProvider,
} from "fastify-type-provider-zod";
import fastifySwagger from "@fastify/swagger";
import fastifySwaggerUi from "@fastify/swagger-ui";
import fastifyStatic from "@fastify/static";
import { z } from "zod";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFile } from "fs/promises";

import { config } from "./config.js";
import * as schemas from "./schemas.js";
import * as ssh from "./ssh.js";
import * as vnc from "./vnc.js";

// Handle both ESM and CJS environments
const currentDir = typeof __dirname !== "undefined" 
  ? __dirname 
  : dirname(fileURLToPath(import.meta.url));

async function main() {
  const fastify = Fastify({
    logger: true,
    trustProxy: true,
  }).withTypeProvider<ZodTypeProvider>();

  // Set up Zod validators
  fastify.setValidatorCompiler(validatorCompiler);
  fastify.setSerializerCompiler(serializerCompiler);

  // Register Swagger for auto-generating OpenAPI spec from Zod schemas
  await fastify.register(fastifySwagger, {
    openapi: {
      info: {
        title: "Titan VM Controller API",
        description:
          "HTTP API for controlling the Titan VM - execute commands via SSH, transfer files via SFTP, and interact with the desktop via VNC",
        version: "1.0.0",
      },
      servers: [
        {
          url: `http://localhost:${config.server.port}`,
          description: "Local development server",
        },
      ],
      tags: [
        { name: "ssh", description: "SSH command execution and file transfer" },
        { name: "vnc", description: "VNC desktop interaction" },
        { name: "status", description: "VM status and health checks" },
      ],
      security: config.auth.apiKey ? [{ ApiKeyAuth: [] }] : [],
      components: {
        securitySchemes: {
          ApiKeyAuth: {
            type: "apiKey",
            in: "header",
            name: "X-API-KEY",
          },
        },
      },
    },
    transform: jsonSchemaTransform,
  });

  // Register Swagger UI
  await fastify.register(fastifySwaggerUi, {
    routePrefix: "/docs",
  });

  // Auth Middleware
  fastify.addHook("onRequest", async (request, reply) => {
    // Skip auth for health check, docs, and ai-plugin.json
    const publicPaths = [
      "/health",
      "/docs",
      "/openapi.json",
      "/openapi.yaml",
      "/.well-known/ai-plugin.json",
    ];
    
    // Also skip static files if they are served under /
    if (publicPaths.some(path => request.url.startsWith(path)) || request.url === "/") {
      return;
    }

    if (config.auth.apiKey) {
      const apiKey = request.headers["x-api-key"];
      // Also support Authorization: Bearer <key> as a fallback
      const authHeader = request.headers["authorization"];
      const bearerToken = authHeader?.startsWith("Bearer ") ? authHeader.substring(7) : null;

      if (apiKey !== config.auth.apiKey && bearerToken !== config.auth.apiKey) {
        reply.code(401).send({
          error: "Unauthorized",
          message: "Invalid or missing API key",
        });
      }
    }
  });


  // Read ai-plugin.json template
  const aiPluginJsonPath = join(currentDir, "..", "ai-plugin.json");
  let aiPluginTemplate = "";
  try {
    aiPluginTemplate = await readFile(aiPluginJsonPath, "utf-8");
  } catch (err) {
    console.error("Failed to read ai-plugin.json:", err);
  }

  // Serve dynamic ai-plugin.json
  fastify.get("/.well-known/ai-plugin.json", async (request, reply) => {
    const protocol = request.protocol;
    const host = request.hostname;
    const baseUrl = `${protocol}://${host}`;
    
    // Replace localhost:3000 with actual host
    const content = aiPluginTemplate.replace(
      /http:\/\/localhost:3000/g,
      baseUrl
    );
    
    return reply.type("application/json").send(JSON.parse(content));
  });

  // Serve static files (logo, etc.) - excluding ai-plugin.json which is handled above
  await fastify.register(fastifyStatic, {
    root: join(currentDir, ".."),
    prefix: "/",
    decorateReply: false,
    // Don't serve ai-plugin.json statically
    setHeaders: (res, path) => {
      if (path.endsWith("ai-plugin.json")) {
        // This shouldn't be reached due to the route above, but just in case
        res.setHeader("Cache-Control", "no-store");
      }
    }
  });

  // Health check
  fastify.get(
    "/health",
    {
      schema: {
        tags: ["status"],
        summary: "Health check endpoint",
        response: {
          200: z.object({
            status: z.literal("ok"),
            timestamp: z.string(),
          }),
        },
      },
    },
    async () => {
      return {
        status: "ok" as const,
        timestamp: new Date().toISOString(),
      };
    }
  );

  // VM Status
  fastify.get(
    "/api/status",
    {
      schema: {
        tags: ["status"],
        summary: "Get VM connection status",
        description:
          "Returns the current connection status for SSH and VNC, including connectivity tests",
        response: {
          200: schemas.vmStatusResponse,
        },
      },
    },
    async () => {
      const [sshConnected, vncConnected] = await Promise.all([
        ssh.testConnection(),
        vnc.testConnection(),
      ]);

      let uptime: string | undefined;
      if (sshConnected) {
        try {
          const result = await ssh.executeCommand("uptime -p", undefined, 5000);
          if (result.success) {
            uptime = result.stdout.trim();
          }
        } catch {
          // Ignore uptime errors
        }
      }

      return {
        ssh: {
          connected: sshConnected,
          host: config.ssh.host,
          port: config.ssh.port,
        },
        vnc: {
          connected: vncConnected,
          host: config.vnc.host,
          port: config.vnc.port,
        },
        uptime,
      };
    }
  );

  // SSH Execute Command
  fastify.post(
    "/api/ssh/execute",
    {
      schema: {
        tags: ["ssh"],
        summary: "Execute a shell command on the VM",
        description:
          "Executes the given shell command via SSH and returns stdout, stderr, and exit code",
        body: schemas.executeCommandBody,
        response: {
          200: schemas.executeCommandResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { command, workingDirectory, timeout } = request.body;
        const result = await ssh.executeCommand(
          command,
          workingDirectory,
          timeout
        );
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "SSH_EXECUTE_ERROR",
        };
      }
    }
  );

  // SSH Upload File
  fastify.post(
    "/api/ssh/upload",
    {
      schema: {
        tags: ["ssh"],
        summary: "Upload a file to the VM",
        description:
          "Uploads a base64-encoded file to the specified path on the VM via SFTP",
        body: schemas.uploadFileBody,
        response: {
          200: schemas.uploadFileResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { path, content, mode } = request.body;
        const result = await ssh.uploadFile(path, content, mode);
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "SSH_UPLOAD_ERROR",
        };
      }
    }
  );

  // SSH Download File
  fastify.post(
    "/api/ssh/download",
    {
      schema: {
        tags: ["ssh"],
        summary: "Download a file from the VM",
        description:
          "Downloads a file from the specified path on the VM and returns it as base64",
        body: schemas.downloadFileBody,
        response: {
          200: schemas.downloadFileResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { path } = request.body;
        const result = await ssh.downloadFile(path);
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "SSH_DOWNLOAD_ERROR",
        };
      }
    }
  );

  // VNC Screenshot
  fastify.get(
    "/api/vnc/screenshot",
    {
      schema: {
        tags: ["vnc"],
        summary: "Capture a screenshot of the VM display",
        description:
          "Captures the current VNC framebuffer and returns it as a base64-encoded image",
        querystring: schemas.screenshotQuery,
        response: {
          200: schemas.screenshotResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { format, quality } = request.query;
        const result = await vnc.getScreenshot(format, quality);
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "VNC_SCREENSHOT_ERROR",
        };
      }
    }
  );

  // VNC Keyboard Input
  fastify.post(
    "/api/vnc/keyboard",
    {
      schema: {
        tags: ["vnc"],
        summary: "Send keyboard input to the VM",
        description:
          "Sends text and/or special key combinations to the VM via VNC",
        body: schemas.keyboardInputBody,
        response: {
          200: schemas.keyboardInputResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { text, keys } = request.body;
        const result = await vnc.sendKeyboardInput(text, keys);
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "VNC_KEYBOARD_ERROR",
        };
      }
    }
  );

  // VNC Mouse Input
  fastify.post(
    "/api/vnc/mouse",
    {
      schema: {
        tags: ["vnc"],
        summary: "Send mouse input to the VM",
        description:
          "Sends mouse movement, clicks, or scroll events to the VM via VNC",
        body: schemas.mouseInputBody,
        response: {
          200: schemas.mouseInputResponse,
          500: schemas.errorResponse,
        },
      },
    },
    async (request, reply) => {
      try {
        const { x, y, action, scrollDelta } = request.body;
        const result = await vnc.sendMouseInput(x, y, action, scrollDelta);
        return result;
      } catch (error) {
        reply.status(500);
        return {
          error: error instanceof Error ? error.message : "Unknown error",
          code: "VNC_MOUSE_ERROR",
        };
      }
    }
  );

  // Serve OpenAPI spec as YAML (for ai-plugin.json reference)
  fastify.get("/openapi.yaml", async (_request, reply) => {
    const yaml = fastify.swagger({ yaml: true });
    reply.type("text/yaml").send(yaml);
  });

  // Serve OpenAPI spec as JSON
  fastify.get("/openapi.json", async (_request, reply) => {
    const json = fastify.swagger();
    reply.type("application/json").send(json);
  });

  // Start the server
  try {
    await fastify.listen({
      port: config.server.port,
      host: config.server.host,
    });

    console.log(`
Titan VM Frontend API running at http://${config.server.host}:${config.server.port}

Endpoints:
  - Swagger UI:     http://localhost:${config.server.port}/docs
  - OpenAPI JSON:   http://localhost:${config.server.port}/openapi.json
  - OpenAPI YAML:   http://localhost:${config.server.port}/openapi.yaml
  - AI Plugin:      http://localhost:${config.server.port}/.well-known/ai-plugin.json
  - Health:         http://localhost:${config.server.port}/health
  - VM Status:      http://localhost:${config.server.port}/api/status

SSH Config:
  - Host: ${config.ssh.host}:${config.ssh.port}
  - User: ${config.ssh.username}

VNC Config:
  - Host: ${config.vnc.host}:${config.vnc.port}
`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

main();
