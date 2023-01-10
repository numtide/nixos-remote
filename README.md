# nixos-remote - install nixos everywhere via ssh

nixos-remote makes it possible to install nixos from Linux machines reachable via ssh.
Under the hood uses a [kexec image](https://github.com/nix-community/nixos-images#kexec-tarballs) to boot
into a NixOS installer from a running Linux system.
It then uses [disko](https://github.com/nix-community/disko) to partition and
format the disks on the target system before it installs the user provided nixos
configuration.

## Requirements

- x86_64 Linux system with kexec support (most x86_64 machine do have kexec support)
- At least 2.5GB RAM (swap does not count). If you do not have enough RAM you
  will see failures unpacking the initrd), this is because kexec needs to load
  the whole nixos into memory.

## Usage
Needs a repo with your configurations with flakes. For a minimal example checkout https://github.com/numtide/nixos-remote-examples.

Your NixOS configuration will also need a [disko](https://github.com/nix-community/disko) configuration  as we can see in
our [example](https://github.com/numtide/nixos-remote-examples/blob/9768e438b1467ec55d42e096860e7199bd1ef43d/flake.nix#L15-L19)

Afterwards you can just run:

```
nix run github:numtide/nixos-remote -- root@yourip --flake github:your-user/your-repo#your-system
```

The parameter passed to `--flake` should point to your nixos configuration
exposed in your flake (`nixosConfigurations.your-system` in the example above).

`nixos-remote --help`
``` shell
Usage: nixos-remote [options] ssh-host

Options:

* -f, --flake flake
  set the flake to install the system from
* -s, --store-paths
  set the store paths to the disko-script and nixos-system directly
  if this is give, flake is not needed
* --no-ssh-copy
  skip copying ssh-keys to target system
* --kexec url
  use another kexec tarball to bootstrap NixOS
* --stop-after-disko
  exit after disko formating, you can then proceed to install manually or some other way
* --no-reboot
  do not reboot after installation
* --extra-files files
  files to copy into the new nixos installation
* --debug
  enable debug output
```

## Using your own kexec image

By default `nixos-remote` will download the kexec image from [here](https://github.com/nix-community/nixos-images#kexec-tarballs).
It is also possible to provide your own by providing a file to `--kexec`. The image will than uploaded prior to executing.

``` shell
nixos-remote \
  --kexec "$(nix build --print-out-paths github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-unstable)/nixos-kexec-installer-x86_64-linux.tar.gz" \
  --flake 'github:your-user/your-repo#your-system' \
  root@yourip
```

`--kexec` can be useful for example for aarch64-linux, where there is no
pre-build image. The following example assumes that your local machine can
build for aarch64-linux either natively or through a remote builder

``` shell
nixos-remote \
  --kexec "$(nix build --print-out-paths github:nix-community/nixos-images#packages.aarch64-linux.kexec-installer-nixos-unstable)/nixos-kexec-installer-aarch64-linux.tar.gz" \
  --flake 'your-flake#your-system' \
  root@yourip
```
