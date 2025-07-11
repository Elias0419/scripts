
export PROMPT='%F{red}%n@%F{cyan}%/%f %F{green}~ %f'
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=10000
setopt SHARE_HISTORY

export PATH=$PATH:/opt:/usr/go/bin:/usr/local/bin:/usr/bin/maven/bin:/opt/python3.12/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib64
export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export MAKEFLAGS='-j13'
export CMAKE_PREFIX_PATH="/opt/qt6:$CMAKE_PREFIX_PATH"
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
alias bat="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep percentage"
alias nano="micro"
alias py="python3"
alias mvn="/usr/bin/maven/bin/mvn"
alias rcache="sh -c 'echo 3 > /proc/sys/vm/drop_caches'"
alias clip="xclip -sel clip"
alias ls='ls --color=auto'
alias grep='grep --color=auto'

gtar() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: gtar <URL-to-.tar[.gz|.xz|.bz2|.Z|.tgz]>" >&2
    return 1
  fi
  cd /build/4_applications
  local url=$1
  local file=${url##*/}  
  local dir

 
  case $file in
    *.tar.gz|*.tgz) dir=${file%%.tar.*} ;;
    *.tar.bz2)       dir=${file%%.tar.bz2} ;;
    *.tar.xz)        dir=${file%%.tar.xz} ;;
    *.tar.Z)         dir=${file%%.tar.Z} ;;
    *.tar)           dir=${file%%.tar} ;;
    *)
      echo "gtar: unrecognized archive suffix in '$file'" >&2
      return 1
      ;;
  esac

 
  wget --show-progress "$url"            || return $?
  tar xf "$file"                        || return $?
  cd "$dir"                             || {
    echo "gtar: failed to cd into '$dir'" >&2
    return 1
  }
}
toggle() {
    local target
    local current
    local cpu_path

    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        current=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    fi

    if [[ "$current" == "performance" ]]; then
        target="powersave"
    else
        target="performance"
    fi

    echo "Switching all CPUs to $target..."

    for cpu_path in /sys/devices/system/cpu/cpu[0-9]*; do
        if [[ -w "$cpu_path/cpufreq/scaling_governor" ]]; then
            echo "$target" > "$cpu_path/cpufreq/scaling_governor"
        fi
    done

    echo "Done."
}


normalize_version() {
    version="$1"
    numeric=$(echo "$version" | cut -d'-' -f1)
    suffix=$(echo "$version" | cut -s -d'-' -f2-)
    numeric=$(echo "$numeric" | sed -E 's/(\.0)+$//')
    if [ -n "$suffix" ]; then
        echo "$numeric-$suffix"
    else
        echo "$numeric"
    fi
}

check_kernel_version() {
    running_version=$(uname -r | sed 's/-[^-]*$//')
    releases_json=$(curl -s https://kernel.org/releases.json) || { echo "Failed to fetch releases.json from kernel.org"; return 1; }
    mainline_release=$(echo "$releases_json" | jq -r '[.releases[] | select(.moniker=="mainline")] | sort_by(.released.timestamp) | last')
    mainline_version=$(echo "$mainline_release" | jq -r '.version')
    norm_running=$(normalize_version "$running_version")
    norm_mainline=$(normalize_version "$mainline_version")
    echo "Running kernel: $running_version (debug: $norm_running)"
    echo "Latest mainline: $mainline_version (debug: $norm_mainline)"
    if [[ "$norm_running" != "$norm_mainline" ]]; then
                echo -n "Get the new kernel? (y/N): "
        read response
        case "$response" in
        [yY][eE][sS]|[yY])
            get_kernel "$mainline_version" "$releases_json"
            ;;
        *)
            echo "Bye"
            ;;
                 esac
        
    fi
}

