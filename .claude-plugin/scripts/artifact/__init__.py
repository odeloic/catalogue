"""catalogue artifact renderer.

All artifact markup and CSS live in this package — change the look here once and
every catalogue skill's output follows. Pure stdlib, no external dependencies.

  tokens.css   design-system contract (shared verbatim with the Storybook repo)
  styles.css   component styles (plain-CSS twin of the Storybook CSS Modules)
  components   HTML-string builders
  kinds        per-artifact renderers (triage/review/bugfix/plan/explain)
  page         document shell + inlined CSS
  __main__     CLI: JSON envelope -> HTML file -> open
"""

from .page import render_page

__all__ = ["render_page"]
