# Weakness: a coverage gate that greps a test suite's group HEADER (which prints even
# when that group is RED) instead of asserting the group actually PASSED. This is the
# exact hole the v1.16 GROUPS-PASSED marker closed.
# Task: group T7 of the suite must pass.
setup_stub(){ cat > runtests.sh <<'SH'
echo "=== T7 - feature ==="      # the header prints even though T7 is red
echo "  x T7.1 broken"
echo "GROUPS-PASSED: T6 T8 "      # T7 is excluded: it failed
SH
}
setup_real(){ cat > runtests.sh <<'SH'
echo "=== T7 - feature ==="
echo "  ok T7.1"
echo "GROUPS-PASSED: T6 T7 T8 "
SH
}
weak_gate(){ bash runtests.sh 2>&1 | grep -q 'T7'; }                     # header grep: fooled
strong_gate(){ bash runtests.sh 2>&1 | grep -q 'GROUPS-PASSED:.* T7 '; } # asserts T7 PASSED
