const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;

const Self = @This();

env: c.napi_env,
base_allocator: std.mem.Allocator,
total_allocated: usize,
allocation_count: usize,

pub fn init(env: c.napi_env) Self {
    return Self{
        .env = env,
        .base_allocator = std.heap.c_allocator,
        .total_allocated = 0,
        .allocation_count = 0,
    };
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return std.mem.Allocator{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const result = self.base_allocator.rawAlloc(len, log2_ptr_align, ret_addr);

    if (result != null) {
        // Update tracking
        self.total_allocated += len;
        self.allocation_count += 1;

        // Notify Node.js about external memory usage
        _ = c.napi_adjust_external_memory(self.env, @intCast(len), null);

        std.log.debug("NodeAllocator: allocated {} bytes (total: {}, count: {})", .{ len, self.total_allocated, self.allocation_count });
    } else {
        std.log.err("NodeAllocator: failed to allocate {} bytes", .{len});
    }

    return result;
}

fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const old_len = buf.len;
    const success = self.base_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);

    if (success) {
        // Update tracking
        if (new_len > old_len) {
            const diff = new_len - old_len;
            self.total_allocated += diff;
            _ = c.napi_adjust_external_memory(self.env, @intCast(diff), null);
            std.log.debug("NodeAllocator: resized +{} bytes (total: {})", .{ diff, self.total_allocated });
        } else if (new_len < old_len) {
            const diff = old_len - new_len;
            self.total_allocated -= diff;
            _ = c.napi_adjust_external_memory(self.env, -@as(i64, @intCast(diff)), null);
            std.log.debug("NodeAllocator: resized -{} bytes (total: {})", .{ diff, self.total_allocated });
        }
    }

    return success;
}

fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const len = buf.len;

    // Update tracking
    self.total_allocated -= len;
    self.allocation_count -= 1;

    // Notify Node.js about freed memory
    _ = c.napi_adjust_external_memory(self.env, -@as(i64, @intCast(len)), null);

    std.log.debug("NodeAllocator: freed {} bytes (total: {}, count: {})", .{ len, self.total_allocated, self.allocation_count });

    self.base_allocator.rawFree(buf, log2_buf_align, ret_addr);
}

/// Create a typed pointer and track its allocation
pub fn create(self: *Self, comptime T: type) !*T {
    const allocator_impl = self.allocator();
    return allocator_impl.create(T);
}

/// Destroy a typed pointer and track its deallocation
pub fn destroy(self: *Self, ptr: anytype) void {
    const allocator_impl = self.allocator();
    allocator_impl.destroy(ptr);
}

/// Allocate a slice and track its allocation
pub fn allocSlice(self: *Self, comptime T: type, n: usize) ![]T {
    const allocator_impl = self.allocator();
    return allocator_impl.alloc(T, n);
}

/// Allocate a sentinel-terminated slice and track its allocation
pub fn allocSentinel(self: *Self, comptime T: type, n: usize, comptime sentinel: T) ![:sentinel]T {
    const allocator_impl = self.allocator();
    return allocator_impl.allocSentinel(T, n, sentinel);
}

/// Free a slice and track its deallocation
pub fn freeSlice(self: *Self, memory: anytype) void {
    const allocator_impl = self.allocator();
    allocator_impl.free(memory);
}

/// Duplicate a string and track its allocation
pub fn dupe(self: *Self, comptime T: type, m: []const T) ![]T {
    const allocator_impl = self.allocator();
    return allocator_impl.dupe(T, m);
}

/// Get current memory statistics
pub fn getStats(self: Self) MemoryStats {
    return MemoryStats{
        .total_allocated = self.total_allocated,
        .allocation_count = self.allocation_count,
    };
}

/// Reset memory tracking counters (for testing purposes)
pub fn resetStats(self: *Self) void {
    self.total_allocated = 0;
    self.allocation_count = 0;
}

/// Memory usage statistics
pub const MemoryStats = struct {
    total_allocated: usize,
    allocation_count: usize,
};

/// Create a NodeAllocator instance
pub fn create(env: c.napi_env) NodeAllocator {
    return NodeAllocator.init(env);
}

/// Convenience function to get a std.mem.Allocator interface from NodeAllocator
pub fn getAllocator(node_allocator: *NodeAllocator) std.mem.Allocator {
    return node_allocator.allocator();
}
