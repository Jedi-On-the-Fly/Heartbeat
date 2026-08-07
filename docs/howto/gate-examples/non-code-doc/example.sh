# Weakness (non-code deliverable): gating a DOCUMENT on the presence of a heading instead
# of on real content. The stub has the section but fills it with a placeholder.
# Task: report.md must contain a Recommendation section with an actual recommendation.
setup_stub(){ printf '# Report\n\n## Recommendation\n\nTODO: fill in\n' > report.md; }
setup_real(){ printf '# Report\n\n## Recommendation\n\nAdopt option B: it halves p95 latency at no extra cost.\n' > report.md; }
weak_gate(){ grep -q '## Recommendation' report.md; }   # the heading exists -> fooled by the stub
strong_gate(){
  # body = lines under "## Recommendation" up to the next "## " heading
  body=$(awk '/^## /{f=0} /^## Recommendation$/{f=1; next} f{print}' report.md)
  printf '%s' "$body" | grep -q '[A-Za-z]' && ! printf '%s' "$body" | grep -qiE '\b(TODO|TBD|placeholder|fill in)\b'
}
