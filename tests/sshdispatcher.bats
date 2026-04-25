#!/usr/bin/env bats
# Tests for sshdispatcher. Run with: bats tests/sshdispatcher.bats
# HOME is overridden to a temp dir; the user's real ~/.ssh/config is never read.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="$SCRIPT_DIR/tests/fixtures"
DISPATCHER="$SCRIPT_DIR/sshdispatcher"
FAKE_SSH="$FIXTURES/fake_ssh"
FAKE_PLINK="$FIXTURES/fake_plink"

setup() {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.ssh"
  cp "$FIXTURES/ssh_config" "$FAKE_HOME/.ssh/config"
  SSH_LOG="$(mktemp)"
  PLINK_LOG="$(mktemp)"
  export FAKE_SSH_LOG="$SSH_LOG"
  export FAKE_PLINK_LOG="$PLINK_LOG"
}

teardown() {
  rm -rf "$FAKE_HOME" "$SSH_LOG" "$PLINK_LOG"
}

# Helper: run dispatcher with fake HOME and fake binaries.
run_dispatcher() {
  HOME="$FAKE_HOME" \
  SSHDISPATCHER_SSH="$FAKE_SSH" \
  SSHDISPATCHER_PLINK="$FAKE_PLINK" \
  FAKE_SSH_LOG="$SSH_LOG" \
  FAKE_PLINK_LOG="$PLINK_LOG" \
  run "$DISPATCHER" "$@"
}

# ── Pass-through ──────────────────────────────────────────────────────────────

@test "normal host passes through to real ssh" {
  run_dispatcher normalhost
  [ "$status" -eq 0 ]
  grep -q "fake_ssh normalhost" "$SSH_LOG"
}

@test "unknown host passes through to real ssh" {
  run_dispatcher someunknownhost
  [ "$status" -eq 0 ]
  grep -q "fake_ssh someunknownhost" "$SSH_LOG"
}

# ── Legacy detection: commented marker ────────────────────────────────────────

@test "switch (commented marker) detected as legacy" {
  run_dispatcher switch
  [ "$status" -eq 0 ]
  grep -q "fake_plink" "$PLINK_LOG"
  [ ! -s "$SSH_LOG" ] || ! grep -q "fake_ssh switch" "$SSH_LOG"
}

@test "poeswitch (commented marker) detected as legacy" {
  run_dispatcher poeswitch
  [ "$status" -eq 0 ]
  grep -q "fake_plink" "$PLINK_LOG"
}

# ── Legacy detection: live marker ─────────────────────────────────────────────

@test "liveswitch (live HostKeyAlgorithms +ssh-dss) detected as legacy" {
  run_dispatcher liveswitch
  [ "$status" -eq 0 ]
  grep -q "fake_plink" "$PLINK_LOG"
}

# ── All eight hostname aliases ────────────────────────────────────────────────

@test "switch alias: switch" {
  run_dispatcher switch; grep -q "fake_plink" "$PLINK_LOG"
}

@test "switch alias: switch.local" {
  run_dispatcher switch.local; grep -q "fake_plink" "$PLINK_LOG"
}

@test "switch alias: 172.17.17.12" {
  run_dispatcher 172.17.17.12; grep -q "fake_plink" "$PLINK_LOG"
}

@test "switch alias: switch.fi" {
  run_dispatcher switch.fi; grep -q "fake_plink" "$PLINK_LOG"
}

@test "poeswitch alias: poeswitch" {
  run_dispatcher poeswitch; grep -q "fake_plink" "$PLINK_LOG"
}

@test "poeswitch alias: poeswitch.local" {
  run_dispatcher poeswitch.local; grep -q "fake_plink" "$PLINK_LOG"
}

@test "poeswitch alias: 172.17.17.2" {
  run_dispatcher 172.17.17.2; grep -q "fake_plink" "$PLINK_LOG"
}

@test "poeswitch alias: poeswitch.fi" {
  run_dispatcher poeswitch.fi; grep -q "fake_plink" "$PLINK_LOG"
}

# ── Argument parsing ──────────────────────────────────────────────────────────

@test "user@host syntax extracts host correctly" {
  run_dispatcher admin@switch
  grep -q "fake_plink" "$PLINK_LOG"
  grep -q "admin@switch" "$PLINK_LOG"
}

@test "-p port flag is passed to plink as -P" {
  run_dispatcher -p 2222 switch
  grep -q "\-P 2222" "$PLINK_LOG"
}

@test "-l user flag sets user for plink" {
  run_dispatcher -l marc switch
  grep -q "marc@switch" "$PLINK_LOG"
}

# ── IdentityFile / .ppk sibling resolution ────────────────────────────────────

@test "ppk sibling found: -i passed to plink" {
  # Write a config stanza for a test host
  cat > "$FAKE_HOME/.ssh/config" <<EOF
Host ppkhost
    HostName 10.0.0.99
    User admin
    IdentityFile $FAKE_HOME/.ssh/switch_key
    # HostKeyAlgorithms +ssh-dss
EOF
  # Create fake ssh -G output pointing to the key
  cat > "$FIXTURES/ssh_G_ppkhost" <<EOF
user admin
port 22
identityfile $FAKE_HOME/.ssh/switch_key
EOF
  # Create the .ppk sibling
  touch "$FAKE_HOME/.ssh/switch_key.ppk"

  run_dispatcher ppkhost
  rm -f "$FIXTURES/ssh_G_ppkhost"

  grep -q "\-i.*switch_key\.ppk" "$PLINK_LOG"
}

@test "no ppk sibling: -i not passed to plink" {
  cat > "$FAKE_HOME/.ssh/config" <<EOF
Host noppkhost
    HostName 10.0.0.98
    User admin
    IdentityFile $FAKE_HOME/.ssh/no_key_here
    # HostKeyAlgorithms +ssh-dss
EOF
  cat > "$FIXTURES/ssh_G_noppkhost" <<EOF
user admin
port 22
identityfile $FAKE_HOME/.ssh/no_key_here
EOF
  run_dispatcher noppkhost
  rm -f "$FIXTURES/ssh_G_noppkhost"

  ! grep -q "\-i" "$PLINK_LOG"
}

# ── Error path: plink missing ─────────────────────────────────────────────────

@test "missing plink produces error and exits 1" {
  HOME="$FAKE_HOME" \
  SSHDISPATCHER_SSH="$FAKE_SSH" \
  SSHDISPATCHER_PLINK="" \
  FAKE_SSH_LOG="$SSH_LOG" \
  FAKE_PLINK_LOG="$PLINK_LOG" \
  run "$DISPATCHER" switch

  [ "$status" -eq 1 ]
  [[ "$output" == *"plink not found"* ]]
}
