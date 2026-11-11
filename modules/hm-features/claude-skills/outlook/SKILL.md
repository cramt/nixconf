---
name: outlook
description: Read and answer Alex's work email (AO@re-zip.com) in Outlook on the web. Use when she says to look at, check, find or reply to an email, or answer someone by mail.
---

# outlook

`outlook-browser` is agent-browser pinned to one persistent session and Chrome
profile, so the sign-in sticks between runs. Every browser command in this skill
goes through it, never bare `agent-browser`. For the agent-browser command set,
run `agent-browser skills get core`.

## 1. Sign in

```bash
outlook-browser login
```

It's idempotent: it opens Outlook and does the Microsoft sign-in only if the
session is logged out (password, then a TOTP code from the account secret). It
prints `signed in: …` when done. Credentials never touch your context, so don't go
reading the secret file.

## 2. Find the email

The inbox list is `[role=option]` rows. To list them, or search:

```bash
outlook-browser eval '[...document.querySelectorAll("[role=option]")].slice(0,15).map(e=>e.innerText.replace(/\s+/g," ").slice(0,160))'
outlook-browser snapshot -i | grep -i '<sender or subject>'
```

Clicking a row's `@ref` sometimes doesn't open it. If Reply stays disabled, click
the row with `mouse move/down/up` at its coordinates from a screenshot. Read the
open thread with:

```bash
outlook-browser eval 'document.querySelector("[role=main]").innerText.slice(0,4000)'
```

Forwarded mail carries the real conversation quoted inside it. Read all of it
before answering.

## 3. Write the reply

Draft in Alex's voice: load `write-like-alex`. Answer in the language the thread
is in (usually Danish). Internal mail to colleagues gets her casual register;
mail to customers gets her public-facing register (capitals, punctuation, a
"Hej <name>" opener and "Alex" sign-off).

Sending is irreversible. Send without asking only when Alex told you to respond
or send. Otherwise show her the draft first. A new recipient she didn't name,
such as a customer, needs her go-ahead.

## 4. Send it

- **Reply**: open the email and click the `Reply` button (not `Reply all` unless
  the thread needs it).
- **New mail**: `New email`. `To` and `Cc` are contenteditable fields: click one,
  `keyboard type` the address, then `press Enter` to resolve it. `fill` the
  `Subject` textbox.
- **Body**: click `Message body`, then type it one line at a time. `keyboard
  inserttext` per line, `press Enter` between lines. Multi-line strings lose
  their line breaks.

Before clicking `Send`, check the recipients with `get text` on the To/Cc refs
and take a screenshot of the body. Afterwards, confirm the mail is the top row of
Sent Items (`open https://outlook.office.com/mail/sentitems`, then the
`[role=option]` eval).
