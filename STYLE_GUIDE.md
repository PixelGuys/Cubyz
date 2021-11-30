In any open source project it is important that all contributors use the same coding style. Otherwise the code ends up being a big mess.

Therefor we agreed on a few simple rules:
# Naming
### Variables and functions
`camelCase`<br>
With the exception of global constants(`static final`):<br>
`UPPERCASE_WITH_UNDERSCORE`
### packages
`lowercase_with_underscore`
### Class names
`CapitalCamelCase`
# Spacing
- Spaces or newline after `,` and `;`
- Spaces between `if`, `for`, `while`, … and `(`
- Spaces before and after binary operators `a = b + c * d;`
- No spaces around unary operators `a = ~b + c * -d`
- Spaces in type casting: `(int) var`
# `{}`
- `{` at the end of the line with a space before it
- `} else {` and `} catch {`
- `{}` may be removed if it encapsulates only a single statement
# Others
- Tabs for Indentation, Spaces for alignment.
- `public`/`protected`/`private` before `static` before `final`


# Example
```
package cubyz.conventions_example;

public class ConventionsHelloWorld {
	public static final float SOME_CONSTANT = 1.05f;

	public static void main(String[] argumentsName) {
		int x = -1
		if (x < SOME_CONSTANT) {
			x = (int) (-x + 5 * SOME_CONSTANT);
		}
	}
}
```

