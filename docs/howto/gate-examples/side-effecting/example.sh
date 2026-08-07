# Weakness: a gate that WRITES its own evidence (a side effect) instead of reading the
# artifact — so it grades its own homework and passes regardless of the real work. The
# auditor flags this as side_effecting. Property mode.
prove(){
  weak(){ echo "status=ok" > result.txt; grep -q ok result.txt; }  # writes then greps itself
  strong(){ grep -q ok out.txt; }                                  # reads only the artifact

  # With FAILING work present, the side-effecting gate still "passes"...
  echo fail > out.txt; rm -f result.txt
  weak || return 1                       # wrongly passes
  [ -f result.txt ] || return 1          # ...and it mutated the workspace

  # ...while the behavioral gate correctly FAILS on the same failing work.
  rm -f result.txt
  strong && return 1

  # On real work the behavioral gate passes and leaves the workspace unchanged.
  echo ok > out.txt
  before=$(ls -A | sort)
  strong || return 1
  after=$(ls -A | sort)
  [ "$before" = "$after" ]
}
