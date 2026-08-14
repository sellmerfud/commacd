# shellcheck disable=SC2148

# sellmerfud note:
# ----------------
# This is a modified version of the script found at:  https://github.com/shyiko/commacd
# I made a few minor tweaks so that it suits me better...
# ----------------

# commacd - a faster way to move around (Bash 3+).

#
# ENV variables that can be used to control commacd:
#   COMMACD_CD - function to change the directory
#     (by default 'builtin cd "$1" && pwd' is used)
#   COMMACD_NOTTY - set it to "on" when you want to suppress user input
#     (print multiple matches and exit)
#   COMMACD_NOFUZZYFALLBACK - set it to "on" if you don't want commacd to use
#     "fuzzy matching" as a fallback for "no matches by prefix"
#     (introduced in 0.2.0)
#   COMMACD_SEQSTART - set it to 1 if you want "multiple choices" to start
#     from 1 instead of 0
#     (introduced in 0.3.0)
#   COMMACD_IMPLICITENTER - set it to "on" to avoid pressing <ENTER> when
#     number of options (to select from) is less than 10
#     (introduced in 0.4.0)
#   COMMACD_MARKERS - space-separated project root "marker"s (for ,, to stop at)
#     (".git/ .hg/ .svn/" by default)
#     (introduced in 1.0.0)
#
# @version 1.0.0
# @author Stanley Shyiko <stanley.shyiko@gmail.com>
# @license MIT

# turn on case-insensitive search by default

if [ -n "$BASH_VERSION" ]; then
  shopt -s nocaseglob
else
  _commacd_errout "commacd: is only supported for bash"
  return
fi

_commacd_errout() {
  local fmt="$1"
  shift
  # shellcheck disable=2059
  printf "$fmt\n" "$@" >&2
}

