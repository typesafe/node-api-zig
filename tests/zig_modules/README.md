The `zig_modules` folder contains a folder per test zig module.

`/tests/zig_modules/{mod}/src/root.zig`

is compiled to

`/test/zig_modules/{mod}.node`

and can be imported in a test using:

```TypeScript
import requireTestModule from "../";

const addon = requireTestModule("{mod}");

```
