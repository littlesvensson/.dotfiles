# https://xebia.com/blog/profiling-zsh-shell-scripts/
# zmodload zsh/zprof


# script for appfw

#compdef appfwctl
compdef _appfwctl appfwctl

# zsh completion for appfwctl                             -*- shell-script -*-

__appfwctl_debug()
{
    local file="$BASH_COMP_DEBUG_FILE"
    if [[ -n ${file} ]]; then
        echo "$*" >> "${file}"
    fi
}

_appfwctl()
{
    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16
    local shellCompDirectiveKeepOrder=32

    local lastParam lastChar flagPrefix requestComp out directive comp lastComp noSpace keepOrder
    local -a completions

    __appfwctl_debug "\n========= starting completion logic =========="
    __appfwctl_debug "CURRENT: ${CURRENT}, words[*]: ${words[*]}"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $CURRENT location, so we need
    # to truncate the command-line ($words) up to the $CURRENT location.
    # (We cannot use $CURSOR as its value does not work when a command is an alias.)
    words=("${=words[1,CURRENT]}")
    __appfwctl_debug "Truncated words[*]: ${words[*]},"

    lastParam=${words[-1]}
    lastChar=${lastParam[-1]}
    __appfwctl_debug "lastParam: ${lastParam}, lastChar: ${lastChar}"

    # For zsh, when completing a flag with an = (e.g., appfwctl -n=<TAB>)
    # completions must be prefixed with the flag
    setopt local_options BASH_REMATCH
    if [[ "${lastParam}" =~ '-.*=' ]]; then
        # We are dealing with a flag with an =
        flagPrefix="-P ${BASH_REMATCH}"
    fi

    # Prepare the command to obtain completions
    requestComp="${words[1]} __complete ${words[2,-1]}"
    if [ "${lastChar}" = "" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go completion code.
        __appfwctl_debug "Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __appfwctl_debug "About to call: eval ${requestComp}"

    # Use eval to handle any environment variables and such
    out=$(eval ${requestComp} 2>/dev/null)
    __appfwctl_debug "completion output: ${out}"

    # Extract the directive integer following a : from the last line
    local lastLine
    while IFS='\n' read -r line; do
        lastLine=${line}
    done < <(printf "%s\n" "${out[@]}")
    __appfwctl_debug "last line: ${lastLine}"

    if [ "${lastLine[1]}" = : ]; then
        directive=${lastLine[2,-1]}
        # Remove the directive including the : and the newline
        local suffix
        (( suffix=${#lastLine}+2))
        out=${out[1,-$suffix]}
    else
        # There is no directive specified.  Leave $out as is.
        __appfwctl_debug "No directive found.  Setting do default"
        directive=0
    fi

    __appfwctl_debug "directive: ${directive}"
    __appfwctl_debug "completions: ${out}"
    __appfwctl_debug "flagPrefix: ${flagPrefix}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        __appfwctl_debug "Completion received error. Ignoring completions."
        return
    fi

    local activeHelpMarker="_activeHelp_ "
    local endIndex=${#activeHelpMarker}
    local startIndex=$((${#activeHelpMarker}+1))
    local hasActiveHelp=0
    while IFS='\n' read -r comp; do
        # Check if this is an activeHelp statement (i.e., prefixed with $activeHelpMarker)
        if [ "${comp[1,$endIndex]}" = "$activeHelpMarker" ];then
            __appfwctl_debug "ActiveHelp found: $comp"
            comp="${comp[$startIndex,-1]}"
            if [ -n "$comp" ]; then
                compadd -x "${comp}"
                __appfwctl_debug "ActiveHelp will need delimiter"
                hasActiveHelp=1
            fi

            continue
        fi

        if [ -n "$comp" ]; then
            # If requested, completions are returned with a description.
            # The description is preceded by a TAB character.
            # For zsh's _describe, we need to use a : instead of a TAB.
            # We first need to escape any : as part of the completion itself.
            comp=${comp//:/\\:}

            local tab="$(printf '\t')"
            comp=${comp//$tab/:}

            __appfwctl_debug "Adding completion: ${comp}"
            completions+=${comp}
            lastComp=$comp
        fi
    done < <(printf "%s\n" "${out[@]}")

    # Add a delimiter after the activeHelp statements, but only if:
    # - there are completions following the activeHelp statements, or
    # - file completion will be performed (so there will be choices after the activeHelp)
    if [ $hasActiveHelp -eq 1 ]; then
        if [ ${#completions} -ne 0 ] || [ $((directive & shellCompDirectiveNoFileComp)) -eq 0 ]; then
            __appfwctl_debug "Adding activeHelp delimiter"
            compadd -x "--"
            hasActiveHelp=0
        fi
    fi

    if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
        __appfwctl_debug "Activating nospace."
        noSpace="-S ''"
    fi

    if [ $((directive & shellCompDirectiveKeepOrder)) -ne 0 ]; then
        __appfwctl_debug "Activating keep order."
        keepOrder="-V"
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local filteringCmd
        filteringCmd='_files'
        for filter in ${completions[@]}; do
            if [ ${filter[1]} != '*' ]; then
                # zsh requires a glob pattern to do file filtering
                filter="\*.$filter"
            fi
            filteringCmd+=" -g $filter"
        done
        filteringCmd+=" ${flagPrefix}"

        __appfwctl_debug "File filtering command: $filteringCmd"
        _arguments '*:filename:'"$filteringCmd"
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        subdir="${completions[1]}"
        if [ -n "$subdir" ]; then
            __appfwctl_debug "Listing directories in $subdir"
            pushd "${subdir}" >/dev/null 2>&1
        else
            __appfwctl_debug "Listing directories in ."
        fi

        local result
        _arguments '*:dirname:_files -/'" ${flagPrefix}"
        result=$?
        if [ -n "$subdir" ]; then
            popd >/dev/null 2>&1
        fi
        return $result
    else
        __appfwctl_debug "Calling _describe"
        if eval _describe $keepOrder "completions" completions $flagPrefix $noSpace; then
            __appfwctl_debug "_describe found some completions"

            # Return the success of having called _describe
            return 0
        else
            __appfwctl_debug "_describe did not find completions."
            __appfwctl_debug "Checking if we should do file completion."
            if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
                __appfwctl_debug "deactivating file completion"

                # We must return an error code here to let zsh know that there were no
                # completions found by _describe; this is what will trigger other
                # matching algorithms to attempt to find completions.
                # For example zsh can match letters in the middle of words.
                return 1
            else
                # Perform file completion
                __appfwctl_debug "Activating file completion"

                # We must return the result of this command, so it must be the
                # last command, or else we must store its result to return it.
                _arguments '*:filename:_files'" ${flagPrefix}"
            fi
        fi
    fi
}

# don't run the completion function when being source-ed or eval-ed
if [ "$funcstack[1]" = "_appfwctl" ]; then
    _appfwctl
fi


# end of appfw script













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
    #export PATH=$(/opt/homebrew/bin/brew --prefix)/bin:$PATH
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
export PATH=$PATH:/Users/janavonsak/go/bin
export GOBIN=$GOPATH/bin
export GOROOT=/opt/homebrew/opt/go/libexec

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

unset KUBECONFIG

# Select from multiple k8s clusters configurations.
function kc {
    local k8s_config
    k8s_config=$(find "$HOME"/.kube/custom-contexts/ -type f \( -iname '*.yaml' -o -iname '*.yml' -o -iname '*.conf' \) | peco)
    export KUBECONFIG="$k8s_config"
}

# Script for work with nvm (nvm ls, nvm ls-remote, nvm use, nvm install <version>, nvm alias default <version>)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/janavonsak/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/janavonsak/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/janavonsak/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/janavonsak/google-cloud-sdk/completion.zsh.inc'; fi
alias python=/usr/bin/python3


