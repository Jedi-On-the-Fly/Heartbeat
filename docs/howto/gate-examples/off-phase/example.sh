# Weakness: a phase's gate checks a DIFFERENT phase's artifact, so it passes before
# this phase's work is even done. The auditor flags this as gate_offphase. Property mode.
prove(){
  echo ok1 > out1.txt        # artifact left behind by an EARLIER phase

  weak(){ grep -q ok1 out1.txt; }                 # checks the prior phase's file
  strong(){ grep -q ok2 out2.txt 2>/dev/null; }   # checks THIS phase's file

  # This phase is not done yet (out2.txt absent):
  weak || return 1           # weak wrongly passes (the prior artifact is present)
  strong && return 1         # strong correctly fails

  # Now this phase is really done:
  echo ok2 > out2.txt
  strong                     # strong passes
}
