#!/usr/bin/env bash
# Print the active kubernetes context, short enough for a status bar.
#
# Raw context names are unusable here: this fleet's are 47-59 characters
# ("arn:aws:eks:us-east-1:826173816446:cluster/demo-eks-cluster"), which on a
# phone is the entire status bar. Only the trailing cluster name carries
# information a human reads at a glance; the account id and region do not.
#
# Prints nothing at all when there is no kubeconfig or no current context, so
# the tmux segment disappears instead of rendering an error.
set -uo pipefail

MAX=${KUBE_CONTEXT_MAX:-22}

# `kubectl config current-context` is authoritative but costs ~70ms of process
# startup, and this runs on every status refresh for every attached client.
# A single-file kubeconfig -- the overwhelmingly common case -- can be read
# directly for about a tenth of that. Fall back to kubectl whenever the layout
# is anything less obvious (KUBECONFIG listing several files, etc).
read_context() {
  local cfg="${KUBECONFIG:-$HOME/.kube/config}"
  if [ -n "${KUBECONFIG:-}" ] && [[ "$KUBECONFIG" == *:* ]]; then
    command -v kubectl >/dev/null 2>&1 && kubectl config current-context 2>/dev/null
    return
  fi
  if [ -r "$cfg" ]; then
    sed -n 's/^current-context:[[:space:]]*//p' "$cfg" | head -n1 | tr -d '"'"'"' \r'
    return
  fi
  command -v kubectl >/dev/null 2>&1 && kubectl config current-context 2>/dev/null
}

ctx="$(read_context || true)"
# No kubeconfig, no current context, no kubectl -- all render as nothing, and
# exit 0, so the tmux segment simply disappears rather than showing an error.
[ -n "$ctx" ] || exit 0

# Provider-shaped names collapse to provider + the cluster's own name.
case "$ctx" in
  arn:aws:eks:*:cluster/*) short="eks:${ctx##*cluster/}" ;;
  gke_*)
    # gke_<project>_<region>_<cluster>; the cluster is the last underscore field
    short="gke:${ctx##*_}" ;;
  *.azmk8s.io|*azure*) short="aks:${ctx%%.*}" ;;
  *) short="$ctx" ;;
esac

# Hard cap regardless of shape, so an unrecognised name can never take the bar.
if [ "${#short}" -gt "$MAX" ]; then
  short="${short:0:$((MAX - 1))}…"
fi

printf '⎈ %s\n' "$short"
