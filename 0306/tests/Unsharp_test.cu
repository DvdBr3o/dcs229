// Catch2 tests for the unsharp-masking image-enhancement operator.
//
// Strategy:
//  * tiny synthetic buffers give exact, hand-checkable answers (constant, step,
//    impulse) against the host reference;
//  * the classic DIP photos in ./data exercise the real decode + enhance path
//    and let us assert qualitative properties (edges boosted, amount=0 is the
//    identity, alpha untouched) plus CUDA/reference parity.

#include "Unsharp.cuh"
#include "UnsharpCpu.hpp"

#include "dcs229/Image.hpp"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_floating_point.hpp>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

// A raw RGBA8 buffer is not text: format it as byte values so Catch2 never tries
// to build a std::string from arbitrary pixel bytes.
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
using dcs229::proj0306::unsharp_reference;

template<typename T>
auto as_u8(T* p) -> auto {
	return reinterpret_cast<std::conditional_t<std::is_const_v<T>, const uint8_t, uint8_t>*>(p);
}

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

auto run_reference(
	const std::vector<char>& src, uint32_t width, uint32_t height, float sigma, float amount
) -> std::vector<char> {
	std::vector<char> out(src.size());
	unsharp_reference<uint8_t>(
		as_u8(src.data()),
		as_u8(out.data()),
		width,
		height,
		4,
		static_cast<size_t>(width) * 4,
		sigma,
		amount
	);
	return out;
}

auto channel(const std::vector<char>& buffer, uint32_t width, uint32_t x, uint32_t y, size_t c)
	-> int {
	return static_cast<unsigned char>(buffer[(static_cast<size_t>(y) * width + x) * 4 + c]);
}

auto cuda_available() -> bool {
	int count = 0;
	return cudaGetDeviceCount(&count) == cudaSuccess && count > 0;
}
}  // namespace

TEST_CASE("gaussian kernel is normalised and symmetric", "[unsharp][reference]") {
	const auto kernel = dcs229::proj0306::gaussian_kernel(1.5f);
	float	   sum	  = 0.0f;
	for (float weight : kernel) sum += weight;
	REQUIRE(sum == Catch::Approx(1.0f).epsilon(1e-5));

	for (size_t i = 0; i < kernel.size(); ++i)
		REQUIRE(kernel[i] == Catch::Approx(kernel[kernel.size() - 1 - i]).epsilon(1e-6));
}

TEST_CASE("constant image is unchanged by unsharp masking", "[unsharp][reference]") {
	constexpr uint32_t	 w = 8, h = 7;
	std::vector<uint8_t> levels(w * h, 130);
	auto				 src = make_gray(levels, w, h);
	auto				 out = run_reference(src, w, h, 1.5f, 1.0f);
	// A constant image has zero mask, so g = f exactly.
	REQUIRE(out == src);
}

TEST_CASE("amount = 0 is the identity", "[unsharp][reference]") {
	constexpr uint32_t	 w = 9, h = 6;
	std::vector<uint8_t> levels(w * h);
	for (size_t i = 0; i < levels.size(); ++i) levels[i] = static_cast<uint8_t>((i * 41) % 256);
	auto src = make_gray(levels, w, h);
	auto out = run_reference(src, w, h, 2.0f, 0.0f);
	REQUIRE(out == src);
}

TEST_CASE("alpha channel is never modified", "[unsharp][reference]") {
	constexpr uint32_t w = 6, h = 6;
	std::vector<char>  src(w * h * 4, 0);
	for (size_t i = 0; i < static_cast<size_t>(w) * h; ++i) {
		src[i * 4 + 0] = static_cast<char>(i * 11);
		src[i * 4 + 1] = static_cast<char>(255 - i * 11);
		src[i * 4 + 2] = static_cast<char>(i * 7);
		src[i * 4 + 3] = static_cast<char>(120 + (i % 32));	 // distinct alphas
	}
	auto out = run_reference(src, w, h, 1.5f, 1.5f);
	for (size_t i = 0; i < static_cast<size_t>(w) * h; ++i)
		REQUIRE(out[i * 4 + 3] == src[i * 4 + 3]);
}

