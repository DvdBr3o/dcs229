#include "dcs229/Image.hpp"

#include <turbojpeg.h>
#include <spng.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <ranges>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace dcs229 {
namespace {
[[noreturn]] auto fail(const char* what, const std::string& detail) -> void {
	throw std::runtime_error(std::string(what) + ": " + detail);
}

[[nodiscard]] auto read_file(const std::filesystem::path& path) -> std::vector<char> {
	std::ifstream file(path, std::ios::binary | std::ios::ate);
	if (!file)
		throw std::runtime_error("cannot open image file: " + path.string());

	const auto end = file.tellg();
	if (end < 0)
		throw std::runtime_error("cannot determine size of image file: " + path.string());
	std::vector<char> buffer(static_cast<size_t>(end));
	if (!buffer.empty()) {
		file.seekg(0);
		file.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
	}
	return buffer;
}

// libspng never throws on its own; this guard just keeps the error paths safe.
// `flags` is SPNG_CTX_ENCODER for encoding, 0 for decoding.
struct SpngCtx {
	spng_ctx* ctx = nullptr;

	explicit SpngCtx(int flags = 0) : ctx(spng_ctx_new(flags)) {
		if (ctx == nullptr)
			throw std::runtime_error("spng_ctx_new failed");
	}

	~SpngCtx() { spng_ctx_free(ctx); }

	SpngCtx(const SpngCtx&)					   = delete;
	auto operator=(const SpngCtx&) -> SpngCtx& = delete;
};

[[nodiscard]] auto decode_png(const char* data, size_t size) -> Bitmap {
	SpngCtx handle;
	auto*	ctx = handle.ctx;

	auto	err = spng_set_png_buffer(ctx, data, size);
	if (err != 0)
		fail("spng_set_png_buffer", spng_strerror(err));

	spng_ihdr ihdr {};
	err = spng_get_ihdr(ctx, &ihdr);
	if (err != 0)
		fail("spng_get_ihdr", spng_strerror(err));

	size_t decoded_size = 0;
	err					= spng_decoded_image_size(ctx, SPNG_FMT_RGBA8, &decoded_size);
	if (err != 0)
		fail("spng_decoded_image_size", spng_strerror(err));

	Bitmap bitmap(ihdr.width, ihdr.height);
	err = spng_decode_image(ctx, bitmap.data(), decoded_size, SPNG_FMT_RGBA8, SPNG_DECODE_TRNS);
	if (err != 0)
		fail("spng_decode_image", spng_strerror(err));
	return bitmap;
}

// Owns a libjpeg-turbo decompression handle; a raw handle would leak on throw.
struct TjHandle {
	tjhandle handle = nullptr;

	TjHandle() : handle(tjInitDecompress()) {
		if (handle == nullptr)
			throw std::runtime_error(std::string("tjInitDecompress: ") + tjGetErrorStr());
	}

	~TjHandle() { tjDestroy(handle); }

