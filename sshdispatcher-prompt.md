# sshdispatcher: a transparent SSH wrapper for legacy DSA-only network gear

## Background

Some older managed network equipment — notably TP-Link JetStream switches like the TL-SG2428P — only offers `ssh-dss` (DSA, 1024-bit) as the SSH host key algorithm. DSA was deprecated in OpenSSH 7.0 (2015), disabled by default in OpenSSH 9.7, and **completely removed at compile time in OpenSSH 9.8 / 10.0** (2024–2025). It cannot be re-enabled via `HostKeyAlgorithms +ssh-dss` in modern OpenSSH — the algorithm name itself is now unknown to the parser, so any config file containing it as a live directive fails to load entirely.

This means modern macOS clients (Homebrew OpenSSH 10+, and eventually system OpenSSH) physically cannot connect to these switches. The firmware is unlikely to ever be updated.

PuTTY's `plink` still supports DSA and is available via `brew install putty`. It's a viable transport, but it doesn't read `~/.ssh/config`, has different CLI syntax, and disrupts muscle memory. Maintaining a forked/legacy OpenSSH build is high-effort for two switches.

## Goal

A small dispatcher script — `sshdispatcher` — that:

1. Is aliased to `ssh` in interactive shells, so typing `ssh switch` Just Works.
2. Reads `~/.ssh/config` to identify hosts that require legacy SSH.
3. Detection mechanism: a host stanza is "legacy" if it contains the line `HostKeyAlgorithms +ssh-dss` **either live or commented out** (`# HostKeyAlgorithms +ssh-dss`). Commented form is preferred since it keeps `ssh -G` working and the rest of OpenSSH happy.
4. For legacy hosts, dispatches to `plink` with appropriate flags. For all other hosts, transparently passes through to real `/usr/bin/ssh` (or Homebrew's, if installed and preferred).
5. Honours standard ssh argv: `user@host`, `-p port`, `-l user`, plus all flags-with-values that should be skipped during host detection (`-i`, `-J`, `-L`, `-R`, `-o`, etc.).
6. Resolves `User`, `Port`, and `IdentityFile` from `~/.ssh/config` via `ssh -G hostname` when not specified on the command line, so all config remains in one place.

Non-goals: scp/sftp/rsync dispatch (handle separately later if needed); honouring `KexAlgorithms`/`Ciphers` from config (plink negotiates its own); supporting more than basic public-key and password auth via plink.

Note that the point is to only do the specific exceptions via putty, otherwise simply pass through to ssh.The script provide below is a starting point and may have bugs you need to fix. We are not writing war and peace here, and this is a utility script only, so you should not over-engineer it.

## Public key authentication

PuTTY uses its own `.ppk` (PuTTY Private Key) format, not OpenSSH format. Conversion is **one-time, not on-the-fly**:

```bash
puttygen ~/.ssh/switch_key -O private -o ~/.ssh/switch_key.ppk
```

The original OpenSSH key stays untouched; the `.ppk` lives alongside it (`switch_key` and `switch_key.ppk` represent the same keypair, public key on the switch is the same either way).

**Dispatcher behaviour for `IdentityFile`:**

- After resolving the host via `ssh -G`, parse out the `identityfile` lines.
- For each candidate identity, look for a `.ppk` sibling at the same path (e.g. `~/.ssh/switch_key` → check for `~/.ssh/switch_key.ppk`).
- If a `.ppk` sibling exists, pass `-i <path>.ppk` to `plink`.
- If multiple candidates have `.ppk` siblings, prefer the first one (matches ssh's first-match-wins behaviour).
- If none exists, omit `-i` entirely and let `plink` fall back to password prompt.
- **Do not** generate `.ppk` files on the fly. Document the `puttygen` command in the README so users convert deliberately.

Caveat: `ssh -G` returns *all* candidate identity files including OpenSSH defaults (`id_rsa`, `id_ed25519`, etc.), even when not explicitly set. The "look for a `.ppk` sibling" rule naturally filters this — defaults don't have `.ppk` siblings unless the user converted them.

## Example config

```
Host switch switch.local 172.17.17.12 switch.fi
    HostName 172.17.17.12
    User admin
    IdentityFile ~/.ssh/switch_key
    # HostKeyAlgorithms +ssh-dss   ← marker (commented; triggers dispatcher)
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

All eight hostnames (across both stanzas) should be detected as legacy. If `~/.ssh/switch_key.ppk` exists, plink uses it; otherwise password prompt.

## Proposed script (starting point — refine as needed)

Bash, uses associative arrays, regex matching, and `ssh -G` for config resolution:

```bash
#!/bin/bash
# sshdispatcher - dispatch legacy DSA hosts to plink, others to real ssh.
# A host is "legacy" if its ~/.ssh/config stanza contains
# `HostKeyAlgorithms +ssh-dss` (live OR commented).

set -euo pipefail

REAL_SSH=$(PATH="/opt/homebrew/bin:/usr/bin" command -v ssh)
PLINK=$(command -v plink || true)
CONFIG="${HOME}/.ssh/config"

declare -A LEGACY=()
current_hosts="" has_dss=0
flush() {
  if (( has_dss )) && [[ -n "$current_hosts" ]]; then
    for h in $current_hosts; do LEGACY[$h]=1; done
  fi
  current_hosts="" has_dss=0
}
if [[ -r "$CONFIG" ]]; then
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed#\#}"; trimmed="${trimmed# }"
    if [[ "$trimmed" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
      flush
      current_hosts="${BASH_REMATCH[1]}"
    elif [[ "$trimmed" =~ [Hh]ost[Kk]ey[Aa]lgorithms[[:space:]]*[+=]?[[:space:]]*[^[:space:]]*ssh-dss ]]; then
      has_dss=1
    fi
  done < "$CONFIG"
  flush
fi

host="" user="" port="" prev=""
flag_takes_value='^-[bcDEeFIiJLlmOopQRSWw]$'
for arg in "$@"; do
  if [[ -n "$prev" ]]; then
    case "$prev" in -p) port="$arg" ;; -l) user="$arg" ;; esac
    prev=""; continue
  fi
  [[ "$arg" =~ $flag_takes_value ]] && { prev="$arg"; continue; }
  [[ "$arg" =~ ^- ]] && continue
  if [[ -z "$host" ]]; then
    if [[ "$arg" =~ ^([^@]+)@(.+)$ ]]; then
      user="${BASH_REMATCH[1]}"; host="${BASH_REMATCH[2]}"
    else
      host="$arg"
    fi
  fi
done

if [[ -n "$host" && -n "${LEGACY[$host]:-}" ]]; then
  [[ -z "$PLINK" ]] && { echo "sshdispatcher: plink not found for legacy host $host" >&2; exit 1; }
  identity=""
  if [[ -z "$user" || -z "$port" || -z "$identity" ]]; then
    while IFS= read -r k v; do
      [[ "$k" == "user" && -z "$user" ]] && user="$v"
      [[ "$k" == "port" && -z "$port" ]] && port="$v"
      if [[ "$k" == "identityfile" && -z "$identity" ]]; then
        expanded="${v/#\~/$HOME}"
        [[ -f "${expanded}.ppk" ]] && identity="${expanded}.ppk"
      fi
    done < <("$REAL_SSH" -G "$host" 2>/dev/null)
  fi
  args=(-ssh -hostkey "*")
  [[ -n "$port" ]] && args+=(-P "$port")
  [[ -n "$identity" ]] && args+=(-i "$identity")
  args+=("${user:-admin}@$host")
  exec "$PLINK" "${args[@]}"
fi

exec "$REAL_SSH" "$@"
```

Note: `-hostkey "*"` accepts any host key on first connection. Future enhancement: per-host fingerprint pinning.

## Installation

- Source lives in `~/Projects/sshdispatcher` (initialise as a git repo).
- Install target for the script: `/usr/local/bin/sshdispatcher` (symlink, so edits in the repo are live). The user already uses `/usr/local/` on this Mac (migrated from Intel days), so this is the correct prefix — do **not** use `~/.local/` or `/opt/homebrew/`. Installation will require `sudo` for the symlink.
- Install target for the man page: `/usr/local/share/man/man1/sshdispatcher.1` (symlink). `man` on macOS already searches `/usr/local/share/man` by default, so no `MANPATH` configuration needed.
- Alias in `~/.zshrc`: `alias ssh=sshdispatcher` — affects interactive shells only, leaves scripts/git/VS Code Remote-SSH using real `ssh` untouched.
- Dependency: `brew install putty` for `plink` and `puttygen`.

## Deliverables

The repository at `~/Projects/sshdispatcher` must contain, at completion:

1. **`sshdispatcher`** — the executable bash script. ShellCheck-clean.
2. **`sshdispatcher.1`** — a man page in standard groff/mdoc format, covering:
   - `NAME`, `SYNOPSIS`, `DESCRIPTION`
   - `DETECTION` — how the `HostKeyAlgorithms +ssh-dss` marker works
   - `OPTIONS` — pass-through behaviour, supported flags
   - `IDENTITY FILES` — `.ppk` sibling lookup, `puttygen` conversion command
   - `EXAMPLES` — sample config stanza and invocations
   - `FILES` — `~/.ssh/config`, `/usr/local/bin/sshdispatcher`
   - `SEE ALSO` — `ssh(1)`, `ssh_config(5)`, `plink(1)`, `puttygen(1)`
   - `LIMITATIONS` — no scp/sftp dispatch, no host-key pinning by default, plink doesn't honour `KexAlgorithms`/`Ciphers` from config
   - Verify with `man -l sshdispatcher.1` before committing.
3. **`README.md`** — problem statement, quickstart, usage, the `puttygen` conversion command, configuration example, trade-offs, link to man page.
4. **`install.sh`** — idempotent installer that:
   - Verifies `/usr/local/bin` and `/usr/local/share/man/man1` exist (create with `sudo mkdir -p` if missing — this should be rare on an established `/usr/local/` setup).
   - Symlinks `sshdispatcher` and `sshdispatcher.1` into them using `sudo ln -sf`.
   - Checks for `plink` in `$PATH` and warns (not errors) if missing.
   - Prints next-step instructions: add the alias to `~/.zshrc`, confirm `/usr/local/bin` is in `$PATH` (it should be by default).
5. **`uninstall.sh`** — removes the symlinks (also requires `sudo`).
6. **`tests/`** — bats-based tests covering:
   - Pass-through: `ssh normalhost` invokes real ssh unchanged.
   - Legacy detection from live and commented `HostKeyAlgorithms +ssh-dss` markers.
   - All eight hostname aliases in the example config detect correctly.
   - `user@host` parsing.
   - `-p port` and `-l user` parsing.
   - `IdentityFile` → `.ppk` sibling resolution (positive case).
   - `IdentityFile` with no `.ppk` sibling (negative case — no `-i` passed).
   - Missing-plink error path.
   - A test fixture `~/.ssh/config` should live under `tests/fixtures/`, and tests should run `sshdispatcher` with `HOME` overridden so the user's real config is untouched. Tests must not require `sudo` or write to `/usr/local/`.
7. **`.gitignore`** — at minimum, exclude editor temp files, `.DS_Store`, and any locally-generated `.ppk` files in fixtures.
8. **`LICENSE`** — not required. This is a personal utility script. Just add a comment to the file with me as the author.
9. **Git history** — meaningful commits, not a single squashed dump. At least: initial scaffold, script, tests, man page, install/uninstall, README polish.

## Tasks (in order)

1. Create `~/Projects/sshdispatcher` and `git init`.
2. Write a brief plan and confirm it before writing code.
3. Scaffold the repo (LICENSE, .gitignore, README skeleton).
4. Implement the script. Run `shellcheck` until clean.
5. Write the bats tests with fixtures. Iterate until they pass.
6. Write the man page. Verify rendering with `man -l`.
7. Write `install.sh` and `uninstall.sh`. Test (the install/uninstall steps will need `sudo` — note this in any output but don't actually run them in the dev loop unless explicitly asked).
8. Polish the README with real usage examples.
9. Final commit; summarise what was built.
