#pragma once

#include <concepts>
#include <cstddef>
#include <cstdint>
#include <filesystem>

namespace dcs229 {
struct ImageView;

// A type-erased, owning-agnostic view of a decoded image.
//
// Pixels are always packed as 8-bit RGBA in row-major order (top row first),
// so `size == width * height * 4`. Keeping a single canonical format lets
// every consumer be format-agnostic, and keeps the view trivially cheap to
// pass around (it is just a span plus two dimensions).
//
// The view never owns its pixels: it is valid only while the image it was
// created from is alive.
struct ImageView {
	const char*					 data	= nullptr;
	size_t						 size	= 0;
	uint32_t					 width	= 0;
	uint32_t					 height = 0;

	[[nodiscard]] constexpr auto pixels() const -> const char* { return data; }

	[[nodiscard]] constexpr auto bytes() const -> size_t { return size; }

	[[nodiscard]] auto			 begin() const -> const char* { return data; }

	[[nodiscard]] auto			 end() const -> const char* { return data + size; }

	template<typename T>
		requires requires(const T& t) {
			{ view_of(t) } -> std::convertible_to<ImageView>;  // ADL
		}

	static constexpr auto from(const T& t) -> ImageView {
		return view_of(t);
	}
};

// Zero-overhead pass-through so `ImageView::from(an_image_view)` works and lets
// an `ImageView` act as a backend itself.
inline constexpr auto view_of(const ImageView& view) noexcept -> ImageView {
	return view;
}

// Concepts describing the image backends. Both are satisfied by PngImage and
// JpgImage below, and by any user type that owns RGBA8 pixels and exposes a
// `view_of` customization (found via ADL).
template<typename T>
concept ImageC = requires(const T& t) {
	{ t.width() } -> std::convertible_to<uint32_t>;
	{ t.height() } -> std::convertible_to<uint32_t>;
	{ t.data() } -> std::convertible_to<const char*>;
	{ t.size() } -> std::convertible_to<size_t>;
	{ view_of(t) } -> std::convertible_to<ImageView>;  // ADL
};

// Owning RGBA8 bitmap: nothrow-movable, non-copyable, RAII-managed.
class Bitmap {
public:
	Bitmap() = default;

	Bitmap(uint32_t width, uint32_t height) :
		_width(width), _height(height), _pixels(new char[bytes()]) {}

	Bitmap(Bitmap&& other) noexcept :
		_width(other._width), _height(other._height), _pixels(other._pixels) {
		other._pixels = nullptr;
		other._width  = 0;
		other._height = 0;
	}

	auto operator=(Bitmap&& other) noexcept -> Bitmap& {
		if (this != &other) {
			delete[] _pixels;
			_width		  = other._width;
			_height		  = other._height;
			_pixels		  = other._pixels;
			other._pixels = nullptr;
			other._width  = 0;
			other._height = 0;
		}
		return *this;
	}

	Bitmap(const Bitmap&)					 = delete;
	auto operator=(const Bitmap&) -> Bitmap& = delete;

	~Bitmap() { delete[] _pixels; }

	[[nodiscard]] auto data() const noexcept -> const char* { return _pixels; }

	[[nodiscard]] auto data() noexcept -> char* { return _pixels; }

	[[nodiscard]] auto size() const noexcept -> size_t { return bytes(); }

	[[nodiscard]] auto bytes() const noexcept -> size_t {
		return static_cast<size_t>(_width) * _height * 4;
	}

	[[nodiscard]] auto width() const noexcept -> uint32_t { return _width; }

	[[nodiscard]] auto height() const noexcept -> uint32_t { return _height; }

	[[nodiscard]] auto empty() const noexcept -> bool { return _pixels == nullptr; }

	[[nodiscard]] auto view() const noexcept -> ImageView {
		return {.data = _pixels, .size = bytes(), .width = _width, .height = _height};
	}

	friend auto view_of(const Bitmap& bmp) noexcept -> ImageView { return bmp.view(); }

private:
	uint32_t _width	 = 0;
	uint32_t _height = 0;
	char*	 _pixels = nullptr;
};

// PNG decoder backed by libspng, outputting RGBA8.
class PngImage {
public:
	explicit PngImage(const std::filesystem::path& path);
	PngImage(const char* data, size_t size);

	PngImage(PngImage&&) noexcept							   = default;
	auto operator=(PngImage&&) noexcept -> PngImage&		   = default;
	PngImage(const PngImage&)								   = delete;
	auto			   operator=(const PngImage&) -> PngImage& = delete;

	[[nodiscard]] auto data() const noexcept -> const char* { return _bitmap.data(); }

