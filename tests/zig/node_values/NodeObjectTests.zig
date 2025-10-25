const std = @import("std");
const node_api = @import("node-api");

const NodeContext = node_api.NodeContext;
const NodeValue = node_api.NodeValue;
const NodeObject = node_api.NodeObject;
const NodeArray = node_api.NodeArray;

pub fn init() @This() {
    return @This(){};
}

// TODO: make this optional
pub fn deinit() !void {}

pub fn has(obj: NodeObject) !bool {
    return try obj.has("prop");
}

pub fn hasOwn(obj: NodeObject) !bool {
    return try obj.hasOwn("prop");
}

pub fn get(obj: NodeObject) !NodeValue {
    return try obj.get("prop");
}

pub fn set(obj: NodeObject, v: NodeValue) !NodeValue {
    return try obj.set("prop", v);
}

pub fn delete(obj: NodeObject) !bool {
    return try obj.delete("prop");
}

pub fn getPropertyNames(obj: NodeObject) !NodeArray {
    return try obj.getPropertyNames();
}
