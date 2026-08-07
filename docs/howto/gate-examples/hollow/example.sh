# Weakness: a hollow gate that asserts nothing (true, or a check that can't fail).
# Task: the build must report tests PASSED in build.log.
setup_stub(){ echo "tests failed" > build.log; }   # lazy: the run did not pass
setup_real(){ echo "tests passed" > build.log; }
weak_gate(){ true; }                                # asserts nothing at all
strong_gate(){ grep -q "tests passed" build.log; }  # asserts the actual outcome
