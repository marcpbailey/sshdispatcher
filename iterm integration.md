# iTerm2 Dynamic Profile template for sshdispatcher

## Context

`sshdispatcher` is tested and working — invoking it from a shell as `sshdispatcher switch.local` succeeds. The remaining problem is purely on the iTerm side: marshall the right command line into iTerm's launch path so a Dynamic Profile entry routes through `sshdispatcher` for legacy DSA hosts. Bonjour click-to-connect hardcodes `/usr/bin/ssh` and is a confirmed dead end (iTerm2 issue #3415); the workable path is Dynamic Profiles with `Custom Command: SSH` + `pathToSSH: /usr/local/bin/sshdispatcher` + `sshIntegration: true`. The current `sshdispatcher.json` is a one-host stopgap that exploits `Name == hostname`. We want a structure where each profile's human-readable `Name` is independent of the SSH hostname.

This plan changes only `sshdispatcher.json`. `sshdispatcher` itself, `install.sh`, and the conductor-injection question are all out of scope.

## Findings from iTerm2 source

### Q1 — Variable that resolves to the SSH hostname

**There is none, and there cannot be.** The full schema for the `"SSH"` block ([SSHConfigurationWindowController.swift:16-21](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/SSHConfigurationWindowController.swift#L16)) has exactly four keys: `sshIntegration`, `environmentVariablesToCopy`, `filesToCopy`, `pathToSSH`. **No host field exists.** The hostname lives exclusively in the top-level `"Command"` — the field is itself the source of truth, so a "hostname variable" would be circular.

What IS available in the expansion environment is the env iTerm passes to the launched job ([PTYSession.m:2934-2944](https://github.com/gnachman/iTerm2/blob/master/sources/PTYSession/PTYSession.m#L2934)): `ITERM_PROFILE`, `ITERM_SESSION_ID`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `COLORTERM`, plus whatever the user's shell startup adds. None of these carry an SSH target. Of these, only `ITERM_PROFILE` is meaningfully variable per profile, which is why the existing one-host trick (`Command: $ITERM_PROFILE` with `Name == hostname`) works.

The constructive solution: put the hostname **literally** in `Command` per profile — `"Command": "admin@poeswitch.local"`. No expansion needed; no `Name`/hostname coupling.

### Q2 — Why `$ITERM_PROFILE` only expands when `sshIntegration: true`

Definitive answer from [ITAddressBookMgr.m:859-890](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/ITAddressBookMgr.m#L859) (`+bookmarkCommandSwiftyString:`):

- **`sshIntegration: false`** → iTerm builds `ssh <command>`, splits into argv via `componentsInShellCommand` (quoting-aware whitespace split), and execs argv directly. No shell wraps the call, so the kernel does not expand `$VAR` and `$ITERM_PROFILE` is passed literally as an argv token to ssh.
- **`sshIntegration: true`** → iTerm builds `/usr/bin/login -fpq <user> <shell> -c "'<path-to-it2ssh>' <command>"` and execs *that*. The shell login spawns reads its `-c` string and expands `$ITERM_PROFILE` from env before it ever calls `it2ssh`.

So the expansion is done by the user's login shell (zsh in our case), not by iTerm or it2ssh. Anything zsh would expand — env vars, command substitution — would expand here.

iTerm also processes the Command string through `iTermExpressionEvaluator` ([ITAddressBookMgr.m:829-857](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/ITAddressBookMgr.m#L829)) before exec — that resolves swifty `\(name)` interpolations only, not `$VAR`. Notable consequence: **`\(iterm2.profileName)` works in both integration modes**, whereas `$ITERM_PROFILE` only works with `sshIntegration: true`. We won't use either; we'll use literal hostnames.

### Q3 — What it2ssh does in the chain, and how that affects sshdispatcher

`it2ssh` is invoked only when `sshIntegration: true`. iTerm bundles it at `/Applications/iTerm.app/Contents/Resources/utilities/it2ssh` (resolved by `iTermPathToSSH()`, [ITAddressBookMgr.m:76-78](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/ITAddressBookMgr.m#L76)) and calls it as a real subprocess — no in-process reimplementation.

Mechanism it2ssh adds (from reading the script):
1. Resolves the SSH binary via `SSH=${SSH:-/usr/bin/ssh}` ([it2ssh:43](it2ssh:43)). iTerm sets `SSH` in the child env to the value of `pathToSSH` ([PTYSession.m:2832-2834](https://github.com/gnachman/iTerm2/blob/master/sources/PTYSession/PTYSession.m#L2832)) — **this is the actual mechanism by which `pathToSSH` overrides the SSH binary.**
2. Calls `$SSH` once with no args ([it2ssh:73](it2ssh:73)) to scrape boolean flag letters from the usage line. sshdispatcher with no args execs through to `/usr/bin/ssh` with no args, which prints usage to stderr — works.
3. Parses argv to identify HOSTNAME (first non-flag positional, [it2ssh:111](it2ssh:111)) and ensures `-t` is present.
4. Emits OSC sequences locally (env dump, `it2ssh=<TOKEN>` handshake, `SendConductor`) for the iTerm parent to read.
5. Execs `$SSH [user_args] -- <hostname> exec sh -c '<conductor-payload>'` ([it2ssh:160-168](it2ssh:160)) — appending a remote-shell conductor injection to the SSH command tail.

When `sshIntegration: false`, none of this happens — iTerm runs `ssh <command>` directly. `pathToSSH` is **not** consulted in that path; the literal binary `/usr/bin/ssh` is used. So `sshIntegration: true` is required just to get the `pathToSSH` override at all.

### Q4 — Does `environmentVariablesToCopy` offer us anything?

**No.** It is local→remote (post-connect), not local pre-launch. It cannot influence Command-field expansion.

The field is a `[String]` list of variable **names** ([SSHConfigurationWindowController.swift:12](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/SSHConfigurationWindowController.swift#L12), GUI tab-separated NSTokenField at line 85). Setting it doesn't *define* values — the values are pulled from whatever is in the local env when SSH runs, then forwarded to the remote shell so the named vars are present after connect. By the time that copy could happen, the Command field has already been built and exec'd.

A second confirming signal: the field is barely consumed in iTerm2's source. A `gh api search/code` for the literal name returns only 2 files (the config struct and the UI XIB) — neither in the launch path. Compare to `pathToSSH`, which appears in 4 files including `ITAddressBookMgr.m` where the actual launch command is constructed ([ITAddressBookMgr.m:745-754](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/ITAddressBookMgr.m#L745)). The launch-construction code reads `sshIntegration` from the config and ignores `environmentVariablesToCopy` entirely. (It is presumably consumed later by the conductor protocol via `dictionaryValue` serialization, which doesn't grep — but that path runs on the remote, not before the local exec.)

**Verdict:** keep `environmentVariablesToCopy: []` in the parent SSH block; it has no bearing on what we're trying to do.

### Q5 — Could the Default profile route Bonjour clicks through sshdispatcher?

**No.** Bonjour copies the Default profile *and then surgically overrides the bits we'd want to inherit.* From `_addBonjourHostProfileWithName:` ([ITAddressBookMgr.m:463-515](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/ITAddressBookMgr.m#L463)):

```objc
Profile* prototype = [[ProfileModel sharedInstance] defaultBookmark];
newBookmark = [NSMutableDictionary dictionaryWithDictionary:prototype];   // copies Default
...
[newBookmark setObject:[NSString stringWithFormat:@"%@ %@%@%@",
                       serviceType, userNameArg, optionalPortArg, destination]
                forKey:KEY_COMMAND_LINE];                                 // overrides to "ssh user@host -p 22"
[newBookmark setObject:kProfilePreferenceCommandTypeCustomValue
                forKey:KEY_CUSTOM_COMMAND];                               // overrides to "Command", not "SSH"
```

Two specific overrides defeat the approach:
- `KEY_CUSTOM_COMMAND` is forced to `Command` (plain shell command), so the entire `SSH` block — including `pathToSSH` and `sshIntegration` — is bypassed at launch.
- `KEY_COMMAND_LINE` is set to the literal string `ssh <user>@<host> -p <port>`, leaving no field to vary.

Independently, even if a hostname variable existed (Q1), it would be moot here: `Command` mode is exec'd via `componentsInShellCommand` with no shell wrapping, so `$VAR` and `\(iterm2.…)` both stay unevaluated. The literal token `ssh` IS subject to PATH resolution, but iTerm2's GUI PATH does not honour `/usr/local/bin/ssh` empirically — so it lands on `/usr/bin/ssh`, the same hardcode the original task started with.

**Verdict:** the Default-profile-as-template angle is closed. Manual Profile-menu launches with the parent/child template (below) remain the only clean path. A separate enhancement request to upstream iTerm2 has been spun off to address the underlying inflexibilities.

## Recommended template

Two-tier structure: one parent owning the SSH block, N children that each repeat `Name`/`Guid`/`Command` and reference the parent. **Important caveat from research**: Dynamic Profile inheritance is **shallow** ([iTermDynamicProfileManager.m:580-591](https://github.com/gnachman/iTerm2/blob/master/sources/Settings/Profiles/iTermDynamicProfileManager.m#L580)) — top-level keys are merged, but if a child sets `"SSH": {…}`, the entire SSH dict overrides. Our children don't set `SSH`, so they inherit the parent's whole block cleanly. This is fine.

Replace `sshdispatcher.json`:

```json
{
  "Profiles": [
    {
      "Name": "Legacy SSH (parent)",
      "Guid": "SSHDISP-PARENT-0000-0000-000000000000",
      "Custom Command": "SSH",
      "Custom Shell": "/bin/zsh",
      "SSH": {
        "sshIntegration": true,
        "pathToSSH": "/usr/local/bin/sshdispatcher",
        "filesToCopy": [],
        "environmentVariablesToCopy": []
      }
    },
    {
      "Name": "PoE Switch",
      "Guid": "SSHDISP-CHILD-0001-0000-000000000000",
      "Dynamic Profile Parent Name": "Legacy SSH (parent)",
      "Command": "admin@poeswitch.local"
    },
    {
      "Name": "Core Switch",
      "Guid": "SSHDISP-CHILD-0002-0000-000000000000",
      "Dynamic Profile Parent Name": "Legacy SSH (parent)",
      "Command": "admin@switch.local"
    }
  ]
}
```

`Dynamic Profile Parent Name` is documented at https://iterm2.com/documentation-dynamic-profiles.html and consumed in `iTermDynamicProfileManager.m`'s `prototypeForDynamicProfile:` (lines 594-624). Adding a new legacy host is a 4-line entry: `Name`, `Guid`, `Dynamic Profile Parent Name`, `Command`.

If the parent profile shouldn't appear in the user-visible profile list, set `"Tags": ["sshdispatcher-internal"]` or simply delete it from the menu via iTerm preferences. (Optional polish — does not change behavior.)

## Critical files

- [sshdispatcher.json](sshdispatcher.json) — replace with the template above; copy the same content to `~/Library/Application Support/iTerm2/DynamicProfiles/sshdispatcher.json`.

## Verification

1. Save the new file to `~/Library/Application Support/iTerm2/DynamicProfiles/sshdispatcher.json`. iTerm picks it up live without restart.
2. Confirm both children appear under iTerm's **Profiles** menu, both showing the parent's SSH settings if you open them in Preferences.
3. Launch the **PoE Switch** child. Tail `/tmp/ssd.log` (sshdispatcher writes a debug line at [sshdispatcher:6](sshdispatcher:6)). Expected log entry:
   ```
   sshdispatcher invoked: -t -- admin@poeswitch.local exec sh -c '...'
   ```
   This confirms iTerm's chain is `login -fpq … -c "'.../it2ssh' admin@poeswitch.local"` → it2ssh → sshdispatcher with the conductor tail.
4. Confirm the legacy switch shell appears with no KEX warning and no anti-spoof pause (the `sshdispatcher.putty` session profile and `-no-antispoof` flag already handle those).
5. Sanity check the parent: in iTerm Preferences, open the **PoE Switch** profile → **Advanced** tab → confirm "Dynamic Profile Parent" reads "Legacy SSH (parent)". This proves the inheritance link resolved.