get_kernel() {
    target_version="$1"
    releases_json="$2"
    archive_url=$(echo "$releases_json" | jq -r ".releases[] | select(.moniker==\"mainline\" and .version==\"$target_version\") | .source")
    archive_file=$(basename "$archive_url")
    echo "Getting the new kernel..."
    echo "Downloading: $archive_url"
    curl -LO "$archive_url" || { echo "Download failed"; return 1; }
    tar -xf "$archive_file" -C /usr/src || { echo "Extraction failed"; return 1; }

    if [[ "$archive_file" == *.tar.gz ]]; then
        kernel_dir="${archive_file%.tar.gz}"
    elif [[ "$archive_file" == *.tar.xz ]]; then
        kernel_dir="${archive_file%.tar.xz}"
    else
        kernel_dir="${archive_file%.*}"
    fi

    ln -sfn "/usr/src/$kernel_dir" /usr/src/linux || { echo "Symlink failed"; return 1; }
    kernel_update
}

kernel_update() {
    cd /usr/src/linux
    mount /dev/nvme0n1p1 /boot
    cp /usr/src/kernel_conf_p14s .config
    make oldconfig
    cp .config  /usr/src/kernel_conf_p14s
    make -j13
    mv /boot/bzImage.efi /boot/bzImage.efi.old
    cp /usr/src/linux/arch/x86/boot/bzImage /boot/bzImage.efi
    echo -n "Kernel update complete. Reboot now? (y/N): "
    read response
    case "$response" in
        [yY][eE][sS]|[yY])
            reboot
            ;;
        *)
            echo "Bye"
            ;;
    esac
}



cont() {
  local pid state user comm
  local stopped_pids=()
  local stopped_names=()

  while read -r pid state user comm; do
    if [[ $state == T ]]; then
      stopped_pids+=("$pid")
      stopped_names+=("$comm")
    fi
  done < <(ps -eo pid=,state=,user=,comm=)

  if (( ${#stopped_pids[@]} == 0 )); then
    echo "▶ No stopped processes"
    return 0
  fi

  echo "Stopped PIDs: ${stopped_pids[@]}"

  for (( i = 1; i <= ${#stopped_pids[@]}; i++ )); do
    pid=${stopped_pids[i]}
    name=${stopped_names[i]}

    if kill -CONT "$pid" 2>/dev/null; then
      echo "▶ Continued process $pid ($name)"
    else
      msg=$(kill -CONT "$pid" 2>&1)
      echo "✖ Failed to continue $pid ($name): $msg"
    fi
  done
}

update_firefox(){
    installed=$(/opt/firefox/firefox --version | awk '{print $3}')
    latest=$(curl -s https://product-details.mozilla.org/1.0/firefox_versions.json | grep '"LATEST_FIREFOX_VERSION"' | cut -d '"' -f4)
	if [[ "$installed" == "$latest" ]]; then
		echo "Installed:"
		echo $installed
		echo "Latest:"
		echo $latest
		echo "Already up to date"
	else
		echo -n "Version" $latest "is available. Update now?  (y/N): "
		read response
		case "$response" in
		    [yY][eE][sS]|[yY])
		        _run_update
		        ;;
		    *)
		        echo "Bye"
		        ;;
		esac
	
	fi

}

_run_update(){
	echo "Updating..."
	mkdir /tmp/upd_ff
	cd /tmp/upd_ff
	wget -O ff.tar.xz "https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US" 
	tar -xf ff.tar.xz -C /opt/
	cd -
	rm -rf /tmp/upd_ff
	echo "Done"	
}
cremount () {
    local dev=${1:-0000:04:00.0}
    local drv=/sys/bus/pci/drivers/rtsx_pci

    [[ -w $drv/unbind && -w $drv/bind ]] || {
        print -u2 "rtsx_pci driver sysfs nodes not found"; return 1
    }

    print -n "$dev" > $drv/unbind
    until [[ ! -e /sys/bus/pci/devices/$dev/driver ]]; do
        sleep 0.05
    done

    print -n "$dev" > $drv/bind
}


source /home/x/work/0/bin/activate
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 

