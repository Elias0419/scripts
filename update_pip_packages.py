import os
import subprocess
import sys
import json
import platform

def get_environment_info():
    print(f"Operating System: {platform.system()} {platform.release()}")
    print(f"Python Version: {platform.python_version()}")
    print(f"Python Executable Path: {sys.executable}")

    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print("Running in a Virtual Environment")
    else:
        print("Not running in a Virtual Environment")

def update_pip_packages():
    get_environment_info()
    print("\nProcessing...")
    command = [sys.executable, '-m', 'pip', 'list', '--outdated', '--format=json']
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        packages = [package['name'] for package in json.loads(result.stdout)]
    except subprocess.CalledProcessError as e:
        print(f"Error executing '{' '.join(command)}': {e}")
        return
    except json.JSONDecodeError as e:
        print(f"JSON Error: {e}")
        return
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        return

    if not packages:
        print("No outdated packages to update.")
        return

    print(f"Outdated packages: {', '.join(packages)}")
    try:
        user_input = input("Update now? (y/n) ")
        if user_input.lower() == "y":
            update_command = [sys.executable, '-m', 'pip', 'install', '--upgrade'] + packages
            try:
                subprocess.run(update_command, check=True)
                print("Packages updated successfully.")
            except subprocess.CalledProcessError as e:
                print(f"Error updating packages: {e}")
    except KeyboardInterrupt:
        print("\nUpdate process interrupted by user.")

update_pip_packages()
