---
name: hnet-setup
description: Set up or troubleshoot an hnet central host, edge client, or a Mac serving both roles. Verify telemetry delivery using the existing hnetctl workflow.
---

# hnet setup

Read the repository's [AGENTS.md](../../../AGENTS.md) and
[README.md](../../../README.md). Keep setup instructions in the README;
this skill guides their use.

1. Establish the intended role: central services, edge collection, or both.
   Inspect existing installation and configuration before choosing commands.
   Do not infer roles from hardware names or read secret values into tool output.
2. Use `hnetctl` from Homebrew, or `./ops/apps/hnetctl/hnetctl` in a checkout.
   Start with the README's prerequisite and status checks. Report missing setup
   precisely; do not install tools or start services as a diagnostic shortcut.
3. Before changing live services, enrollment, or Tailscale forwarding, state the
   effect and check that the user authorized that operation. Central Compose
   startup uses `start` and private forwarding uses `serve`. `up` also starts
   experimental Kubernetes and is not the default setup path.
4. Follow the README for enrollment. Register arbitrary safe names with
   `hnetctl client-add NAME` on the central host, then transfer its private
   enrollment file to the edge Mac. Central hosts collecting locally use the
   inventory entry marked `central: true`. Existing installations retain their
   imported labels, ports, and credentials. Preserve configuration, backups,
   and volumes; stop on conflicts rather than replacing them.
5. Verify `client-check --connection`, then have the user complete an agent
   reply and confirm that Mac's label, model, and tokens in Grafana. Empty
   connection probes prove connectivity, not model-usage delivery. Do not send
   model requests or inspect private conversation content to manufacture proof.

Report what was verified, what remains unverified, and the exact next action.
Never describe fixture tests as a successful live installation.
