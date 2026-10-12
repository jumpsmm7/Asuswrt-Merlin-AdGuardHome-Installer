# Repository instructions for GitHub Copilot

Read [AGENTS.md](../AGENTS.md) before implementing or reviewing changes. It is the canonical policy and takes precedence over provider-specific instructions.

Select the relevant repository skill from [the shared agent integration guide](../docs/agent-integrations.md). Use the existing `.tasks/` records, coordinate with the PR observer and publishing writer, and validate findings against the current diff before suggesting a minimal fix.

Use [the shared MCP guide](../docs/mcp-servers.md) for the combined catalog, client support and availability rules. Inspect effective tools and follow canonical policy's verified-repository fallback; local configuration does not activate hosted connections.

Follow the shared [ARM virtual validation](../AGENTS.md#arm-virtual-validation) rules and [virtual testing guide](../docs/virtual-arm-testing.md). Host checks, native guest assertions, modeled firmware commands and physical router evidence have separate scopes. Confirm the published head's actual checks and complete review-thread data before claiming completion.

These instructions configure repository guidance. They do not install or authenticate GitHub Copilot or any other external service.
