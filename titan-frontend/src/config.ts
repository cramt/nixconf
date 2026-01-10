export const config = {
  server: {
    port: parseInt(process.env.PORT || "3000", 10),
    host: process.env.HOST || "0.0.0.0",
  },
  ssh: {
    host: process.env.SSH_HOST || "127.0.0.1",
    port: parseInt(process.env.SSH_PORT || "46437", 10),
    username: process.env.SSH_USERNAME || "cramt",
    password: process.env.SSH_PASSWORD || "titan",
  },
  vnc: {
    host: process.env.VNC_HOST || "127.0.0.1",
    port: parseInt(process.env.VNC_PORT || "14859", 10),
  },
  auth: {
    apiKey: process.env.TITAN_API_KEY || process.env.API_KEY,
  },
};
