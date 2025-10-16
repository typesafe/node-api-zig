The `node-api` Zig package provides [Node-API](https://nodejs.org/api/n-api.html) bindings for writing idiomatic Zig add-ons for V8 runtimes like Node.JS or Bun.

The module relies heavily on conventions to simplify memory & lifetime management, async processing, type conversions, etc.

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

## Define functions

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