	TjHandle(const TjHandle&)					 = delete;
	auto operator=(const TjHandle&) -> TjHandle& = delete;
};

[[nodiscard]] auto decode_jpg(const char* data, size_t size) -> Bitmap {
	auto*	 jpeg	   = reinterpret_cast<const unsigned char*>(data);
	auto	 jpeg_size = static_cast<unsigned long>(size);
	TjHandle raii;
	auto*	 decompressor = raii.handle;

	int		 width = 0, height = 0, subsamp = 0, colorspace = 0;
	if (tjDecompressHeader3(decompressor, jpeg, jpeg_size, &width, &height, &subsamp, &colorspace)
		!= 0)
		fail("tjDecompressHeader3", tjGetErrorStr());

	Bitmap bitmap(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
	if (tjDecompress2(
			decompressor,
			jpeg,
			jpeg_size,
			reinterpret_cast<unsigned char*>(bitmap.data()),
			width,
			0,
			height,
			TJPF_RGBA,
			TJFLAG_ACCURATEDCT
		)
		!= 0)
		fail("tjDecompress2", tjGetErrorStr());
	return bitmap;
}

// Sniff the format and dispatch to the matching decoder.
[[nodiscard]] auto decode_any(const char* data, size_t size) -> Bitmap {
	if (size >= 8 && static_cast<unsigned char>(data[0]) == 0x89 && data[1] == 'P' && data[2] == 'N'
		&& data[3] == 'G')
		return decode_png(data, size);
	if (size >= 2 && static_cast<unsigned char>(data[0]) == 0xFF
		&& static_cast<unsigned char>(data[1]) == 0xD8)
		return decode_jpg(data, size);
	throw std::runtime_error("unrecognised image format");
}
}  // namespace

PngImage::PngImage(const std::filesystem::path& path) {
	const auto buffer = read_file(path);
	_bitmap			  = decode_png(buffer.data(), buffer.size());
}

PngImage::PngImage(const char* data, size_t size) : _bitmap(decode_png(data, size)) {}

JpgImage::JpgImage(const std::filesystem::path& path) {
	const auto buffer = read_file(path);
	_bitmap			  = decode_jpg(buffer.data(), buffer.size());
}

JpgImage::JpgImage(const char* data, size_t size) : _bitmap(decode_jpg(data, size)) {}

AnyImage::AnyImage(const std::filesystem::path& path) {
	const auto buffer = read_file(path);
	_bitmap			  = decode_any(buffer.data(), buffer.size());
}

AnyImage::AnyImage(const char* data, size_t size) : _bitmap(decode_any(data, size)) {}

auto load_image(const std::filesystem::path& path) -> AnyImage {
	const auto buffer = read_file(path);
	return AnyImage(buffer.data(), buffer.size());
}

auto load_image(const char* data, size_t size) -> AnyImage {
	return AnyImage(data, size);
}

auto decode_image(const std::filesystem::path& path) -> ImageView {
	const auto buffer = read_file(path);
	return decode_image(buffer.data(), buffer.size());
}

// NOTE: the view points into `decode_any`'s temporary Bitmap, so it is only
// valid until the end of the full expression that produced it.
auto decode_image(const char* data, size_t size) -> ImageView {
	return AnyImage(data, size).view();
}

namespace {
auto write_file(const std::filesystem::path& path, const void* data, size_t size) -> void {
	std::ofstream file(path, std::ios::binary | std::ios::trunc);
	if (!file)
		throw std::runtime_error("cannot open output file: " + path.string());
	file.write(static_cast<const char*>(data), static_cast<std::streamsize>(size));
	if (!file)
		throw std::runtime_error("failed writing output file: " + path.string());
}

// RAII wrapper for C encoder buffers. libspng allocates with malloc, while
// libjpeg-turbo's buffer must be released with tjFree, so the deleter is a
// parameter. Move-only; never copied.
class BufferOwner {
public:
	using Deleter = void (*)(void*);

	BufferOwner() = default;

	BufferOwner(void* ptr, Deleter deleter) : _ptr(ptr), _deleter(deleter) {}

	BufferOwner(BufferOwner&& other) noexcept : _ptr(other._ptr), _deleter(other._deleter) {
		other._ptr = nullptr;
	}

	auto operator=(BufferOwner&& other) noexcept -> BufferOwner& {
		if (this != &other) {
			release();
			_ptr	   = other._ptr;
			_deleter   = other._deleter;
			other._ptr = nullptr;
		}
		return *this;
	}

	BufferOwner(const BufferOwner&)					   = delete;
	auto operator=(const BufferOwner&) -> BufferOwner& = delete;

	~BufferOwner() { release(); }

	[[nodiscard]] auto get() const -> void* { return _ptr; }

private:
	auto release() -> void {
		if (_ptr != nullptr && _deleter != nullptr)
			_deleter(_ptr);
		_ptr = nullptr;
	}

