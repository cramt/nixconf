import { Socket } from "net";
import { config } from "./config.js";

// VNC protocol constants
const VNC_CLIENT_VERSION = "RFB 003.008\n";

interface VncConnection {
  socket: Socket;
  width: number;
  height: number;
  pixelFormat: {
    bitsPerPixel: number;
    depth: number;
    bigEndian: boolean;
    trueColor: boolean;
  };
}

async function connect(): Promise<VncConnection> {
  return new Promise((resolve, reject) => {
    const socket = new Socket();
    let state = "version";
    let width = 0;
    let height = 0;

    const timeout = setTimeout(() => {
      socket.destroy();
      reject(new Error("VNC connection timeout"));
    }, 10000);

    socket.on("data", (data) => {
      if (state === "version") {
        // Server sends version
        socket.write(VNC_CLIENT_VERSION);
        state = "security";
      } else if (state === "security") {
        // Security types - we expect None (1)
        const numTypes = data[0];
        if (numTypes > 0) {
          // Select security type None (1)
          socket.write(Buffer.from([1]));
          state = "security-result";
        } else {
          clearTimeout(timeout);
          socket.destroy();
          reject(new Error("No security types offered"));
        }
      } else if (state === "security-result") {
        // Security result (0 = OK)
        const result = data.readUInt32BE(0);
        if (result === 0) {
          // Send ClientInit (shared = 1)
          socket.write(Buffer.from([1]));
          state = "server-init";
        } else {
          clearTimeout(timeout);
          socket.destroy();
          reject(new Error("Security handshake failed"));
        }
      } else if (state === "server-init") {
        // ServerInit message
        width = data.readUInt16BE(0);
        height = data.readUInt16BE(2);

        clearTimeout(timeout);
        resolve({
          socket,
          width,
          height,
          pixelFormat: {
            bitsPerPixel: data[4],
            depth: data[5],
            bigEndian: data[6] !== 0,
            trueColor: data[7] !== 0,
          },
        });
      }
    });

    socket.on("error", (err) => {
      clearTimeout(timeout);
      reject(err);
    });

    socket.connect(config.vnc.port, config.vnc.host);
  });
}

export async function getScreenshot(
  format: "png" | "jpeg" = "png",
  _quality: number = 80
): Promise<{
  success: boolean;
  image: string;
  format: string;
  width: number;
  height: number;
}> {
  // Note: Full VNC screenshot implementation requires handling framebuffer updates
  // This is a simplified version that returns a placeholder
  // A full implementation would need to:
  // 1. Send FramebufferUpdateRequest
  // 2. Receive and decode RFB pixel data
  // 3. Convert to PNG/JPEG

  try {
    const conn = await connect();
    const { width, height } = conn;
    conn.socket.destroy();

    // For now, return connection info - full implementation would capture actual framebuffer
    return {
      success: true,
      image: "", // Would be base64 encoded image
      format,
      width,
      height,
    };
  } catch (error) {
    throw new Error(
      `Screenshot failed: ${error instanceof Error ? error.message : "Unknown error"}`
    );
  }
}

