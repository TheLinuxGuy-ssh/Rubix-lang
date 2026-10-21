#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=================================================="
echo "    Rubix Language (.ix) Compiler Test Suite"
echo "    (Compiler implemented in 100% pure x86-64 assembly)"
echo "=================================================="

# 1. Build the compiler from source assembly
echo "[1/18] Building rubix_compiler with GNU as & ld..."
as src/main.s -o rubix_compiler.o
ld rubix_compiler.o -o rubix_compiler
rm -f rubix_compiler.o
echo "       rubix_compiler build OK!"

# 2. Test 01_hello.ix
echo "[2/18] Testing examples/01_hello.ix..."
./rubixc -r examples/01_hello.ix > /tmp/rubix_t1.out
grep -q "Hello from Rubix language" /tmp/rubix_t1.out
echo "       Test 01 PASSED!"

# 3. Test 02_arithmetic.ix
echo "[3/18] Testing examples/02_arithmetic.ix..."
./rubixc -r examples/02_arithmetic.ix > /tmp/rubix_t2.out
grep -q "a \* b = 420" /tmp/rubix_t2.out
grep -q "(a + b) \* 2 - 4 = 100" /tmp/rubix_t2.out
echo "       Test 02 PASSED!"

# 4. Test 03_control_flow.ix
echo "[4/18] Testing examples/03_control_flow.ix..."
./rubixc -r examples/03_control_flow.ix > /tmp/rubix_t3.out
grep -q "Sum of 1 to 10 = 55" /tmp/rubix_t3.out
echo "       Test 03 PASSED!"

# 5. Test 04_functions.ix
echo "[5/18] Testing examples/04_functions.ix..."
./rubixc -r examples/04_functions.ix > /tmp/rubix_t4.out
grep -q "max(42, 100) = 100" /tmp/rubix_t4.out
grep -q "55" /tmp/rubix_t4.out
echo "       Test 04 PASSED!"

# 6. Test 05_prime_numbers.ix
echo "[6/18] Testing examples/05_prime_numbers.ix..."
./rubixc -r examples/05_prime_numbers.ix > /tmp/rubix_t5.out
grep -q "Total prime numbers found: 15" /tmp/rubix_t5.out
echo "       Test 05 PASSED!"

# 7. Test 06_arrays.ix (Dynamic heap alloc, indexing, array literals, free)
echo "[7/18] Testing examples/06_arrays.ix (Heap, Indexing, Literals)..."
./rubixc -r examples/06_arrays.ix > /tmp/rubix_t6.out
grep -q "300" /tmp/rubix_t6.out
grep -q "50" /tmp/rubix_t6.out
echo "       Test 06 PASSED!"

# 8. Test 07_types_and_logic.ix (Booleans, Chars, Logic, Optional Types)
echo "[8/18] Testing examples/07_types_and_logic.ix (Bool, Char, &&, ||, !)..."
./rubixc -r examples/07_types_and_logic.ix > /tmp/rubix_t7.out
grep -q "R" /tmp/rubix_t7.out
echo "       Test 07 PASSED!"

# 9. Test 08_many_params.ix (Unbounded >6 parameters)
echo "[9/18] Testing examples/08_many_params.ix (8 parameters caller/callee)..."
./rubixc -r examples/08_many_params.ix > /tmp/rubix_t8.out
grep -q "36" /tmp/rubix_t8.out
echo "       Test 08 PASSED!"

# 10. Test 09_modules.ix (Multi-file module imports)
echo "[10/18] Testing examples/09_modules.ix (import \"module.ix\")..."
./rubixc -r examples/09_modules.ix > /tmp/rubix_t9.out
grep -q "64" /tmp/rubix_t9.out
echo "       Test 10 PASSED!"

# 11. Test 11_for_loops.ix (For loops with break, continue, nesting)
echo "[11/18] Testing examples/11_for_loops.ix (For loops, break/continue, nesting)..."
./rubixc -r examples/11_for_loops.ix > /tmp/rubix_t10.out
grep -q "ALL FOR LOOP TESTS PASSED" /tmp/rubix_t10.out
echo "       Test 11 PASSED!"

