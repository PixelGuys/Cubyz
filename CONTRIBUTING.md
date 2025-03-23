# About this document

This document contains a set of guidelines to help you contribute to Cubyz in a smooth and efficient manner.

Making a pull requests that go through multiple rounds of reviews before getting merged is annoying for everyone involved.

The sections are roughly sorted by the time you'll encounter them, starting before selecting what to work on and ending after you made your pull request.

I'd recommend to check out the [Discord Server](https://discord.gg/XtqCRRG) if you have any further questions.

# Learn Zig

Kind of obvious, but still important: https://ziglang.org/learn/

If you are new to Zig it can also be very helpful to ask questions. For example, if something feels annoying to write, then you might be missing knowledge about better approaches. Asking a question is usually faster than writing 100 lines of cumbersome code (and it saves a review cycle).

# Disable Zig's automatic formatter

Cubyz uses a slightly modified version of `zig fmt` which uses tabs and behaves slightly different in regards to spacing.
Because of that, if you use the the default Zig formatter it will reformat all your files.

To fix this you need to disable zig's formatter (In VSCode you can disable this in the Zig extension settings).

To run the formatter locally on a specific file, you can use `./compiler/zig/zig build fmt -- fileName.zig`.

# Select something to work on

The best way to start is obviously the issues tab. The issues are organized with labels (most importantly the Contributor friendly label) and milestones, so it should be easy to find something.

But of course the ever-growing list of issues is not complete and other changes are welcome as well, as long as they are not going in a completely different direction. And also make sure to explain what you are trying to do in the pull request description.

You might also find some ideas on [Discord](https://discord.gg/XtqCRRG).

# Start ₛₘₐₗₗ

Especially as a first time contributor it is likely that your code is not meeting the standards of Cubyz. This is totally normal, but obviously it means that your changes will go through more review cycles.

To have more success it would help to split things up into smaller PRs, maybe start by doing some preliminary changes leading up to feature, for example you could start by just introducing some new utility functions you will need for the actual feature. And of course it can be helpful to ask first if you are even going in the right direction.

This saves time on your end spent reworking your large pull request 10 times. And reviewing your large pull request 10 times is also not fun.

# Write correct, readable and maintainable code

## Explicitly handle all errors (except from those that can't happen)

Error handling usually means logging the error and continuing with a sensible default. For example if you can't read a file, then the best solution would be to write a message to `std.log.err` that states the file path and the error string. It is also fine to bubble up the error with `try` a few levels before handling it.

Not all errors can happen. Specifically in Cubyz the `error.OutOfMemory` cannot happen with the standard allocators (`main.globalAllocator` and `main.stackAllocator`). In this case `catch unreachable` is the right way to handle the error.

## Choose the right allocator for the job

Cubyz has two main allocators.
- The `main.stackAllocator` is a thread-local allocator that is optimized for local allocations. Use for anything that you free at the end of the scope. An example use-case would be a local `List`.
- The `main.globalAllocator` is intended to be used for general purpose use cases that don't need to or can't be particularly optimized.

Sometimes it might also make sense to use an arena allocator `utils.NeverFailingArenaAllocator`, or a `MemoryPool`. But generally these should only be used where it makes sense.

Also it is important to note that Cubyz uses a different allocator interface `utils.NeverFailingAllocator` which cannot return `error.OutOfMemory`. Along with it come some data structures like `main.List` and more in `utils` which should be preferred over the standard library data structures because they simplify the code.

## Free all resources

Everything you allocate, needs to be freed.
Everything you init needs to be deinited.
Everything you lock needs to be unlocked.
This needs to be true even for error paths such as introduced by `try`.
Usually you should be fine by using `defer` and `errdefer`. There is also leak-checking in debug mode, so make sure you test your feature in debug mode to check for leaks.

## Keep it simple

Often the simplest code is easier to read, easier to maintain and more efficient too.
- Don't add generic interfaces for things that don't need them (now). (unless you are certain that you will need them of course)
- Use syntax sugar of the language where applicable (like `catch`, `orelse`, `for`, `.{}`, `&.{}`, `inline` case, decl literals)
- If you use the same segment of code multiple times, then it's time to make a helper function
- If a thing already exists in the code base or the standard library, then use it. Noteworthy namespaces are `std.mem`, `std.meta`, `std.math`, `main.utils`.

## Follow the style guide

Most of the syntax is handled by a modified version of zig fmt and checked by the CI (see the formatting section above).

There are a few more things not covered by the formatter:
- **Naming conventions:** camelCase for variables, constants and functions; CapitalCamelCase for types
- **Line limit:** There is no line limit (I hate seeing code that gets wrapped over by 1 word, because of an arbitrary line limit), but of course try to be reasonable. If you need 200 characters, then you should probably consider splitting it or adding some well-named helper variables.
- **Comments:** Don't write comments, unless there is something non-obvious going on that needs to be explained.<br>
  But in either case it's better to write readable code with descriptive names, instead of writing long comments, since comments will naturally degrade over time as the surrounding code changes.
- **Imports:** Import aliasing is nice (if only ZLS would support it). But please don't import/alias functions. If I see a function then knowing where it's from adds some more context. And if there are no aliases then I can assume that a bare function name is defined locally.
- **Files as Structs:** Don't use files as struct unless you have a good reason for it. I've tried it a few times, but generally I don't think it really adds much and in larger files it can be rather confusing.
- **File/Directory organization:** Generally try to split things off that are unrelated, and keep things together that are directly interacting with each other. In my opinion the sweet spot for file size is (very roughly) 1000 lines.<br>
  Instances of a generic interfaces (e.g. GuiWindow, *Generator, Command) should be put into separate files in one directory, since they usually don't have anything in common other than their interface.
- **Order of Declarations:** Generally I prefer seeing things (helper functions and variables) declared before they are used, as is required in languages like C and C++. However I don't really have a strong opinion on this.
  What matters most in my opinion is that related things are close together (e.g. init next to deinit, serialize next to deserialize, helper functions next to where they are used).

# Don't put multiple changes into one pull request

It may seem tempting to bundle up somewhat related features into one pull request. But this often causes unnecessary delays.

Let's say you have 3 features and made a small mistake in one of them.

If you bundle up all 3 features, then because of your small mistake, a review cycle is needed.
But by the time you fixed the mistake, maybe someone else worked on a file you touched and there are merge conflicts. The more changes you bundle into one PR the more likely it is that this happens. This is especially bad if one of your actions is refactoring a bunch of code.
And even if it doesn't happen, now the same code has to be reviewed again in it's entirety.

If instead you make 3 separate PRs, the first two can be merged on the same day, while the last one needs to be edited. The chances of a merge conflict are small, since 2/3 changes are already merged. And code review is also easier, since only the broken code has to be reviewed more than once.

# Check the changes after creating your pull request

With a quick check you can ensure that you didn't add any unintended changes.

With a more thorough review of your changes you can sometimes catch small mistakes, leftover TODOs or random debug code.

And of course make sure to check the CI results, you should also get an e-mail notification if the CI fails.

