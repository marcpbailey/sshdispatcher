# Task: Draft iTerm2 enhancement request + fix subtask prompt

> Paste this entire file as the first message of a fresh Claude Code session opened in `/Users/marc/Projects/sshdispatcher/`.

## Task

Produce TWO markdown documents inside `/Users/marc/Projects/sshdispatcher/`:

1. `iterm-enhancement-request.md` — a fileable enhancement request to iTerm2 upstream, formatted to comply with iTerm2's contribution conventions.
2. `iterm-fix-prompt.md` — a self-contained prompt for a *future* Claude Code session that will work on proposed fixes. Break the work into **discrete subtasks** (one per enhancement, possibly more if a single enhancement decomposes naturally). Do NOT propose them as one monolithic effort.

**STRICT CONSTRAINT: This task writes only those two markdown files. NO code is written, no source files in iTerm2 or elsewhere are modified. The follow-up fix work happens in a different session — your job is to set that session up well.**

## Background

- The user (Marc) maintains `sshdispatcher` at `/Users/marc/Projects/sshdispatcher/` — a transparent ssh wrapper that routes legacy DSA hosts through PuTTY's plink. Installed at `/usr/local/bin/sshdispatcher`, also symlinked as `/usr/local/bin/ssh`.
- We want iTerm2 to be able to route SSH sessions (especially Bonjour-discovered ones) through this wrapper, but the current iTerm2 architecture has several inflexibilities that prevent this cleanly. Findings are documented in `/Users/marc/Projects/sshdispatcher/iterm integration.md` — **read that first**; it cites the exact iTerm2 source-code lines that motivate each enhancement below.
- iTerm2 source: https://github.com/gnachman/iTerm2 (mirror; primary issue tracker is on GitLab — see Contribution Conventions below).
- Relevant iTerm2 files (URLs are the master branch):
  - `sources/Settings/Profiles/ITAddressBookMgr.m` — profile launch construction (`+bookmarkCommandSwiftyString:` ~lines 859-890; `+computeCommandForProfile:` ~lines 829-857; `_addBonjourHostProfileWithName:` ~lines 463-515; `iTermPathToSSH()` ~lines 76-78)
  - `sources/Settings/SSHConfigurationWindowController.swift` — SSH block schema (Config struct ~lines 10-56)
  - `sources/Settings/Profiles/iTermDynamicProfileManager.m` — `prototypeForDynamicProfile:` ~lines 594-624; `profileByMergingProfile:intoProfile:` ~lines 580-591 (shallow merge)
  - `sources/PTYSession/PTYSession.m` — env setup ~lines 2832-2834 and 2934-2944
  - Bundled wrapper: `OtherResources/it2ssh` (in repo) → installed at `/Applications/iTerm.app/Contents/Resources/utilities/it2ssh`

## Enhancement request contents (4 items)

For each of the four items below, the enhancement request must contain: (a) **Problem** — concrete user impact, with an example; (b) **Current behaviour** — cite the exact source files/lines; (c) **Proposed change** — high-level direction (no code); (d) **Files likely to need changes**; (e) **Test/verification considerations** (which existing tests touch this area, what new tests are warranted). Keep each item focused.

### 1. Harmonise shell/expansion paths into one uniform flow

The current launch path branches on `sshIntegration` (true vs false), on `Custom Command` type (Login Shell / Command / SSH), and Bonjour-injected profiles bypass much of it (forcibly setting `KEY_CUSTOM_COMMAND = kProfilePreferenceCommandTypeCustomValue` and a raw `KEY_COMMAND_LINE` string). The result: `$VAR` expansion works in some paths and not others; `\(iterm2.…)` interpolation works in some and not others; Bonjour profiles ignore the SSH block entirely. Propose: a single uniform flow such that **a profile launches the same way regardless of how it was created (static, dynamic, Bonjour, URI handler) and regardless of which Custom Command type is selected**, with a single, predictable, documented expansion model.

### 2. Allow inheritance for Bonjour (Bonjour template profile)

`_addBonjourHostProfileWithName:` overwrites `KEY_CUSTOM_COMMAND` and `KEY_COMMAND_LINE` after copying Default. Propose: respect a designated **Bonjour template profile** (either the Default or a profile with a special tag/flag) such that its `Custom Command` type and `SSH` block are inherited. The Bonjour resolver should populate hostname/user/port into the inherited profile **without** clobbering the command type or the SSH block.

