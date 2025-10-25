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

pub fn len(arr: NodeArray) !u32 {
    return try arr.len();
}

pub fn get(arr: NodeArray, index: u32) !NodeValue {
    return try arr.get(index);
}

pub fn set(arr: NodeArray, index: u32, v: NodeValue) !NodeValue {
    return try arr.set(index, v);
}
