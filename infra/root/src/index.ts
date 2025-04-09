import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => {
  return c.redirect("https://github.com/cramt");
});

export default app;
