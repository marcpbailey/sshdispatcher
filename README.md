# sshdispatcher

A transparent `ssh` wrapper that routes connections to legacy DSA-only network gear through PuTTY's `plink`, while leaving all other hosts to the real `ssh`.

## Problem

Some older managed network switches (e.g. TP-Link JetStream TL-SG2428P) only support `ssh-dss` (DSA 1024-bit) host keys. DSA was deprecated in OpenSSH 7.0 (2015), disabled by default in OpenSSH 9.7, and **completely removed** from OpenSSH 9.8/10.0 (2024–2025). Modern macOS clients can no longer connect to these devices regardless of what you put in `~/.ssh/config` — the algorithm name is unknown to the parser.

PuTTY's `plink` still supports DSA and is available via Homebrew. `sshdispatcher` makes it invisible.

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

# 4. Convert your switch key to PuTTY format (one-time per key)
puttygen ~/.ssh/switch_key -O private -o ~/.ssh/switch_key.ppk
```

## Configuration

Mark a host stanza as legacy by including the commented line `# HostKeyAlgorithms +ssh-dss`. The comment form is preferred over the live form because OpenSSH 10+ does not recognise `ssh-dss` as a valid token, so a live directive causes the entire `~/.ssh/config` to fail to load.

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
ssh switch            # → plink (DSA host)
ssh poeswitch.local   # → plink (DSA host)
ssh myserver          # → real ssh (unaffected)
ssh -p 2222 switch    # → plink with -P 2222
ssh admin@switch      # → plink as admin@switch
```

## Key conversion

PuTTY uses `.ppk` format instead of OpenSSH format. Convert once per key:

```bash
puttygen ~/.ssh/switch_key -O private -o ~/.ssh/switch_key.ppk
```

The original key is unchanged. Both files represent the same keypair; the public key on the switch is the same either way. `sshdispatcher` detects the `.ppk` sibling automatically — if it exists, `plink` uses it; if not, `plink` falls back to a password prompt.

## Trade-offs

| Aspect | Detail |
|--------|--------|
| Scope | Only `ssh` sessions are dispatched. `scp`, `sftp`, and `rsync` are not handled. |
| KexAlgorithms / Ciphers | `plink` negotiates its own key exchange and cipher suite. The values in `~/.ssh/config` are not forwarded to it. |
| Host-key pinning | `-hostkey "*"` is passed to `plink`, accepting any host key on first connection. |
| Other `ssh` flags | Non-legacy hosts get the full original argv. Legacy hosts get a reconstructed minimal command line (`-p`, `-l`, `-i` only). |
| Scripts & tools | The alias only applies to interactive shells. `git`, VS Code Remote-SSH, and other tools invoke `/usr/bin/ssh` or Homebrew's `ssh` directly and are unaffected. |

## Man page

```bash
man sshdispatcher
```

## Running the tests

```bash
brew install bats-core   # if not already installed
bats tests/
```