	[[nodiscard]] auto size() const noexcept -> size_t { return _bitmap.size(); }

	[[nodiscard]] auto width() const noexcept -> uint32_t { return _bitmap.width(); }

	[[nodiscard]] auto height() const noexcept -> uint32_t { return _bitmap.height(); }

	[[nodiscard]] auto empty() const noexcept -> bool { return _bitmap.empty(); }

	[[nodiscard]] auto view() const noexcept -> ImageView { return _bitmap.view(); }

	friend auto		   view_of(const PngImage& png) noexcept -> ImageView { return png.view(); }

private:
	Bitmap _bitmap;
};

// JPEG decoder backed by libjpeg-turbo, outputting RGBA8.
class JpgImage {
public:
	explicit JpgImage(const std::filesystem::path& path);
	JpgImage(const char* data, size_t size);

	JpgImage(JpgImage&&) noexcept							   = default;
	auto operator=(JpgImage&&) noexcept -> JpgImage&		   = default;
	JpgImage(const JpgImage&)								   = delete;
	auto			   operator=(const JpgImage&) -> JpgImage& = delete;

	[[nodiscard]] auto data() const noexcept -> const char* { return _bitmap.data(); }

	[[nodiscard]] auto size() const noexcept -> size_t { return _bitmap.size(); }

	[[nodiscard]] auto width() const noexcept -> uint32_t { return _bitmap.width(); }

	[[nodiscard]] auto height() const noexcept -> uint32_t { return _bitmap.height(); }

	[[nodiscard]] auto empty() const noexcept -> bool { return _bitmap.empty(); }

	[[nodiscard]] auto view() const noexcept -> ImageView { return _bitmap.view(); }

	friend auto		   view_of(const JpgImage& jpg) noexcept -> ImageView { return jpg.view(); }

private:
	Bitmap _bitmap;
};

// Sniffs the magic bytes and decodes to RGBA8 through the matching backend.
// Throws std::runtime_error for an unrecognised or corrupt file.
//
// NOTE: the returned view is non-owning, so it is only valid while the image it
// came from is alive. `decode_image` is meant for immediate use inside a
// full-expression; for anything longer-lived use `load_image` below.
[[nodiscard]] auto decode_image(const std::filesystem::path& path) -> ImageView;
[[nodiscard]] auto decode_image(const char* data, size_t size) -> ImageView;

// Format-agnostic owning image: sniffs the file and stores the decoded RGBA8
// pixels in a `Bitmap`, so it is safe to keep around. Move-only, nothrow-movable.
class AnyImage {
public:
	AnyImage() = default;

	explicit AnyImage(const std::filesystem::path& path);
	AnyImage(const char* data, size_t size);

	AnyImage(AnyImage&&) noexcept							   = default;
	auto operator=(AnyImage&&) noexcept -> AnyImage&		   = default;
	AnyImage(const AnyImage&)								   = delete;
	auto			   operator=(const AnyImage&) -> AnyImage& = delete;

	[[nodiscard]] auto data() const noexcept -> const char* { return _bitmap.data(); }

	[[nodiscard]] auto size() const noexcept -> size_t { return _bitmap.size(); }

	[[nodiscard]] auto width() const noexcept -> uint32_t { return _bitmap.width(); }

	[[nodiscard]] auto height() const noexcept -> uint32_t { return _bitmap.height(); }

	[[nodiscard]] auto empty() const noexcept -> bool { return _bitmap.empty(); }

	[[nodiscard]] auto view() const noexcept -> ImageView { return _bitmap.view(); }

	friend auto		   view_of(const AnyImage& img) noexcept -> ImageView { return img.view(); }

private:
	Bitmap _bitmap;
};

// Convenience alias: a decoded image you can safely hold on to.
[[nodiscard]] auto load_image(const std::filesystem::path& path) -> AnyImage;
[[nodiscard]] auto load_image(const char* data, size_t size) -> AnyImage;

// Encoders take the canonical RGBA8 buffer and write it out. The format is
// chosen by the output path's extension (".png" or ".jpg"/".jpeg"); anything
// else throws std::runtime_error. `quality` (1-100) only affects JPEG.
// Both throw std::runtime_error on I/O or encoding failure.
auto save_png(const ImageView& image, const std::filesystem::path& path) -> void;
auto save_jpg(const ImageView& image, const std::filesystem::path& path, int quality = 90) -> void;

// Picks the encoder from `path`'s extension. Throws for an unknown extension.
auto save_image(const ImageView& image, const std::filesystem::path& path, int quality = 90)
	-> void;

}  // namespace dcs229
