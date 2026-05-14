#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CONFIG_ROOT="${STARTER_DIR}/config/hermes/profiles"
DEFAULT_BASE_URL="${NINE_ROUTER_BASE_URL:-https://my-hermes.otomotives.com/v1}"
DEFAULT_API_KEY="${NINE_ROUTER_API_KEY:-local-9router-placeholder}"

prompt() {
  local label="$1"
  local default_value="${2:-}"
  local value
  if [[ -n "${default_value}" ]]; then
    read -r -p "${label} [${default_value}]: " value
    printf '%s' "${value:-${default_value}}"
  else
    read -r -p "${label}: " value
    printf '%s' "${value}"
  fi
}

prompt_required() {
  local label="$1"
  local default_value="${2:-}"
  local value
  while true; do
    value="$(prompt "${label}" "${default_value}")"
    if [[ -n "${value// /}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf 'Value is required.\n' >&2
  done
}

prompt_yes_no() {
  local label="$1"
  local default_value="${2:-n}"
  local value suffix
  if [[ "${default_value}" == "y" ]]; then
    suffix="Y/n"
  else
    suffix="y/N"
  fi
  while true; do
    read -r -p "${label} [${suffix}]: " value
    value="${value:-${default_value}}"
    case "${value}" in
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

upper_snake() {
  printf '%s' "$1" \
    | tr '[:lower:]' '[:upper:]' \
    | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//; s/_+/_/g'
}

pascal_case() {
  local input="$1"
  awk -v s="${input}" 'BEGIN {
    n=split(s, a, /[^A-Za-z0-9]+/);
    for (i=1; i<=n; i++) {
      if (a[i] == "") continue;
      printf toupper(substr(a[i],1,1)) tolower(substr(a[i],2));
    }
  }'
}

csv_to_bullets() {
  local raw="$1"
  local item
  printf '%s' "${raw}" | tr ',' '\n' | while IFS= read -r item; do
    item="$(printf '%s' "${item}" | sed -E 's/^ +//; s/ +$//')"
    [[ -n "${item}" ]] && printf -- '- %s\n' "${item}"
  done
}

list_profiles() {
  find "${CONFIG_ROOT}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

copy_reference_extras() {
  local reference="$1"
  local target="$2"
  local ref_dir="${CONFIG_ROOT}/${reference}"
  local target_dir="${CONFIG_ROOT}/${target}"

  if [[ -d "${ref_dir}/skills" && ! -e "${target_dir}/skills" ]]; then
    cp -R "${ref_dir}/skills" "${target_dir}/skills"
    find "${target_dir}/skills" -type f -print0 | xargs -0 sed -i.bak \
      -e "s/${reference}/${target}/g" \
      -e "s/$(pascal_case "${reference}")/$(pascal_case "${target}")/g" || true
    find "${target_dir}/skills" -name '*.bak' -delete
  fi
}

write_soul() {
  local file="$1"
  cat > "${file}" <<EOF_SOUL
# Hermes ${display_name}

## Identity

- Name: Hermes ${display_name}
- Role: ${role_title}
- Expertise: ${expertise}
- Purpose: ${purpose}
- Authority: ${authority}
- Communication channel: Discord \`${discord_channel}\`. Receives direct human mentions and orchestrator-assigned tasks.
- 9Router combo: \`${model_combo}\`.
- Reference profile: \`${reference_profile}\`.

## Style

- Communicate in the user's language; default to Indonesian when the user uses Indonesian.
- Be concise, practical, and outcome-oriented.
- Lead with status, result, or recommended action before supporting details.
- Use short bullets for progress updates and final summaries.
- Ask at most one clarifying question when ambiguity blocks safe execution.

## Capabilities

$(csv_to_bullets "${capabilities}")

## Tool and Runtime Boundaries

- Terminal access: ${terminal_policy}.
- File access: ${file_policy}.
- Network/research access: ${research_policy}.
- Git access: ${git_policy}.
- Lifecycle: ${lifecycle}.
- Max turns: ${max_turns}.
- Default workspace: \`/home/hermes/workspace\`.
- Shared task queue: \`/var/lib/morph-agency/queue.db\`.
- Large handoff directory: \`/var/lib/morph-agency/handoff/\`.

## Avoid

- Never expose secrets, Discord tokens, provider credentials, API keys, or private env values.
- Never perform destructive operations without explicit user confirmation.
- Never deploy to production without explicit user confirmation.
- Never push to protected branches unless explicitly requested and approved.
- Never fabricate task results. If blocked, report the blocker and the next best option.
- Never bypass the orchestrator for autonomous inter-agent delegation unless the routing policy explicitly allows it.
${extra_avoid_bullets}

## Defaults

- If the task is clear and within authority, proceed without asking for permission.
- If the task needs another specialist, report the recommended handoff target to the orchestrator.
- If expected output is unclear, produce a concise plan and ask one clarifying question.
- Prefer small, verifiable steps over large unreviewable changes.
- Write important artifacts to the handoff directory when the result is too large for Discord.
- End with concrete next steps or verification commands when useful.

## Autonomous Discord Protocol

- Treat Discord as the human-visible interface and progress log.
- Treat SQLite queue records as the source of truth for assigned autonomous work.
- Include task id, acceptance criteria, and status when reporting delegated work.
- Keep bot-to-bot reply chains bounded; stop and summarize if the conversation loops.
- Escalate to \`#escalation\` for destructive actions, deployments, high-cost tasks, credential changes, or policy uncertainty.
EOF_SOUL
}

write_config() {
  local file="$1"
  cat > "${file}" <<EOF_CONFIG
agent:
  name: hermes-${profile}
  max_turns: ${max_turns}

model:
  provider: custom
  default: ${model_combo}
  base_url: ${base_url}
  api_key: ${api_key}

terminal:
  backend: local
  cwd: /home/hermes/workspace
  timeout: ${terminal_timeout}
  persistent_shell: true

memory:
  memory_enabled: true

compression:
  threshold: 0.45

display:
  streaming: true

approvals:
  mode: ${approval_mode}

security:
  redact_secrets: true
  tirith_enabled: true

checkpoints:
  enabled: true
  max_snapshots: 50

timezone: Asia/Jakarta

discord:
  require_mention: true
  auto_thread: true

gateway:
  platforms:
    discord:
      enabled: true
      token: \${DISCORD_BOT_TOKEN}

streaming:
  enabled: true
  transport: edit

group_sessions_per_user: true

delegation:
  max_concurrent_children: ${max_children}
  max_spawn_depth: ${max_depth}
  orchestrator_enabled: ${orchestrator_enabled}
EOF_CONFIG
}

write_discord_policy() {
  local file="$1"
  cat > "${file}" <<EOF_POLICY
profile: ${profile}
bot_name: ${bot_name}
channel: ${discord_channel}
lifecycle: ${lifecycle}
require_mention: true
auto_thread: true

allowed_interactions:
  humans:
    - direct_mention
    - channel_message_when_mentioned
  agents:
    - orchestrator_assignment
    - status_report

routing:
  receives_from:
    - orchestrator
  may_delegate_to: []
  escalation_channel: '#escalation'

response_policy:
  progress_updates: concise
  final_response: summary_with_next_steps
  max_reply_depth: 3

safety:
  require_confirmation_for:
    - destructive_file_operations
    - production_deployments
    - credential_changes
    - protected_branch_pushes
    - high_cost_model_usage
EOF_POLICY
}

write_env_template() {
  local file="$1"
  local token_var="DISCORD_BOT_TOKEN_$(upper_snake "${profile}")"
  cat > "${file}" <<EOF_ENV
NINE_ROUTER_API_KEY=${api_key}
NINE_ROUTER_BASE_URL=${base_url}
DISCORD_BOT_TOKEN=
HERMES_AGENT_NAME=hermes-${profile}
HERMES_PROFILE=${profile}
MORPH_AGENCY_DIR=/var/lib/morph-agency
MORPH_AUTONOMOUS_MODE=orchestrated
MORPH_ROUTING_POLICY=/var/lib/morph-agency/config/autonomous-routing.yaml
MORPH_DISCORD_POLICY=/home/\${HERMES_USER:-hermes}/.hermes/profiles/${profile}/discord-policy.yaml

# Add this variable to the project root .env for repeatable setup:
# ${token_var}=replace-with-${bot_name}-token
EOF_ENV
}

write_skill() {
  local skill_dir="$1"
  install -d -m 755 "${skill_dir}"
  cat > "${skill_dir}/SKILL.md" <<EOF_SKILL
# ${display_name} Agent Playbook

Use this skill when a task is assigned to the \`${profile}\` profile or when work matches this agent role: ${role_title}.

## Mission

${purpose}

## Inputs to Confirm

- Task id or Discord message link
- Acceptance criteria
- Source files, URLs, or artifacts to inspect
- Deadline or priority
- Escalation requirements

## Workflow

1. Restate the objective in one concise sentence.
2. Check boundaries: ${terminal_policy}; ${file_policy}; ${git_policy}.
3. Execute the smallest useful next step.
4. Write large outputs to \`/var/lib/morph-agency/handoff/<task-id>/\`.
5. Report result, confidence, blockers, and next step.

## Output Format

- Status: one of \`done\`, \`blocked\`, \`needs_review\`, \`handoff_ready\`.
- Summary: concise result.
- Evidence: commands, files, URLs, or artifacts checked.
- Next step: one recommended action.

## Escalate When

- Credentials or secrets are required.
- Production deployment or destructive operation is requested.
- The task exceeds this profile authority: ${authority}.
- Model/provider behavior is inconsistent with expected output.
EOF_SKILL
}

write_readme() {
  local file="$1"
  local token_var="DISCORD_BOT_TOKEN_$(upper_snake "${profile}")"
  cat > "${file}" <<EOF_README
# ${display_name} Profile

Generated by \`scripts/45-create-agent-profile.sh\`.

## Runtime Mapping

| Item | Value |
| --- | --- |
| Profile | \`${profile}\` |
| Agent name | \`hermes-${profile}\` |
| 9Router combo | \`${model_combo}\` |
| Discord bot | \`${bot_name}\` |
| Discord channel | \`${discord_channel}\` |
| Lifecycle | \`${lifecycle}\` |

## Required Manual Setup

1. Create 9Router combo \`${model_combo}\`.
2. Create Discord bot \`${bot_name}\` and invite it to \`${discord_channel}\`.
3. Add token to root \`.env\`:

\`\`\`bash
${token_var}=replace-with-token
\`\`\`

4. Sync repo to VPS.
5. Create Hermes profile and install user-level gateway. See \`docs/ADDING_NEW_AGENT.md\`.

## Smoke Tests

\`\`\`bash
sudo -iu hermes /home/hermes/.local/bin/hermes --profile ${profile} -z 'reply with OK only'
\`\`\`

Discord:

\`\`\`text
@${bot_name} reply with OK only
\`\`\`
EOF_README
}

install_runtime_profile() {
  local target_dir="/home/${HERMES_USER:-hermes}/.hermes/profiles/${profile}"
  local hermes_user="${HERMES_USER:-hermes}"

  require_root
  id "${hermes_user}" >/dev/null 2>&1 || die "User ${hermes_user} does not exist. Run 30-install-hermes.sh first."
  command -v hermes >/dev/null 2>&1 || die "hermes binary not found. Run 30-install-hermes.sh first."

  sudo -u "${hermes_user}" hermes profile create "${profile}" >/dev/null 2>&1 || true
  ensure_dir "${target_dir}" "${hermes_user}:${hermes_user}" 700
  install -o "${hermes_user}" -g "${hermes_user}" -m 644 "${profile_dir}/SOUL.md" "${target_dir}/SOUL.md"
  install -o "${hermes_user}" -g "${hermes_user}" -m 600 "${profile_dir}/config.yaml" "${target_dir}/config.yaml"
  install -o "${hermes_user}" -g "${hermes_user}" -m 640 "${profile_dir}/discord-policy.yaml" "${target_dir}/discord-policy.yaml"

  if [[ ! -f "${target_dir}/.env" ]]; then
    install -o "${hermes_user}" -g "${hermes_user}" -m 600 "${profile_dir}/.env.template" "${target_dir}/.env"
  fi

  if prompt_yes_no "Install/start user-level gateway service now" "n"; then
    sudo -iu "${hermes_user}" hermes --profile "${profile}" gateway install
    sudo -u "${hermes_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${hermes_user}")" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "${hermes_user}")/bus" \
      systemctl --user daemon-reload
    sudo -u "${hermes_user}" XDG_RUNTIME_DIR="/run/user/$(id -u "${hermes_user}")" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "${hermes_user}")/bus" \
      systemctl --user enable --now "hermes-gateway-${profile}"
  fi
}

printf '\nMorph AI Agent Profile Generator\n'
printf '================================\n\n'
printf 'Existing profiles:\n'
list_profiles | sed 's/^/  - /'
printf '\n'

raw_profile="$(prompt_required 'New profile name (lowercase, e.g. reviewer)')"
profile="$(slugify "${raw_profile}")"
[[ "${profile}" =~ ^[a-z][a-z0-9-]*$ ]] || die "Invalid profile name after slugify: ${profile}"

profile_dir="${CONFIG_ROOT}/${profile}"
if [[ -e "${profile_dir}" ]]; then
  if ! prompt_yes_no "Profile ${profile} already exists. Overwrite generated files" "n"; then
    die "Aborted."
  fi
fi

reference_profile="$(prompt 'Reference existing profile' 'executor')"
[[ -d "${CONFIG_ROOT}/${reference_profile}" ]] || die "Reference profile not found: ${reference_profile}"

default_display="$(pascal_case "${profile}")"
display_name="$(prompt_required 'Display name' "${default_display}")"
role_title="$(prompt_required 'Agent role/title' 'Specialist Agent')"
purpose="$(prompt_required 'Primary purpose / mission')"
expertise="$(prompt_required 'Expertise keywords (comma separated)' "${role_title}")"
capabilities="$(prompt_required 'Capabilities (comma separated)' 'analyze tasks, produce structured output, report blockers')"
authority="$(prompt_required 'Authority / decision scope' 'Can complete assigned tasks within its role and escalate blockers')"

printf '\nLifecycle options: always-on, spawn-on-demand, cron-based\n'
lifecycle="$(prompt_required 'Lifecycle' 'spawn-on-demand')"

model_combo="$(prompt_required '9Router model combo' "morph-${profile}")"
base_url="$(prompt_required '9Router base URL' "${DEFAULT_BASE_URL}")"
api_key="$(prompt_required '9Router API key placeholder/value' "${DEFAULT_API_KEY}")"

bot_name="$(prompt_required 'Discord bot name' "Morph$(pascal_case "${display_name}")")"
discord_channel="$(prompt_required 'Discord channel' "#${profile}")"

printf '\nAccess presets: readonly, workspace-write, system-ops, no-terminal\n'
access_preset="$(prompt_required 'Access preset' 'workspace-write')"
case "${access_preset}" in
  readonly)
    terminal_policy='Read-only inspection commands only'
    file_policy='Read-only except handoff artifacts'
    git_policy='Read-only git commands only'
    approval_mode='smart'
    ;;
  workspace-write)
    terminal_policy='Local workspace commands allowed'
    file_policy='May edit assigned workspace files and handoff artifacts'
    git_policy='May inspect git state and prepare changes; protected pushes require confirmation'
    approval_mode='smart'
    ;;
  system-ops)
    terminal_policy='System operations allowed only with explicit approval'
    file_policy='May edit deployment/config files assigned by user or orchestrator'
    git_policy='May inspect git and prepare ops changes; deploy/push requires confirmation'
    approval_mode='strict'
    ;;
  no-terminal)
    terminal_policy='No terminal execution by default'
    file_policy='No file modification by default'
    git_policy='No git access by default'
    approval_mode='strict'
    ;;
  *) die "Unknown access preset: ${access_preset}" ;;
esac

if prompt_yes_no 'Allow web research / docs lookup' 'y'; then
  research_policy='Allowed for task-relevant research and documentation lookup'
else
  research_policy='Not allowed unless explicitly assigned'
fi

max_turns="$(prompt_required 'Max turns' '80')"
terminal_timeout="$(prompt_required 'Terminal timeout seconds' '600')"
max_children="$(prompt_required 'Max concurrent child agents' '0')"
max_depth="$(prompt_required 'Max spawn depth' '0')"
if prompt_yes_no 'Can this profile orchestrate/delegate to other profiles' 'n'; then
  orchestrator_enabled='true'
else
  orchestrator_enabled='false'
fi

extra_avoid_bullets=''
extra_avoid="$(prompt 'Extra Avoid bullets (comma separated, optional)' '')"
if [[ -n "${extra_avoid}" ]]; then
  extra_avoid_bullets="$(csv_to_bullets "${extra_avoid}")"
fi

create_skill='n'
if prompt_yes_no 'Generate profile skill playbook' 'y'; then
  create_skill='y'
fi

install -d -m 755 "${profile_dir}"
copy_reference_extras "${reference_profile}" "${profile}"
write_soul "${profile_dir}/SOUL.md"
write_config "${profile_dir}/config.yaml"
write_discord_policy "${profile_dir}/discord-policy.yaml"
write_env_template "${profile_dir}/.env.template"
write_readme "${profile_dir}/README.md"

if [[ "${create_skill}" == 'y' ]]; then
  write_skill "${profile_dir}/skills/${profile}-playbook"
fi

printf '\nGenerated profile files:\n'
find "${profile_dir}" -maxdepth 3 -type f | sort | sed 's/^/  - /'

if prompt_yes_no 'Append reminder block to AGENT_REGISTRY.md' 'y'; then
  cat >> "${STARTER_DIR}/AGENT_REGISTRY.md" <<EOF_REGISTRY

<!-- Generated profile reminder: ${profile}
Add this profile to the roster table after review:
| \`${profile}\` | ${role_title} | ${purpose} | \`${model_combo}\` | \`${discord_channel}\` | \`${bot_name}\` | ${lifecycle} | candidate |
-->
EOF_REGISTRY
  log "Added AGENT_REGISTRY.md reminder block."
fi

if [[ "${STARTER_DIR}" == /home/* || -d "/home/${HERMES_USER:-hermes}/.hermes" ]]; then
  if prompt_yes_no 'Install generated profile into local VPS runtime now (requires root)' 'n'; then
    install_runtime_profile
  fi
fi

cat <<EOF_DONE

Next steps:
1. Create 9Router combo: ${model_combo}
2. Create Discord bot ${bot_name} and channel ${discord_channel}
3. Add DISCORD_BOT_TOKEN_$(upper_snake "${profile}") to .env
4. Sync repo to VPS if generated locally
5. Follow docs/ADDING_NEW_AGENT.md to install/start the gateway
6. Smoke test: sudo -iu hermes /home/hermes/.local/bin/hermes --profile ${profile} -z 'reply with OK only'

Useful idea: after this profile is stable, add it to /var/lib/morph-agency/config/autonomous-routing.yaml so the orchestrator can route matching tasks automatically.
EOF_DONE
