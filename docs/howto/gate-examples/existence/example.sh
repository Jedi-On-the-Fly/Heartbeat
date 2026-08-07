# Weakness: asserting a file EXISTS instead of that its contents are correct.
# Task: write config.json with port 8080.
setup_stub(){ echo "oops, not json" > config.json; }   # file exists, content wrong
setup_real(){ echo '{"port":8080}' > config.json; }
weak_gate(){ test -f config.json; }                     # exists -> fooled by the stub
strong_gate(){ python3 -c "import json,sys; sys.exit(0 if json.load(open('config.json')).get('port')==8080 else 1)"; }
