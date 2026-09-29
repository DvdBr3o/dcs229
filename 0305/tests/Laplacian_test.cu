// Catch2 tests for the Laplacian image-enhancement operator.
//
// Strategy:
//  * tiny synthetic buffers give exact, hand-checkable answers (impulse, step,
//    constant, checkerboard) against the host reference;
//  * the classic DIP photos in ./data exercise the real decode + enhance path
//    and let us assert qualitative properties (edges boosted, flat areas
//    preserved, alpha untouched) plus CUDA/reference parity.

#include "Laplacian.cuh"
#include "LaplacianCpu.hpp"

#include "dcs229/Image.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <type_traits>
#include <filesystem>
#include <string>
#include <utility>
#include <vector>

// A raw RGBA8 buffer is not text: format it as byte values so Catch2 never
// tries to build a std::string from arbitrary pixel bytes.
namespace Catch {
template<>
struct StringMaker<std::vector<char>> {
	static auto convert(const std::vector<char>& value) -> std::string {
		std::string out = "{ ";
		for (size_t i = 0; i < value.size(); ++i) {
			if (i != 0)
				out += ", ";
			out += std::to_string(static_cast<unsigned char>(value[i]));
		}
		out += " }";
		return out;
	}
};
}  // namespace Catch

namespace {
using dcs229::proj0305::sharpen_reference;

// Build a packed RGBA8 buffer from 8-bit grey levels (alpha = 255).
auto make_gray(const std::vector<uint8_t>& levels, uint32_t width, uint32_t height)
	-> std::vector<char> {
	REQUIRE(levels.size() == static_cast<size_t>(width) * height);
	std::vector<char> buffer(levels.size() * 4);
	for (size_t i = 0; i < levels.size(); ++i) {
		buffer[i * 4 + 0] = static_cast<char>(levels[i]);
		buffer[i * 4 + 1] = static_cast<char>(levels[i]);
		buffer[i * 4 + 2] = static_cast<char>(levels[i]);
		buffer[i * 4 + 3] = static_cast<char>(0xFF);
	}
	return buffer;
}
}  // namespace

// ---------------------------------------------------------------------------
// Helpers for the host reference.
// ---------------------------------------------------------------------------
namespace {
template<typename T>
auto as_u8(T* p) -> auto {
	return reinterpret_cast<std::conditional_t<std::is_const_v<T>, const uint8_t, uint8_t>*>(p);
}

auto run_reference(const std::vector<char>& src, uint32_t width, uint32_t height)
	-> std::vector<char> {
	std::vector<char> out(src.size());
	sharpen_reference<uint8_t>(
		as_u8(src.data()),
		as_u8(out.data()),
		width,
		height,
		4,
		static_cast<size_t>(width) * 4
	);
	return out;
}

auto channel(const std::vector<char>& buffer, uint32_t width, uint32_t x, uint32_t y, size_t c)
	-> int {
	return static_cast<unsigned char>(buffer[(static_cast<size_t>(y) * width + x) * 4 + c]);
}
}  // namespace

TEST_CASE("constant image is unchanged by the Laplacian enhancement", "[laplacian][reference]") {
	constexpr uint32_t	 w = 5, h = 4;
	std::vector<uint8_t> levels(w * h, 120);
	auto				 src = make_gray(levels, w, h);
	auto				 out = run_reference(src, w, h);
	REQUIRE(out == src);
}

TEST_CASE("borders are copied through untouched", "[laplacian][reference]") {
	constexpr uint32_t	 w = 6, h = 5;
	std::vector<uint8_t> levels;
	levels.reserve(w * h);
	for (size_t i = 0; i < w * h; ++i) levels.push_back(static_cast<uint8_t>((i * 37) % 256));
	auto src = make_gray(levels, w, h);
	auto out = run_reference(src, w, h);

	for (uint32_t x = 0; x < w; ++x) {
		REQUIRE(channel(out, w, x, 0, 0) == channel(src, w, x, 0, 0));
		REQUIRE(channel(out, w, x, h - 1, 0) == channel(src, w, x, h - 1, 0));
	}
	for (uint32_t y = 0; y < h; ++y) {
		REQUIRE(channel(out, w, 0, y, 0) == channel(src, w, 0, y, 0));
		REQUIRE(channel(out, w, w - 1, y, 0) == channel(src, w, w - 1, y, 0));
	}
}

