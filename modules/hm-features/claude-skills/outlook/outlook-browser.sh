# outlook-browser: agent-browser pinned to one persistent session and profile,
# so Alex's Outlook sign-in survives browser restarts.
#
#   outlook-browser login        sign in if needed (idempotent)
#   outlook-browser <args...>    any agent-browser command in that session
#
# CREDS_FILE and STUB are substituted in by nix (myLib/agent-skills.nix).

export AGENT_BROWSER_SESSION=outlook
export AGENT_BROWSER_PROFILE="${XDG_STATE_HOME:-$HOME/.local/state}/outlook-browser/profile"
mkdir -p "$AGENT_BROWSER_PROFILE"

if [ "${1:-}" != "login" ]; then
    exec agent-browser "$@"
fi

cred() { jq -r --arg k "$1" '.[$k]' "$CREDS_FILE"; }

# Which step of Microsoft's sign-in flow the page is on. Selectors are the
# login.microsoftonline.com form names, stable for years; text matches cover
# the method pickers, which have no stable ids.
STATE_JS='(() => {
  const vis = (s) => { const e = document.querySelector(s); return !!(e && e.offsetParent) }
  const t = document.body ? document.body.innerText : ""
  if (/^outlook\./.test(location.host)) return "done"
  if (vis("input[name=otc]")) return "otc"
  if (vis("input[name=passwd]")) return "password"
  if (vis("input[name=loginfmt]")) return "email"
  if (t.includes("Use my password")) return "choose"
  if (t.includes("Use a verification code")) return "verify"
  if (t.includes("Stay signed in")) return "kmsi"
  return "wait"
})()'

click_text() {
    agent-browser eval "(() => { const el = [...document.querySelectorAll('button, [role=button], [role=link], a, div[data-value]')].find((e) => e.innerText.trim() === $(jq -Rn --arg s "$1" '$s')); if (!el) return 'missing'; el.click(); return 'ok' })()" >/dev/null
}

agent-browser open https://outlook.office.com/mail/ >/dev/null
agent-browser wait 4000 >/dev/null

stub_pid=""
trap '[ -n "$stub_pid" ] && kill "$stub_pid" 2>/dev/null || true' EXIT

otc_tries=0
for _ in $(seq 1 45); do
    state=$(agent-browser eval "$STATE_JS" | tr -d '"')
    case "$state" in
        done)
            echo "signed in: $(agent-browser get title)"
            exit 0
            ;;
        email)
            if [ -z "$stub_pid" ]; then
                node "$STUB" "$(agent-browser get cdp-url)" >/dev/null &
                stub_pid=$!
                sleep 2
            fi
            agent-browser fill 'input[name=loginfmt]' "$(cred email)" >/dev/null
            agent-browser click '#idSIButton9' >/dev/null
            ;;
        choose) click_text "Use my password" ;;
        password)
            agent-browser fill 'input[name=passwd]' "$(cred password)" >/dev/null
            agent-browser click '#idSIButton9' >/dev/null
            ;;
        verify) click_text "Use a verification code" ;;
        otc)
            otc_tries=$((otc_tries + 1))
            if [ "$otc_tries" -gt 2 ]; then
                echo "verification code rejected twice; check the TOTP secret" >&2
                exit 1
            fi
            agent-browser fill 'input[name=otc]' "$(oathtool --totp -b "$(cred mfaSecret | tr -d ' ')")" >/dev/null
            agent-browser press Enter >/dev/null
            sleep 4
            ;;
        kmsi) agent-browser click '#idSIButton9' >/dev/null ;;
        *) ;;
    esac
    sleep 2
done

echo "sign-in did not finish; last state: $state, url: $(agent-browser get url)" >&2
agent-browser snapshot -i >&2 || true
exit 1
