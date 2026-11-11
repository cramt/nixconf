// Microsoft opens sign-in with a passkey prompt, which headless Chrome can
// never answer, so the page hangs on it. An empty virtual authenticator makes
// the WebAuthn request fail at once, and Microsoft then offers "Use my password".
// The authenticator lives only as long as this CDP connection, so the process
// stays up until outlook-browser kills it after login.
const browserWs = process.argv[2]
const port = new URL(browserWs).port
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()

for (const target of targets.filter((t) => t.type === "page")) {
    const ws = new WebSocket(target.webSocketDebuggerUrl)
    await new Promise((resolve) => ws.addEventListener("open", resolve))
    let nextId = 0
    const send = (method, params = {}) =>
        new Promise((resolve) => {
            const id = ++nextId
            const onMessage = (event) => {
                const msg = JSON.parse(event.data)
                if (msg.id !== id) return
                ws.removeEventListener("message", onMessage)
                resolve(msg)
            }
            ws.addEventListener("message", onMessage)
            ws.send(JSON.stringify({ id, method, params }))
        })
    await send("WebAuthn.enable", { enableUI: false })
    await send("WebAuthn.addVirtualAuthenticator", {
        options: {
            protocol: "ctap2",
            transport: "internal",
            hasResidentKey: true,
            hasUserVerification: true,
            isUserVerified: false,
            automaticPresenceSimulation: true,
        },
    })
}
console.log("stub attached")
setTimeout(() => process.exit(0), 10 * 60 * 1000)
