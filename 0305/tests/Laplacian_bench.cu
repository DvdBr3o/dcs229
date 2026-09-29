// Catch2 micro-benchmarks comparing the Laplacian-enhancement implementations.
//
// Run with:  xmake run 0305.bench
//            xmake run 0305.bench -- --benchmark-samples 50
//
// Variants: scalar CPU, tiled CPU, OpenMP CPU, AVX2 SIMD CPU, and (if a CUDA
// device is present) the GPU kernel. Each benchmark runs on a synthetic
// RGBA8 buffer at a realistic 256x256 and 1024x1024 resolution.

#include "Laplacian.cuh"
#include "LaplacianCpu.hpp"

#include "dcs229/Bench.hpp"
#include "dcs229/Image.hpp"

#include <catch2/benchmark/catch_benchmark.hpp>
#include <catch2/catch_test_macros.hpp>

#include <cstdint>
#include <vector>

namespace {
constexpr uint32_t kSmall = 256;
constexpr uint32_t kLarge = 1024;

auto			   make_noise(uint32_t width, uint32_t height) -> std::vector<char> {
	std::vector<char> buffer(static_cast<size_t>(width) * height * 4);
	uint32_t		  state = 0x1234'5678u;
	for (auto& byte : buffer) {
		state = state * 1664525u + 1013904223u;
		byte  = static_cast<char>(state >> 24);
	}
	// Opaque alpha.
	for (size_t i = 3; i < buffer.size(); i += 4) buffer[i] = static_cast<char>(0xFF);
	return buffer;
}

auto cuda_available_() -> bool {
	int count = 0;
	return cudaGetDeviceCount(&count) == cudaSuccess && count > 0;
}
}  // namespace

TEST_CASE("Laplacian CPU/GPU benchmarks (256x256)", "[laplacian][benchmark][!benchmark]") {
	auto			  src = make_noise(kSmall, kSmall);
	std::vector<char> dst(src.size());

	BENCHMARK("cpu scalar") {
		return dcs229::proj0305::laplacian_scalar(src.data(), dst.data(), kSmall, kSmall);
	};

	BENCHMARK("cpu tiled") {
		return dcs229::proj0305::laplacian_tiled(src.data(), dst.data(), kSmall, kSmall);
	};

	BENCHMARK("cpu openmp") {
		return dcs229::proj0305::laplacian_openmp(src.data(), dst.data(), kSmall, kSmall);
	};

	BENCHMARK("cpu simd (avx2)") {
		return dcs229::proj0305::laplacian_simd(src.data(), dst.data(), kSmall, kSmall);
	};

	if (cuda_available_())
		BENCHMARK("cuda") {
			return dcs229::proj0305::laplacian_sharpen(src.data(), dst.data(), kSmall, kSmall);
		};
}

TEST_CASE("Laplacian CPU/GPU benchmarks (1024x1024)", "[laplacian][benchmark][!benchmark]") {
	auto			  src = make_noise(kLarge, kLarge);
	std::vector<char> dst(src.size());

	BENCHMARK("cpu scalar") {
		return dcs229::proj0305::laplacian_scalar(src.data(), dst.data(), kLarge, kLarge);
	};

	BENCHMARK("cpu tiled") {
		return dcs229::proj0305::laplacian_tiled(src.data(), dst.data(), kLarge, kLarge);
	};

	BENCHMARK("cpu openmp") {
		return dcs229::proj0305::laplacian_openmp(src.data(), dst.data(), kLarge, kLarge);
	};

	BENCHMARK("cpu simd (avx2)") {
		return dcs229::proj0305::laplacian_simd(src.data(), dst.data(), kLarge, kLarge);
	};

	if (cuda_available_())
		BENCHMARK("cuda") {
			return dcs229::proj0305::laplacian_sharpen(src.data(), dst.data(), kLarge, kLarge);
		};
}
