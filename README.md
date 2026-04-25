# sshdispatcher

A transparent `ssh` wrapper that routes connections to legacy DSA-only hosts through PuTTY's `plink`, while leaving all other hosts to the real `ssh`.

## Problem

`ssh-dss` (DSA 1024-bit) host keys were deprecated in OpenSSH 7.0 (2015), disabled by default in OpenSSH 9.7, and **completely removed** from OpenSSH 9.8/10.0 (2024–2025). Any host that has not migrated to a modern host key type (RSA 3072+, ECDSA, or Ed25519) is unreachable from current OpenSSH clients — the algorithm name is unknown to the parser, so even `HostKeyAlgorithms +ssh-dss` in `~/.ssh/config` causes the file to fail to load.

This affects any device where the SSH implementation is fixed and cannot be upgraded: managed network switches, embedded appliances, serial console servers, legacy VMs — anything where the firmware is end-of-life or the vendor simply hasn't shipped a fix. TP-Link JetStream switches are a good example: common in home and small-office networks, only offering `ssh-dss`, with no firmware update in sight.

PuTTY's `plink` still supports DSA and is available via Homebrew. `sshdispatcher` makes the handoff invisible.

## Quickstart

```bash
# 1. Install dependencies
brew install putty

# 2. Install sshdispatcher
git clone https://github.com/your/sshdispatcher ~/Projects/sshdispatcher
cd ~/Projects/sshdispatcher
./install.sh          # needs sudo for /usr/local symlinks

# 3. Add to ~/.zshrc
echo 'alias ssh=sshdispatcher' >> ~/.zshrc
source ~/.zshrc

# 4. Convert any keys to PuTTY format (one-time per key)
puttygen ~/.ssh/mykey -O private -o ~/.ssh/mykey.ppk
```

## Configuration

Mark a host stanza as legacy by adding the commented line `# HostKeyAlgorithms +ssh-dss`. The comment form is required — a live `HostKeyAlgorithms +ssh-dss` directive causes OpenSSH 10+ to reject the entire `~/.ssh/config` because `ssh-dss` is no longer a recognised algorithm token.

```
Host switch switch.local 172.17.17.12 switch.fi
    HostName 172.17.17.12
    User admin
    IdentityFile ~/.ssh/switch_key
    # HostKeyAlgorithms +ssh-dss   ← triggers dispatcher
    KexAlgorithms +diffie-hellman-group1-sha1
    Ciphers aes256-cbc

Host poeswitch poeswitch.local 172.17.17.2 poeswitch.fi
    HostName 172.17.17.2
    User admin
    IdentityFile ~/.ssh/poeswitch_key
    # HostKeyAlgorithms +ssh-dss
    KexAlgorithms +diffie-hellman-group1-sha1
    Ciphers aes256-cbc
```

All aliases on the `Host` line are detected. Both stanzas above yield eight legacy hostnames total.

## Usage

After adding the alias, `ssh` works as normal:

```bash
ssh switch            # → plink (legacy DSA host)
ssh poeswitch.local   # → plink (legacy DSA host)
ssh myserver          # → real ssh (unaffected)
ssh -p 2222 switch    # → plink with -P 2222
ssh admin@switch      # → plink as admin@switch
```

On first connection to a legacy host, `plink` will prompt you to verify and accept the host key. Accepted keys are cached in `~/.putty/sshhostkeys`. Subsequent connections are silent.

## Key conversion

PuTTY uses `.ppk` format instead of OpenSSH format. Convert once per key:

```bash
puttygen ~/.ssh/mykey -O private -o ~/.ssh/mykey.ppk
```

The original key is unchanged. Both files represent the same keypair. `sshdispatcher` detects the `.ppk` sibling automatically — if it exists, `plink` uses it; if not, `plink` falls back to a password prompt.

## Trade-offs

| Aspect | Detail |
|--------|--------|
| Scope | Only `ssh` sessions are dispatched. `scp`, `sftp`, and `rsync` are not handled. |
| KexAlgorithms / Ciphers | `plink` negotiates its own key exchange and cipher suite. The values in `~/.ssh/config` are not forwarded to it. |
| Host-key verification | `plink` handles this interactively and caches keys in `~/.putty/sshhostkeys`. There is no fingerprint pinning in the dispatcher. |
| Other `ssh` flags | Non-legacy hosts get the full original argv. Legacy hosts get a reconstructed minimal command line (`-p`, `-l`, `-i` only). |
| Scripts & tools | The alias only applies to interactive shells. `git`, VS Code Remote-SSH, and other tools invoke `/usr/bin/ssh` or Homebrew's `ssh` directly and are unaffected. |

## Man page

```bash
man sshdispatcher
```

## PuTTY session profile

The file [`sshdispatcher.putty`](sshdispatcher.putty) is a PuTTY session profile that `install.sh` symlinks to `~/.putty/sessions/sshdispatcher`. It does two things:

- Moves `dh-group1-sha1` above PuTTY's warn threshold so plink never prompts "Continue with connection?" when connecting to a host that only supports that key-exchange algorithm.

`install.sh` creates the symlink automatically. If you skip the installer, the dispatcher writes the file itself on first use.

## Running the tests

```bash
brew install bats-core   # if not already installed
bats tests/
```