### 3. Create `$ITERM_TARGET_HOST` environment variable

Today `ITERM_PROFILE` is the only per-profile variable available for `$VAR` expansion in the SSH-mode `Command` field, which forces the workaround of naming profiles after their hostname. Propose: when launching an SSH-mode session, iTerm2 should populate `ITERM_TARGET_HOST` (and ideally `ITERM_TARGET_USER`, `ITERM_TARGET_PORT`) in the env so the `Command` field — and any user shell hook — can reference them. Site for the change is the env-setup block around `PTYSession.m:2934-2944`. Discuss whether the value source is the SSH block (which has no Host field today — see issue #2 above) or another mechanism.

### 4. Configurable URI handling, transparently

Today `ssh://` URI handling appears to force-feed a hardcoded ssh invocation, opaquely. Propose: route URI launches through the same uniform flow as item #1, allowing the user to configure which profile (or wrapper binary) handles each URI scheme, in a way that's discoverable in iTerm2 Preferences. Find the URI handler entry point in the source (likely something like `application:openURL:` or a registered URL scheme handler — check `iTermAppDelegate.m` and grep for `ssh://`) and cite it.

## Contribution conventions — research before writing

Before drafting the request, look up:

- iTerm2's `CONTRIBUTING.md` (probably at the repo root on GitHub) — quote any rules about issue/feature-request format.
- iTerm2's official issue tracker. **Important:** issues are typically filed on GitLab at https://gitlab.com/gnachman/iterm2/-/issues, not on GitHub. Verify this is still the case.
- Any issue templates GitLab is enforcing (look at https://gitlab.com/gnachman/iterm2/-/tree/master/.gitlab/issue_templates if it exists).
- The wiki at https://gitlab.com/gnachman/iterm2/-/wikis/home for any "how to file an enhancement request" guidance.

The enhancement request document must follow whatever format upstream expects. If they use a specific template, mirror its sections. If they require labels/tags, note them. If they ask for one-issue-per-enhancement (which is likely), structure the document so each of the four items can be split into its own issue easily — perhaps as four top-level sections with "Suggested issue title:" and "Suggested labels:" headers. Cite the specific contribution rules at the top of the document.

## Future-session fix prompt

`iterm-fix-prompt.md` should be a self-contained prompt that someone (or Claude in a fresh session) can use to begin implementation work. It must:

- State the goal, link to the enhancement request, and link to `/Users/marc/Projects/sshdispatcher/iterm integration.md`.
- Decompose into **discrete, independently-implementable subtasks**. At minimum one per enhancement item, but split further where natural (e.g. the harmonisation enhancement may need a refactor subtask before the unification subtask). Each subtask: scope, files to touch, expected change shape, manual verification steps, tests to add or update.
- Identify dependencies between subtasks (e.g. "do subtask 2 before 3 because…").
- Note that the work will land as a **PR upstream**. Reference iTerm2's PR conventions discovered in your contribution-rules research (commit message format, branch naming, signing requirements, CI expectations, etc.).
- Do NOT write any code in the prompt — describe the work, don't pre-solve it.

## Process

1. Read `/Users/marc/Projects/sshdispatcher/iterm integration.md` end-to-end. It's the ground truth for the source-code references you'll cite.
2. Use WebFetch / `gh api` / WebSearch to look up the contribution rules and any GitLab issue templates. Cite URLs.
3. Spot-check 2-3 of the source-code references in the iTerm2 repo to confirm the line numbers haven't drifted (use `gh api repos/gnachman/iTerm2/contents/<path>` or raw.githubusercontent.com). If they have, update the citations.
4. Find the URI handler entry point for ssh:// URIs (mentioned in item #4) — it may be in `iTermAppDelegate.m` or a URL scheme registration. Cite it.
5. Draft both documents. Reread for cohesion — the fix prompt should match the enhancement request's structure 1:1 (each subtask traces back to an enhancement item).
6. Save the two files. Do not modify any other file.

End your turn by listing the two files you created and a one-line summary of each. No further action.
