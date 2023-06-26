#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

REPO_NAME=$(echo $GITHUB_REPOSITORY | tr "/" "-")
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$REPO_NAME}"
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
image="$INPUT_IMAGE"
vm_memory="${INPUT_VM_MEMORY}"

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  flyctl apps create --name "$app" --org "$org" || true
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach --app "$app" "$INPUT_POSTGRES" || true
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_ENV_FILE" ]; then
  flyctl secrets import --app "$app" < $INPUT_ENV_FILE
fi

if [ "$INPUT_UPDATE" != "false" ]; then
  flyctl deploy --vm-memory "$vm_memory" --app "$app" --region "$region" --strategy immediate --image "$image"
fi

# Make some info available to the GitHub workflow.
fly status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
echo "::set-output name=hostname::$hostname"
echo "::set-output name=url::https://$hostname"
echo "::set-output name=id::$appid"
echo "hostname=$hostname" >> $GITHUB_OUTPUT
echo "url=https://$hostname" >> $GITHUB_OUTPUT
echo "id=$appid" >> $GITHUB_OUTPUT