TEST_CASE(
	"step edge overshoots on the bright side and undershoots on the dark side",
	"[unsharp][reference]"
) {
	// Vertical step: left half 60, right half 190.
	constexpr uint32_t	 w = 12, h = 8;
	std::vector<uint8_t> levels(w * h, 60);
	for (uint32_t y = 0; y < h; ++y)
		for (uint32_t x = 6; x < w; ++x) levels[y * w + x] = 190;
	auto src = make_gray(levels, w, h);
	auto out = run_reference(src, w, h, 1.0f, 1.5f);

	// On the dark side of the step the blur pulls the value up, so f - blur < 0
	// and the pixel gets darker; on the bright side it gets brighter.
	REQUIRE(channel(out, w, 5, 4, 0) < channel(src, w, 5, 4, 0));
	REQUIRE(channel(out, w, 6, 4, 0) > channel(src, w, 6, 4, 0));
	// Far from the edge nothing changes.
	REQUIRE(channel(out, w, 0, 4, 0) == channel(src, w, 0, 4, 0));
	REQUIRE(channel(out, w, w - 1, 4, 0) == channel(src, w, w - 1, 4, 0));
}

TEST_CASE(
	"an isolated impulse is dimmed while its neighbours are boosted", "[unsharp][reference]"
) {
	constexpr uint32_t	 w = 9, h = 9;
	std::vector<uint8_t> levels(w * h, 80);
	levels[4 * w + 4] = 220;
	auto src		  = make_gray(levels, w, h);
	auto out		  = run_reference(src, w, h, 1.0f, 1.0f);

	// The centre is brighter than its neighbourhood, so blur < f and the mask is
	// positive: the impulse grows (clamped toward 255). The neighbours get a
	// negative mask and darken.
	REQUIRE(channel(out, w, 4, 4, 0) >= channel(src, w, 4, 4, 0));
	REQUIRE(channel(out, w, 4, 3, 0) < channel(src, w, 4, 3, 0));
}

