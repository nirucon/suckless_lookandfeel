# --- ~/.bash_aliases (MatteBlack Noir friendly, Arch) ---
# This file is sourced by ~/.bashrc (at the end). Keep aliases & small functions here.

# 0) Always prefer grayscale/neutral tools output (theme responsibility is on terminal).
#    We avoid overriding core commands destructively (no rm -rf shortcuts here).

# 1) Editors/quick shortcuts
alias v='nvim'
alias e='nvim'
alias catn='nl -ba' # show line numbers quickly (non-color)

# 2) Deluxe ls: prefer eza if present, always show hidden files, human sizes, git info
if command -v eza >/dev/null 2>&1; then
  # Common flags:
  # -a (hidden), -l (long), -h (human), --group-directories-first, --icons=auto, --git
  alias ls='eza -alh --group-directories-first --icons=auto --git'
  alias ll='eza -alh --group-directories-first --icons=auto --git --time-style=long-iso'
  alias l1='eza -a1 --icons=auto'
  alias lS='eza -alh --group-directories-first --icons=auto --git --sort=size'
  alias lt='eza -alh --group-directories-first --icons=auto --git --tree'
  alias l.='eza -d .* --icons=auto' # show only dot entries in cwd
else
  # GNU ls fallback (good defaults, always shows hidden files)
  alias ls='ls -Alh --color=auto --group-directories-first'
  alias ll='ls -Alh --color=auto --group-directories-first'
  alias l1='ls -A1 --color=auto'
  alias lS='ls -Alh --color=auto --group-directories-first -S'
  # Tree-like view using 'tree' if available
  if command -v tree >/dev/null 2>&1; then
    alias lt='tree -a -C'
  fi
  alias l.='ls -d .[^.]* ..?* --color=auto 2>/dev/null || true'
fi

# 3) Grep / ripgrep / bat (non-destructive, tasteful defaults)
alias grep='grep --color=auto'
if command -v rg >/dev/null 2>&1; then
  alias rgi='rg -i --hidden --follow --no-ignore-vcs' # case-insensitive, shows hidden, respects repo
  alias rgf='rg --fixed-strings --hidden --follow --no-ignore-vcs'
fi
if command -v bat >/dev/null 2>&1; then
  alias batp='bat --paging=always' # page output
  alias batn='bat --style=plain'   # no decorations
fi

# 4) Filesystem, size & disk usage
alias df='df -h'
alias du='du -h'
alias duf='du -sh * | sort -h' # summarize sizes in cwd
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# 5) Safe extract helper (x) — only if not already defined by ~/.bashrc
type x >/dev/null 2>&1 || x() {
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

# 6) Arch package helpers (safe defaults)
alias pacs='pacman -Ss'       # search repos
alias pacq='pacman -Qs'       # search installed
alias paci='sudo pacman -S'   # install
alias pacr='sudo pacman -Rns' # remove (w/ deps)
alias pacl='pacman -Ql'       # list package files
alias paco='pacman -Qtdq'     # list orphans
alias pacf='pacman -F'        # find package owning a file (requires files db)

# Full system update (prefers yay if available)
if command -v yay >/dev/null 2>&1; then
  alias yays='yay -Ss'
  alias yayi='yay -S'
  alias yayr='yay -Rns'
  up() { yay -Syu --combinedupgrade --removemake --cleanafter --answerdiff None --answerclean All --useask; }
else
  up() { sudo pacman -Syu; }
fi

# 7) Git: compact, readable graph & quality-of-life aliases
alias gs='git status -sb'
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gco='git checkout'
alias gsw='git switch'
alias gcb='git checkout -b'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gl='git log --oneline --decorate'
alias gll="git log --graph --pretty=format:'%C(bold)%h%C(reset) %C(white)%s%C(reset) %C(dim white)- %cr%C(reset) %C(dim white)%an%C(reset)%C(auto)%d%C(reset)' --abbrev-commit"
alias gd='git diff'
alias gds='git diff --staged'
gclean() {
  git remote prune origin
  git branch --merged | grep -vE '^\*|main|master|develop' | xargs -r git branch -d
}

# 8) Systemd & journal (quick)
alias sc='sudo systemctl'
alias scu='systemctl --user'
alias jctl='journalctl -p 3 -xb' # errors from last boot

# 9) Networking & IP helpers (safe, no changes)
alias pingg='ping -c 5 1.1.1.1'
myip() { curl -fsS https://ifconfig.me || curl -fsS https://ipinfo.io/ip; }

# 10) Optional: trash instead of rm if trash-cli exists (does not override rm)
if command -v trash-put >/dev/null 2>&1; then
  alias del='trash-put' # safe delete to trash
  alias undel='trash-restore'
fi

# 11) Docker/Podman shortcuts (only if available)
if command -v docker >/dev/null 2>&1; then
  alias d='docker'
  alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
  alias di='docker images'
  alias dd='docker system df'
fi
if command -v podman >/dev/null 2>&1; then
  alias p='podman'
  alias pps='podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
  alias pi='podman images'
  alias pd='podman system df'
fi
