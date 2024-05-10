const std = @import("std");
const print = std.debug.print;
const parseInt = std.fmt.parseInt;
const writeInt = std.mem.writeInt;
const eql = std.mem.eql;

const QOI_OP_RGB: u8 = 0xFE;
const QOI_OP_RGBA: u8 = 0xFF;

const QOI_OP_INDEX: u8 = 0x00;
const QOI_OP_DIFF: u8 = 0x40;
const QOI_OP_LUMA: u8 = 0x80;
const QOI_OP_RUN: u8 = 0xC0;

const QOI_TAG: u8 = 0xC0;
const QOI_TAG_MASK: u8 = 0x3F;

const QOI_MAGIC = "qoif";
const QOI_PADDING: *const [8]u8 = &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };

const QoiPixel = extern union {
    vals: extern struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8,
    },
    channels: [4]u8,
    concatenated_pixel_values: u32,
};

const QoiDesc = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 0,
    colorspace: u8 = 0,

    fn qoiSetEverything(w: u32, h: u32, ch: u8, c: u8) QoiDesc {
        return QoiDesc{ .width = w, .height = h, .channels = ch, .colorspace = c };
    }
    fn writeQoiHeader(self: QoiDesc, dest: *[14]u8) void {
        @memcpy(dest[0..4], QOI_MAGIC);
        writeInt(u32, dest[4..8], self.width, .big);
        writeInt(u32, dest[8..12], self.height, .big);
        dest[12] = self.channels;
        dest[13] = self.colorspace;
    }
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
        print("QOI file info:\n", .{});
        print("  Width:      {d}\n", .{self.width});
        print("  Height:     {d}\n", .{self.height});
        print("  Channels:   {d}\n", .{self.channels});
        if (self.colorspace == 0) {
            print("  Colorspace: sRGB\n", .{});
        } else {
            print("  Colorspace: Linear RGB\n", .{});
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
            self.buffer[i].vals.red = 0;
            self.buffer[i].vals.green = 0;
            self.buffer[i].vals.blue = 0;
            self.buffer[i].vals.red = 255;
        }

        self.prev_pixel.vals.red = 0;
        self.prev_pixel.vals.green = 0;
        self.prev_pixel.vals.blue = 0;
        self.prev_pixel.vals.alpha = 255;

        self.pad = 0;
        self.run = 0;

        self.img_area = desc.width * desc.height;
        self.qoi_len = len;
        self.pixel_seek = 0;

        self.data = data;
        self.offset = self.data + 14;
    }
    fn qoiDecRGB(dec: *QoiDec) void {
        dec.prev_pixel.vals.red = dec.offset[1];
        dec.prev_pixel.vals.green = dec.offset[2];
        dec.prev_pixel.vals.blue = dec.offset[3];
        dec.offset += 4;
    }
    fn qoiDecRGBA(dec: *QoiDec) void {
        dec.prev_pixel.vals.red = dec.offset[1];
        dec.prev_pixel.vals.green = dec.offset[2];
        dec.prev_pixel.vals.blue = dec.offset[3];
        dec.prev_pixel.vals.alpha = dec.offset[4];
        dec.offset += 5;
    }
    fn qoiDecIndex(dec: *QoiDec, tag: u8) void {
        dec.prev_pixel = dec.buffer[tag & QOI_TAG_MASK];
        dec.offset += 1;
    }
    fn qoiDecDiff(dec: *QoiDec, tag: u8) void {
        const diff: u8 = tag & QOI_TAG_MASK;

        const red_diff: u8 = ((diff >> 4) & 0x03) - 2;
        const green_diff: u8 = ((diff >> 2) & 0x03) - 2;
        const blue_diff: u8 = (diff & 0x03) - 2;

        dec.prev_pixel.vals.red += red_diff;
        dec.prev_pixel.vals.green += green_diff;
        dec.prev_pixel.vals.blue += blue_diff;

        dec.offset += 1;
    }
    fn qoiDecLuma(dec: *QoiDec, tag: u8) void {
        const lumaGreen: u8 = (tag & QOI_TAG_MASK) - 32;

        dec.prev_pixel.vals.red +%= lumaGreen + ((dec.offset[1] & 0xF0) >> 4) - 8;
        dec.prev_pixel.vals.green +%= lumaGreen;
        dec.prev_pixel.vals.blue +%= lumaGreen + (dec.offset[1] & 0x0F) - 8;

        dec.offset += 2;
    }
    fn qoiDecRun(dec: *QoiDec, tag: u8) void {
        dec.run = tag & QOI_TAG_MASK;
        dec.offset += 1;
    }
    fn qoiDecodeChunk(dec: *QoiDec) QoiPixel {
        if (dec.run > 0) {
            dec.run -= 1;
        } else {
            const tag: u8 = dec.offset[0];

            if (tag == QOI_OP_RGB) {
                dec.qoiDecRGB();
            } else if (tag == QOI_OP_RGBA) {
                dec.qoiDecRGBA();
            } else {
                const tag_type: u8 = tag & QOI_TAG;
                switch (tag_type) {
                    QOI_OP_INDEX => dec.qoiDecIndex(tag),
                    QOI_OP_DIFF => dec.qoiDecDiff(tag),
                    QOI_OP_LUMA => dec.qoiDecLuma(tag),
                    QOI_OP_RUN => dec.qoiDecRun(tag),
                    else => {
                        dec.offset += 1;
                    },
                }
            }
            const index_pos: u6 = @truncate(dec.prev_pixel.vals.red *% 3 +% dec.prev_pixel.vals.green *% 5 +% dec.prev_pixel.vals.blue *% 7 +% dec.prev_pixel.vals.alpha *% 11);
            dec.buffer[index_pos] = dec.prev_pixel;
        }
        dec.pixel_seek += 1;
        return dec.prev_pixel;
    }
};

