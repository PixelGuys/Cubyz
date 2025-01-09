# this file is temporary

# for x in range(17):
#     print(f"v {x / 16} 0 0")
#     print(f"v {x / 16} 0 0.0625")
#     print(f"v {x / 16} 1 0")
#     print(f"v {x / 16} 1 0.0625")

# for y in range(17):
#     print(f"v 0 {y / 16} 0")
#     print(f"v 0 {y / 16} 0.0625")
#     print(f"v 1 {y / 16} 0")
#     print(f"v 1 {y / 16} 0.0625")

# for x in range(17):
#     print(f"vt {x / 64 + 0.25} 0")
#     print(f"vt {x / 64 + 0.25} 0.25")

# for y in range(17):
#     print(f"vt 0.25 {y / 64}")
#     print(f"vt 0.5 {y / 64}")

for x in range(0, 16):
    n = 3
    print(f"f {x * 4 + 5}/{x * 2 + 5}/{n} {x * 4 + 6}/{x * 2 + 7}/{n} {x * 4 + 8}/{x * 2 + 8}/{n} {x * 4 + 7}/{x * 2 + 6}/{n}")

for x in range(0, 16):
    n = 5
    print(f"f {x * 4 + 6 + 68}/{x * 2 + 5 + 34}/{n} {x * 4 + 5 + 68}/{x * 2 + 7 + 34}/{n} {x * 4 + 7 + 68}/{x * 2 + 8 + 34}/{n} {x * 4 + 8 + 68}/{x * 2 + 6 + 34}/{n}")


# for x in range(1, 17):
#     n = 2
#     print(f"f {x * 4 + 7}/{x * 2 + 8 - 2}/{n} {x * 4 + 8}/{x * 2 + 6 - 2}/{n} {x * 4 + 6}/{x * 2 + 5 - 2}/{n} {x * 4 + 5}/{x * 2 + 7 - 2}/{n}")

# for x in range(1, 17):
#     n = 4
#     print(f"f {x * 4 + 5 + 68}/{x * 2 + 5 + 34 - 2}/{n} {x * 4 + 6 + 68}/{x * 2 + 7 + 34 - 2}/{n} {x * 4 + 8 + 68}/{x * 2 + 8 + 34 - 2}/{n} {x * 4 + 7 + 68}/{x * 2 + 6 + 34 - 2}/{n}")