const std = @import("std");
const print = std.debug.print;
const eql = std.mem.eql;

const QoiEnum = enum(u8) {
    QOI_OP_RGB = 0xFE,
    QOI_OP_RGBA = 0xFF,

    QOI_OP_INDEX = 0x00,
    QOI_OP_DIFF = 0x40,
    QOI_OP_LUMA = 0x80,
    QOI_OP_RUN = 0xC0,
};

const QoiTagEnum = enum(u8) {
    QOI_TAG = 0xC0,
    QOI_TAG_MASK = 0x3F,
};

const QOI_MAGIC = "qoif";

const QoiPixel = extern union {
    vals: extern struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8,
    },
    channels: [4]u8,
};

const QoiDesc = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,

    fn readQoiHeader(self: *QoiDesc, src: *[14]u8) !void {
        if (!eql(u8, src[0..4], QOI_MAGIC)) {
            return error.InvalidInput;
        }
        self.width = std.mem.readInt(u32, src[4..8], .big);
        self.height = std.mem.readInt(u32, src[8..12], .big);
        self.channels = src[12];
        self.colorspace = src[13];
    }
    fn printQoiInfo(self: *QoiDesc) void {
        print("file is a QOI\n", .{});
        print("Dimensions: {d}x{d} | \x1b[31mR\x1b[0m\x1b[32mG\x1b[0m\x1b[34mB\x1b[0m", .{ self.width, self.height });
        if (self.channels > 3) print("\x1b[37mA\x1b[0m", .{});

        switch (self.colorspace) {
            0 => print(" (sRGB)\n", .{}),
            else => print(" (Linear RGB)\n", .{}),
        }
    }
};

const QoiDec = struct {
    buffer: [64]QoiPixel,
    prev_pixel: QoiPixel,

    pixel_seek: usize,
    img_area: usize,
    qoi_len: usize,

    data: [*]u8,
    offset: [*]u8,

    run: u8,
    pad: u24,
    fn qoiDecInit(self: *QoiDec, desc: QoiDesc, data: [*]u8, len: usize) void {
        for (0..64) |i| {
            for (0..3) |j| self.buffer[i].channels[j] = 0;
            self.buffer[i].vals.alpha = 255;
        }

        for (0..3) |i| self.prev_pixel.channels[i] = 0;
        self.prev_pixel.vals.alpha = 255;

        self.pad = 0;
        self.run = 0;

        self.img_area = desc.width * desc.height;
        self.qoi_len = len;
        self.pixel_seek = 0;

        self.data = data;
        self.offset = self.data + 14;
    }
    fn qoiDecFullColor(dec: *QoiDec, s: u3) void {
        @memcpy(dec.prev_pixel.channels[0 .. s - 1], dec.offset[1..s]);
        dec.offset += s;
    }
    fn qoiDecIndex(dec: *QoiDec, tag: u8) void {
        dec.prev_pixel = dec.buffer[tag & @intFromEnum(QoiTagEnum.QOI_TAG_MASK)];
        dec.offset += 1;
    }
    fn qoiDecDiff(dec: *QoiDec, tag: u8) void {
        const diff: u8 = tag & @intFromEnum(QoiTagEnum.QOI_TAG_MASK);

        dec.prev_pixel.vals.red +%= @as(u8, (diff >> 4 & 0x03) -% 2);
        dec.prev_pixel.vals.green +%= @as(u8, (diff >> 2 & 0x03) -% 2);
        dec.prev_pixel.vals.blue +%= @as(u8, (diff & 0x03) -% 2);

        dec.offset += 1;
    }
    fn qoiDecLuma(dec: *QoiDec, tag: u8) void {
        const lumaGreen: u8 = (tag & @intFromEnum(QoiTagEnum.QOI_TAG_MASK)) -% 32;

        dec.prev_pixel.vals.red +%= lumaGreen +% ((dec.offset[1] & 0xF0) >> 4) -% 8;
        dec.prev_pixel.vals.green +%= lumaGreen;
        dec.prev_pixel.vals.blue +%= lumaGreen +% (dec.offset[1] & 0x0F) -% 8;

        dec.offset += 2;
    }
    fn qoiDecRun(dec: *QoiDec, tag: u8) void {
        dec.run = tag & @intFromEnum(QoiTagEnum.QOI_TAG_MASK);
        dec.offset += 1;
    }
    fn qoiDecodeChunk(dec: *QoiDec) QoiPixel {
        if (dec.run > 0) {
            dec.run -= 1;
            dec.pixel_seek += 1;
            return dec.prev_pixel;
        }

        const tag: u8 = dec.offset[0];
        switch (tag) {
            @intFromEnum(QoiEnum.QOI_OP_RGB) => dec.qoiDecFullColor(4),
            @intFromEnum(QoiEnum.QOI_OP_RGBA) => dec.qoiDecFullColor(5),
            else => {
                const tag_enum: QoiEnum = @enumFromInt(tag & @intFromEnum(QoiTagEnum.QOI_TAG));
                switch (tag_enum) {
                    QoiEnum.QOI_OP_INDEX => dec.qoiDecIndex(tag),
                    QoiEnum.QOI_OP_DIFF => dec.qoiDecDiff(tag),
                    QoiEnum.QOI_OP_LUMA => dec.qoiDecLuma(tag),
                    QoiEnum.QOI_OP_RUN => dec.qoiDecRun(tag),
                    else => dec.offset += 1,
                }
            },
        }

        const index_pos: u6 = @truncate(dec.prev_pixel.vals.red *% 3 +% dec.prev_pixel.vals.green *% 5 +% dec.prev_pixel.vals.blue *% 7 +% dec.prev_pixel.vals.alpha *% 11);
        dec.buffer[index_pos] = dec.prev_pixel;

        dec.pixel_seek += 1;
        return dec.prev_pixel;
    }
};

