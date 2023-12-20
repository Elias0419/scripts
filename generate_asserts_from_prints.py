# import re

import re
import sys
import math
import numpy as np
# v3 broken
# def handle_output(expected, actual):
#     if isinstance(expected, (float, np.float32, np.float64)) and isinstance(actual, (float, np.float32, np.float64)):
#         return handle_math_isclose(expected, actual)
#     elif isinstance(expected, np.ndarray) and isinstance(actual, np.ndarray):
#         return handle_numpy_any(expected, actual)
#     else:
#         return handle_standard_equality(expected, actual)
#
# def handle_standard_equality(expected, actual):
#     return expected == actual
#
# def handle_math_isclose(expected, actual, rel_tol=1e-09, abs_tol=0.0):
#     return math.isclose(expected, actual, rel_tol=rel_tol, abs_tol=abs_tol)
#
# def handle_numpy_any(expected, actual):
#     return np.any(np.isclose(expected, actual))
#
# def parse_expected_output(output):
#     try:
#         # Attempt to parse output as a numeric value
#         return float(output) if '.' in output else int(output)
#     except ValueError:
#         # If it's not a number, return the string itself
#         return output
#
# def generate_asserts_from_prints(path):
#     print_pattern = r"print\(([\w_]+\s*\(.*?\))\)\s*#\s*(.+)"
#
#     with open(path, "r") as file:
#         content = file.readlines()
#
#     assert_statements = []
#     for line in content:
#         match = re.search(print_pattern, line)
#         if match:
#             function_call = match.group(1)
#             expected_output_str = match.group(2).strip()
#             expected_output = parse_expected_output(expected_output_str)
#             # Modify the assert statement to use the handle_output function
#             assert_statement = f"assert handle_output({expected_output}, {function_call})\n"
#             assert_statements.append(assert_statement)
#
#     with open(path, "a") as file:
#         file.write("\n# Generated Assert Statements\n")
#         file.writelines(assert_statements)
# generate_asserts_from_prints(sys.argv[1])

# v2
def generate_asserts_from_prints(path):
    # This pattern matches a print statement and captures everything after the # as expected output
    print_pattern = r"print\(([\w_]+\s*\(.*?\))\)\s*#\s*(.+)"

    with open(path, "r") as file:
        content = file.readlines()

    assert_statements = []
    for line in content:
        match = re.search(print_pattern, line)
        if match:
            function_call = match.group(1)
            expected_output = match.group(2).strip()
            # Create an assert statement
            assert_statement = f"assert {function_call} == {expected_output}\n"
            assert_statements.append(assert_statement)

    with open(path, "a") as file:
        file.write("\n# Generated Assert Statements\n")
        file.writelines(assert_statements)

generate_asserts_from_prints(sys.argv[1])

# integers only
# import sys
#
# def generate_asserts_from_prints(path):
#     print_pattern = r"print\(([\w_]+\s*\([^)]*\))\)\s*#(\s*\d+)"
#
#     with open(path, "r") as file:
#         content = file.readlines()
#
#     assert_statements = []
#     for line in content:
#         match = re.search(print_pattern, line)
#         if match:
#             function_call = match.group(1)
#             expected_output = match.group(2).strip()
#             assert_statement = f"assert {function_call} == {expected_output}\n"
#             assert_statements.append(assert_statement)
#
#     with open(path, "a") as file:
#         file.write("\n# Generated Assert Statements\n")
#         file.writelines(assert_statements)
#
# generate_asserts_from_prints(sys.argv[1])