TEST_CASE("alpha channel is never modified", "[laplacian][reference]") {
	constexpr uint32_t w = 4, h = 4;
	std::vector<char>  src(w * h * 4, 0);
	for (size_t i = 0; i < static_cast<size_t>(w) * h; ++i) {
		src[i * 4 + 0] = static_cast<char>(i * 12);
		src[i * 4 + 1] = static_cast<char>(255 - i * 12);
		src[i * 4 + 2] = static_cast<char>(i * 5);
		src[i * 4 + 3] = static_cast<char>(100 + i);  // distinct alphas
	}
	auto out = run_reference(src, w, h);
	for (size_t i = 0; i < static_cast<size_t>(w) * h; ++i)
		REQUIRE(out[i * 4 + 3] == src[i * 4 + 3]);
}

TEST_CASE("isolated impulse produces the known 5/-1 kernel response", "[laplacian][reference]") {
	// Bright pixel in a flat field of 100: g = f - Lap{f}.
	// Centre (2,2): f=200, the four neighbours are 100, so Lap = 400 - 4*200 = -400,
	//               g = 200 + 400 = 600 -> clamp 255.
	// 4-neighbours of the impulse, e.g. (2,1): f=100, its own neighbours include the
	//               impulse (200) and three 100s, so Lap = 200 + 300 - 400 = 100,
	//               g = 100 - 100 = 0.
	// Diagonals like (1,1) never see the impulse, Lap = 0, g = 100 unchanged.
	constexpr uint32_t	 w = 5, h = 5;
	std::vector<uint8_t> levels(w * h, 100);
	levels[2 * w + 2] = 200;
	auto src		  = make_gray(levels, w, h);
	auto out		  = run_reference(src, w, h);

	REQUIRE(channel(out, w, 2, 2, 0) == 255);
	REQUIRE(channel(out, w, 2, 1, 0) == 0);
	REQUIRE(channel(out, w, 1, 2, 0) == 0);
	REQUIRE(channel(out, w, 3, 2, 0) == 0);
	REQUIRE(channel(out, w, 2, 3, 0) == 0);
	// Diagonals and everything else stay flat.
	REQUIRE(channel(out, w, 1, 1, 0) == 100);
	REQUIRE(channel(out, w, 0, 0, 0) == 100);
}

TEST_CASE(
	"flat field adjacent to an edge is darkened then sharpened correctly", "[laplacian][reference]"
) {
	// Vertical step: left half 50, right half 200 (interior columns only).
	constexpr uint32_t	 w = 6, h = 6;
	std::vector<uint8_t> levels(w * h, 50);
	for (uint32_t y = 0; y < h; ++y)
		for (uint32_t x = 3; x < w; ++x) levels[y * w + x] = 200;
	auto src = make_gray(levels, w, h);
	auto out = run_reference(src, w, h);

	// Column 2 (dark side of the step): f=50, right neighbour=200, Lap=150, g=50-150 -> 0.
	REQUIRE(channel(out, w, 2, 2, 0) == 0);
	// Column 3 (bright side): f=200, left neighbour=50, Lap=-150, g=200+150 -> 350 -> 255.
	REQUIRE(channel(out, w, 3, 2, 0) == 255);
	// Far from the edge the field is flat and unchanged.
	REQUIRE(channel(out, w, 1, 2, 0) == 50);
	REQUIRE(channel(out, w, 4, 2, 0) == 200);
}

TEST_CASE("checkerboard is amplified at every interior pixel", "[laplacian][reference]") {
	constexpr uint32_t	 w = 6, h = 6;
	std::vector<uint8_t> levels(w * h);
	for (uint32_t y = 0; y < h; ++y)
		for (uint32_t x = 0; x < w; ++x) levels[y * w + x] = ((x + y) % 2 == 0) ? 0 : 255;
	auto src = make_gray(levels, w, h);
	auto out = run_reference(src, w, h);

	// Interior 0-pixel: four neighbours are 255, Lap = 4*255 = 1020, g = -1020 -> 0.
	// Interior 255-pixel: four neighbours are 0, Lap = -1020, g = 255 + 1020 -> 255.
	// So a perfect checkerboard stays a checkerboard (clamped at both rails).
	for (uint32_t y = 1; y + 1 < h; ++y)
		for (uint32_t x = 1; x + 1 < w; ++x)
			REQUIRE(channel(out, w, x, y, 0) == channel(src, w, x, y, 0));
}

