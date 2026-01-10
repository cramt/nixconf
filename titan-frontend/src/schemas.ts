import { z } from "zod";

// SSH Execute
export const executeCommandBody = z.object({
  command: z.string().describe("The shell command to execute on the VM"),
  workingDirectory: z
    .string()
    .optional()
    .describe("The working directory to execute the command in"),
  timeout: z
    .number()
    .int()
    .default(30000)
    .describe("Timeout in milliseconds (default 30000)"),
});

export const executeCommandResponse = z.object({
  success: z.boolean().describe("Whether the command executed successfully"),
  exitCode: z.number().int().describe("The exit code of the command"),
  stdout: z.string().describe("Standard output from the command"),
  stderr: z.string().describe("Standard error from the command"),
  duration: z.number().int().describe("Execution time in milliseconds"),
});

// SSH Upload
export const uploadFileBody = z.object({
  path: z.string().describe("The destination path on the VM"),
  content: z.string().describe("Base64 encoded file content"),
  mode: z
    .string()
    .default("0644")
    .describe("File permissions in octal (e.g., '0755')"),
});

export const uploadFileResponse = z.object({
  success: z.boolean(),
  path: z.string().describe("The path where the file was uploaded"),
  size: z.number().int().describe("Size of the uploaded file in bytes"),
});

// SSH Download
export const downloadFileBody = z.object({
  path: z.string().describe("The path of the file to download"),
});

export const downloadFileResponse = z.object({
  success: z.boolean(),
  path: z.string().describe("The path of the downloaded file"),
  content: z.string().describe("Base64 encoded file content"),
  size: z.number().int().describe("Size of the file in bytes"),
});

// VNC Screenshot
export const screenshotQuery = z.object({
  format: z
    .enum(["png", "jpeg"])
    .optional()
    .default("png")
    .describe("Image format for the screenshot"),
  quality: z
    .string()
    .optional()
    .default("80")
    .transform((v) => parseInt(v, 10))
    .pipe(z.number().int().min(1).max(100))
    .describe("JPEG quality (1-100), only used when format is jpeg"),
});

export const screenshotResponse = z.object({
  success: z.boolean(),
  image: z.string().describe("Base64 encoded image data"),
  format: z.string().describe("Image format (png or jpeg)"),
  width: z.number().int().describe("Image width in pixels"),
  height: z.number().int().describe("Image height in pixels"),
});

// VNC Keyboard Input
export const keyboardInputBody = z.object({
  text: z
    .string()
    .optional()
    .describe("Text to type (sent as individual keystrokes)"),
  keys: z
    .array(
      z.enum([
        "enter",
        "tab",
        "escape",
        "backspace",
        "delete",
        "up",
        "down",
        "left",
        "right",
        "home",
        "end",
        "pageup",
        "pagedown",
        "f1",
        "f2",
        "f3",
        "f4",
        "f5",
        "f6",
        "f7",
        "f8",
        "f9",
        "f10",
        "f11",
        "f12",
        "ctrl+c",
        "ctrl+v",
        "ctrl+z",
        "ctrl+a",
        "ctrl+s",
        "alt+tab",
        "alt+f4",
      ])
    )
    .optional()
    .describe("Special keys or key combinations to send"),
});

export const keyboardInputResponse = z.object({
  success: z.boolean(),
});

// VNC Mouse Input
export const mouseInputBody = z.object({
  x: z.number().int().describe("X coordinate"),
  y: z.number().int().describe("Y coordinate"),
  action: z
    .enum(["move", "click", "doubleclick", "rightclick", "scroll"])
    .default("click")
    .describe("Mouse action to perform"),
  scrollDelta: z
    .number()
    .int()
    .default(0)
    .describe("Scroll amount (positive for up, negative for down)"),
});

export const mouseInputResponse = z.object({
  success: z.boolean(),
});

// VM Status
export const vmStatusResponse = z.object({
  ssh: z.object({
    connected: z.boolean().describe("Whether SSH connection is available"),
    host: z.string().describe("SSH host"),
    port: z.number().int().describe("SSH port"),
  }),
  vnc: z.object({
    connected: z.boolean().describe("Whether VNC connection is available"),
    host: z.string().describe("VNC host"),
    port: z.number().int().describe("VNC port"),
  }),
  uptime: z.string().optional().describe("VM uptime if available"),
});

// Error response
export const errorResponse = z.object({
  error: z.string().describe("Error message"),
  code: z.string().optional().describe("Error code"),
});
