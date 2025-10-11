# ---- ~/.bashrc (clean & robust) ----

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Guard: if current directory is gone, jump home (fixes getcwd errors)
if ! builtin pwd >/dev/null 2>&1; then
  cd "$HOME" 2>/dev/null || cd /
  export PWD="$(pwd -P)"
fi

# Prompt and aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
