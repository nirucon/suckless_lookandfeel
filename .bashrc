# --- ~/.bashrc (Arch Linux) ---

# 0) Interactive shells only
[[ $- != *i* ]] && return

# 1) Recover from deleted CWD (avoid getcwd errors)
if ! builtin pwd >/dev/null 2>&1; then
  cd "$HOME" 2>/dev/null || cd /
  export PWD="$(pwd -P)"
fi

# 2) Base environment (editor, pager, PATH without duplicates)
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
export PAGER="${PAGER:-less}"

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/bin:"*) ;; *) PATH="$HOME/bin:$PATH" ;; esac
export PATH

# 3) Shell options: quality of life + case-insensitivity + mild autocorrect
shopt -s checkwinsize         # keep terminal size in sync
shopt -s cmdhist              # save multi-line commands as one line
shopt -s histappend           # append history instead of overwriting
shopt -s autocd               # type a directory name to cd into it
shopt -s cdspell              # autocorrect minor typos in 'cd' (incl. case)
shopt -s dirspell 2>/dev/null # correct dirs during completion (if supported)
shopt -s nocaseglob           # case-insensitive globbing (MatteBlack friendly)
shopt -s globstar             # ** recursive globs
shopt -s extglob              # extended globs

# 4) Readline: smarter completion (kept here too even if ~/.inputrc exists)
bind "set completion-ignore-case on"
bind "set show-all-if-ambiguous on"
bind "set mark-symlinked-directories on"

# 5) History: large, deduped, and flushed every prompt
export HISTSIZE=50000
export HISTFILESIZE=200000
export HISTCONTROL=ignoredups:erasedups
export HISTIGNORE="ls:ll:la:cd:pwd:clear:history"
# write new lines to history, reload, and preserve any PROMPT_COMMAND you already have
__niru_hist_cmd='history -a; history -c; history -r'
PROMPT_COMMAND="${__niru_hist_cmd}${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# 6) Colors for 'ls' and friends (dircolors if available)
if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b 2>/dev/null || true)"
fi

# 7) Filesystem & text helpers (aliases kept conservative/safe)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias la='eza -a --group-directories-first --icons=auto'
  alias ll='eza -alh --group-directories-first --icons=auto --time-style=long-iso'
else
  alias ls='ls --color=auto --group-directories-first'
  alias la='ls -A'
  alias ll='ls -Alh'
fi
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }

# Quick extractor: x file.[zip|tar|gz|xz|7z|rar|…]
x() {
  local f="$1"
  [[ -r "$f" ]] || {
    echo "No such file: $f" >&2
    return 1
  }
  case "$f" in
  *.tar.bz2) tar xjf "$f" ;;
  *.tar.gz) tar xzf "$f" ;;
  *.tar.xz) tar xJf "$f" ;;
  *.tar.zst) tar --zstd -xf "$f" ;;
  *.bz2) bunzip2 "$f" ;;
  *.rar) unrar x "$f" ;;
  *.gz) gunzip "$f" ;;
  *.tar) tar xf "$f" ;;
  *.tbz2) tar xjf "$f" ;;
  *.tgz) tar xzf "$f" ;;
  *.zip) unzip "$f" ;;
  *.7z) 7z x "$f" ;;
  *.xz) unxz "$f" ;;
  *)
    echo "Don't know how to extract '$f'." >&2
    return 2
    ;;
  esac
}

# 8) Arch Linux helpers (pacman / yay)
alias pacs='pacman -Ss'       # search repos
alias paci='sudo pacman -S'   # install
alias pacr='sudo pacman -Rns' # remove (with deps)
alias pacq='pacman -Qs'       # search installed
alias pacl='pacman -Ql'       # list files in package
alias paco='pacman -Qtdq'     # list orphans
alias pacf='pacman -F'        # file belongs to which pkg (needs files db)

if command -v yay >/dev/null 2>&1; then
  alias yays='yay -Ss'
  alias yayi='yay -S'
  alias yayr='yay -Rns'
  # Full system update (repo + AUR); noedit speeds it up, remove if you want to edit PKGBUILDs
  up() { yay -Syu --noconfirm --combinedupgrade --removemake --cleanafter --answerdiff None --answerclean All --useask --nocleanmenu; }
else
  up() { sudo pacman -Syu; }
fi

# Clean orphans safely
cleanup() {
  local orphans
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  [[ -z "$orphans" ]] && {
    echo "No orphans."
    return 0
  }
  printf "Orphans:\n%s\n" "$orphans"
  read -rp "Remove these orphans? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] && sudo pacman -Rns --nosave --noconfirm $orphans || true
}

# 9) System helpers
alias jctl='journalctl -p 3 -xb' # show errors of last boot
alias sc='sudo systemctl'
alias scu='systemctl --user'

# 10) man/less friendliness
export LESS='-R'
command -v lesspipe >/dev/null 2>&1 && eval "$(SHELL=/bin/sh lesspipe)"

# 11) fzf integration (if installed)
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --info=hidden"
  [[ -f /usr/share/fzf/completion.bash ]] && . /usr/share/fzf/completion.bash
  [[ -f /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash
fi

# 12) Git completion / prompt helpers (Arch typically ships here)
[[ -r /usr/share/git/completion/git-completion.bash ]] && . /usr/share/git/completion/git-completion.bash
[[ -r /usr/share/git/completion/git-prompt.sh ]] && . /usr/share/git/completion/git-prompt.sh

# Lightweight git branch helper (uses __git_ps1 if present, else a fast fallback)
__niru_git_ps1() {
  if type __git_ps1 >/dev/null 2>&1; then
    __git_ps1 " %s"
  else
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    local b
    b=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null) || return 0
    printf " (%s)" "$b"
  fi
}

# 13) Prompt (MatteBlack Noir: grayscale + white only)
#     - dim gray brackets/separators
#     - bright white user@host and prompt char
#     - light gray for directory and git
export PROMPT_DIRTRIM=3
if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
  PS1='[\u@\h \W$(__niru_git_ps1)] $ '
else
  c_dim='\[\e[90m\]' # dim gray
  c_gra='\[\e[37m\]' # light gray
  c_wht='\[\e[97m\]' # bright white (accent)
  c_rst='\[\e[0m\]'
  PS1="${c_dim}[${c_wht}\u@\h ${c_gra}\W\$(__niru_git_ps1)${c_dim}]${c_rst} ${c_wht}\$${c_rst} "
fi

# 14) Optional local overrides (never error if missing)
[[ -f ~/.bash_aliases ]] && . ~/.bash_aliases
[[ -f ~/.bashrc.local ]] && . ~/.bashrc.local
