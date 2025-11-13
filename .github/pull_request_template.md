## What does this PR change?

## If not already covered by an issue (specified below), what is the motivation for the change(s) in this PR?

## What issues does this PR resolve? (Add as many as are applicable)
### Example: Fixes #12345
- Fixes #
- Fixes #

## What design decisions did you make to develop your solution ? Why did you make those choices?
 - If this change required refactoring existing code, explain why it needed to be refactored. What limitation are you resolving with the refactor?

## If this change is something the users will notice, please write a one-sentence description of this change so it may be used in a changelog:

## Checklist before submitting the PR:
- [ ] Please read the contributing guidelines document and ensure your changes are in compliance with those guidelines.
- [ ] Are there any open pull requests that resolve the same issue? If so, mention them in this PR. Multiple approaches are welcomed as the one that is liked most will be selected.
- [ ] Please run the cubyz formatter on your changes to ensure formatting consistency
    - The CI will catch this if you don't
- [ ] Make sure your PR is named appropriately to describe the change briefly. No "fix #12345" etc, please.
- [ ] Did you remove an old item/block/biome/etc? Please add a migration in the appropriate `_migrations.zig.zon` to smoothly migrate existing worldsto your new change.
- [ ] Have you tested your change?
    - [ ] Make sure the game opens and you can join a world
    - [ ] Analyze your change and determine which features it impacts. Make sure your change does not cause those features to break.
    - [ ] Did you modify or add any static functions? (i.e. data in -> data out, no out-of-scope variables touched) If so, please write a test for those functions you've changed/added.

