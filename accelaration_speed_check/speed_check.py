import numpy as np
import time

kernel = np.array([[-1,-2,-1],[0,0,0],[1,2,1]], dtype=np.int32)

with open("image_rgb.bin", "rb") as f:
    data = np.frombuffer(f.read(96), dtype=np.uint8).reshape(3, 32).astype(np.int32)

N = 10000
start = time.perf_counter()
for _ in range(N):
    results = []
    for col in range(30):
        window = data[:, col:col+3]
        conv = np.sum(window * kernel)
        results.append(max(conv, 0))  # ReLU
    pooled = [max(results[i:i+4]) for i in range(0, 28, 4)]  # max pool, groups of 4
end = time.perf_counter()

avg_ns = (end - start) / N * 1e9
print(f"Software time: {avg_ns:.1f} ns")
print(f"Speedup vs FPGA (1420ns): {avg_ns/1420:.2f}x")