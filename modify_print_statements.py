import re
import sys

def replace_markers_with_print_statements(path):
    # Updated pattern to capture code and comments separately
    pattern = r">>>(\s*)([\w_]+\s*\([^)]*\))(\s*#.*)?"

    with open(path, "r") as file:
        content = file.readlines()

    modified_content = []
    for line in content:
        # Using a lambda function in sub for conditional replacement
        new_line = re.sub(pattern, lambda match: f"print({match.group(2)}){match.group(3) if match.group(3) else ''}", line)
        modified_content.append(new_line)

    with open(path, "w") as file:
        file.writelines(modified_content)

# Example usage
replace_markers_with_print_statements(sys.argv[1])
