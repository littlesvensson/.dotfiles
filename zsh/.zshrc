# https://xebia.com/blog/profiling-zsh-shell-scripts/
# zmodload zsh/zprof

# If not running interactively, don't do anything.
case $- in
    *i*) ;;
    *) return;;
esac

# Simple OS detection in Bash using $OSTYPE.
OS="UNKNOWN"
case "$OSTYPE" in
    darwin*)
	    OS="OSX"
        ;;
    linux*)
        OS="LINUX"
        ;;
    dragonfly*|freebsd*|netbsd*|openbsd*)
        OS="BSD"
        ;;
    *)
        OS="UNKNOWN"
        ;;
esac

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1) man page.
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
# history saving options
setopt histignorespace # Ignore commands that start with space.
setopt histignorealldups # Never add duplicate entries.
setopt histreduceblanks # Remove unnecessary blank lines.
setopt incappendhistory # Immediately append to the history file.

# Append to the history file, don't overwrite it.
setopt appendhistory

# Prompt expansion
setopt promptsubst

# Globbing characters
unsetopt nomatch

# Command-line completion
# Create global directory
[ -d ~/.zsh_completions ] || mkdir ~/.zsh_completions
# - curl -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/zsh/_docker-compose -o ~/.zsh_completions/_docker-compose
# - curl -L https://git.kernel.org/pub/scm/git/git.git/plain/contrib/completion/git-completion.zsh -o ~/.zsh_completions/_git
fpath=(~/.zsh_completions $fpath)

# Enable autocompletion.
#setopt completealiases
autoload -Uz compinit && compinit
_comp_options+=(globdots)

zstyle ':completion:*' menu select
# small letters will match small and capital letters
#zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
# capital letters also match small letters
#zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
# case-insensitive matching only if there are no case-sensitive matches
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'

# Map Ctrl+r to search in history
bindkey "^R" history-incremental-search-backward
# Cycle through history based on characters already typed on the line
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
# Set vi/vim binding
#bindkey -v
# setup key accordingly
bindkey "^[[H" beginning-of-line # Home
bindkey "^[[F" end-of-line # End
bindkey "^[[2~" overwrite-mode # Insert
bindkey "^[[3~" delete-char # Del
bindkey "^[[A" up-line-or-beginning-search # Up
bindkey "^[[B" down-line-or-beginning-search # Down
bindkey "^[[C" forward-char # Left
bindkey "^[[D" backward-char # Right

# Switching directories for lazy people
setopt autocd
# See: http://zsh.sourceforge.net/Intro/intro_6.html
setopt autopushd pushdminus pushdsilent pushdtohome pushdignoredups

# Disable paste highlighting.
zle_highlight+=(paste:none)

# Project DIR
CDPATH=.:~:~/projects

# Default editor.
export EDITOR=vim
export K9S_EDITOR=vim

# Add local ~/bin and ~/.local/bin to PAT
#export PATH=~/bin:~/.local/bin:$PATH

# Only apply for MacOS system.
if [ "$OS" = "OSX" ]; then
    export CLICOLOR=1
    export LSCOLORS="GxFxCxDxBxegedabagaced"
    export PATH=$(/opt/homebrew/bin/brew --prefix)/bin:$PATH
    # Let brew know that we are running on full 64-bit system.
    export ARCHFLAGS="-arch x86_64"
    zstyle ':completion:*' list-colors $LSCOLORS
elif [ "$OS" = "LINUX" ]; then
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

# Helper function to set Git branch in shell prompt.
parse_git_branch() {
    # Uncoment this line if your system is not UTF-8 ready.
    # git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ git:\1/'
    # Uncomment this on UTF-8 compatible system.
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ ⎇  \1/'
}

# Helper function to set kubernetes context in shell prompt.
parse_k8s_context() {
  if [ -z $KUBECONFIG ]; then
    return
  fi

  local context namespace
  context=$(yq e '.current-context // ""' "$KUBECONFIG")
  namespace=$(yq e "(.contexts[] | select(.name == \"$context\").context.namespace) // \"\"" "$KUBECONFIG")

  if [[ -n $context ]] && [[ -n $namespace ]]; then
    echo -n " (k8s:$context/$namespace)"
  # elif [[ -n $context ]] ; then
  #   echo -n " (k8s:$context)"
  fi
}

