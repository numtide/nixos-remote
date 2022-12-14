showUsage() {
  cat <<USAGE
Usage: nixos-remote [options] ssh-host

Options:

* -f, --flake flake
  set the flake to install the system from
* -s, --store-paths
  set the store paths to the disko-script and nixos-system directly
  if this is give, flake is not needed
* --no-ssh-copy
  skip copying ssh-keys to target system
* --no-reboot
  do not reboot after installation, allowing further customization of the target installation.
* --kexec url
  use another kexec tarball to bootstrap NixOS
* --stop-after-disko
  exit after disko formating, you can then proceed to install manually or some other way
* --extra-files files
  files to copy into the new nixos installation
* --disk-encryption-keys remote_path local_path
  copy the contents of the file or pipe in local_path to remote_path in the installer environment,
  after kexec but before installation. Can be repeated.
* --debug
  enable debug output
USAGE
}

abort() {
  echo "aborted: $*" >&2
  exit 1
}

kexec_url=https://github.com/nix-community/nixos-images/releases/download/nixos-22.11/nixos-kexec-installer-x86_64-linux.tar.gz
enable_debug=""
maybereboot="reboot"

declare -A disk_encryption_keys

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --flake)
      flake=$2
      shift
      ;;
    -s | --store-paths)
      disko_script=$(readlink -f "$2")
      nixos_system=$(readlink -f "$3")
      shift
      shift
      ;;
    --help)
      showUsage
      exit 0
      ;;
    --kexec)
      kexec_url=$2
      shift
      ;;
    --no-ssh-copy-id)
      no_ssh_copy=y
      ;;
    --debug)
      enable_debug="-x"
      set -x
      ;;
    --extra-files)
      extra_files=$2
      shift
      ;;
    --disk-encryption-keys)
      disk_encryption_keys["$2"]="$3"
      shift
      shift
      ;;
    --stop-after-disko)
      stop_after_disko=y
      ;;
    --no-reboot)
      maybereboot=""
      ;;
    *)
      if [[ -z ${ssh_connection:-} ]]; then
        ssh_connection="$1"
      else
        showUsage
        exit 1
      fi
      ;;
  esac
  shift
done


# ssh wrapper
timeout_ssh_() {
  timeout 10 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$ssh_connection" "$@"
}
ssh_() {
  ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$ssh_connection" "$@"
}
nixCopy() {
  NIX_SSHOPTS='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' nix copy --extra-experimental-features nix-command "$@"
}
nix_build() {
  nix \
    --experimental-features flakes build \
    --extra-experimental-features nix-command \
    --no-write-lock-file \
    --print-out-paths \
    "$@"
}

if [[ -z ${ssh_connection:-} ]]; then
  abort "ssh-host must be set"
fi

