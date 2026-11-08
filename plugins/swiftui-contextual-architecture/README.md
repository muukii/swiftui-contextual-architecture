# SwiftUI Contextual Architecture Plugin

An [Agent Plugins 1.0.0](https://agent-plugins.org/specification) package for building Swift applications with explicit ownership of login sessions, UI contexts, services, and persistent storage.

## Included skill

[`swift-app-session-foundation`](skills/swift-app-session-foundation/SKILL.md) guides construction and refactoring of:

- UIContext/UIIntent routing and authentication transitions.
- Session and window ownership, including shared multiwindow services.
- Environment, login, and credential storage boundaries.
- Ordered shutdown, data-retention policies, and retryable cleanup.
- Stale-result rejection, failed saves, and restart recovery.

The skill and its references are written in English. They describe lessons from Pairs, PairsNext, and MoriDesktop and distinguish observed behavior from recommended contracts. Access to those repositories is optional; no original application source is bundled.

## Package root and loading

This directory is the plugin root:

```text
swiftui-contextual-architecture/
├── plugin.json
├── README.md
└── skills/
    └── swift-app-session-foundation/
        ├── SKILL.md
        ├── agents/openai.yaml
        └── references/
```

Select this directory when loading the plugin in an Agent Plugins-compatible client. The client discovers the skill under `skills/`; how it exposes or invokes the skill is client-specific. In a client that supports named skill invocation, request `swift-app-session-foundation` for the relevant task. The optional `agents/openai.yaml` supplies Codex skill metadata.

The portable manifest uses the [canonical plugin schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json). This is a skills-only package: it has no MCP servers, executable hooks, or runtime dependencies. No native marketplace registration is required by the portable format or bundled here.

## Distribution

Distribute this entire directory with `plugin.json` at its root. All skill files and relative references remain inside the package. The repository's `.agents/skills/` alias is only for local discovery and is not part of the distribution.

Before a release:

1. Update the version in `plugin.json`.
2. Validate that manifest against its canonical schema and validate the skill with an Agent Skills validator, such as `skills-ref validate skills/swift-app-session-foundation` from the plugin root.
3. Check that package paths and skill references resolve inside this directory.
4. Archive this directory and inspect the archive before uploading it to the chosen distribution service.

For example, from the repository root:

```sh
mkdir -p .tmp/dist
COPYFILE_DISABLE=1 tar -czf .tmp/dist/swiftui-contextual-architecture-0.1.0.tar.gz \
  -C plugins swiftui-contextual-architecture
```

After extraction, use `swiftui-contextual-architecture/` as the plugin root. The archive includes the package only, not the Swift demo, Git metadata, or implementation notes. An archive is a distribution convenience, not an additional Agent Plugins requirement.

Agent Plugins specifies the portable package contract. Installation, publishing, registry submission, and update delivery are defined by the receiving client or service; the standard does not define a universal `publish` command.