# Use when splitting a path into its component parts.
# The first part will begin with a forward slash if the path
# was absolute.  Each other part will always begin with a forward slash.
# The output of this function should be redirectoed to `mapfile` to convert
# the parts into an array as follows:
#  ==> mapfile -t myarray <<< "$(_commacd_split "$PWD")"
# This ensures that paths with spaces in the component part are handled correctly.
_commacd_split() {
  local str="$1" lead_slash=""
  if [[ "$str" == /* ]]; then
    lead_slash="/"
    str=${str#/}
  fi
  echo "${lead_slash}${str//\//$'\n'/}"
}

# First arg is string used between each joined part
# The rest of the args are returned as a single string joined
# together.
_commacd_join() {
  local IFS="$1"
  shift
  echo "$*"
}

# Resolve the given path honoring glob characters
# It will generation zero or more paths
_commacd_expand() (  # subshell because we are calling shopt
  shopt -s extglob nullglob
  shopt -u failglob
  # Allow globbing in case $1 contains '*'
  # shellcheck disable=SC2206
  local paths=($1)

  printf "%s\n" "${paths[@]}"
)

# Change the current directory
_commacd_cd() {
  local dir="$1" IFS=$' \t\n' display
  [[ -z "$dir" ]] && return  # Use cancelled a selection

  if [[ -z "$COMMACD_CD" ]]; then
    if [[ "$PWD" != "$dir" ]]; then
      display="$(builtin cd "$dir" || return 1)"
      if [[ -z "$display" ]]; then
        builtin cd "$dir" && pwd || return 1
      else
        builtin cd "$dir" || return 1
      fi
    else
      _commacd_errout "commacd: no matches found"
      return 1
    fi
  else
    $COMMACD_CD "$dir"
  fi
}

# show match selection menu
_commacd_choose_match() {
  local -a matches
  mapfile -t matches <<< "$(printf "%s\n" "$@" | sort)"
  local i=${COMMACD_SEQSTART:-0}
  local num="${#matches[@]}"
  local width=${#num}
  for match in "${matches[@]}"; do
    _commacd_errout "%*s  %s" "$width" "$((i++))" "$match"
  done
  local selection
  local threshold=$((11-${COMMACD_SEQSTART:-0}))
  # Loop until we get a valid response
  while true; do
    if [[ "$COMMACD_IMPLICITENTER" == "on" && \
        ${#matches[@]} -lt $threshold ]]; then
      read -r -n1 -e -p ': ' selection >&2
    else
      read -r -e -p ': ' selection >&2
    fi
    if [[ -z "$selection" ]]; then
      # User cancelled operation
      echo -n ""
      return
    elif [[ "$selection" =~ ^[0-9]+$ ]]; then
      local i=$((selection-${COMMACD_SEQSTART:-0}))
      if [[ "${matches[i]}" != "" ]]; then
        echo -n "${matches[i]}"
        return
      else
        _commacd_errout "Invalid selection! %s" "$selection"
      fi
    else
      _commacd_errout "Invalid selection! %s" "$selection"
    fi
  done
}

# takes a path and returns the same path with glob (*)
# at the end of each component to allow for prefix matching
#  /aaa/bbb/ccc ==> /aaa*/bbb*/ccc*/
_commacd_prefix_glob() {
  local -  # restore -f option on exit
  set -f
  local components
  local path="${1%/}" IFS=$'\n'
  # shellcheck disable=SC2046
  mapfile -t components <<< "$(_commacd_split "$path")"
  # If there were no matches mapfile will create an array with
  # a single empty entry.
  [[ ${#components[@]} == 1 ]] && [[ -z "${components[0]}" ]] && components=()
  echo -n "$(_commacd_join \* "${components[@]}")*/"
}

# takes a path and returns the same path with glob (*)
# at the start and end of each component to allow for infix matching
#  /aaa/bbb/ccc ==> /*aaa*/*bbb*/*ccc*/
_commacd_infix_glob() {
  local -  # restore -f option on exit
  set -f
  local path="${1%/}" IFS=$'\n'
  if [[ ! "$path" =~ "/" ]]; then
    path="*$path*"
  else
    path="$(_commacd_prefix_glob "$path")"
    path="${path%/}"
    path="${path//\//\/*}"
    [[ ! "$path" == /* ]] && path="*$path"
  fi
  echo -n "$path/"
}

# Utility function used by _commacd_forward()
_commacd_forward_by_prefix() {
  local matches
  mapfile -t matches <<< "$(_commacd_expand "$(_commacd_prefix_glob "$1")")"
  # If there were no matches mapfile will create an array with
  # a single empty entry.
  [[ ${#matches[@]} == 1 ]] && [[ -z "${matches[0]}" ]] && matches=()
  if [[ "$COMMACD_NOFUZZYFALLBACK" != "on" ]] && [[ ${#matches[@]} == 0 ]]; then
    mapfile -t matches <<< "$(_commacd_expand "$(_commacd_infix_glob "$1")")"
    [[ ${#matches[@]} == 1 ]] && [[ -z "${matches[0]}" ]] && matches=()
  fi
  case ${#matches[@]} in
    0) echo -n "";;
    *) printf "%s\n" "${matches[@]}"
  esac
}


# jump forward (`,`)
_commacd_forward() {
  local IFS=$'\n' matches dir
  if [[ -z "$1" ]]; then
    _commacd_errout "USAGE: , <pat>"
    return 1
  fi
  mapfile -t matches <<< "$(_commacd_forward_by_prefix "$@")"
  # If there were no matches mapfile will create an array with
  # a single empty entry.
  [[ ${#matches[@]} == 1 ]] && [[ -z "${matches[0]}" ]] && matches=()
  if [[ "$COMMACD_NOTTY" == "on" ]]; then
    printf "%s\n" "${matches[@]}"
    return
  fi

  case ${#matches[@]} in
    0)
      _commacd_errout "No match for '%s'" "$1"
      return 1
      ;;
    1)
      _commacd_cd "${matches[0]}"
      ;;
    *)
      # https://github.com/shyiko/commacd/issues/12
      # trap 'trap - SIGINT; stty '"$(stty -g)" SIGINT

      dir="$(_commacd_choose_match "${matches[@]}")"
      # make sure trap is removed regardless of whether read -e ... was
      # interrupted or not
      # trap - SIGINT
      if [[ -z "$dir" ]]; then
        return 0
      else
        _commacd_cd "$dir"
      fi
      ;;
  esac
}

# See if the subdirectory listed in the COMMACD_MARKERS
# variable exists in the given directory
_commacd_marked() {
  local dir markers
  dir="${1%/}"
  mapfile -t markers <<< "$(echo "${COMMACD_MARKER:-.git/ .hg/ .svn/}" | tr ' ' '\n')"
  for marker in "${markers[@]}"; do
    if [[ -e "$dir/$marker" ]]; then
      return 0
    fi
  done
  return 1
}

# search backward for a directory containing a marker (`,,`)
# ie. the root of a project
_commacd_backward_projcect_root() {
  local dir="${PWD%/*}"
  while [[ -n "$dir" ]] && ! _commacd_marked "$dir"; do
    dir="${dir%/*}"
  done

  if [[ "$COMMACD_NOTTY" == "on" ]]; then
    printf "%s\n" "$dir"
    return
  elif [[ -z "$dir" ]]; then
    _commacd_errout "No project root found"
    return 1
  else
    _commacd_cd "$dir"
  fi
}

# search backward for the directory whose name begins with $1 (`,, $1`)
_commacd_backward_by_prefix() {
  local parts num_parts idx dir target
  target="${1}"
  dir=""
  # if the target is an absolute path then just pass it along
  # because it probably was generated by tab completion.
  if [[ "${target:0:1}" == "/" ]]; then
    [[ -d "$target" ]] && dir="$target"
  else
    mapfile -t parts <<< "$(_commacd_split "$PWD")"
    num_parts=${#parts[@]}
    if ((num_parts > 1)); then
      for ((idx = num_parts - 2; idx >= 0; --idx)); do
        if [[ "${parts[idx],,}" == /"${target,,}"* ]]; then
          dir="$(_commacd_join '' "${parts[@]:0:idx+1}")"
          break
        elif [[ "$COMMACD_NOFUZZYFALLBACK" != "on" ]] && [[ "${parts[idx],,}" == /*"${target,,}"* ]]; then
          dir="$(_commacd_join '' "${parts[@]:0:idx+1}")"
          break
        fi
      done
    fi
  fi

  if [[ "$COMMACD_NOTTY" == "on" ]]; then
    printf "%s\n" "$dir"
    return
  elif [[ -z "$dir" ]]; then
    _commacd_errout "no match found"
    return 1
  else
    _commacd_cd "$dir"
  fi
}

# replace $1 with $2 in $PWD (`,, $1 $2`)
_commacd_backward_substitute() {
  # echo -n "${PWD/$1/$2}"
  local cwd_parts num_parts idx dir head_parts tail_parts
  local head_matches matches target
  local target_prefix="$1" repl_prefix="$2"

  mapfile -t cwd_parts <<< "$(_commacd_split "$PWD")"
  num_parts="${#cwd_parts[@]}"
  # Find right most part of the workding directory path
  # that starts with the target prefix
  for ((idx=num_parts - 1; idx >= 0; idx--)); do
    local part="${cwd_parts[$idx]}"
    [[ "${part,,}" == /"${target_prefix,,}"* ]] && break
  done

  if [[ $idx == -1 ]] && [[ "$COMMACD_NOFUZZYFALLBACK" != "on" ]]; then
    for ((idx=num_parts - 1; idx >= 0; idx--)); do
      local part="${cwd_parts[$idx]}"
      [[ "${part,,}" == /*"${target_prefix,,}"* ]] && break
    done
  fi

  if [[ $idx == -1 ]]; then
    _commacd_errout "'%s' cannot be matched in the working directory path!" "$target_prefix"
    return 1
  else
    target="${cwd_parts[idx]}"  # The full target for error reporting
    # The head of the cwd path preceeding the target with
    # with the replacment prefix and a glob appended for lookup
    head_parts=("${cwd_parts[@]:0:idx}" "/$repl_prefix*")
    head="$(_commacd_join '' "${head_parts[@]}")"
    mapfile -t head_matches <<< "$(_commacd_expand "$head")"
    # The tail is everything following the replaced path part
    tail_parts=("${cwd_parts[@]:idx+1}")
    tail="$(_commacd_join '' "${tail_parts[@]}")"
    # Find all directories that exist when we append the tail
    # too one of the head matches.
    final_matches=()
    for head_match in "${head_matches[@]}"; do
      local candidate="$head_match$tail"
      if [[ -d "$candidate" ]] && [[ "$candidate" != "$PWD" ]]; then
        final_matches+=("$candidate")
      fi
    done

    if [[ ${#final_matches[@]} == 0 ]] && [[ "$COMMACD_NOFUZZYFALLBACK" != "on" ]]; then
      head_parts=("${cwd_parts[@]:0:idx}" "/*$repl_prefix*")
      head="$(_commacd_join '' "${head_parts[@]}")"
      mapfile -t head_matches <<< "$(_commacd_expand "$head")"
      # The tail is everything following the replaced path part
      tail_parts=("${cwd_parts[@]:idx+1}")
      tail="$(_commacd_join '' "${tail_parts[@]}")"
      # Find all directories that exist when we append the tail
      # too one of the head matches.
      final_matches=()
      for head_match in "${head_matches[@]}"; do
        local candidate="$head_match$tail"
        if [[ -d "$candidate" ]] && [[ "$candidate" != "$PWD" ]]; then
          final_matches+=("$candidate")
        fi
      done
    fi

    case "${#final_matches[@]}" in
      0)
        _commacd_errout "'%s' cannot be matched in same location as '%s'" "$repl_prefix" "${target:1}"
        return 1
        ;;
      1)
        _commacd_cd "${final_matches[0]}"
        ;;
      *)
        dir="$(_commacd_choose_match "${final_matches[@]}")"
        if [[ -z "$dir" ]]; then
          return 0
        else
          _commacd_cd "$dir"
        fi
    esac
  fi
}

# choose `,,` strategy based on a number of arguments
_commacd_backward() {
  # when called for completion without args, we get an empty arg
  [[ $# == 1 && -z "$1" ]] && shift
  case $# in
    0) _commacd_backward_projcect_root ;;
    1) _commacd_backward_by_prefix "$1" ;;
    2) _commacd_backward_substitute "$@" ;;
    *)
      printf "USAGE: ,,               -- cd to project root\n"
      printf "USAGE: ,, <pat>         -- cd to closest parent that matches <pat>\n"
      printf "USAGE: ,, <pat1> <pat2> -- cd to path with <pat1> replaced by <pat2> in working directory\n"
      return 1
      ;;
  esac
}

_commacd_backward_forward_by_prefix() {
  local dir path matches num_matches idx IFS=$'\n'
  path="${1%/}/"
  if [[ "${path:0:1}" == "/" ]]; then
    # assume that we've been brought here by the completion
    local absdir=("${path%/}"*)
    printf "%s\n" "${absdir[*]}"
    return
  fi

  dir="$PWD"
  while [[ -n "$dir" ]]; do
    dir="${dir%/*}"
    mapfile -t matches <<< "$(_commacd_expand "$dir/$(_commacd_prefix_glob "$1")")"
    [[ ${#matches[@]} == 1 ]] && [[ -z "${matches[0]}" ]] && matches=()
    # Filter out all matches that reference $PWD
    num_matches=${#matches[@]}
    for ((idx = 0; idx < num_matches; ++idx)); do
      [[ "${matches[idx]}" == "$PWD"* ]] && unset 'matches[idx]'
    done
    matches=("${matches[@]}")
    if [[ "$COMMACD_NOFUZZYFALLBACK" != "on" ]] && [[ ${#matches[@]} == 0 ]]; then
      mapfile -t matches <<< "$(_commacd_expand "$dir/$(_commacd_infix_glob "$1")")"
      [[ ${#matches[@]} == 1 ]] && [[ -z "${matches[0]}" ]] && matches=()
      # Filter out all matches that reference $PWD
      num_matches=${#matches[@]}
      for ((idx = 0; idx < num_matches; ++idx)); do
        [[ "${matches[idx]}" == "$PWD"* ]] && unset 'matches[idx]'
      done
      matches=("${matches[@]}")
    fi
    if [[ ${#matches[@]} != 0 ]]; then
      printf "%s\n" "${matches[@]}"
      return
    fi
  done
  echo -n ""
}

# combine backtracking with `, $1` (`,,, $1`)
_commacd_backward_forward() {
  if [[ -z "$1" ]]; then
    printf "\
USAGE: ,,, <pat>   -- cd up the working directory and back down to\n\
                      the first directory that matches <pat>\n"
    return 1;
  fi
  local IFS=$'\n'
  local candidates dir
  mapfile -t candidates <<< "$(_commacd_backward_forward_by_prefix "$1")"
  # If there were no matches mapfile will create an array with
  # a single empty entry.
  [[ ${#candidates[@]} == 1 ]] && [[ -z "${candidates[0]}" ]] && candidates=()

  if [[ "$COMMACD_NOTTY" == "on" ]]; then
    printf "%s\n" "${candidates[@]}"
    return
  fi

  case ${#candidates[@]} in
    0)
      printf "No match for '%s'\n" "$1"
      return 1
      ;;
    1)
      dir="${candidates[0]}"
      ;;
    *)
      dir="$(_commacd_choose_match "${candidates[@]}")"
      [[ -z "$dir" ]] && return  # user cancelled
      ;;
  esac

  _commacd_cd "$dir"
}

_commacd_completion() {
  local pattern=${COMP_WORDS[COMP_CWORD]} IFS=$'\n'
  # shellcheck disable=SC2088
  # Expand patterns that start with tilde to $HOME
  if [[ "${pattern:0:2}" == "~/" ]]; then
    pattern="${HOME%/}/${pattern:2}"
  fi
  # local completion=($(COMMACD_NOTTY=on $1 "$pattern"))
  local completion
  mapfile -t completion <<< "$(COMMACD_NOTTY=on $1 "$pattern")"
  # If there were no matches mapfile will create an array with
  # a single empty entry.
  [[ ${#completion[@]} == 1 ]] && [[ -z "${completion[0]}" ]] && completion=()

  for i in "${!completion[@]}"; do
    completion[i]="${completion[$i]%/}";
  done
  mapfile -t COMPREPLY <<< "$(compgen -W "$(printf "%s\n" "${completion[@]}")" -- '')"
}

_commacd_forward_completion() {
  _commacd_completion _commacd_forward
}

_commacd_backward_completion() {
  if [[ ${#COMP_WORDS[@]} -le 2 ]]; then
    _commacd_completion _commacd_backward
  fi
}

_commacd_backward_forward_completion() {
  _commacd_completion _commacd_backward_forward
}

alias ,=_commacd_forward
alias ,,=_commacd_backward
alias ,,,=_commacd_backward_forward

if [ -n "$BASH_VERSION" ]; then
  complete -o filenames -F _commacd_forward_completion ,
  complete -o filenames -F _commacd_backward_completion ,,
  complete -o filenames -F _commacd_backward_forward_completion ,,,
fi
