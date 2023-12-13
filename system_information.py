import os
import platform
import psutil
import socket
import subprocess
from prettytable import PrettyTable

def get_boot_time():
    boot_time = subprocess.run(["systemd-analyze", "time"])
    return boot_time

def get_os_info():
    table = PrettyTable()
    table.field_names = ["Property", "Value"]
    table.add_row(["OS", platform.system()])
    table.add_row(["Release", platform.release()])
    table.add_row(["Version", platform.version()])
    return table

def get_cpu_info():
    table = PrettyTable()
    table.field_names = ["Property", "Value"]
    table.add_row(["Physical cores", psutil.cpu_count(logical=False)])
    table.add_row(["Total cores", psutil.cpu_count(logical=True)])
    table.add_row(["Max Frequency", f"{psutil.cpu_freq().max:.2f}Mhz"])
    table.add_row(["Current Frequency", f"{psutil.cpu_freq().current:.2f}Mhz"])
    return table

def get_memory_info():
    mem = psutil.virtual_memory()
    table = PrettyTable()
    table.field_names = ["Property", "Value"]
    table.add_row(["Total", f"{mem.total / (1024 ** 3):.2f} GB"])
    table.add_row(["Available", f"{mem.available / (1024 ** 3):.2f} GB"])
    table.add_row(["Used", f"{mem.used / (1024 ** 3):.2f} GB"])
    table.add_row(["Percentage", f"{mem.percent}%"])
    return table

def get_disk_info():
    partitions = psutil.disk_partitions()
    table = PrettyTable()
    table.field_names = ["Device", "Total", "Used", "Free", "Percentage"]
    for partition in partitions:
        usage = psutil.disk_usage(partition.mountpoint)
        table.add_row([
            partition.device,
            f"{usage.total / (1024 ** 3):.2f} GB",
            f"{usage.used / (1024 ** 3):.2f} GB",
            f"{usage.free / (1024 ** 3):.2f} GB",
            f"{usage.percent}%"
        ])
    return table

def get_network_info():
    if_addrs = psutil.net_if_addrs()
    table = PrettyTable()
    table.field_names = ["Interface", "Address"]
    for interface, addresses in if_addrs.items():
        if addresses:
            table.add_row([interface, addresses[0].address])
    return table

def display_system_info():
    print(get_boot_time())

    print("Operating System Information:")
    print(get_os_info())

    print("\nCPU Information:")
    print(get_cpu_info())

    print("\nMemory Information:")
    print(get_memory_info())

    print("\nDisk Information:")
    print(get_disk_info())

    print("\nNetwork Information:")
    print(get_network_info())

if __name__ == "__main__":
    display_system_info()
