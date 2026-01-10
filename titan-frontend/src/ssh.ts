import { Client, SFTPWrapper } from "ssh2";
import { config } from "./config.js";

export interface CommandResult {
  success: boolean;
  exitCode: number;
  stdout: string;
  stderr: string;
  duration: number;
}

export async function executeCommand(
  command: string,
  workingDirectory?: string,
  timeout: number = 30000
): Promise<CommandResult> {
  const startTime = Date.now();

  return new Promise((resolve, reject) => {
    const conn = new Client();
    let stdout = "";
    let stderr = "";
    let exitCode = 0;

    const timeoutId = setTimeout(() => {
      conn.end();
      reject(new Error(`Command timed out after ${timeout}ms`));
    }, timeout);

    conn.on("ready", () => {
      const cmd = workingDirectory
        ? `cd ${workingDirectory} && ${command}`
        : command;

      conn.exec(cmd, (err, stream) => {
        if (err) {
          clearTimeout(timeoutId);
          conn.end();
          reject(err);
          return;
        }

        stream.on("close", (code: number) => {
          clearTimeout(timeoutId);
          exitCode = code ?? 0;
          conn.end();
          resolve({
            success: exitCode === 0,
            exitCode,
            stdout,
            stderr,
            duration: Date.now() - startTime,
          });
        });

        stream.on("data", (data: Buffer) => {
          stdout += data.toString();
        });

        stream.stderr.on("data", (data: Buffer) => {
          stderr += data.toString();
        });
      });
    });

    conn.on("error", (err) => {
      clearTimeout(timeoutId);
      reject(err);
    });

    conn.connect({
      host: config.ssh.host,
      port: config.ssh.port,
      username: config.ssh.username,
      password: config.ssh.password,
    });
  });
}

export async function uploadFile(
  path: string,
  content: string,
  mode: string = "0644"
): Promise<{ success: boolean; path: string; size: number }> {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const buffer = Buffer.from(content, "base64");

    conn.on("ready", () => {
      conn.sftp((err, sftp) => {
        if (err) {
          conn.end();
          reject(err);
          return;
        }

        const writeStream = sftp.createWriteStream(path, {
          mode: parseInt(mode, 8),
        });

        writeStream.on("close", () => {
          conn.end();
          resolve({
            success: true,
            path,
            size: buffer.length,
          });
        });

        writeStream.on("error", (err: Error) => {
          conn.end();
          reject(err);
        });

        writeStream.end(buffer);
      });
    });

    conn.on("error", reject);

    conn.connect({
      host: config.ssh.host,
      port: config.ssh.port,
      username: config.ssh.username,
      password: config.ssh.password,
    });
  });
}

export async function downloadFile(
  path: string
): Promise<{ success: boolean; path: string; content: string; size: number }> {
  return new Promise((resolve, reject) => {
    const conn = new Client();
    const chunks: Buffer[] = [];

    conn.on("ready", () => {
      conn.sftp((err, sftp) => {
        if (err) {
          conn.end();
          reject(err);
          return;
        }

        const readStream = sftp.createReadStream(path);

        readStream.on("data", (chunk: Buffer) => {
          chunks.push(chunk);
        });

        readStream.on("close", () => {
          conn.end();
          const buffer = Buffer.concat(chunks);
          resolve({
            success: true,
            path,
            content: buffer.toString("base64"),
            size: buffer.length,
          });
        });

        readStream.on("error", (err: Error) => {
          conn.end();
          reject(err);
        });
      });
    });

    conn.on("error", reject);

    conn.connect({
      host: config.ssh.host,
      port: config.ssh.port,
      username: config.ssh.username,
      password: config.ssh.password,
    });
  });
}

export async function testConnection(): Promise<boolean> {
  return new Promise((resolve) => {
    const conn = new Client();

    const timeout = setTimeout(() => {
      conn.end();
      resolve(false);
    }, 5000);

    conn.on("ready", () => {
      clearTimeout(timeout);
      conn.end();
      resolve(true);
    });

    conn.on("error", () => {
      clearTimeout(timeout);
      resolve(false);
    });

    conn.connect({
      host: config.ssh.host,
      port: config.ssh.port,
      username: config.ssh.username,
      password: config.ssh.password,
    });
  });
}