fn printHelp() void {
    print("Freestanding QOI Decoder in \x1b[33mZig\x1b[0m\n", .{});
    print("Example usage: qoi-dec-zig [input.qoi] [output.pam]\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or
        args.len > 3 or
        eql(u8, args[1], "-h") or
        eql(u8, args[1], "--help") or
        args[1].len < 1)
    {
        _ = printHelp();
        return;
    }

    print("Opening {s} ... ", .{args[1]});

    const file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    const qoi_bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(qoi_bytes);

    var desc: QoiDesc = .{ .width = 0, .height = 0, .channels = 0, .colorspace = 0 };
    try desc.readQoiHeader(qoi_bytes[0..14]);
    desc.printQoiInfo();

    const raw_image_length: usize = @intCast(desc.width * desc.height * desc.channels);
    if (raw_image_length == 0) return error.InvalidInput;
    var seek: usize = 0;

    var dec: QoiDec = undefined;
    dec.qoiDecInit(desc, qoi_bytes.ptr, qoi_bytes.len);

    const bytes: []u8 = try allocator.alloc(u8, raw_image_length);
    defer allocator.free(bytes);

    print("Decoding {s} --> {s} ... ", .{ args[1], args[2] });

    // !(@intFromPtr(dec.offset) - @intFromPtr(dec.data) > dec.qoi_len - 8) or
    while (!(@intFromPtr(dec.offset) - @intFromPtr(dec.data) > dec.qoi_len - 8) or !(dec.pixel_seek >= dec.img_area)) {
        const px: QoiPixel = dec.qoiDecodeChunk();
        @memcpy(bytes[seek .. seek + desc.channels], px.channels[0..desc.channels]);
        seek += desc.channels;
    }

    const outfile = try std.fs.cwd().createFile(args[2], .{ .truncate = true });
    defer outfile.close();

    const widthString = try std.fmt.allocPrint(allocator, "{}", .{desc.width});
    defer allocator.free(widthString);
    const heightString = try std.fmt.allocPrint(allocator, "{}", .{desc.height});
    defer allocator.free(heightString);

    const channelString = switch (desc.channels) {
        3 => "\nDEPTH 3\n",
        else => "\nDEPTH 4\n",
    };
    const tuplTypeString = switch (desc.channels) {
        3 => "RGB\n",
        else => "RGB_ALPHA\n",
    };

    const pam_header_offset: u8 = @intCast(widthString.len + heightString.len + channelString.len + tuplTypeString.len + 44);

    _ = try outfile.write("P7\n" ++ "WIDTH ");
    _ = try outfile.write(widthString);
    _ = try outfile.write("\nHEIGHT ");
    _ = try outfile.write(heightString);
    _ = try outfile.write(channelString);
    _ = try outfile.write("MAXVAL 255\n" ++ "TUPLTYPE ");
    _ = try outfile.write(tuplTypeString);
    _ = try outfile.write("ENDHDR\n");

    _ = try outfile.writeAll(bytes);

    print("\x1b[32mSuccess!\x1b[0m\n", .{});
    const final_filesize: usize = raw_image_length + pam_header_offset;
    print("\tOriginal:\t{d} bytes\n\tDecompressed:\t{d} bytes ", .{ qoi_bytes.len, final_filesize });
    if (final_filesize > qoi_bytes.len) {
        const percent_inc: f64 = (@as(f64, @floatFromInt(final_filesize)) / @as(f64, @floatFromInt(qoi_bytes.len))) * 100.0;
        print("(\x1b[33m{d:.2}%\x1b[0m bigger)\n", .{percent_inc});
    } else {
        print("\n", .{});
    }
}
