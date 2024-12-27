# .bashrc

# Load central setup.

if [ -f /eecs/local/share/bashrc.common ]; then
  . /eecs/local/share/bashrc.common
fi

# For tmux being used in conjuction with Neovim
# Path Variables
export TERM='xterm-256color'
export EDITOR='nvim'
export VISUAL='nvim'

# set bash to vim mode
set -o vi

# The default umask creates files which are not readable by group or others.
# Uncomment the following to make created files readable by group or others.
#umask 022


set $PATH:/eecs/local/pkg/gcc-12.3.0/bin

# My terminal anchor
PS1='\u@\h: \w\$ '

