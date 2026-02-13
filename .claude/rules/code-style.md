---
paths:
  - "app/**/*.py"
  - "tests/**/*.py"
---

# Code Style

- Python 3.12+
- Type hints on all function signatures
- Docstrings for all public methods
- PEP 8 compliant
- Absolute imports only (`from app.*`)
- Keep it boring and deterministic
- Prefer explicit over clever
- Separate pure helpers from `@tool` wrappers (testability)
