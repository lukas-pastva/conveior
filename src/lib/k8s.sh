# shellcheck shell=bash
# conveior - Kubernetes helpers (pod lookup, exec, tar streaming).

# k8s_find_pod <namespace> <name> [label selector]
# Prints the first Running pod. Without a selector the pod name must be <name>,
# <name>-<hash>-<id> (Deployment/ReplicaSet) or <name>-<n> (StatefulSet).
k8s_find_pod() {
  local ns="$1" name="$2" selector="${3:-}" pods
  if [[ -n "$selector" ]]; then
    pods="$(kubectl -n "$ns" get pods -l "$selector" --field-selector=status.phase=Running \
      -o custom-columns=:metadata.name --no-headers 2>/dev/null)" || return 1
  else
    pods="$(kubectl -n "$ns" get pods --field-selector=status.phase=Running \
      -o custom-columns=:metadata.name --no-headers 2>/dev/null)" || return 1
    pods="$(printf '%s\n' "$pods" | grep -E "^${name}(-[a-z0-9]{5,10}-[a-z0-9]{5}|-[0-9]+)?$")"
  fi
  pods="$(printf '%s\n' "$pods" | sed '/^$/d' | head -n 1)"
  [[ -n "$pods" ]] || return 1
  printf '%s' "$pods"
}

# k8s_exec <namespace> <pod> <container or empty> <command...>
k8s_exec() {
  local ns="$1" pod="$2" container="$3"
  shift 3
  if [[ -n "$container" ]]; then
    kubectl -n "$ns" exec -i "$pod" -c "$container" -- "$@"
  else
    kubectl -n "$ns" exec -i "$pod" -- "$@"
  fi
}

# k8s_dir_empty <namespace> <pod> <container> <path>  - rc 0 when the directory has no entries
k8s_dir_empty() {
  local out
  out="$(k8s_exec "$1" "$2" "$3" sh -c 'ls -A "$1" 2>/dev/null | head -n 1' sh "$4")" || return 2
  [[ -z "$out" ]]
}

# k8s_tar_to_dir <namespace> <pod> <container> <remote path> <local dir>
# Streams `tar cf -` from the pod into <local dir>. Remote tar may exit 1 (file changed while
# reading) - that is accepted as long as the local tar consumed a complete archive.
k8s_tar_to_dir() {
  local ns="$1" pod="$2" container="$3" src="$4" dest="$5" rcs rc_remote rc_local
  find "$dest" -mindepth 1 -delete
  k8s_exec "$ns" "$pod" "$container" tar cf - -C "$src" . | tar xf - -C "$dest"
  rcs=("${PIPESTATUS[@]}")   # must be copied in one statement, every command resets PIPESTATUS
  rc_remote="${rcs[0]}"
  rc_local="${rcs[1]}"
  if (( rc_local != 0 )); then
    err "incomplete archive from ${pod}:${src} (local tar rc=$rc_local, remote rc=$rc_remote)"
    return 1
  fi
  if (( rc_remote > 1 )); then
    err "tar in ${pod}:${src} failed (rc=$rc_remote)"
    return 1
  fi
  (( rc_remote == 1 )) && warn "tar in ${pod}:${src} reported warnings (files changed while reading), archive is complete"
  return 0
}

# k8s_dir_from_tar <namespace> <pod> <container> <local dir> <remote path>
# Streams <local dir> contents into <remote path> inside the pod.
k8s_dir_from_tar() {
  local ns="$1" pod="$2" container="$3" src="$4" dest="$5"
  tar cf - -C "$src" . | k8s_exec "$ns" "$pod" "$container" tar xf - -C "$dest"
}
