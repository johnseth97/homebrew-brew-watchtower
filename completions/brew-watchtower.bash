# Bash completion for brew-watchtower.
_brew_watchtower_groups() {
  brew-watchtower groups 2>/dev/null | awk '{print $1}'
}

_brew_watchtower() {
  local cur prev command
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  command="${COMP_WORDS[1]}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W 'groups list add remove check run status drift blurb config setup schedule version help' -- "$cur") )
    return
  fi

  case "$command" in
    check|run|status)
      COMPREPLY=( $(compgen -W "$(_brew_watchtower_groups)" -- "$cur") )
      ;;
    remove)
      if [[ $COMP_CWORD -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "$(_brew_watchtower_groups)" -- "$cur") )
      fi
      ;;
    add)
      case "$COMP_CWORD" in
        2) COMPREPLY=( $(compgen -W "$(_brew_watchtower_groups)" -- "$cur") ) ;;
        3) COMPREPLY=( $(compgen -W 'formula cask' -- "$cur") ) ;;
        5) COMPREPLY=( $(compgen -W 'auto interactive' -- "$cur") ) ;;
      esac
      ;;
    config)
      COMPREPLY=( $(compgen -W 'init show path' -- "$cur") )
      ;;
    schedule)
      if [[ $COMP_CWORD -eq 2 ]]; then
        COMPREPLY=( $(compgen -W "$(_brew_watchtower_groups)" -- "$cur") )
      fi
      ;;
  esac
}
complete -F _brew_watchtower brew-watchtower
