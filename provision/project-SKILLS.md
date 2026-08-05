# Skills to install

## Already installed: `onepassword`

Nothing to do for this one. It is deployed into every project automatically and
linked into all three agents, and it explains how to use secrets here - run
anything needing a credential as `op-env -- <command>`, and `op-env --names` to
see what is available.

Before an agent can use secrets, this project needs to be pointed at a
1Password Environment, once:

```bash
op-login <environment-id>     # ID from the 1Password app:
                              # Developer > View Environments >
                              # Manage environment > Copy environment ID
op-env --status               # confirm, and list the variable names
```

To change what the skill says, edit
`C:\AgentDev\Dotfiles\wsl\.agents\skills\onepassword\SKILL.md` on the host. The
next `corral new` picks it up - no base-image rebuild needed. Existing projects
keep the copy they were created with.

## The rest, installed by hand

These are not installed automatically - run them here, in this project, and
pick the agents you want when prompted.

```bash
npx skills add kunchenguid/chrome-devtools-axi --skill chrome-devtools-axi -g
npx skills add kunchenguid/lavish-axi --skill lavish
npx skills add kunchenguid/gh-axi --skill gh-axi -g
```

`-g` installs for the whole instance, so it covers every project inside it and
only needs running once. Without `-g` the skill is installed into this project
alone, so it needs running again in each new project.

Check what is present:

```bash
skills list        # this project
skills list -g     # instance-wide
```

## Running them without the interactive picker

Useful if you are scripting it. Three things the CLI is particular about:

- `-y` is required, or it opens a multi-select and waits forever.
- Agent names are repeated as separate `-a` flags. A comma-separated list is
  rejected as `Invalid agents`, and the identifier is `claude-code`, not
  `claude`.
- Several `-a` flags in one invocation reports success but installs for only
  some of them - in project scope `pi` gets dropped silently. Install one
  agent at a time.

```bash
for a in claude-code codex pi; do
  npx --yes skills add kunchenguid/gh-axi --skill gh-axi -g -a "$a" -y
done
```

## Changing this list

Edit `C:\AgentDev\provision\project-SKILLS.md` on the host. New projects pick
it up; existing ones keep the copy they were created with.

Skill payloads (`.agents/`, `.claude/skills/`, `.codex/skills/`, `.pi/skills/`)
are gitignored. `skills-lock.json` is tracked, so committed once you install
something, it records what this project expects.
