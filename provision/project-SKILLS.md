# Skills to install

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