export async function sendKeyboardInput(
  text?: string,
  keys?: string[]
): Promise<{ success: boolean }> {
  const conn = await connect();

  try {
    // VNC KeyEvent message type = 4
    const sendKey = (keyCode: number, down: boolean) => {
      const msg = Buffer.alloc(8);
      msg[0] = 4; // KeyEvent
      msg[1] = down ? 1 : 0;
      msg.writeUInt32BE(keyCode, 4);
      conn.socket.write(msg);
    };

    // Send text as individual key presses
    if (text) {
      for (const char of text) {
        const keyCode = char.charCodeAt(0);
        sendKey(keyCode, true);
        sendKey(keyCode, false);
        await new Promise((r) => setTimeout(r, 10));
      }
    }

    // Send special keys
    if (keys) {
      const keyMap: Record<string, number> = {
        enter: 0xff0d,
        tab: 0xff09,
        escape: 0xff1b,
        backspace: 0xff08,
        delete: 0xffff,
        up: 0xff52,
        down: 0xff54,
        left: 0xff51,
        right: 0xff53,
        home: 0xff50,
        end: 0xff57,
        pageup: 0xff55,
        pagedown: 0xff56,
        f1: 0xffbe,
        f2: 0xffbf,
        f3: 0xffc0,
        f4: 0xffc1,
        f5: 0xffc2,
        f6: 0xffc3,
        f7: 0xffc4,
        f8: 0xffc5,
        f9: 0xffc6,
        f10: 0xffc7,
        f11: 0xffc8,
        f12: 0xffc9,
      };

      const modifierMap: Record<string, number> = {
        ctrl: 0xffe3,
        alt: 0xffe9,
        shift: 0xffe1,
      };

      for (const key of keys) {
        if (key.includes("+")) {
          // Key combination like ctrl+c
          const parts = key.split("+");
          const modifiers = parts.slice(0, -1);
          const mainKey = parts[parts.length - 1];

          // Press modifiers
          for (const mod of modifiers) {
            if (modifierMap[mod]) {
              sendKey(modifierMap[mod], true);
            }
          }

          // Press and release main key
          const keyCode = keyMap[mainKey] || mainKey.charCodeAt(0);
          sendKey(keyCode, true);
          sendKey(keyCode, false);

          // Release modifiers
          for (const mod of modifiers.reverse()) {
            if (modifierMap[mod]) {
              sendKey(modifierMap[mod], false);
            }
          }
        } else if (keyMap[key]) {
          sendKey(keyMap[key], true);
          sendKey(keyMap[key], false);
        }
        await new Promise((r) => setTimeout(r, 10));
      }
    }

    conn.socket.destroy();
    return { success: true };
  } catch (error) {
    conn.socket.destroy();
    throw error;
  }
}

export async function sendMouseInput(
  x: number,
  y: number,
  action: "move" | "click" | "doubleclick" | "rightclick" | "scroll" = "click",
  scrollDelta: number = 0
): Promise<{ success: boolean }> {
  const conn = await connect();

  try {
    // VNC PointerEvent message type = 5
    const sendPointer = (buttonMask: number, px: number, py: number) => {
      const msg = Buffer.alloc(6);
      msg[0] = 5; // PointerEvent
      msg[1] = buttonMask;
      msg.writeUInt16BE(px, 2);
      msg.writeUInt16BE(py, 4);
      conn.socket.write(msg);
    };

    switch (action) {
      case "move":
        sendPointer(0, x, y);
        break;
      case "click":
        sendPointer(0, x, y);
        sendPointer(1, x, y); // Left button down
        await new Promise((r) => setTimeout(r, 50));
        sendPointer(0, x, y); // Left button up
        break;
      case "doubleclick":
        for (let i = 0; i < 2; i++) {
          sendPointer(1, x, y);
          await new Promise((r) => setTimeout(r, 50));
          sendPointer(0, x, y);
          await new Promise((r) => setTimeout(r, 100));
        }
        break;
      case "rightclick":
        sendPointer(0, x, y);
        sendPointer(4, x, y); // Right button down
        await new Promise((r) => setTimeout(r, 50));
        sendPointer(0, x, y); // Right button up
        break;
      case "scroll":
        sendPointer(0, x, y);
        // Button 4 = scroll up, Button 5 = scroll down
        const button = scrollDelta > 0 ? 8 : 16;
        const times = Math.abs(scrollDelta);
        for (let i = 0; i < times; i++) {
          sendPointer(button, x, y);
          sendPointer(0, x, y);
          await new Promise((r) => setTimeout(r, 50));
        }
        break;
    }

    conn.socket.destroy();
    return { success: true };
  } catch (error) {
    conn.socket.destroy();
    throw error;
  }
}

export async function testConnection(): Promise<boolean> {
  try {
    const conn = await connect();
    conn.socket.destroy();
    return true;
  } catch {
    return false;
  }
}