# parse flake nixos-install style syntax, get the system attr
if [[ -n "${flake:-}" ]]; then
  if [[ $flake =~ ^(.*)\#([^\#\"]*)$ ]]; then
   flake="${BASH_REMATCH[1]}"
   flakeAttr="${BASH_REMATCH[2]}"
  fi
  if [[ -z "${flakeAttr:-}" ]]; then
    echo "Please specify the name of the NixOS configuration to be installed, as a URI fragment in the flake-uri."
    echo "For example, to use the output nixosConfigurations.foo from the flake.nix, append \"#foo\" to the flake-uri."
    exit 1
  fi
  disko_script=$(nix_build "${flake}#nixosConfigurations.${flakeAttr}.config.system.build.disko")
  nixos_system=$(nix_build "${flake}#nixosConfigurations.${flakeAttr}.config.system.build.toplevel")
elif [[ -n "${disko_script:-}" ]] && [[ -n "${nixos_system:-}" ]]; then
  if [[ ! -e "${disko_script}" ]] || [[ ! -e "${nixos_system}" ]]; then
    echo "${disko_script} and ${nixos_system} must be existing store-paths"
    exit 1
  fi
  :
else
  abort "flake must be set"
fi

# wait for machine to become reachable (possibly forever)
# TODO we probably need an architecture detection here
# TODO if we have specified a user here but we are already booted into the
# installer, than the user might not work anymore
until facts=$(ssh_ -o ConnectTimeout=10 -- <<SSH
set -efu ${enable_debug}
has(){
  command -v tar >/dev/null && echo "y" || echo "n"
}
cat <<FACTS
is_os=\$(uname)
is_kexec=\$(if test -f /etc/is_kexec; then echo "y"; else echo "n"; fi)
has_tar=\$(has tar)
has_sudo=\$(has sudo)
has_wget=\$(has wget)
has_curl=\$(has curl)
FACTS
SSH
); do
  sleep 5
done

# make facts available in script
# shellcheck disable=SC2046
export $(echo "$facts" | grep -E '^(has|is)_[a-z0-9_]+=\S+' | xargs)

if [[ ${has_tar-n} == "n" ]]; then
  abort "no tar command found, but required to unpack kexec tarball"
fi
maybesudo=""
if [[ ${has_sudo-n} == "y" ]]; then
  maybesudo="sudo"
fi
if [[ ${is_os-n} != "Linux" ]]; then
  abort "This script requires Linux as the operating system, but got $is_os"
fi

if [[ ${is_kexec-n} != "y" ]] && [[ ${no_ssh_copy-n} != "y" ]]; then
  ssh-copy-id -o ConnectTimeout=10 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$ssh_connection"
fi

if [[ ${is_kexec-n} == "n" ]]; then
  ssh_ << SSH
set -efu ${enable_debug}
"${maybesudo}" rm -rf /root/kexec
"${maybesudo}" mkdir -p /root/kexec
SSH

  if [[ -f "$kexec_url" ]]; then
    ssh_ "${maybesudo} tar -C /root/kexec -xvzf-" < "$kexec_url"
  elif [[ ${has_curl-n} == "y" ]]; then
    ssh_ "curl --fail -Ss -L '${kexec_url}' | ${maybesudo} tar -C /root/kexec -xvzf-"
  elif [[ ${has_wget-n} == "y" ]]; then
    ssh_ "wget '${kexec_url}' -O- | ${maybesudo} tar -C /root/kexec -xvzf-"
  else
    curl --fail -Ss -L "${kexec_url}" | ssh_ "${maybesudo} tar -C /root/kexec -xvzf-"
  fi

  ssh_ << SSH
TMPDIR=/root/kexec setsid ${maybesudo} /root/kexec/kexec/run
SSH

  # wait for machine to become unreachable
  while timeout_ssh_ -- exit 0; do sleep 1; done

  # After kexec we explicitly set the user to root@
  ssh_connection="root@${ssh_connection#*@}"

  # watiting for machine to become available again
  until ssh_ -o ConnectTimeout=10 -- exit 0; do sleep 5; done
fi
for path in "${!disk_encryption_keys[@]}"
do
  echo "Uploading ${disk_encryption_keys[$path]} to $path"
  ssh_ "umask 077; cat > $path" < "${disk_encryption_keys[$path]}"
done

nixCopy --to "ssh://$ssh_connection" "$disko_script"
ssh_ "$disko_script"

if [[ ${stop_after_disko-n} == "y" ]]; then
  exit 0
fi

nixCopy --to "ssh://$ssh_connection?remote-store=local?root=/mnt" "$nixos_system"
if [[ -n ${extra_files:-} ]]; then
  if [[ -d "$extra_files" ]]; then
    extra_files="$extra_files/"
  fi
  rsync -vrlF -e "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" "$extra_files" "${ssh_connection}:/mnt/"
fi

ssh_ <<SSH
set -efu ${enable_debug}
# needed for installation if initrd-secrets are used
mkdir -m777 -p /mnt/tmp
nixos-install --no-root-passwd --no-channel-copy --system "$nixos_system"
${maybereboot}
SSH
