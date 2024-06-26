import sys
import subprocess
import select
import os
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class FileChangeHandler(FileSystemEventHandler):
    def __init__(self, file_path):
        self.file_path = file_path

    def on_modified(self, event):
        if event.src_path == self.file_path:
            try:
                result = subprocess.run(['python', self.file_path], capture_output=True, text=True)
                print(result.stdout)
                print(result.stderr, file=sys.stderr)
            except Exception as e:
                print(f"Error running file\n{e}")

def clear_terminal():
    os.system('clear')

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python watcher.py /path/to/python_script.py")
        sys.exit(1)

    file_path = sys.argv[1]

    event_handler = FileChangeHandler(file_path)
    observer = Observer()
    observer.schedule(event_handler, path=file_path, recursive=False)

    print(f"Watching for changes in {file_path}.")
    observer.start()

    try:
        while True:
            if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
                line = sys.stdin.read(1)
                if line == 'c':
                    clear_terminal()
    except KeyboardInterrupt:
        observer.stop()
    except Exception as e:
        print(f"An error occurred\n{e}")
        observer.stop()
    finally:
        observer.join()
