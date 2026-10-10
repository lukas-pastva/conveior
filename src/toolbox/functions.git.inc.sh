#!/bin/bash

# -----------------------------------------------------------------
#  debug logger – prints only when you run with  DEBUG=1 …
# -----------------------------------------------------------------
_dbg() { [[ -n "${DEBUG:-}" ]] && echo "[${FUNCNAME[1]}] $*" >&2; }

function gitlab_user_statistics() {

  # Declare global variables within the function
  declare -A user_commit_count  # Declare globally to ensure it's accessible throughout the script
  total_commits=0               # Global variable to hold the total commits
  project_users=""              # Global variable to hold project users
  project_commit_count=0        # Global variable to hold commits per project

  # Prompt user for GitLab URL and Access Token
  read -p "Enter GitLab URL (e.g., https://gitlab.yourdomain.com): " GITLAB_URL
  read -s -p "Enter your GitLab Access Token: " PRIVATE_TOKEN
  echo    # To add a newline after the token prompt

  # Set the output file name
  OUTPUT_FILE="gitlab_stats.txt"

  # Date range for last month's activity (Adjust as necessary)
  SINCE_DATE=$(date -d "1 month ago" +"%Y-%m-%dT00:00:00Z")
  UNTIL_DATE=$(date +"%Y-%m-%dT23:59:59Z")

  # Function to get all items across all pages
  get_all_items() {
    local url="$1"
    local items=()
    local page=1
    local per_page=100

    while :; do
      response=$(curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$url&page=$page&per_page=$per_page")
      item_count=$(echo "$response" | jq 'length')

      if [[ $item_count -eq 0 ]]; then
        break
      fi

      items+=($(echo "$response" | jq -r '.[].id'))
      ((page++))
    done

    echo "${items[@]}"
  }

  # Function to get all groups
  get_groups() {
    local url="$GITLAB_URL/api/v4/groups?"
    get_all_items "$url"
  }

  # Function to get all projects in a group
  get_projects_in_group() {
    local group_id=$1
    local url="$GITLAB_URL/api/v4/groups/$group_id/projects?"
    get_all_items "$url"
  }

  # Function to get project details (path and name)
  get_project_details() {
    local project_id=$1
    curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id"
  }

  # Function to get all commits for a project in the last month
  get_commits_for_project() {
    local project_id=$1
    local commits=()
    local page=1
    local per_page=100

    while :; do
      response=$(curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/api/v4/projects/$project_id/repository/commits?since=$SINCE_DATE&until=$UNTIL_DATE&page=$page&per_page=$per_page")
      commit_count=$(echo "$response" | jq 'length')

      if [[ $commit_count -eq 0 ]]; then
        break
      fi

      commits+=($(echo "$response" | jq -r '.[] | @base64'))
      ((page++))
    done

    echo "${commits[@]}"
  }

  # Function to collect user commits and accumulate totals for both users and commits
  get_commit_count_per_user() {
    local project_id=$1
    local commits_encoded=($(get_commits_for_project $project_id))
    local project_user_list=()

    # Initialize project commit count
    project_commit_count=0

    # Extract user emails and count commits per user
    for commit_enc in "${commits_encoded[@]}"; do
      commit=$(echo "$commit_enc" | base64 --decode)
      email=$(echo "$commit" | jq -r '.author_email')
      email=$(echo "$email" | xargs)  # Trim whitespace

      # Validate the email and count commits
      if [[ -n "$email" && "$email" != "null" && "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        project_user_list+=("$email")
        user_commit_count["$email"]=$(( ${user_commit_count["$email"]} + 1 ))
      fi
      total_commits=$((total_commits + 1))                # Increment total commit count globally
      project_commit_count=$((project_commit_count + 1))  # Increment project commit count
    done

    # Create a comma-separated list of unique emails
    local unique_emails=$(echo "${project_user_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ', ' | sed 's/, $//')
    project_users="$unique_emails"  # Set the global variable
  }

  # Start writing to the output file
  echo "GitLab User Statistics" | tee "$OUTPUT_FILE"
  echo "Date range: $SINCE_DATE to $UNTIL_DATE" | tee -a "$OUTPUT_FILE"
  echo "=============================================" | tee -a "$OUTPUT_FILE"

  # Loop through all groups and projects, and count commits for each user
  echo "Fetching groups and repositories..." | tee -a "$OUTPUT_FILE"

  group_ids=($(get_groups))

  for group in "${group_ids[@]}"; do
    project_ids=($(get_projects_in_group $group))
    for project in "${project_ids[@]}"; do
      # Get project details (name and path)
      project_details=$(get_project_details $project)
      project_name=$(echo "$project_details" | jq -r '.name')
      project_path=$(echo "$project_details" | jq -r '.path_with_namespace')

      # Call the function without command substitution
      get_commit_count_per_user $project

      # If project_users is empty, set commit_count to 0; otherwise, count the users
      if [[ -z "$project_users" ]]; then
        commit_count=0
      else
        commit_count=$(echo "$project_users" | tr ',' '\n' | grep -v '^$' | wc -l)  # Ensure no empty lines are counted
      fi

      # Output project details, users, total commits, and other information
      echo "Group ID: $group, Project ID: $project, Project Path: $project_path, Project Name: $project_name" | tee -a "$OUTPUT_FILE"
      echo "Users: $commit_count, Commits in Project: $project_commit_count" | tee -a "$OUTPUT_FILE"

      # Output user list (if any) on a new line
      if [[ -n "$project_users" ]]; then
        echo "Users List:" | tee -a "$OUTPUT_FILE"
        echo "$project_users" | tr ',' '\n' | grep -v '^$' | sed 's/^/ - /' | tee -a "$OUTPUT_FILE"  # Exclude empty lines
      fi
      echo "" | tee -a "$OUTPUT_FILE"  # Add new line after each project's data
    done
  done

  # Print the final summary of users and commit counts
  echo "" | tee -a "$OUTPUT_FILE"
  echo "Final Summary of Users and Commit Counts:" | tee -a "$OUTPUT_FILE"
  echo "=========================================" | tee -a "$OUTPUT_FILE"

  # Print user emails and their total commit counts
  for email in "${!user_commit_count[@]}"; do
    echo "$email: ${user_commit_count[$email]} commits" | tee -a "$OUTPUT_FILE"
  done

  # Print total number of unique users and total commits
  echo "" | tee -a "$OUTPUT_FILE"
  echo "Total number of unique users: ${#user_commit_count[@]}" | tee -a "$OUTPUT_FILE"
  echo "Total number of commits: $total_commits" | tee -a "$OUTPUT_FILE"  # Print total commit count

  echo "Statistics saved to $OUTPUT_FILE"
}

function git_add_file() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local THE_FILE=$2
  local CONTENTS=$3

  rm -rf /tmp/${GIT_REPO} || true
  cd /tmp
  git clone --quiet https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL}.git > /dev/null 2>&1
  # Save file
  echo -e "${CONTENTS}" > "/tmp/${GIT_REPO}/${THE_FILE}"
  # Commit changes
  cd /tmp/${GIT_REPO}
  git add . > /dev/null 2>&1
  git commit -m "Added by automation." > /dev/null 2>&1
  git push > /dev/null 2>&1
}

function git_edit_file() {
  local GIT_URL=$1
  local GIT_REPO="${GIT_URL##*/}"
  local ANCHOR=$2
  local THE_FILE=$3
  local CONTENTS=$4
  local UNIQUE_IDENTIFIER=$5

  cd /tmp
  git clone --quiet https://lukas-pastva:${GLOBAL_GIT_TOKEN}@${GIT_URL}.git
  cd /tmp/${GIT_REPO}

  # Check if CONTENTS already exists in the file
  if ! grep -Fq "$UNIQUE_IDENTIFIER" "${THE_FILE}"; then

    # Save file
    preprocessed_VAR=$(printf '%s' "$CONTENTS" | sed 's/\\/&&/g;s/^[[:blank:]]/\\&/;s/$/\\/')
    sed -i -e "/$ANCHOR/a\\
    ${preprocessed_VAR%?}" "/tmp/${GIT_REPO}/${THE_FILE}"

    # Commit changes
    git add .
    git commit -m "Added by automation."
    git push
  else
    echo_with_time "Contents already exist in the file. No changes made."
  fi
  rm -rf /tmp/${GIT_REPO} || true
}

# GitLab Group Deep Backup (multi-group, hierarchical, safe-paging)
# Usage (env or prompt inside): gitlab_private_token, group_id, [gitlab_url, backup_dir, rclone_bucket]
# Optional env toggles:
#   BACKUP_WIKI_GIT=1, BACKUP_REGISTRY=1, BACKUP_ARTIFACTS=1, PROJECT_COMMITS_LIMIT=500, GL_PER_PAGE=100
#   EXCLUDE_PROJECTS="group/a,group/b,tmp/*", KEEP_FILES_ON_ERROR=1, ZIP_CMD=zip, DEBUG_GL_BACKUP=1
gitlab_backup() {
  # ---------- small helpers (scoped) ----------
  _trim() { echo "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
  _safe() { echo "$1" | sed -E 's#[^a-zA-Z0-9._/-]+#_#g'; }
  _mkdir() { mkdir -p "$1" 2>/dev/null || true; }
  _dbg() { [[ -n "${DEBUG_GL_BACKUP:-}" ]] && echo "[DBG] $*" >&2; }
  _save_json() { # $1 path, $2 json
    local p="$1" j="$2"
    [[ -z "${j:-}" || "$j" == "null" ]] && return 0
    _mkdir "$(dirname "$p")"
    echo -e "$j" > "$p"
  }

  # defaults (user override allowed)
  : "${KEEP_FILES_ON_ERROR:=1}"
  : "${ZIP_CMD:=zip}"

  # ---------- curl wrapper ----------
  _curl() { curl -sS -H "PRIVATE-TOKEN: $gitlab_private_token" "$@"; }

  # ---------- zip readiness ----------
  _ensure_zip_ready() {
    _mkdir "$zip_destination_dir"
    if ! command -v "$ZIP_CMD" >/dev/null 2>&1; then
      echo "[ERROR] '$ZIP_CMD' not found. Install it or set ZIP_CMD=7z (or another)."
      return 1
    fi
    if ! touch "${zip_destination_dir}/.__writetest" 2>/dev/null; then
      echo "[ERROR] Cannot write to ${zip_destination_dir}. Set backup_dir to a writable location."
      return 1
    fi
    rm -f "${zip_destination_dir}/.__writetest"
    return 0
  }

  # ---------- exclude projects ----------
  _should_exclude_project() {
    local path="$1"
    [[ -z "${EXCLUDE_PROJECTS:-}" ]] && return 1
    IFS=',' read -r -a pats <<< "$EXCLUDE_PROJECTS"
    for pat in "${pats[@]}"; do
      pat="$(_trim "$pat")"
      [[ -z "$pat" ]] && continue
      case "$path" in
        $pat) return 0 ;;
      esac
    done
    return 1
  }

  # ---------- pagination ----------
  _get_all_pages() { # $1 endpoint (path after /api/v4), $2 per_page
    local ep="$1" pp="${2:-${GL_PER_PAGE:-100}}"
    local page=1 out="[]"
    while : ; do
      local sep='?'; [[ "$ep" == *\?* ]] && sep='&'
      local url="${gitlab_url}/api/v4${ep}${sep}per_page=${pp}&page=${page}"
      _dbg "GET $url"
      local rsp http body
      rsp=$(_curl "$url" -w $'\n%{http_code}' || true)
      http="$(echo "$rsp" | tail -n1)"
      body="$(echo "$rsp" | sed '$d')"

      [[ "$http" != "200" ]] && { _dbg "HTTP $http for $ep (page $page)"; break; }

      local t; t=$(jq -r 'type' 2>/dev/null <<<"$body" || echo "null")
      if [[ "$t" == "array" ]]; then
        out=$(jq -cs '.[0] + .[1]' <(echo "$out") <(echo "$body"))
        local n; n=$(jq 'length' <<<"$body")
        (( n < pp )) && break
      else
        echo "$body"
        return 0
      fi
      ((page++))
    done
    echo "$out"
  }

  # ---------- data backup ----------
  _backup_data() { # entity id path parent_dir endpoint_suffix
    local entity=$1 id=$2 path=$3 parent_dir=$4 suffix=$5
    local backup_dir="${parent_dir}/_${entity}/$(_safe "$path")"
    local data; data=$(_get_all_pages "$suffix")
    [[ "$(jq 'length' <<<"$data" 2>/dev/null || echo 0)" -eq 0 ]] && return 0
    _mkdir "$backup_dir"
    _save_json "${backup_dir}/${entity}.json" "$data"

    if [[ "$entity" == "issues" ]]; then
      echo "$data" | jq -c '.[]' | while IFS= read -r issue; do
        local issue_iid project_id notes
        issue_iid=$(jq -r '.iid' <<<"$issue")
        project_id=$(jq -r '.project_id' <<<"$issue")
        notes=$(_get_all_pages "/projects/${project_id}/issues/${issue_iid}/notes")
        [[ "$notes" != "[]" ]] && _save_json "${backup_dir}/issue_${issue_iid}_comments.json" "$notes"
      done
    fi
  }

  _clone_branches() {
    local repo_url=$1 clone_dir=$2
    local branches
    branches=$(git ls-remote --heads "$repo_url" | awk '{print $2}' | sed 's#refs/heads/##')
    for branch in $branches; do
      local sanitized_branch branch_dir
      sanitized_branch=$(echo "$branch" | sed 's#[/:]#_#g')
      branch_dir="${clone_dir}/${sanitized_branch}"
      _mkdir "$branch_dir"
      git clone --quiet --branch "$branch" --single-branch "$repo_url" "$branch_dir" || true
    done
  }

  _clone_wiki_if_enabled() { # http_url_to_repo, dest base
    [[ "${BACKUP_WIKI_GIT:-0}" != "1" ]] && return 0
    local http="$1" base="$2"
    local wiki="${http%.git}.wiki.git"
    local dest="$base/_wiki.git"
    _mkdir "$dest"
    local remote="${wiki/https:\/\//https:\/\/user:${gitlab_private_token}@}"
    git clone --quiet --mirror "$remote" "$dest" 2>/dev/null || true
  }

  _backup_registry_meta() { # project_id, meta_dir
    [[ "${BACKUP_REGISTRY:-0}" != "1" ]] && return 0
    local pid="$1" b="$2"
    local repos=$(_get_all_pages "/projects/${pid}/registry/repositories")
    _save_json "${b}/registry_repositories.json" "$repos"
    echo "$repos" | jq -r '.[].id' | while read -r rid; do
      local tags=$(_get_all_pages "/projects/${pid}/registry/repositories/${rid}/tags")
      _save_json "${b}/registry_repository_${rid}_tags.json" "$tags"
    done
  }

  _backup_pipelines_jobs() { # project_id, meta_dir
    local pid="$1" meta="$2"
    local pips=$(_get_all_pages "/projects/${pid}/pipelines?order_by=id&sort=desc")
    _save_json "${meta}/pipelines.json" "$pips"
    echo "$pips" | jq -r '.[].id' | while read -r pip; do
      local jobs=$(_get_all_pages "/projects/${pid}/pipelines/${pip}/jobs")
      _save_json "${meta}/pipeline_${pip}_jobs.json" "$jobs"
      if [[ "${BACKUP_ARTIFACTS:-0}" == "1" ]]; then
        echo "$jobs" | jq -rc '.[] | select(.artifacts_file and .artifacts_file.filename != null) | {id,artifacts_file}' |
        while read -r j; do
          local jid fn
          jid=$(jq -r '.id' <<<"$j")
          fn=$(jq -r '.artifacts_file.filename' <<<"$j")
          _mkdir "${meta}/artifacts/${pip}"
          _curl -L "${gitlab_url}/api/v4/projects/${pid}/jobs/${jid}/artifacts" \
            -o "${meta}/artifacts/${pip}/${jid}-${fn}" || true
        done
      fi
    done
  }

  _backup_mrs_deep() { # project_id, project_path, base_dir
    local pid="$1" ppath="$2" base="$3"
    local dir="${base}/_${ppath}/merge_requests"
    _mkdir "$dir"
    local mrs=$(_get_all_pages "/projects/${pid}/merge_requests?state=all")
    _save_json "${dir}/merge_requests.json" "$mrs"
    echo "$mrs" | jq -r '.[].iid' | while read -r iid; do
      local notes discussions changes
      notes=$(_get_all_pages "/projects/${pid}/merge_requests/${iid}/notes")
      discussions=$(_get_all_pages "/projects/${pid}/merge_requests/${iid}/discussions")
      changes=$(_curl "${gitlab_url}/api/v4/projects/${pid}/merge_requests/${iid}/changes")
      [[ "$notes" != "[]" ]]       && _save_json "${dir}/mr_${iid}_notes.json" "$notes"
      [[ "$discussions" != "[]" ]] && _save_json "${dir}/mr_${iid}_discussions.json" "$discussions"
      [[ -n "$changes" ]]          && _save_json "${dir}/mr_${iid}_changes.json" "$changes"
    done
  }

  _backup_project_core() { # project_id, project_path, root_dir
    local pid="$1" ppath="$2" root="$3"
    local meta="${root}/_meta/${ppath}"
    _mkdir "$meta"

    _save_json "${meta}/project.json"            "$(_curl "${gitlab_url}/api/v4/projects/${pid}")"
    _save_json "${meta}/branches.json"           "$(_get_all_pages "/projects/${pid}/repository/branches")"
    _save_json "${meta}/tags.json"               "$(_get_all_pages "/projects/${pid}/repository/tags")"
    _save_json "${meta}/releases.json"           "$(_get_all_pages "/projects/${pid}/releases")"
    _save_json "${meta}/milestones.json"         "$(_get_all_pages "/projects/${pid}/milestones?state=all")"
    _save_json "${meta}/labels.json"             "$(_get_all_pages "/projects/${pid}/labels")"
    _save_json "${meta}/hooks.json"              "$(_get_all_pages "/projects/${pid}/hooks")"
    _save_json "${meta}/members_all.json"        "$(_get_all_pages "/projects/${pid}/members/all")"
    _save_json "${meta}/protected_branches.json" "$(_get_all_pages "/projects/${pid}/protected_branches")"
    _save_json "${meta}/environments.json"       "$(_get_all_pages "/projects/${pid}/environments")"
    _save_json "${meta}/deployments.json"        "$(_get_all_pages "/projects/${pid}/deployments?order_by=id&sort=desc")"

    if [[ "${PROJECT_COMMITS_LIMIT:-0}" -gt 0 ]]; then
      _save_json "${meta}/commits.json" "$(_curl "${gitlab_url}/api/v4/projects/${pid}/repository/commits?per_page=${PROJECT_COMMITS_LIMIT}")"
    fi

    _backup_mrs_deep "$pid" "$ppath" "$root"
    _backup_pipelines_jobs "$pid" "$meta"
    _backup_registry_meta "$pid" "$meta"
  }

  # ---------- recursive traversal ----------
  _clone_recursive() {
    local backup_root_dir=$1 current_group_id=$2 parent_dir=$3

    # projects in this group
    local page=1
    while : ; do
      local url="${gitlab_url}/api/v4/groups/${current_group_id}/projects?include_subgroups=false&with_shared=false&per_page=${GL_PER_PAGE:-100}&page=${page}"
      _dbg "GET  $url"
      local rsp; rsp=$(_curl "$url" -w $'\n%{http_code}')
      local http; http="$(echo "$rsp" | tail -n1)"
      local body; body="$(echo "$rsp" | sed '$d')"
      [[ "$http" != "200" ]] && { echo "[WARN] $url → $http, skipping page"; break; }
      [[ "$(jq -r 'type' <<<"$body")" != "array" ]] && break
      [[ "$(jq 'length' <<<"$body")" -eq 0 ]] && break

      echo "$body" | jq -c '.[]' | while read -r proj; do
        local project_id project_path repo_url
        project_id=$(jq -r '.id' <<<"$proj")
        project_path=$(_safe "$(jq -r '.path_with_namespace' <<<"$proj")")
        repo_url=$(jq -r '.http_url_to_repo' <<<"$proj")

        echo "Project: $project_path"
        if _should_exclude_project "$project_path"; then
          echo "[INFO] Skipping excluded project: $project_path"
          continue
        fi

        if [[ -n "$repo_url" && "$repo_url" != "null" ]]; then
          local clone_dir="$backup_root_dir/_repositories/$project_path"
          _mkdir "$clone_dir"
          local remote="${repo_url/https:\/\//https:\/\/user:${gitlab_private_token}@}"
          _clone_branches "$remote" "$clone_dir"

          local mirror_dir="$backup_root_dir/_mirror/$project_path"
          _mkdir "$mirror_dir"
          git clone --quiet --mirror "$remote" "$mirror_dir" || true

          _clone_wiki_if_enabled "$repo_url" "$backup_root_dir/_mirror/$project_path"
        else
          echo "[WARN]  $project_path has no repository URL – skipping code clone"
        fi

        _backup_data variables           "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/variables"
        _backup_data pipeline_schedules  "$project_id" "$project_path" "$backup_root_dir" "/projects/${project_id}/pipeline_schedules"
        _backup_data wikis               "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/wikis"
        _backup_data snippets            "$project_id" "$project_path" "$parent_dir"      "/projects/${project_id}/snippets"
        _backup_data issues              "$project_id" "$project_path" "$backup_root_dir" "/projects/${project_id}/issues?state=all&with_labels_details=true&include_subscribed=true"

        _backup_project_core "$project_id" "$project_path" "$backup_root_dir"
      done
      ((page++))
    done

    # subgroups
    page=1
    while : ; do
      local url="${gitlab_url}/api/v4/groups/${current_group_id}/subgroups?per_page=${GL_PER_PAGE:-100}&page=${page}"
      _dbg "GET  $url"
      local rsp; rsp=$(_curl "$url" -w $'\n%{http_code}')
      local http; http="$(echo "$rsp" | tail -n1)"
      local body; body="$(echo "$rsp" | sed '$d')"
      [[ "$http" != "200" ]] && { _dbg "HTTP $http – stop subgroup paging"; break; }
      [[ "$(jq -r 'type' <<<"$body")" != "array" ]] && break
      [[ "$(jq 'length' <<<"$body")" -eq 0 ]] && break

      echo "$body" | jq -c '.[]' | while read -r sg; do
        local subgroup_id group_path
        subgroup_id=$(jq -r '.id' <<<"$sg")
        group_path=$(_safe "$(jq -r '.full_path' <<<"$sg")")
        echo "Group: $group_path"

        _backup_data variables_group "$subgroup_id" "$group_path" "$backup_root_dir" "/groups/${subgroup_id}/variables"
        _clone_recursive "$backup_root_dir" "$subgroup_id" "$parent_dir"
      done
      ((page++))
    done
  }

  # ---------- init (prompts + dirs) ----------
  if [[ ${gitlab_private_token:-} == "" ]]; then
    read -r -p "Enter your GitLab Private Token: " gitlab_private_token
    export gitlab_private_token
  fi
  if [[ ${group_id:-} == "" ]]; then
    read -r -p "Enter your GitLab Group ID(s) (comma-separated for multiple): " group_id
    export group_id
  fi
  [[ ${gitlab_url:-} == "" ]] && gitlab_url="https://gitlab.com"

  local backup_root_base zip_destination_dir
  if [[ ${backup_dir:-} == "" ]]; then
    backup_root_base="/tmp/backup/files"
    zip_destination_dir="/tmp/backup/zip"
  else
    case "${backup_dir}" in
      "/"|"/mnt"|"/c"|"/d"|"/e"|"/f"|"/home"|"/root"|"/etc"|"/var"|"/usr"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/opt")
        echo "Error: backup_dir cannot be a critical system directory."
        return 1
        ;;
      *)
        backup_root_base="${backup_dir}/files"
        zip_destination_dir="${backup_dir}/zip"
        ;;
    esac
  fi
  _mkdir "$backup_root_base" "$zip_destination_dir"

  local date_and_time; date_and_time=$(date +%Y-%m-%d_%H-%M-%S)

  IFS=',' read -r -a _group_ids_raw <<< "$group_id"
  local _had_any=false

  for _gid_raw in "${_group_ids_raw[@]}"; do
    local gid="$(_trim "$_gid_raw")"
    [[ -z "$gid" ]] && continue
    _had_any=true

    local group_backup_dir="${backup_root_base}/group_${gid}"

    # group info
    local group_meta; group_meta=$(_curl "${gitlab_url}/api/v4/groups/${gid}" || true)
    local group_name; group_name=$(jq -r '.name // empty' <<<"$group_meta")
    if [[ -z "$group_name" || "$group_name" == "null" ]]; then
      echo "[WARN] Cannot resolve group ${gid}; skipping."
      continue
    fi

    echo "===== Backing up Group ID ${gid} (${group_name}) ====="
    _mkdir "$group_backup_dir/_meta/group"

    _save_json "${group_backup_dir}/_meta/group/group.json" "$group_meta"
    _save_json "${group_backup_dir}/_meta/group/members_all.json" "$(_get_all_pages "/groups/${gid}/members/all")"
    _save_json "${group_backup_dir}/_meta/group/labels.json"      "$(_get_all_pages "/groups/${gid}/labels")"
    _save_json "${group_backup_dir}/_meta/group/milestones.json"  "$(_get_all_pages "/groups/${gid}/milestones?state=all")"
    _save_json "${group_backup_dir}/_meta/group/hooks.json"       "$(_get_all_pages "/groups/${gid}/hooks")"
    _save_json "${group_backup_dir}/_meta/group/boards.json"      "$(_get_all_pages "/groups/${gid}/boards")"
    _save_json "${group_backup_dir}/_meta/group/epics.json"       "$(_get_all_pages "/groups/${gid}/epics?state=all")" || true

    _backup_data "variables_group" "$gid" "$group_name" "$group_backup_dir" "/groups/${gid}/variables"

    _clone_recursive "$group_backup_dir" "$gid" "$group_backup_dir"

    echo "Zipping group ${gid} ..."
    local zip_ok=1
    if _ensure_zip_ready; then
      ( cd "$(dirname "$group_backup_dir")" && \
        "$ZIP_CMD" -q -r \
          "${zip_destination_dir}/gitlab_backup_group_${gid}_${date_and_time}.zip" \
          "$(basename "$group_backup_dir")" -x "*.zip" ) || zip_ok=0
    else
      zip_ok=0
    fi

    if [[ "$zip_ok" -eq 1 ]]; then
      echo "Cleanup group ${gid} ..."
      if [[ "$group_backup_dir" == *"/files/group_"* ]]; then
        rm -rf "$group_backup_dir"
      else
        echo "Cannot cleanup, safety check failed for '$group_backup_dir'"
      fi
    else
      echo "[WARN] Zip failed; keeping ${group_backup_dir}."
      if [[ "${KEEP_FILES_ON_ERROR}" == "0" ]]; then
        echo "[WARN] KEEP_FILES_ON_ERROR=0 set → force cleanup."
        [[ "$group_backup_dir" == *"/files/group_"* ]] && rm -rf "$group_backup_dir"
      fi
    fi

    if [ -n "${rclone_bucket:-}" ]; then
      echo "RClone is enabled, uploading backup for group ${gid}"
      rclone --config /tmp/rclone.conf copy \
        "${zip_destination_dir}/gitlab_backup_group_${gid}_${date_and_time}.zip" \
        "s3:${rclone_bucket}/gitlab/gitlab-backup_${gid}_${date_and_time}" || true
    fi

    echo "===== Done Group ${gid} ====="
  done

  if [[ "$_had_any" != "true" ]]; then
    echo "[ERROR] No valid group IDs were provided."
    return 1
  fi

  echo "All done."
}



function gitlab_update_file() {
  project_id="$1"
  file_path="$2"
  branch_name="$3"
  commit_message="$4"
  file_contents="$5"

  # Encode the file path for URL
  encoded_file_path=$(printf '%s' "$file_path" | jq -sRr @uri)

  # Construct the API URL dynamically, ensuring there's no newline character at the end
  api_url="https://gitlab.com/api/v4/projects/${project_id}/repository/files/${encoded_file_path}"

  # Ensure the file contents are properly escaped as a JSON string
  json_safe_contents=$(echo "$file_contents" | jq -sR .)

  curl -s --request PUT "$api_url" \
      -H "PRIVATE-TOKEN: $GLOBAL_GIT_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
          \"branch\": \"${branch_name}\",
          \"author_email\": \"$GLOBAL_GIT_EMAIL\",
          \"author_name\": \"$GLOBAL_GIT_USER\",
          \"content\": $json_safe_contents,
          \"commit_message\": \"${commit_message}\"
      }" # > /dev/null 2>&1
}

function git_set_remote() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: set_git_remote <repo_url> <token>"
    echo "  <repo_url>: The URL of the repository where you want to change the remote (e.g., https://github.com/username/new-repository.git)"
    echo "  <token>: Your personal access token for authentication"
    return 1
  fi

  local repo_url=$1
  local token=$2

  # Check if the URL has 'https://' at the start and strip it out because we'll add it along with the token
  if [[ $repo_url =~ ^https:// ]]; then
    repo_url="${repo_url#https://}"
  fi

  # Construct the new URL with the token
  local new_url="https://${token}@${repo_url}"

  # Set the new URL to the Git remote named 'origin'
  git remote set-url origin "$new_url"
  echo "Remote URL set to ${new_url}"
}

function github_backup() {

  export GIT_TERMINAL_PROMPT=0          # never prompt for username/pw

  ##################################################################
  # helpers
  ##################################################################
  _clone_branches() {                    # $1 remote  $2 dest dir
      local remote=$1 dest=$2
      git ls-remote --heads "$remote" | awk '{print $2}' | sed 's#refs/heads/##' |
      while read -r br; do
          local safe=${br//[\/:]/_}
          mkdir -p "$dest/$safe"
          git clone --quiet --branch "$br" --single-branch "$remote" "$dest/$safe" \
               >/dev/null 2>&1 || _dbg "git clone failed on branch $br"
      done
  }

  _paged_json() {                        # $1 endpoint-without-?  $2 outfile
      local ep=$1 out=$2 page=1 buf='[]'
      while : ; do
          local url="${ep}?per_page=100&page=${page}"
          _dbg "GET  $url"
          local rsp; rsp=$(curl -s -w "%{http_code}" -H "Authorization: token $github_token" "$url")
          local code=${rsp: -3} body=${rsp::-3}
          _dbg "HTTP $code  body preview: $(echo "$body" | head -c120 | tr '\n' ' ')…"

          [[ "$code" != "200" ]] && { _dbg "non-200, stop paging"; break; }
          [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && { _dbg "payload not array, stop paging"; break; }

          [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break
          buf=$(jq -s 'add' <(echo "$buf") <(echo "$body"))
          ((page++))
      done
      [[ "$(echo "$buf" | jq 'length')" -gt 0 ]] && printf '%s' "$buf" > "$out"
  }

  ##################################################################
  # prompts
  ##################################################################
  : "${github_token:=$(read -rp 'GitHub Personal Access Token: ' t && echo "$t")}"
  : "${github_user:=$(read -rp 'GitHub username / org: ' u && echo "$u")}"
  : "${REPO_SCOPE:=owner}"
  local ts; ts=$(date +%Y-%m-%d_%H-%M-%S)

  ##################################################################
  # destination dirs
  ##################################################################
  if [[ -z ${backup_dir:-} ]]; then
      root="/tmp/backup/files"; zip_dir="/tmp/backup/zip"
  else
      case "$backup_dir" in
          "/"|"/mnt"|"/home"|"/root"|"/etc"|"/var"|"/usr"|"/bin"|"/sbin"|"/lib"|"/lib64"|"/opt")
              echo "ERR: backup_dir cannot be critical"; return 1 ;;
          *)  root="$backup_dir/files"; zip_dir="$backup_dir/zip" ;;
      esac
  fi
  mkdir -p "$root"

  ##################################################################
  # decide user vs org endpoint
  ##################################################################
  local api
  if curl -sI "https://api.github.com/orgs/$github_user" | grep -q '^Status: 200'; then
      api="https://api.github.com/orgs/$github_user/repos"
      [[ -z "$REPO_SCOPE" ]] && REPO_SCOPE=all
  else
      api="https://api.github.com/users/$github_user/repos"
  fi

  ##################################################################
  # iterate repo pages
  ##################################################################
  local page=1
  while : ; do
      local url="${api}?type=${REPO_SCOPE}&per_page=100&page=${page}"
      _dbg "LIST $url"
      local rsp; rsp=$(curl -s -w "%{http_code}" -H "Authorization: token $github_token" "$url")
      local code=${rsp: -3} body=${rsp::-3}
      _dbg "HTTP $code  body preview: $(echo "$body" | head -c120 | tr '\n' ' ')…"

      [[ "$code" != "200" ]] && { _dbg "non-200, stop repo pagination"; break; }
      [[ "$(echo "$body" | jq -r 'type')" != "array" ]] && { _dbg "payload not array, stop"; break; }
      [[ "$(echo "$body" | jq 'length')" -eq 0 ]] && break

      echo "$body" | jq -c '.[]' | while read -r repo_raw; do
          if [[ "$(echo "$repo_raw" | jq -r 'type')" != "object" ]]; then
              _dbg "⚠️  skipping non-object entry: $repo_raw"; continue
          fi
          local full; full=$(echo "$repo_raw" | jq -r '.full_name')
          echo "➡  $full"

          local remote="https://${github_token}@github.com/${full}.git"
          local repo_dir="$root/_repositories/$full"
          local mir_dir="$root/_mirror/$full"
          mkdir -p "$repo_dir" "$mir_dir"

          _clone_branches "$remote" "$repo_dir"
          git clone --quiet --mirror "$remote" "$mir_dir" >/dev/null 2>&1 || \
              _dbg "mirror clone failed $full"

          # -------- metadata ---------------------------------------------
          local m="$root/_metadata/$full"; mkdir -p "$m"
          curl -s -H "Authorization: token $github_token" \
               "https://api.github.com/repos/$full" > "$m/repo.json"

          for ep in issues pulls; do
              _paged_json "https://api.github.com/repos/$full/${ep}?state=all" "$m/${ep}.json"
          done
          [[ -s "$m/issues.json" ]] && jq -c '.[]' "$m/issues.json" |
              while read -r i; do
                  _paged_json "https://api.github.com/repos/$full/issues/$(echo "$i" | jq -r '.number')/comments" \
                              "$m/issue_$(echo "$i" | jq -r '.number')_comments.json"
              done
          [[ -s "$m/pulls.json" ]] && jq -c '.[]' "$m/pulls.json" |
              while read -r p; do
                  local num; num=$(echo "$p" | jq -r '.number')
                  _paged_json "https://api.github.com/repos/$full/pulls/$num/reviews"  "$m/pr_${num}_reviews.json"
                  _paged_json "https://api.github.com/repos/$full/pulls/$num/comments" "$m/pr_${num}_comments.json"
              done
          _paged_json "https://api.github.com/repos/$full/releases" "$m/releases.json"

          # -------- wiki --------------------------------------------------
          if git ls-remote --exit-code --heads "https://github.com/${full}.wiki.git" >/dev/null 2>&1; then
              local w="$root/_wiki/$full"; mkdir -p "$w"
              git clone --quiet --mirror "https://${github_token}@github.com/${full}.wiki.git" "$w" \
                   >/dev/null 2>&1 || _dbg "wiki clone failed $full"
          fi
      done
      ((page++))
  done

  ##################################################################
  # archive + cleanup
  ##################################################################
  echo "Zipping …"
  mkdir -p "$zip_dir"
  local zip="$zip_dir/github_backup_${github_user}_${ts}.zip"
  (cd "$root" && zip -q -r "$zip" . -x '*.zip')
  find "$root" -mindepth 1 -delete

  [[ -n ${rclone_bucket:-} ]] && \
      rclone --config /tmp/rclone.conf copy "$zip" "s3:${rclone_bucket}/github/$(basename "$zip")"

  echo "✅  GitHub backup ready → $zip"
}