fn printHelp() void {
    print("Freestanding QOI Decoder in \x1b[33mZig\x1b[0m\n", .{});
    print("Example usage: qoi-dec-zig [input.qoi] [output]\n", .{});
}

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        _ = printHelp();
        return;
    }

    if (eql(u8, args[1], "-h") or
        eql(u8, args[1], "--help") or
        args.len < 3 or
        args.len > 3 or
        args[1].len < 1)
    {
        _ = printHelp();
        return;
    }

    print("Opening {s} ...\n", .{args[1]});

    const file = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer file.close();

    const qoi_bytes = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(qoi_bytes);

    var desc = QoiDesc.qoiSetEverything(0, 0, 0, 0);
    try desc.readQoiHeader(qoi_bytes[0..14]);
    desc.printQoiInfo();

    const raw_image_length: usize = @intCast(desc.width * desc.height * desc.channels);
    var seek: usize = 0;
    if (raw_image_length == 0) return error.InvalidInput;

    var dec: QoiDec = undefined;
    dec.qoiDecInit(desc, qoi_bytes.ptr, qoi_bytes.len);

    const bytes: []u8 = try allocator.alloc(u8, raw_image_length + 4);
    defer allocator.free(bytes);

    print("Decoding {s} --> {s} ...\n", .{ args[1], args[2] });

    // !(dec.offset - dec.data > dec.qoi_len - 8) or
    while (!(dec.pixel_seek >= dec.img_area)) {
        const px: QoiPixel = dec.qoiDecodeChunk();
        bytes[seek] = px.vals.red;
        bytes[seek + 1] = px.vals.green;
        bytes[seek + 2] = px.vals.blue;
        if (desc.channels > 3) bytes[seek + 3] = px.vals.alpha;
        seek += desc.channels;
    }

    const outfile = try std.fs.cwd().createFile(args[2], .{ .truncate = true });
    defer outfile.close();
    _ = try outfile.writeAll(bytes);

    print("\x1b[32mSuccess!\x1b[0m\n", .{});
}
