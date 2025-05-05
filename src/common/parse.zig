const std = @import("std");
const common = @import("common.zig");

fn convertToKebab(comptime name: []const u8) []const u8 {
    comptime var result: []const u8 = "";

    inline for (name) |c| {
        if (c == '_') {
            result = result ++ "-";
        } else {
            result = result ++ [_]u8{c};
        }
    }
    return result;
}

fn getFullNames(fields: []const std.builtin.Type.StructField) []const []const u8 {
    comptime var names: []const []const u8 = &[_][]const u8{};

    inline for (fields) |field| {
        const name = comptime convertToKebab(field.name);
        names = names ++ .{"--" ++ name};
    }

    return names;
}

fn getShorthandNames(fields: []const std.builtin.Type.StructField) []const []const u8 {
    comptime var names: []const []const u8 = &[_][]const u8{};

    inline for (fields) |field| {
        names = names ++ .{"-" ++ .{field.name[0]}};
    }

    return names;
}

fn parseArgument(Argument: type, optional_value: ?[]const u8) !Argument {
    const type_info = @typeInfo(Argument);
    const value = optional_value orelse return error.MissingValue;

    switch (type_info) {
        .@"enum" => |e| {
            inline for (e.fields) |field| {
                if (std.mem.eql(u8, value, field.name)) {
                    return @field(Argument, field.name);
                }
            }
            return error.InvalidEnumValue;
        },
        .pointer => |p| {
            if (p.size != .one and p.child == u8) {
                return value;
            }

            @compileError("Pointer types are not supported");
        },
        else => {
            return error.UnsupportedType;
        },
    }
}

pub fn parse(Arguments: type, argument_iter: *std.process.ArgIterator) !Arguments {
    const type_info = @typeInfo(Arguments);
    if (type_info != .@"struct") {
        return error.InvalidType;
    }
    const struct_info = type_info.@"struct";
    const full_names = getFullNames(struct_info.fields);
    const shorthand_names = getShorthandNames(struct_info.fields);

    var args: Arguments = .default;
    _ = argument_iter.next(); // Skip the first argument (the program name)

    while (argument_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        }

        var found = false;
        inline for (struct_info.fields, full_names, shorthand_names) |field, full_name, shorthand| {
            if (std.mem.eql(u8, arg, full_name) or std.mem.eql(u8, arg, shorthand)) {
                @field(&args, field.name) = parseArgument(field.type, argument_iter.next()) catch |err| {
                    std.log.info("Error parsing argument {s}: {s}\n", .{ arg, @errorName(err) });
                    return err;
                };
                found = true;
                break;
            }
        }
        if (!found) {
            common.print("Unknown argument: {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }

    return args;
}

pub fn getAddress(address: []const u8) !struct { []const u8, u16 } {
    const index = std.mem.indexOf(u8, address, ":");
    if (index == null) {
        return error.InvalidAddress;
    }

    const addr = address[0..index.?];
    const port = address[index.? + 1 ..];

    return .{ addr, try std.fmt.parseInt(u16, port, 10) };
}
