import pprint
import inspect
import pickle
import datetime

##############################################
import inspect
from pprint import pprint

def inspect_class(class_to_inspect, less=True):
    if not isinstance(class_to_inspect, type):
        print(f"{class_to_inspect} is not a Python Class")
        return
    instance = class_to_inspect()
    print(f"\nInspecting class: {class_to_inspect.__name__}\n")
    if less:
        print("Pass `less=False` for more details.\n")

    print("Init Signature:")
    print(f"  {inspect.signature(class_to_inspect.__init__)}\n")

    print("Class-level attributes:")
    class_attrs = {name: value for name, value in class_to_inspect.__dict__.items()}
    if class_attrs:
        for name, value in class_attrs.items():
            print(f"  {name} = {value}")
    else:
        print("  None")

    if not less:
        print("\nInstance-level attributes:")
        instance_attrs = vars(instance)
        if instance_attrs:
            for name, value in instance_attrs.items():
                print(f"  {name} = {value}")
        else:
            print("  None")

        print("\nAll attributes and methods:")
        all_members = [name for name, _ in inspect.getmembers(class_to_inspect)]
        for name in all_members:
            print(f"  {name}")

#################################################


def is_pickleable(obj, depth=0):
    try:
        pickle.dumps(obj)
        return True
    except TypeError as e:
        print('  ' * depth + f"Failed in {type(obj)}: {e}")
        if hasattr(obj, '__dict__'):
            for key, val in obj.__dict__.items():
                print('  ' * depth + f"Checking attribute {key} of type {type(val)}")
                is_pickleable(val, depth + 1)
        return False
        
        
def log_caller_info(depths=1, to_file=False, filename="caller_info_log.txt"):
    stack = inspect.stack()
    if isinstance(depths, int):
        depths = [depths]

    output_lines = []

    for depth in depths:
        if depth < len(stack):
            caller_frame = stack[depth]
            file_name = caller_frame.filename
            line_number = caller_frame.lineno
            function_name = caller_frame.function
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            line = f"{timestamp} - Called from {file_name}, line {line_number}, in {function_name}\n"
            output_lines.append(line)
        else:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            line = f"{timestamp} - No caller information available for depth: {depth}\n"
            output_lines.append(line)

    if to_file:

        with open(filename, 'a') as f:
            f.writelines(output_lines)
    else:
        print(''.join(output_lines))
        
        

def debug_print(*args):
    pp = pprint.PrettyPrinter(indent=4)
    frame = inspect.currentframe()
    try:
        caller = inspect.getouterframes(frame)[1]
        frameinfo = inspect.getframeinfo(caller[0])
        args_name = inspect.getargvalues(caller[0]).locals
        arg_names = frameinfo.code_context[0].strip().split("debug_print(")[1].split(")")[0].replace(" ", "").split(",")

        for arg_name, obj in zip(arg_names, args):
            print(f"\n\nName: {arg_name}")
            print("Type:", type(obj))
            print("Value:")
            pp.pprint(obj)
            print("-" * 40, "\n\n")
    finally:
        del frame