TEST_CASE("float reference matches the integer path after clamping", "[laplacian][reference]") {
	constexpr uint32_t	 w = 7, h = 5;
	std::vector<uint8_t> levels(w * h);
	for (size_t i = 0; i < levels.size(); ++i) levels[i] = static_cast<uint8_t>((i * 53) % 256);
	auto src_u8 = make_gray(levels, w, h);

	// Same pixels, but stored as float RGBA.
	std::vector<float> src_f32(static_cast<size_t>(w) * h * 4);
	for (size_t i = 0; i < levels.size(); ++i) {
		const auto v	   = static_cast<float>(levels[i]);
		src_f32[i * 4 + 0] = v;
		src_f32[i * 4 + 1] = v;
		src_f32[i * 4 + 2] = v;
		src_f32[i * 4 + 3] = 255.0f;
	}

	std::vector<char>  out_u8(src_u8.size());
	std::vector<float> out_f32(src_f32.size());
	sharpen_reference<uint8_t>(as_u8(src_u8.data()), as_u8(out_u8.data()), w, h, 4, w * 4);
	sharpen_reference<float>(src_f32.data(), out_f32.data(), w, h, 4, w * 4);

	for (size_t i = 0; i < levels.size(); ++i) {
		for (size_t c = 0; c < 3; ++c) {
			// The uint8 path clamps to [0, 255]; clamp the float result to match.
			const float clamped = std::clamp(out_f32[i * 4 + c], 0.0f, 255.0f);
			REQUIRE(static_cast<int>(out_u8[i * 4 + c] & 0xFF) == static_cast<int>(clamped));
		}
		REQUIRE(out_f32[i * 4 + 3] == 255.0f);	// alpha untouched
	}
}

// ---------------------------------------------------------------------------
// Tests over the classic digital-image-processing sample photographs.
// ---------------------------------------------------------------------------

namespace {
auto data_dir() -> std::filesystem::path {
	return std::filesystem::path(DCS229_TEST_DATA_DIR);
}

auto require_image(const char* name) -> dcs229::PngImage {
	auto path = data_dir() / name;
	REQUIRE(std::filesystem::exists(path));
	return dcs229::PngImage(path);
}
}  // namespace

TEST_CASE("classic sample images decode to the canonical RGBA8 format", "[laplacian][data]") {
	for (const char* name : {"lena.png", "baboon.png", "board.png", "checkerboard.png"}) {
		auto image = require_image(name);
		INFO(name);
		REQUIRE(image.width() == 256);
		REQUIRE(image.height() == 256);
		REQUIRE(image.size() == static_cast<size_t>(image.width()) * image.height() * 4);
	}
}

TEST_CASE(
	"Canny-style quantitative check: mean gradient magnitude increases", "[laplacian][data]"
) {
	// Sharpening must boost local contrast: the mean absolute Laplacian response
	// of the output should exceed that of the input on a real photograph.
	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();
	std::vector<char> out(image.size());
	dcs229::proj0305::laplacian_sharpen(image.data(), out.data(), w, h);

	auto mean_abs_gradient = [&](const char* buf) {
		double sum = 0;
		size_t n   = 0;
		for (uint32_t y = 1; y + 1 < h; ++y) {
			for (uint32_t x = 1; x + 1 < w; ++x) {
				for (size_t c = 0; c < 3; ++c) {
					const auto idx = [&](uint32_t sx, uint32_t sy) {
						return (static_cast<size_t>(sy) * w + sx) * 4 + c;
					};
					const int center = static_cast<unsigned char>(buf[idx(x, y)]);
					const int lap	 = static_cast<unsigned char>(buf[idx(x, y - 1)])
									 + static_cast<unsigned char>(buf[idx(x, y + 1)])
									 + static_cast<unsigned char>(buf[idx(x - 1, y)])
									 + static_cast<unsigned char>(buf[idx(x + 1, y)]) - 4 * center;
					sum += std::abs(lap);
					++n;
				}
			}
		}
		return sum / static_cast<double>(n);
	};

	REQUIRE(mean_abs_gradient(out.data()) > mean_abs_gradient(image.data()));
}

