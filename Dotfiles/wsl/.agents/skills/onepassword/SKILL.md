---
name: onepassword
description: Use secrets and environment variables from 1Password inside an agent workspace instance, via `op-env`, without ever seeing their values. Use whenever a task needs an API key, token, password, connection string or `.env` file - or when a command fails for want of a credential. Triggers: secret, credential, API key, token, password, .env, environment variable, dotenv, op-env, op run, 1Password, environment, vault.
---

# Secrets in this workspace

You can **use** every secret this project is entitled to. You cannot **read**
any of them, and you should not try.

That is not a restriction to work around - it is the design. Secrets are
injected into the process that needs them and never pass through your context.

## The one command

```bash
op-env -- <command>
```

`op-env` resolves this project's 1Password Environment and runs `<command>` with
every variable in it already present in the environment. The command runs as
you, the values are in its environment, and nothing was printed.

```bash
op-env -- npm run dev
op-env -- python manage.py migrate
op-env -- curl -H "Authorization: Bearer $API_TOKEN" https://api.example.com
```

That last one works: `$API_TOKEN` is expanded by the shell *inside* the command
op-env runs, not by your shell. Quote it single or let op-env's child expand it -
do not try to expand it yourself first, because your shell has nothing to expand.

### Seeing what exists

```bash
op-env --names     # variable NAMES only - never values
op-env --status    # whether secrets are configured, and which Environment
```

`--names` is how you find out that `STRIPE_SECRET_KEY` is available. There is no
command that will show you what it equals, and that is deliberate.

## What you do not have

There is **no `OP_SERVICE_ACCOUNT_TOKEN` in your environment**, on purpose. So:

- `op read`, `op item get`, `op environment read` and `op run` will all fail
  with `no account found`. That is expected. Do not treat it as a bug to fix.
- **Do not use `sudo` to read the token, or to run `op` as root.** The token is
  root-owned at `/etc/agentdev/op/token`. You have passwordless sudo, so this
  is technically possible; it is nonetheless a direct violation of the reason
  this setup exists. Do not do it, and do not suggest it.
- Do not write a resolved value anywhere - not to a file, a log, a commit
  message, or your reply.

If you genuinely cannot complete a task without seeing a value, say so and
explain why. Do not route around the boundary.

## When it is not configured

```
op-env: not configured. Ask the user to run 'op-login'.
```

**Ask the user to run `op-login`.** They will need the Environment ID from the
1Password app and the service account token. This is the same rule as
`gh auth login`: obtaining credentials is theirs to do, not yours.

Do not hardcode a credential as a fallback, do not invent a placeholder that
looks real, and do not disable the code path that needs the secret.

## Adding a variable

You cannot. Variables are added in the 1Password app under
Developer > View Environments. If a task needs a new credential stored, tell the
user the variable name you expect and let them add it - then `op-env --names`
will show it.

## Writing code against this

Application code should read secrets from **environment variables**, plainly:

```python
api_key = os.environ["STRIPE_SECRET_KEY"]     # good
```

Do not write code that shells out to `op`, reads the token file, or tries to
resolve `op://` references itself. The injection has already happened by the
time your code runs - it just reads its environment.

For anything needing a `.env` file on disk, prefer `op-env` instead. If a tool
truly cannot be launched any other way, say so rather than materialising a file
full of real values.

## Note on MCP

`pi` has `pi-mcp-extension` installed and Claude and Codex support MCP natively,
so MCP servers generally work here. **1Password's MCP server does not.** It is
supplied by the 1Password desktop app, which this instance cannot reach - there
is no `/mnt/c` and no interop. `op-env` is the supported path; do not spend time
trying to configure a 1Password MCP server.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `op-env: not configured` | No token stored. Ask the user to run `op-login`. |
| `no account found for filter` | You called `op` directly. Use `op-env` instead. |
| Variable missing inside the command | Not in the Environment. Check `op-env --names`; if absent, ask the user to add it in the 1Password app. |
| `<concealed by 1Password>` in output | Working as intended - `op run` masks secret values in output. Not an error. |
| Value looks empty in your shell | Correct. The variables exist only inside the command `op-env` runs, never in your shell. |
| Need it in a long-running server | Launch the server itself under `op-env`, e.g. `op-env -- npm run dev`. |
