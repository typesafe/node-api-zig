const node_api = @import("node-api");
const TestClass = @import("TestClass.zig");

comptime {
    node_api.@"export"(TestClass);
}