	void*	_ptr	 = nullptr;
	Deleter _deleter = nullptr;
};

[[nodiscard]] auto encode_png(const ImageView& image) -> std::pair<void*, size_t> {
	SpngCtx handle(SPNG_CTX_ENCODER);
	auto*	ctx = handle.ctx;

	auto	err = spng_set_option(ctx, SPNG_ENCODE_TO_BUFFER, 1);
	if (err != 0)
		fail("spng_set_option", spng_strerror(err));

	spng_ihdr ihdr {};
	ihdr.width				= image.width;
	ihdr.height				= image.height;
	ihdr.bit_depth			= 8;
	ihdr.color_type			= SPNG_COLOR_TYPE_TRUECOLOR_ALPHA;
	ihdr.compression_method = 0;
	ihdr.filter_method		= 0;
	ihdr.interlace_method	= 0;

	err						= spng_set_ihdr(ctx, &ihdr);
	if (err != 0)
		fail("spng_set_ihdr", spng_strerror(err));

	err = spng_encode_image(ctx, image.data, image.size, SPNG_FMT_PNG, SPNG_ENCODE_FINALIZE);
	if (err != 0)
		fail("spng_encode_image", spng_strerror(err));

	size_t len = 0;
	void*  buf = spng_get_png_buffer(ctx, &len, &err);
	if (buf == nullptr || err != 0)
		fail("spng_get_png_buffer", spng_strerror(err));
	return {buf, len};
}

// A JPEG compressor handle lives in the same struct shape as TjHandle but with
// tjInitCompress; kept separate so the two usages don't get confused.
struct TjCompressor {
	tjhandle handle = nullptr;

	TjCompressor() : handle(tjInitCompress()) {
		if (handle == nullptr)
			throw std::runtime_error(std::string("tjInitCompress: ") + tjGetErrorStr());
	}

	~TjCompressor() { tjDestroy(handle); }

	TjCompressor(const TjCompressor&)					 = delete;
	auto operator=(const TjCompressor&) -> TjCompressor& = delete;
};

// Returns a tjFree-owned buffer; the caller wraps it in a tjFree guard.
[[nodiscard]] auto encode_jpg(const ImageView& image, int quality)
	-> std::pair<unsigned char*, unsigned long> {
	TjCompressor   compressor;
	auto*		   handle = compressor.handle;

	unsigned long  size	  = 0;
	unsigned char* buffer = nullptr;
	if (tjCompress2(
			handle,
			reinterpret_cast<const unsigned char*>(image.data),
			static_cast<int>(image.width),
			static_cast<int>(image.width) * 4,
			static_cast<int>(image.height),
			TJPF_RGBA,
			&buffer,
			&size,
			TJSAMP_444,
			quality,
			TJFLAG_ACCURATEDCT
		)
		!= 0)
		fail("tjCompress2", tjGetErrorStr());
	return {buffer, size};
}
}  // namespace

auto save_png(const ImageView& image, const std::filesystem::path& path) -> void {
	const auto [buffer, size] = encode_png(image);
	BufferOwner guard {buffer, &std::free};
	write_file(path, buffer, size);
}

auto save_jpg(const ImageView& image, const std::filesystem::path& path, int quality) -> void {
	if (quality < 1 || quality > 100)
		throw std::runtime_error("JPEG quality must be in [1, 100]");

	const auto [buffer, size] = encode_jpg(image, quality);
	BufferOwner guard {buffer, [](void* p) { tjFree(static_cast<unsigned char*>(p)); }};
	write_file(path, buffer, size);
}

auto save_image(const ImageView& image, const std::filesystem::path& path, int quality) -> void {
	std::string ext = path.extension().string();
	std::ranges::transform(ext, ext.begin(), [](unsigned char c) {
		return static_cast<char>(std::tolower(c));
	});

	if (ext == ".png")
		return save_png(image, path);
	if (ext == ".jpg" || ext == ".jpeg")
		return save_jpg(image, path, quality);
	throw std::runtime_error(
		"unsupported output extension: " + ext + " (expected .png, .jpg or .jpeg)"
	);
}
}  // namespace dcs229
