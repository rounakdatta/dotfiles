# Example Claude Skill

This is an example skill file that demonstrates the format.

## Purpose

Skill files provide context, guidelines, or reference information that Claude can use when helping you with tasks.

## When to Use Skills

- **Coding Standards**: Team or personal coding conventions
- **Project Context**: Architecture decisions, design patterns used
- **Domain Knowledge**: Specific terminology or business logic
- **Workflows**: Preferred development or deployment workflows
- **Private Information**: API details, internal systems (use private repo for these!)

## Format Tips

- Use clear, descriptive headings
- Provide examples where helpful
- Keep information current and relevant
- Use markdown for formatting

## Example Content

Here's what a skill might contain:

### Preferred Testing Approach

When writing tests in this project:
- Use descriptive test names that explain the scenario
- Follow Arrange-Act-Assert pattern
- Mock external dependencies
- Aim for high coverage of critical paths

### Code Review Checklist

Before submitting PRs:
- [ ] All tests passing
- [ ] No commented-out code
- [ ] Updated documentation
- [ ] Followed project naming conventions
