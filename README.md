The `node-api` module provides [Node-API](https://nodejs.org/api/n-api.html) bindings for writing idiomatic Zig addons
for V8-based runtimes like Node.JS or Bun. Thanks to its conventions-based approach it bridges the gap seamlessly, 
with almost no Node-API specific code!

![build-badge](https://img.shields.io/github/actions/workflow/status/typesafe/node-api-zig/ci.yml)
![test-badge](https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2Ftypesafe%2F26882516c7ac38bf94a81784f966bd86%2Fraw%2Fnode-api-zig-test-badge.json)

## Key Features

- **function mapping**, including async support (auto-conversion to Promises)
- **class mapping**, incl. support for fields, instance (async) methods and satic (async) methods.
- **wrapping/unwrapping** of native objects instances
- **memory management** with convention-based `init`, `deinit` support & `allocator` injection
- **error handling** with `errorunion` support
- Convention-base **type conversion**
  - **by value**: through (de)serialization or various types with automatic memory management
  - **by reference**:
    - Zig-managed values: through pointers to (wrapped) native Zig values
    - JS-managed values: through wrappers types (`NodeValue` et.al.) for read/write
  - **type-safe callbacks**: `NodeFunction(fn (u32, u32) !u32)`

## Getting started

Install the `node_api` (note the underscore) dependency

```sh
> zig fetch --save https://github.com/typesafe/node-api-zig/archive/refs/tags/v0.0.4-beta.tar.gz
```

Add the `node-api` module to your library:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const node_api = b.dependency("node_api", .{});
    mod.addImport("node-api", node_api.module("node-api"));

    const lib = b.addLibrary(.{
        // if Linux
        .use_llvm = true,
        .name = "my-native-node-module",
        .root_module = mod,
    });

    b.installArtifact(lib);
}
```

Initialize your Node-API extension:

```zig
const node_api = @import("node-api");

comptime {
    // export encrypt function (or types, or values or pointers)
    node_api.@"export"(.{ 
      .encrypt = encrypt,
      // ...
    });
}

fn encrypt(
    // serialized from JS string, borrowed memory
    value: []const u8,
    // serialized from JS object by value (use *Options for wrapped native instances)
    options: Options,
    // "injected" by convention, any memory allocated with it is freed after returning to JS
    allocator: std.mem.Allocator,
) ![]const u8 {
    const res = allocator.alloc(u8, 123);

    // ...

    return res; // freed by node-api
}
```

Use your library as node module:

```TypeScript
import { createRequire } from "module";
const require = createRequire(import.meta.url);

const { encrypt } = require("my-native-node-module.node");

const m = encrypt("secret", { salt: "..." });

```

## Features

### Module Initialization

There are 2 options to initialize a module:

- `node_api.@"export"`: conveniant for exporting comptime values, which is very likely
- `node_api.init(fn (node: NodeContext) !NodeValue)`: for exporting runtime values


```Zig
comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    // init & return `exports` value/object/function
}
```

### NodeContext

The `node_api.init` initialization function as well as any 



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
