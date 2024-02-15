#!/bin/sh
# This script is intended to be run on freshly installed fedora.
# It is my personal list of programs that I use and want to install as easily as possible.


if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  echo "Type \"su\" provide admin password and rerun."
  echo "If you haven't established root password yet, type \"sudo passwd root\" and provide password to be used for \"su\""
  exit 1
fi

dnf install vim -y

dnf install htop -y

# adobe flash player (for FB, YT,...)
rpm -ivh http://linuxdownload.adobe.com/adobe-release/adobe-release-x86_64-1.0-1.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-adobe-linux
dnf install flash-plugin -y

# video codec
dnf install ffmpeg-libs -y

# Java
# Fedora should include support for Java via OpenJDK
dnf install java icedtea-web -y

# audio
dnf install xmms xmms-mp3 xmms-faad2 xmms-flac xmms-pulse xmms-skins -y

# audio codecs gst-plugins-ugly
dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm -y
dnf install gstreamer1-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} --setopt=strict=0 -y

# video player
dnf install vlc -y

# guake
dnf install guake -y
# guake autostart
cp /usr/share/applications/guake.desktop /etc/xdg/autostart/
# manual settings: color=#1ec503
# Palette: right-most, top field

# Arduino IDE + fix
ARD_VERSION="1.8.19"
wget https://downloads.arduino.cc/arduino-${ARD_VERSION}-linux64.tar.xz -P ~
tar xvf ~/arduino-${ARD_VERSION}-linux64.tar.xz
rm arduino-${ARD_VERSION}-linux64.tar.xz
~/arduino-${ARD_VERSION}/install.sh
rm -rf java # fix "no menu"
            # see the issue:
            # https://github.com/arduino/Arduino/issues/11150
# Another fix may be needed
#dnf install java-latest-openjdk # fix
#printf "##########################################################"
#printf "Pick the line that says \"java-latest\""
#printf "##########################################################"
#alternatives --config java


# Sublime text 3
echo "Sublime Text editor works without buying license, but your company might get in trouble"
INSTALL=0
while true; do
    read -p "Do you wish to install this program? [y/n] " yn
    case $yn in
        [Yy]* ) echo "installing"; INSTALL=1; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [[ $INSTALL == 1 ]]; then
  rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
  dnf config-manager --add-repo https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo
  dnf install sublime-text
  #Update
  #dnf and install Sublime Text

  # Sublime addon: Package controll
  echo "Manual install of Sublime-text package controll:"
  echo "https://packagecontrol.io/installation"
  # Sublime addon: SFTP
  echo "Manual install of Sublime-text SFTP:"
  echo "https://wbond.net/sublime_packages/sftp/installation"
fi

# M$ stuff
dnf install unar -y # for .RAR archives
dnf install abiword -y # for .RTF text files
# Teams
wget https://packages.microsoft.com/yumrepos/ms-teams/teams-1.2.00.32451-1.x86_64.rpm
dnf localinstall teams-1.2.00.32451-1.x86_64.rpm -y

# prevent new windows stealing focus
# only for gnome
gconftool-2 --set /apps/metacity/general/focus_new_windows --type string strict
# read more here:
# http://bertrandbenoit.blogspot.com/2011/09/change-window-behavior-to-prevent-focus.html
#
# Manual GMONE plugins
# https://extensions.gnome.org/extension/1414/unblank/
# https://extensions.gnome.org/extension/3933/toggle-night-light/

# Bitcoin Markets tray addon / widget
git clone https://github.com/OttoAllmendinger/gnome-shell-bitcoin-markets.git
cd gnome-shell-bitcoin-markets
make install
cd -

# cmd-line app for YouTube (YT) download and conversion
dnf install youtube-dl -y
# Example: download video
#youtube-dl https://www.youtube.com/watch?v=k0kg80jAtI8
# Example: download and convert to MP3
#youtube-dl -x --audio-format mp3 https://www.youtube.com/watch?v=kRb41Joq-94&list=PL_MHjKxnHz1sm0YARyIdgev09N9A-3FEP


#############################
# git setup

# more readable log and also make alias log -> l
# usage:
# git l
git config --global alias.l "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
# more aliases
git config --global alias.s status
git config --global alias.a add
git config --global alias.c commit
git config --global alias.ch checkout
#git config --global alias.d diff         # uses standard diff
git config --global diff.tool vimdiff     # setup vimdiff for git diff tool
git config --global merge.tool vimdiff    # setup vimdiff for git merge tool
git config --global difftool.prompt false # stop asking every time if I really want to use vimdiff - fuck yeah I do!
git config --global alias.d difftool      # shortcut: git diff > git d
git config --global alias.r restore
# TODO alias with parameter (not from user) example git c == git commit -m

# stop asking git for username and Password
# prerequisite - generate SSH key on computer and load it in web account
# https://docs.github.com/en/github/using-git/changing-a-remotes-url
# Change the current working directory to your local project.
# git remote -v
# git remote set-url origin git@github.com:USERNAME/REPOSITORY.git
# git remote -v


# vim shortcuts:
#1st. Put this to your ~/.bashrc
printf "bind -r '\C-s'\nstty -ixon" >> ~/.bashrc

# 2nd. Place this to your ~/.vimrc
printf "inoremap <C-s> <esc>:w<cr>                 \" save files\nnnoremap <C-s> :w<cr>\ninoremap <C-d> <esc>:wq\!<cr>               \" save and exit\nnnoremap <C-d> :wq\!<cr>\ninoremap <C-q> <esc>:qa\!<cr>               \" quit discarding changes\nnnoremap <C-q> :qa\!<cr>" >> ~/.vimrc

# vim line numbers
echo ":set number" >> ~/.vimrc

# install tray icons as extension of gnome
dnf install gnome-shell-extension-topicons-plus.noarch -y
echo "Manualy install TopIcons Plus from page:"
echo "https://extensions.gnome.org/extension/1031/topicons/"
echo ""
echo "Manually install Gnome extensions for vertical workspaces"
echo "https://extensions.gnome.org/extension/4144/vertical-overview/"

# Add cdl function - shortcut for cd;ll
echo "" >> ~/.bashrc
echo "# Calling \"cdl <folder_name>\" is equal to \"cd <folder_name>; ll\"" >> ~/.bashrc
echo "function cdl() {" >> ~/.bashrc
echo "#  echo \"cd \\\"\$1\\\"; ll\"" >> ~/.bashrc
echo "  cd \"\$1\"" >> ~/.bashrc
echo "  ll" >> ~/.bashrc
echo "}" >> ~/.bashrc

source ~/.bashrc

#### Manualy put to .bashrc
# subl ~/.bashrc

# # Set up aliases
# alias flash="my_flash"
# alias fl="flash"
# alias f="flash"

# alias terminal="my_terminal"
# alias term="terminal"
# alias t="terminal"
# alias serial="terminal"
# alias ser="terminal"
# alias s="terminal"

# alias flt="my_flt"
# alias ft="flt"

# #alias all="make && flash && terminal"
# alias all="make -j EXTRAFLAGS+=\"-DESP32_IGNORE_CHIP_REVISION_CHECK\" && flash && terminal"
source ~/.bashrc
