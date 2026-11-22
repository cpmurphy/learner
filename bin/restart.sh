#! /bin/bash

SCRIPT_DIR=$(dirname "$0")

# load the deployment environment variables
# Needed are: DEPLOY_USER, DEPLOY_HOST, DEPLOY_DIR
# shellcheck source=deploy_env.sh
. "${SCRIPT_DIR}"/../deploy_env.sh


# ensure that we don't keep running if any of the commands fail
ssh "${DEPLOY_USER}"@"${DEPLOY_HOST}" \
  "DEPLOY_DIR=${DEPLOY_DIR}" \
  "APP_NAME=${APP_NAME}" \
  frontend=${FRONTEND_NAME:-chess-learner} \
  backend=${BACKEND_NAME:-stockfish-pool} \
'bash -s' <<'EOF'
set -e
set -x
systemctl_cmd=${SYSTEMCTL:-systemctl --user}
$systemctl_cmd daemon-reload
# shellcheck disable=SC2086 # $systemctl_cmd is a command plus its options
$systemctl_cmd restart "$backend.service" "$frontend.service"
EOF
