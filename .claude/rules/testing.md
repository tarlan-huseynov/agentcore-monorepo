---
paths:
  - "tests/**/*.py"
---

# Testing Conventions

- Run tests: `uv run pytest tests/ -v`
- All tests use `unittest.mock` -- no live API calls
- Test pure business-logic helpers (`_get_weather`, `_get_time`, `_get_joke`) directly
- Test `@tool` wrappers via mock `ToolContext` with `invocation_state`
- Test orchestrator with mocked `Agent` and `create_model`
