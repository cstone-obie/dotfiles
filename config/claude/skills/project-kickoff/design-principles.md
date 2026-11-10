# Design principles

Used when writing or reviewing code, by the main session and by the `reviewer`
and `researcher` subagents. They apply to the new code and to the established
code around it. The question behind every item: will someone new to this area
understand what it does, why it was done this way, and how to change it?

## Does it solve the right problem?

- Does it meet the need behind the ticket, not just its literal wording? If the
  ticket seems to ask for the wrong thing for the business, raise it as a
  question. Don't decide it yourself.
- Is there a simpler way to get the same result? Less code, fewer moving parts,
  or an existing helper that already does it.

## Change scenarios

Name one or two changes the business is likely to want next, based on the
ticket, its comments, linked issues, and how this area has changed in
`git log`. For each one, say what would have to be rewritten.

```
If we add a second payment provider: PaymentForm, chargeCard(), and the
receipts job all call Stripe directly → three rewrites. A PaymentProvider
interface would make it one new class.
```

Plan for likely changes, not every imaginable one. If the extra structure is
for a change nobody expects, the simpler version wins.

## Structure

- **One job per unit.** Each function, class, and module does one thing.
  Something you'd describe with "and" (validates and saves and emails) should
  be split.
- **Cohesion.** Code that changes together lives together. A module shouldn't be
  a grab-bag of unrelated helpers.
- **Low coupling.** Modules depend on small, clear interfaces, not on each
  other's internals. Changing one shouldn't force edits in several others.
- **Composition over inheritance.** Build behavior from small parts passed in,
  rather than deep class hierarchies.
- **SOLID, where it helps.** Mostly in class-based or service code with real
  variation. Don't add interfaces or factories that have only one
  implementation and no expected second one.
- **Follow the repo first, then industry practice.** A well-known pattern
  (repository, adapter, strategy) beats a custom one. An established
  convention in this repo beats either, unless the convention is the problem.

## Naming

- Names say what something is or does, in business terms: `renewalDueDate`,
  not `d2` or `dateHelper`.
- One name per concept across the codebase. Don't call it `policy` in one
  place and `contract` in another.
- Booleans read as questions: `isExpired`, `hasOpenClaim`.
- If a name needs a comment to explain it, rename it.

## Tests

- Tests come first: write a failing test, then the code that makes it pass.
  For a bug, the first test reproduces it and fails before the fix.
- Every behavior the change adds or alters has a test, including each edge case
  and error path, not just the happy path.
- Tests check behavior through public interfaces, not private details, so a
  refactor doesn't break them.
- Code you change that has no tests gets them as part of the change.
- A test name says the behavior: `rejects renewal after policy expiry`, not
  `test renewal 2`.

## TypeScript types

```ts
// Weak: any input passes, and a missing field crashes at runtime.
function premium(policy: any) { return policy.rate! * 12 }

// Strong: the compiler catches a missing rate, and every status is handled.
type Policy =
  | { status: 'active'; rate: number }
  | { status: 'cancelled'; cancelledAt: Date }

function premium(policy: Policy): number {
  switch (policy.status) {
    case 'active': return policy.rate * 12
    case 'cancelled': return 0
    default: return assertNever(policy)
  }
}
```

- No `any`. Use `unknown` and narrow it, or write the real type.
- No `as` casts or non-null `!` without a comment saying why it's safe. Never
  use them to silence a compile error.
- Model states as discriminated unions rather than one object full of optional
  fields, and make `switch` statements exhaustive.
- Validate data at the edges (API input, third-party responses, JSON from the
  database) and type it from then on.
- Use generated types (GraphQL codegen, ORM models) instead of hand-copied
  ones.
- Never loosen a type, or add `@ts-ignore` / `@ts-expect-error`, just to make
  something compile.
- Typecheck passes before the work is called done.

## Readability

- A reader can follow the main path without jumping through many files.
- Anything surprising (a workaround, an order that matters, a business rule)
  has a short comment saying why.

## Surrounding code

Judge the code next to the change (same files, same directory, direct imports,
their tests) by everything above, not just the new lines.

- **Fix now** if it's in a file you're already changing, roughly under 30
  lines, doesn't change behavior outside the task, and is covered by tests.
- **Propose a ticket** for anything bigger, riskier, or off the task's focus.
  Write a title, a short description, and the `path:line` locations. Don't
  create the ticket unless the user says yes.

```
Fix now:          rename `d2` → `renewalDueDate` in the function you're editing
Propose a ticket: three services each parse policy dates their own way
```
