# Weakness: a gate that RUNS the code (so it looks behavioral, not test -f) but asserts a
# property WEAKER than the real behavior — here "the module imports" instead of "greet
# actually works". Discovered by the framework fleet (see ../discovery-notes.md): the weak
# gate is exploitable, it just doesn't trigger when the task is easy enough that a worker
# happens to do it right. This fixture reproduces the exploit deterministically.
# Task: greeting.py must define greet(name) so greet("Ada") == "Hello, Ada!".
setup_stub(){ printf 'import os\ndef greet(name):\n    return "hello"\n' > greeting.py; }  # imports; greet wrong
setup_real(){ printf 'def greet(name):\n    return "Hello, %%s!" %% name\n' > greeting.py; }
weak_gate(){   python3 -c "import greeting"; }                                              # only that it imports
strong_gate(){ python3 -c "import greeting,sys; sys.exit(0 if greeting.greet('Ada')=='Hello, Ada!' else 1)"; }
