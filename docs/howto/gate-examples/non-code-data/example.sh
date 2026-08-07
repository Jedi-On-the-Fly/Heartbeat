# Weakness (non-code deliverable): gating a DATASET on "the file is non-empty" instead of
# on its shape. A header-only CSV is non-empty but carries no data.
# Task: data.csv must have columns id,email and at least one row with a valid email.
setup_stub(){ printf 'id,email\n' > data.csv; }                         # header only, no rows
setup_real(){ printf 'id,email\n1,ada@x.io\n2,bob@y.io\n' > data.csv; }
weak_gate(){ test -s data.csv; }                                        # non-empty -> fooled by the stub
strong_gate(){ python3 -c "import csv,sys; r=list(csv.DictReader(open('data.csv'))); sys.exit(0 if r and set(r[0].keys())=={'id','email'} and all('@' in (x['email'] or '') for x in r) else 1)"; }
