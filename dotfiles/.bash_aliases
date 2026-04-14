# Editor
alias v='nvim'
alias e='nvim'

# Visa med radnummer
alias catn='nl -ba'

# ls / eza
if command -v eza >/dev/null 2>&1; then
  alias ls='eza -alh --group-directories-first --icons=auto --git'
  alias ll='eza -alh --group-directories-first --icons=auto --git --time-style=long-iso'
  alias l1='eza -a1 --icons=auto'
  alias lS='eza -alh --group-directories-first --icons=auto --git --sort=size'
  alias lt='eza -alh --tree --group-directories-first --icons=auto'
  alias l.='eza -d .* --icons=auto'
else
  alias ls='ls -Alh --color=auto --group-directories-first'
  alias ll='ls -Alh --color=auto --group-directories-first'
  alias l1='ls -A1 --color=auto'
  alias lS='ls -Alh --color=auto --group-directories-first -S'
  alias l.='ls -d .[^.]* ..?* --color=auto 2>/dev/null || true'
fi

# Sök / visning
alias grep='grep --color=auto'
command -v rg >/dev/null 2>&1 && alias rgi='rg -i --hidden --follow --no-ignore-vcs'
command -v rg >/dev/null 2>&1 && alias rgf='rg --fixed-strings --hidden --follow --no-ignore-vcs'
command -v bat >/dev/null 2>&1 && alias batp='bat --paging=always'
command -v bat >/dev/null 2>&1 && alias batn='bat --style=plain'

# Filsystem / navigation
alias df='df -h'
alias du='du -h'
alias duf='du -sh * 2>/dev/null | sort -h'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Ladda om bash-konfig
alias reloadbash='source ~/.bashrc'

# Extrahera arkiv
type x >/dev/null 2>&1 || x() {
  local f="$1"
  [[ -r "$f" ]] || { echo "No such file: $f" >&2; return 1; }
  case "$f" in
    *.tar.bz2) tar xjf "$f" ;;
    *.tar.gz)  tar xzf "$f" ;;
    *.tar.xz)  tar xJf "$f" ;;
    *.tar.zst) tar --zstd -xf "$f" ;;
    *.bz2)     bunzip2 "$f" ;;
    *.rar)     unrar x "$f" ;;
    *.gz)      gunzip "$f" ;;
    *.tar)     tar xf "$f" ;;
    *.tbz2)    tar xjf "$f" ;;
    *.tgz)     tar xzf "$f" ;;
    *.zip)     unzip "$f" ;;
    *.7z)      7z x "$f" ;;
    *.xz)      unxz "$f" ;;
    *) echo "Don't know how to extract '$f'." >&2; return 2 ;;
  esac
}

# Arch / pacman / paru
alias pacs='pacman -Ss'
alias pacq='pacman -Qs'
alias paci='sudo pacman -S'
alias pacr='sudo pacman -Rns'
alias pacl='pacman -Ql'
alias paco='pacman -Qtdq'
alias pacf='pacman -F'

alias paras='paru -Ss'
alias parai='paru -S'
alias parar='paru -Rns'

update() {
  paru -Syu --skipreview
}

orphans() {
  pacman -Qtdq
}

removeorphans() {
  local pkgs
  pkgs=$(pacman -Qtdq)
  [[ -n "$pkgs" ]] && sudo pacman -Rns $pkgs || echo "Inga orphan-paket hittades."
}

cleanup() {
  echo "Rensar oanvänd cache..."
  paru -Sc
  echo
  echo "Kontrollerar orphan-paket..."
  local pkgs
  pkgs=$(pacman -Qtdq)
  [[ -n "$pkgs" ]] && sudo pacman -Rns $pkgs || echo "Inga orphan-paket hittades."
}

# Git
alias gs='git status -sb'
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -m'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gl='git log --oneline --decorate --graph'
alias gd='git diff'
alias gds='git diff --staged'

gclean() {
  git remote prune origin
  git branch --merged | grep -vE '^\*|main|master|develop' | xargs -r git branch -d
}

# Systemd / loggar
alias sc='sudo systemctl'
alias scu='systemctl --user'
alias jctl='journalctl -p 3 -xb'
alias jctlf='journalctl -f'

# Nätverk
alias pingg='ping -c 5 1.1.1.1'
myip() {
  curl -fsS https://ifconfig.me || curl -fsS https://ipinfo.io/ip
}

# Papperskorg istället för hård radering, om trash-cli finns
if command -v trash-put >/dev/null 2>&1; then
  alias del='trash-put'
  alias undel='trash-restore'
fi