TEST_CASE("flat pixels of a real photo are left unchanged", "[laplacian][data]") {
	// Wherever a colour channel has zero Laplacian (locally constant along the
	// cross), the enhancement is the identity for that channel. Natural photos
	// contain many such pixels, so this also guards against spurious changes.
	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();
	std::vector<char> out(image.size());
	dcs229::proj0305::laplacian_sharpen(image.data(), out.data(), w, h);

	auto idx = [&](uint32_t x, uint32_t y, size_t c) {
		return (static_cast<size_t>(y) * w + x) * 4 + c;
	};

	size_t flat = 0;
	for (uint32_t y = 1; y + 1 < h; ++y) {
		for (uint32_t x = 1; x + 1 < w; ++x) {
			for (size_t c = 0; c < 3; ++c) {
				const int center = static_cast<unsigned char>(image.data()[idx(x, y, c)]);
				const int lap	 = static_cast<unsigned char>(image.data()[idx(x, y - 1, c)])
								 + static_cast<unsigned char>(image.data()[idx(x, y + 1, c)])
								 + static_cast<unsigned char>(image.data()[idx(x - 1, y, c)])
								 + static_cast<unsigned char>(image.data()[idx(x + 1, y, c)])
								 - 4 * center;
				if (lap != 0)
					continue;
				++flat;
				REQUIRE(out[idx(x, y, c)] == image.data()[idx(x, y, c)]);
			}
		}
	}
	REQUIRE(flat > 0);	// a natural photo must contain locally-flat pixels
}

// Whether a usable CUDA device is present; used to skip the GPU tests cleanly
// without catching Catch2's internal SKIP exception.
namespace {
auto cuda_available() -> bool {
	int count = 0;
	return cudaGetDeviceCount(&count) == cudaSuccess && count > 0;
}
}  // namespace

TEST_CASE("CUDA kernel matches the host reference on a real image", "[laplacian][cuda][data]") {
	if (!cuda_available())
		SKIP("no CUDA device available");

	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();

	std::vector<char> gpu(image.size());
	std::vector<char> ref(image.size());
	dcs229::proj0305::laplacian_sharpen(image.data(), gpu.data(), w, h);
	sharpen_reference<uint8_t>(
		as_u8(image.data()),
		as_u8(ref.data()),
		w,
		h,
		4,
		static_cast<size_t>(w) * 4
	);

	REQUIRE(gpu == ref);
}

TEST_CASE("CUDA kernel handles small odd sizes without out-of-bounds", "[laplacian][cuda]") {
	if (!cuda_available())
		SKIP("no CUDA device available");

	// 3x3 and 1xN force partial blocks and degenerate borders.
	for (const auto& [w, h] : {
			 std::pair<uint32_t, uint32_t> {3, 3},
			 {1, 7},
			 {7, 1}
	 }) {
		std::vector<uint8_t> levels(w * h);
		for (size_t i = 0; i < levels.size(); ++i) levels[i] = static_cast<uint8_t>((i * 71) % 256);
		auto			  src = make_gray(levels, w, h);

		std::vector<char> gpu(src.size());
		std::vector<char> ref(src.size());
		dcs229::proj0305::laplacian_sharpen(src.data(), gpu.data(), w, h);
		sharpen_reference<uint8_t>(as_u8(src.data()), as_u8(ref.data()), w, h, 4, w * 4);
		INFO(w << "x" << h);
		REQUIRE(gpu == ref);
	}
}

// ---------------------------------------------------------------------------
// Encoder tests: the CLI writes the enhanced image through these.
// ---------------------------------------------------------------------------

namespace {
auto temp_path(const char* stem, const char* ext) -> std::filesystem::path {
	return std::filesystem::temp_directory_path() / (std::string(stem) + ext);
}

auto as_view(const std::vector<char>& buffer, uint32_t width, uint32_t height)
	-> dcs229::ImageView {
	return {.data = buffer.data(), .size = buffer.size(), .width = width, .height = height};
}
}  // namespace

TEST_CASE("PNG encode is lossless through decode", "[encode][data]") {
	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();
	std::vector<char> enhanced(image.size());
	dcs229::proj0305::laplacian_sharpen(image.data(), enhanced.data(), w, h);

	const auto path = temp_path("dcs229_encode_test", ".png");
	dcs229::save_png(as_view(enhanced, w, h), path);
	REQUIRE(std::filesystem::exists(path));

	auto reloaded = dcs229::load_image(path);
	REQUIRE(reloaded.width() == w);
	REQUIRE(reloaded.height() == h);
	REQUIRE(
		std::equal(
			enhanced.begin(),
			enhanced.end(),
			reloaded.data(),
			reloaded.data() + reloaded.size()
		)
	);

	std::filesystem::remove(path);
}

