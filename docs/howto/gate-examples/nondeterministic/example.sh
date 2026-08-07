# Weakness: a gate whose verdict depends on something OTHER than the artifact (here
# $RANDOM), so it is flaky — it can pass without the behavior holding, and a phase
# can advance on a coin flip. Property mode.
prove(){
  echo greeting > out.txt
  weak(){ [ $(( RANDOM % 2 )) -eq 0 ]; }   # verdict unrelated to out.txt
  strong(){ grep -q greeting out.txt; }    # depends only on the artifact

  # The behavioral gate is STABLE: same artifact -> same verdict, every time.
  strong && strong && strong && strong && strong || return 1

  # The flaky gate yields BOTH verdicts on the SAME unchanged artifact.
  s0=0; s1=0
  for _ in $(seq 1 50); do if weak; then s1=1; else s0=1; fi; done
  [ "$s0" = 1 ] && [ "$s1" = 1 ]
}