# 12. Test 12_stdlib.ix (File I/O, Strings, Math)
echo "[12/18] Testing examples/12_stdlib.ix (File I/O, Strings, Math)..."
./rubixc -r examples/12_stdlib.ix > /tmp/rubix_t11.out
grep -q "ALL STANDARD LIBRARY TESTS PASSED" /tmp/rubix_t11.out
echo "       Test 12 PASSED!"

# 13. Test large_system_test.ix (Large code, 200-elem sort, matrix mult, multi-file)
echo "[13/18] Testing examples/large_system_test.ix (Large code, 200-elem sort, matrix mult)..."
./rubixc -r examples/large_system_test.ix > /tmp/rubix_t12.out
grep -q "ALL LARGE SYSTEM TESTS PASSED" /tmp/rubix_t12.out
echo "       Test 13 PASSED!"

# 14. Test comprehensive_large_test.ix (1000-elem Sieve, recursive bsearch, prefix sums, 4x4 matrix, break/continue)
echo "[14/18] Testing examples/comprehensive_large_test.ix (Grand Final Stress Test)..."
./rubixc -r examples/comprehensive_large_test.ix > /tmp/rubix_t13.out
grep -q "ALL 6 GRAND FINAL STRESS TESTS PASSED" /tmp/rubix_t13.out
echo "       Test 14 PASSED!"

# 15. Test 15_floats.ix (Float/Double f64 arithmetic, conversions, and print_float)
echo "[15/18] Testing examples/15_floats.ix (Float/Double f64, arithmetic, print_float)..."
./rubixc -r examples/15_floats.ix > /tmp/rubix_t14.out
grep -q "3.141592" /tmp/rubix_t14.out
grep -q "26.250000" /tmp/rubix_t14.out
echo "       Test 15 PASSED!"

# 16. Test 16_structs.ix (Struct declarations, literals, field access and mutation)
echo "[16/18] Testing examples/16_structs.ix (Struct definitions, literals, field access)..."
./rubixc -r examples/16_structs.ix > /tmp/rubix_t15.out
grep -q "100" /tmp/rubix_t15.out
grep -q "10000" /tmp/rubix_t15.out
echo "       Test 16 PASSED!"

# 17. Test 17_native_floats.ix (True Type Propagation & SSE2 Native Operators)
echo "[17/18] Testing examples/17_native_floats.ix (Native Float Operators, SSE2, Mixed Math)..."
./rubixc -r examples/17_native_floats.ix > /tmp/rubix_t17.out
grep -Fq "a + b = 13.000000" /tmp/rubix_t17.out
grep -Fq "a * b = 26.250000" /tmp/rubix_t17.out
grep -Fq "3.0^2 + 4.0^2 = 25.000000" /tmp/rubix_t17.out
echo "       Test 17 PASSED!"

# 18. Test Multi-Target & Separate Compilation
echo "[18/19] Testing Windows PE target (-t windows) & Separate Compilation (-c)..."
./rubixc -t windows examples/01_hello.ix -o test_win_pe
file test_win_pe.exe | grep -q "PE32+ executable"
./rubixc -c examples/01_hello.ix -o test_sep.o
./rubixc test_sep.o -o test_sep_bin
./test_sep_bin | grep -q "Hello from Rubix"
echo "       Test 18 PASSED!"

# 19. Test Compiler Fixes (Struct scoping, SSE2 float comparisons, assignment typing)
echo "[19/19] Testing examples/18_compiler_fixes.ix..."
./rubixc -r examples/18_compiler_fixes.ix > /tmp/rubix_t19.out
grep -q "PASS: -1.5 < -0.5 is TRUE" /tmp/rubix_t19.out
grep -q "ALL COMPILER FIXES VERIFIED" /tmp/rubix_t19.out
echo "       Test 19 PASSED!"

# Clean up test output binaries
rm -f 01_hello 02_arithmetic 03_control_flow 04_functions 05_prime_numbers 06_arrays 07_types_and_logic 08_many_params 09_modules 11_for_loops 12_stdlib large_system_test comprehensive_large_test 15_floats 16_structs 17_native_floats 18_compiler_fixes test_win_pe.exe test_sep.o test_sep_bin out.s *.s

echo "=================================================="
echo "    ALL 19 TESTS PASSED FOR RUBIX (.ix)!"
echo "=================================================="