TEST_CASE("JPEG encode round-trips within a lossy tolerance", "[encode][data]") {
	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();
	std::vector<char> enhanced(image.size());
	dcs229::proj0305::laplacian_sharpen(image.data(), enhanced.data(), w, h);

	const auto path = temp_path("dcs229_encode_test", ".jpg");
	dcs229::save_jpg(as_view(enhanced, w, h), path, 95);

	auto reloaded = dcs229::load_image(path);
	REQUIRE(reloaded.width() == w);
	REQUIRE(reloaded.height() == h);

	// JPEG at quality 95 is not exact, but should stay close on average.
	double sum = 0;
	for (size_t i = 0; i < enhanced.size(); ++i)
		sum += std::abs(
			static_cast<int>(static_cast<unsigned char>(enhanced[i]))
			- static_cast<int>(static_cast<unsigned char>(reloaded.data()[i]))
		);
	const double mean_abs = sum / static_cast<double>(enhanced.size());
	INFO("mean abs error = " << mean_abs);
	REQUIRE(mean_abs < 5.0);

	std::filesystem::remove(path);
}

TEST_CASE("save_image dispatches on the extension and rejects unknown ones", "[encode]") {
	constexpr uint32_t w = 4, h = 4;
	std::vector<char>  pixels(static_cast<size_t>(w) * h * 4, 100);
	for (size_t i = 0; i < pixels.size(); i += 4) pixels[i + 3] = static_cast<char>(0xFF);

	for (const char* ext : {".png", ".PNG", ".jpg", ".jpeg"}) {
		const auto path = temp_path("dcs229_save_image_test", ext);
		REQUIRE_NOTHROW(dcs229::save_image(as_view(pixels, w, h), path));
		REQUIRE(std::filesystem::exists(path));
		std::filesystem::remove(path);
	}

	const auto bad = temp_path("dcs229_save_image_test", ".bmp");
	REQUIRE_THROWS(dcs229::save_image(as_view(pixels, w, h), bad));
	REQUIRE_FALSE(std::filesystem::exists(bad));
}

// ---------------------------------------------------------------------------
// CPU implementation parity: every CPU variant must match the host reference.
// ---------------------------------------------------------------------------

namespace {
using dcs229::proj0305::laplacian_openmp;
using dcs229::proj0305::laplacian_scalar;
using dcs229::proj0305::laplacian_simd;
using dcs229::proj0305::laplacian_tiled;

auto check_cpu_variants(const std::vector<char>& src, uint32_t width, uint32_t height) -> void {
	std::vector<char> ref(src.size());
	sharpen_reference<uint8_t>(
		as_u8(src.data()),
		as_u8(ref.data()),
		width,
		height,
		4,
		static_cast<size_t>(width) * 4
	);

	const auto require_equal = [&](const char* name, auto run) {
		std::vector<char> out(src.size());
		run(out.data());
		INFO(name << " " << width << "x" << height);
		REQUIRE(out == ref);
	};

	require_equal("scalar", [&](char* dst) { laplacian_scalar(src.data(), dst, width, height); });
	require_equal("tiled", [&](char* dst) { laplacian_tiled(src.data(), dst, width, height); });
	require_equal("openmp", [&](char* dst) { laplacian_openmp(src.data(), dst, width, height); });
	require_equal("simd", [&](char* dst) { laplacian_simd(src.data(), dst, width, height); });
}
}  // namespace

TEST_CASE("all CPU variants match the reference on synthetic buffers", "[laplacian][cpu]") {
	for (const auto& [w, h] : {
			 std::pair<uint32_t, uint32_t> {16, 16},
			 { 3,	 3},
			 { 1,	 9},
			 { 9,	 1},
			 {17,  5},
			 { 5, 17}
	 }) {
		std::vector<uint8_t> levels(static_cast<size_t>(w) * h);
		for (size_t i = 0; i < levels.size(); ++i) levels[i] = static_cast<uint8_t>((i * 97) % 256);
		check_cpu_variants(make_gray(levels, w, h), w, h);
	}
}

TEST_CASE("all CPU variants match the reference on a real image", "[laplacian][cpu][data]") {
	auto image = require_image("lena.png");
	check_cpu_variants(
		std::vector<char>(image.data(), image.data() + image.size()),
		image.width(),
		image.height()
	);
}
