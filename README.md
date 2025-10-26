The `node-api` Zig package provides [Node-API](https://nodejs.org/api/n-api.html) bindings for writing idiomatic Zig addons for V8-based runtimes like Node.JS or Bun.
Thanks to its conventions-based approach it bridges the gap seamlessly, with almost no Node-API specific code!

![build-badge](https://img.shields.io/github/actions/workflow/status/typesafe/node-api-zig/ci.yml)
![test-badge](https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2Ftypesafe%2F26882516c7ac38bf94a81784f966bd86%2Fraw%2Fnode-api-zig-test-badge.json)

```zig
const node_api = @import("node-api");
const Options = @import("Options");

comptime {
    // or node_api.init(fn (node) NodeValue) for runtime values
    node_api.@"export"(encrypt);
}

fn encrypt(value: []const u8, options: Options, allocator: std.mem.Allocator) ![]const u8 {
    const res = allocator.alloc(u8, 123);
    errdefer allocator.free(res);

    // ...

    return res; // freed by node-api
}

```

```TypeScript
import { createRequire } from "module";
const require = createRequire(import.meta.url);

const encrypt = require("zig-module.node");

// call zig function
const m = encrypt("secret", { salt: "..."});

```

TODO:

- [ ] auto-register class for members of type `type`.
- [ ] Make `NodeFunction` thread safe by convention when it is used in an async function/method.
- [ ] Add `NodeObject` for "by reference" access to JS objects from Zig
- [ ] Add `NodeArray` for "by reference" access to JS objects from Zig
- [ ] Add support for externals
  - [ ] `External`
  - [ ] `ExternalBuffer`
  - [ ] `ExternalArrayBuffer`
- [ ] Use `Result(T, E)` as alternative to `errorunion`s for improved error messages.

# Features

- **function mapping**, including async support (auto-conversion to Promises)
- **class mapping**, incl. support for fields, instance methods, satic methods
- **auto-wrapping** of native objects instances, similar to defining classes but for instances created in native Zig code
- **memory management** with convention-based `init`, `deinit` support & `allocator` injection
- `errorunion` support
- mapping JS values
  - by value: through (de)serialization or various types
  - by reference
    - Zig-managed values: through pointers to (wrapped) native Zig values
    - JS-managed values: through wrappers types (`NodeValue` et.al.) for read/write
  - typesafe callbacks: `NodeFunction(fn (u32, u32) !u32)`

# Getting started

TODO

# Features

## Initialize Module

Call the `node_api.register` method at compile time:

```Zig
comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    // init & return `exports` value/object/function
}
```

```TypeScript
// `fromZig` = return value of `init` above.
import fromZig from(zig-module.node);
```

## Type Conversions

Struct types, functions, fields, parameters and return values are all converted by convention.
Unsupported types result in compile errors.

| Native type          | Node type             | Remarks                                                                                                                                         |
| -------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `type`               | `Class` or `Function` | Returning or passing a struct `type` to JS, turns it into a class.<br>Returning or passing a `fn`, turns it into a JS-callable, well, function. |
| `i32`,`i64`,`u32`    | `number`              |                                                                                                                                                 |
| `u64`                | `BigInt`              |                                                                                                                                                 |
| `[]const u8`, `[]u8` | `string`              | UTF-8                                                                                                                                           |
| `[]const T`, `[]T`   | `array`               |                                                                                                                                                 |
| `*T`                 | `Object`              | Passing struct pointers to JS will wrap & track them.                                                                                           |
| `NodeValue`          | `any`                 | NodeValue can be used to access JS values by reference.                                                                                         |

Function parameters and return types can be

- native Zig types (unsupported types will result in compile time errors)
- one of the NodeValue types to access values by reference.

Native values and NodeValue instance can be converted using `Convert`:

- `nativeFromNode(comptime T: type, value: NodeValue, allocator. Allocator) T`
- `nodeFromNative(value: anytype) NodeValue`

## Define functions

Arguments can be of type:

- NodeContext => will result in the injection of the current NodeContext
- allocator => will inject the (arean) allocator for the current invocation, memory is freed after returning
- native Zig type => will be deserialized
- pointer => will return the native instance of a wrapped object
- optional
- enum
- NodeXxx values for references

## Define async functions

## Define classes

`node.defineClass` transforms a Zig struct to a JS-accessible class by convention:

```zig

comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    // epo
    return try node.serialize(.{
        .MyClass = try node.defineClass(MyClass),
    });
}

const MyClass = struct {
    Self = @This();

    field1: i32,
    field2: ?[]u8,

    pub fn init() Self {
        return .{ .field1 = 0, .field2 = null };
    }

    pub fn method1(self: Self, v: i32) !void {

    }

 }

```

### Contstructors

`init` maps to `new`.

### Function parameters

- parameters of type Self work as expected, they come from the unwrapped JS value
- you can inject the current NodeContext, simply by adding a parameter of that type
- you can pass NodeValue, NodeObject, NodeArray values parameters for by-ref semantics
- you can declare Zig types as parameters, these result in a deserialized copy
  - note that parameters that require memory allocation will be owned by the class instance (see below)

## Wrap objects

## Memory management

- class instances are allocated and freed automatically
  - new-ing instance (from JS) will allocate memory (and update V8 stats)
  - GC finalizers will automatically free the memory (and update V8 stats)
- Zig type arguments that require allocations are "owned by the instance"
  - when the are store as field values the will be freed as part of the finalization process
    - existing field values must be freed manually when they are overwritten!

/\*

Scenarios:

native (wrapped) instance lifecycle:

- new in JS -> finalize in Zig
- create in Zig -> finalize in Zig

external instance memory:

- arena per instance?
- managed by instance if instance has allocator field

parameters and return values:

- pointers to structs result in uwrapped values
- parameters and return type memory
  - arena per function call

setting field values

- frees previous value, if any

  \*/
