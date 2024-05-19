# QOI Image Decoder in Zig

This Zig program decodes images in the Quite OK Image Format (QOI) into Portable Arbitrary Map (PAM) files. It is a freestanding implementation, existing entirely in one file. The QOI format is a simple, lossless image format designed for fast encoding and decoding.

<div align="center">
<img src="https://ninja.dog/1nzHoy.svg" alt="QOI Logo" width=230/>
</div>

## Program Details

I wrote this mostly as a learning exercise, and I was heavily inspired by the [Simplified QOI Codec Library](https://github.com/Aftersol/Simplified-QOI-Codec), a one header file library for encoding and decoding QOI files written in C.

### Benchmarks

*Coming Soon*

## Building

In order to build this program, you will need to have the latest version of the Zig programming language (at least version `0.12.0`) installed on your system as well as `git`. You can find instructions for installing Zig on the [official website](https://ziglang.org/). Once that is set up, follow the steps below for building the `qoi-dec-zig` binary:

```bash
git clone https://github.com/gianni-rosato/qoi-dec-zig # Clone the repo
cd qoi-dec-zig # Enter the directory
zig build -Doptimize=ReleaseFast # Build the program
```

## Usage

The program is run from the command line with the following arguments:

```bash
qoi-zig [input.pam] [output] [colorspace]
```

- `input.pam`: The input PAM image file to encode.
- `output`: The output QOI image file to create.
- `colorspace`: The colorspace of the image. Use `0` for sRGB with linear alpha and `1` for linear RGB.

If the input file is too small for the specified image dimensions & channels, an error message is printed.

## Creating QOI Files

If you're just interested in testing this program, you can use the QOI files in the `examples/` directory. If you want to create your own QOI files, you can use [my standalone QOI encoder](https://github.com/gianni-rosato/qoi-enc-zig/) or [FFmpeg](https://wiki.x266.mov/docs/utilities/ffmpeg):

Create a QOI file from an input image with FFmpeg:

```bash
ffmpeg -i [input] -c qoi output.qoi
```

Create a QOI file from a valid input PAM image with `qoi-zig`:

```bash
qoi-zig [input.pam] output.qoi [colorspace]
```

## Examples

There are some QOI examples provided in the `examples/` directory. You can use these to test the program and see how it works.

Decode `transparent.qoi` to `transparent.pam`:

```bash
qoi-dec-zig examples/transparent.qoi transparent.pam
```

Decode `photo.qoi` to `photo.pam`:

```bash
qoi-dec-zig examples/photo.qoi photo.pam
```

This program does not perform any error checking on the input QOI file. Incorrect inputs can lead to unexpected results or program crashes; always ensure that your input data is correct before running the program.

## Dependencies

This program requires the Zig programming language, at least version `0.12.0`. It also uses the standard library provided with Zig. No other dependencies are required.

## License

This program is released under the BSD 3-Clause License. You are free to use, modify, and distribute the program under the terms of this license.

## Acknowledgments

Thank you to the authors of the Simplified QOI Codec Library, and Cancername for their expert consulting on the Zig programming language! Much appreciated!

- [QOI Specification](https://qoiformat.org/qoi-specification.pdf)
- [QOI Site](https://qoiformat.org/)
- [Zig](https://ziglang.org/)