TEST_CASE("larger amount sharpens more", "[unsharp][reference]") {
	constexpr uint32_t	 w = 10, h = 10;
	std::vector<uint8_t> levels(w * h, 90);
	levels[5 * w + 5] = 200;
	auto src		  = make_gray(levels, w, h);
	auto mild		  = run_reference(src, w, h, 1.0f, 0.5f);
	auto hard		  = run_reference(src, w, h, 1.0f, 2.0f);

	// Darkening at a neighbour scales with the amount.
	REQUIRE(channel(hard, w, 5, 4, 0) <= channel(mild, w, 5, 4, 0));
	REQUIRE(channel(hard, w, 5, 4, 0) < channel(src, w, 5, 4, 0));
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

TEST_CASE("classic sample images decode to the canonical RGBA8 format", "[unsharp][data]") {
	for (const char* name : {"lena.png", "baboon.png", "board.png", "checkerboard.png"}) {
		auto image = require_image(name);
		INFO(name);
		REQUIRE(image.width() == 256);
		REQUIRE(image.height() == 256);
		REQUIRE(image.size() == static_cast<size_t>(image.width()) * image.height() * 4);
	}
}

TEST_CASE("unsharp masking increases mean local gradient on a real photo", "[unsharp][data]") {
	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();
	std::vector<char> out(image.size());
	dcs229::proj0306::unsharp_sharpen(image.data(), out.data(), w, h, 1.5f, 1.0f);

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

// ---------------------------------------------------------------------------
// CUDA / reference parity.
// ---------------------------------------------------------------------------

TEST_CASE("CUDA kernel matches the host reference on a real image", "[unsharp][cuda][data]") {
	if (!cuda_available())
		SKIP("no CUDA device available");

	auto			  image = require_image("lena.png");
	const uint32_t	  w = image.width(), h = image.height();

	std::vector<char> gpu(image.size());
	std::vector<char> ref(image.size());
	dcs229::proj0306::unsharp_sharpen(image.data(), gpu.data(), w, h, 1.5f, 1.0f);
	unsharp_reference<uint8_t>(
		as_u8(image.data()),
		as_u8(ref.data()),
		w,
		h,
		4,
		static_cast<size_t>(w) * 4,
		1.5f,
		1.0f
	);

	// The GPU uses a float intermediate and rounds with +0.5 while the reference
	// truncates, so allow a small per-pixel tolerance.
	int max_diff = 0;
	for (size_t i = 0; i < gpu.size(); ++i)
		max_diff = std::max(
			max_diff,
			std::abs(
				static_cast<int>(static_cast<unsigned char>(gpu[i]))
				- static_cast<int>(static_cast<unsigned char>(ref[i]))
			)
		);
	INFO("max abs difference = " << max_diff);
	REQUIRE(max_diff <= 1);
}

TEST_CASE("CUDA kernel handles small odd sizes without out-of-bounds", "[unsharp][cuda]") {
	if (!cuda_available())
		SKIP("no CUDA device available");

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
		dcs229::proj0306::unsharp_sharpen(src.data(), gpu.data(), w, h, 1.0f, 1.0f);
		unsharp_reference<
			uint8_t>(as_u8(src.data()), as_u8(ref.data()), w, h, 4, w * 4, 1.0f, 1.0f);
		INFO(w << "x" << h);
		for (size_t i = 0; i < gpu.size(); ++i)
			REQUIRE(
				std::abs(
					static_cast<int>(static_cast<unsigned char>(gpu[i]))
					- static_cast<int>(static_cast<unsigned char>(ref[i]))
				)
				<= 1
			);
	}
}

// ---------------------------------------------------------------------------
// CPU implementation parity: every CPU variant must match the host reference.
// ---------------------------------------------------------------------------

namespace {
using dcs229::proj0306::unsharp_openmp;
using dcs229::proj0306::unsharp_scalar;
using dcs229::proj0306::unsharp_simd;
using dcs229::proj0306::unsharp_tiled;

auto check_cpu_variants(
	const std::vector<char>& src, uint32_t width, uint32_t height, float sigma, float amount
) -> void {
	std::vector<char> ref(src.size());
	unsharp_reference<uint8_t>(
		as_u8(src.data()),
		as_u8(ref.data()),
		width,
		height,
		4,
		static_cast<size_t>(width) * 4,
		sigma,
		amount
	);

	const auto require_close = [&](const char* name, auto run) {
		std::vector<char> out(src.size());
		run(out.data());
		INFO(name << " " << width << "x" << height);
		for (size_t i = 0; i < out.size(); ++i)
			REQUIRE(
				std::abs(
					static_cast<int>(static_cast<unsigned char>(out[i]))
					- static_cast<int>(static_cast<unsigned char>(ref[i]))
				)
				<= 1
			);
	};

	require_close("scalar", [&](char* dst) {
		unsharp_scalar(src.data(), dst, width, height, sigma, amount);
	});
	require_close("tiled", [&](char* dst) {
		unsharp_tiled(src.data(), dst, width, height, sigma, amount);
	});
	require_close("openmp", [&](char* dst) {
		unsharp_openmp(src.data(), dst, width, height, sigma, amount);
	});
	require_close("simd", [&](char* dst) {
		unsharp_simd(src.data(), dst, width, height, sigma, amount);
	});
}
}  // namespace

TEST_CASE("all CPU variants match the reference on synthetic buffers", "[unsharp][cpu]") {
	for (const auto& [w, h] : {
			 std::pair<uint32_t, uint32_t> {24, 24},
			 { 3,	 3},
			 { 1,	 9},
			 {33,  7},
			 { 7, 33}
	 }) {
		std::vector<uint8_t> levels(static_cast<size_t>(w) * h);
		for (size_t i = 0; i < levels.size(); ++i) levels[i] = static_cast<uint8_t>((i * 97) % 256);
		check_cpu_variants(make_gray(levels, w, h), w, h, 1.5f, 1.0f);
	}
}

TEST_CASE("all CPU variants match the reference on a real image", "[unsharp][cpu][data]") {
	auto image = require_image("lena.png");
	check_cpu_variants(
		std::vector<char>(image.data(), image.data() + image.size()),
		image.width(),
		image.height(),
		1.5f,
		1.0f
	);
}