# Load colors
autoload -U colors && colors

# Set shell prompt.
if [ $commands[starship] ]; then
    eval "$(starship init zsh)"
else
    # Prompt with Git branch if available.
    local git_branch='%{$fg_bold[blue]%}$(parse_git_branch)'
    local k8s_context='%{$fg_bold[magenta]%}$(parse_k8s_context)'
    # PS1="%{$fg_bold[green]%}%m %{$fg_bold[yellow]%}%(3~|.../%2~|%~)${git_branch} %{$fg_bold[yellow]%}% \$ %{$reset_color%}%{$fg[white]%}"
    PS1="%{$fg_bold[green]%}%m %{$fg_bold[yellow]%}%(3~|.../%2~|%~)${git_branch}${k8s_context} %{$fg_bold[yellow]%}% \$ %{$reset_color%}%{$fg[white]%}"
fi

# Some nice aliases to have
alias diff='colordiff'
alias git-cloc='git ls-files | xargs cloc'
alias sup='sudo su -'
alias ls='ls --color'
alias ll='ls -lA'
#alias ls='exa'
#alias ll='exa -alh'
#alias tree='exa --tree'
alias k='kubectl'
alias g='git'
# dh print history of visited directories. Use cd -number to go to selected folder.
alias dh='dirs -v'
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Source another Aliases from external file (if exists).
if [ -f ~/.aliases ]; then
    . ~/.aliases
fi

# GO LANG
export GOPATH=$HOME/go
if [ "$OS" = "LINUX" ]; then
    export GOROOT=$HOME/bin/go
elif [ "$OS" = "OSX" ]; then
    export GOROOT=$(brew --prefix)/opt/go/libexec/go
fi
#export PATH=$GOROOT/bin:$PATH

# PYTHON
# Temporarily turn off restriction for pip
gpip(){
    PIP_REQUIRE_VIRTUALENV="" pip "$@"
}

gpip3(){
    PIP_REQUIRE_VIRTUALENV="" pip3 "$@"
}

# Kubernetes
# Check if 'kubectl' is a command in $PATH
if [ $commands[kubectl] ]; then
    [ -s ~/.zsh_completions/_kubectl ] || kubectl completion zsh > ~/.zsh_completions/_kubectl
  # Placeholder 'kubectl' shell function:
  # Will only be executed on the first call to 'kubectl'
  # kubectl() {
    # Remove this function, subsequent calls will execute 'kubectl' directly
  #  unfunction "$0"
    # Load auto-completion
  #  source <(kubectl completion zsh)
    # Execute 'kubectl' binary
  #  $0 "$@"
  #}
fi

# k8s-kx
 kx() {
    eval $(k8s-kx)
}


kexec() {
    kubectl exec -it "$1" -- sh
}

# NPM
NPM_PACKAGES="${HOME}/.npm-packages"
export PATH="$PATH:$NPM_PACKAGES/bin"
# Preserve MANPATH if you already defined it somewhere in your config.
# Otherwise, fall back to `manpath` so we can inherit from `/etc/manpath`.
export MANPATH="${MANPATH-$(manpath)}:$NPM_PACKAGES/share/man"
# Tell npm where to store globally installed packages
# $ npm config set prefix "${HOME}/.npm-packages"

# Check if 'npm' is a command in $PATH
if [ $commands[npm] ]; then
    [ -s ~/.zsh_completions/_npm ] || npm completion > ~/.zsh_completions/_npm
  # Placeholder 'npm' shell function:
  # Will only be executed on the first call to 'npm'
  # npm() {
    # Remove this function, subsequent calls will execute 'kubectl' directly
  #  unfunction "$0"
    # Load auto-completion
  #  source <(npm completion)
    # Execute 'npm' binary
  #  $0 "$@"
  #}
fi

# Uncomment this line if your terminal doesn't propagate 256 colors support.
#TERM=xterm-256color
# zprof

unset KUBECONFIG

# Select from multiple k8s clusters configurations.
function kc {
    local k8s_config
    k8s_config=$(find "$HOME"/.kube/custom-contexts/ -type f \( -iname '*.yaml' -o -iname '*.yml' -o -iname '*.conf' \) | peco)
    export KUBECONFIG="$k8s_config"
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
