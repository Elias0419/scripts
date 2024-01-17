

import psutil
import json
import time
from datetime import datetime
from pathlib import Path
import subprocess
import threading

data_lock = threading.Lock()


def execute_command(command):
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing '{command}': {e}")
        return None


def get_network_data(interface, retry_interval=5, total_retry_duration=60):
    start_time = time.time()
    while True:
        net_io = psutil.net_io_counters(pernic=True)
        interface_data = net_io.get(interface, None)

        if interface_data is not None:
            return interface_data.bytes_sent, interface_data.bytes_recv

        if time.time() - start_time > total_retry_duration:
            raise ValueError(f"Interface '{interface}' not found")

        time.sleep(retry_interval)


def get_system_uptime():
    boot_time = datetime.fromtimestamp(psutil.boot_time())
    current_time = datetime.now()
    uptime = current_time - boot_time
    return uptime.total_seconds()


def convert_to_html(text):
    bold_strings = [
        "1: lo:",
        "2: eno1:",
        "3: net_in",
        "4: net_ap:",
        "● hostapd.service",
    ]
    lines = text.split("\n")
    html_output = [
        '<div id="generated-div"><ul style="list-style-type:none; padding: 0;">'
    ]

    for line in lines:
        for bold_str in bold_strings:
            if bold_str in line:
                line = line.replace(bold_str, f"<b>{bold_str}</b>")

        html_output.append(f"<li>{line}</li>")

    html_output.append("</ul></div>")
    return "".join(html_output)


def get_system_info():
    try:
        ip_info = execute_command(["ip", "a"])
        hostapd_info = execute_command(["sudo", "systemctl", "status", "hostapd"])

        formatted_ip_info = convert_to_html(ip_info) if ip_info is not None else "No IP data available"
        formatted_hostapd_info = convert_to_html(hostapd_info) if hostapd_info is not None else "No hostapd data available"

    except Exception as e:
        print(f"Error in get_system_info: {e}")
        formatted_ip_info = "No IP data available"
        formatted_hostapd_info = "No hostapd data available"

    return formatted_ip_info, formatted_hostapd_info



def read_data(file_path, data_type):
    default_network_data = {"upload": 0, "download": 0, "uptime_seconds": 0}

    default_system_data = {"ip_info": "", "hostapd_info": ""}

    default_data = (
        default_network_data if data_type == "network" else default_system_data
    )

    if file_path.exists():
        try:
            with open(file_path, "r") as file:
                return json.load(file)
        except (IOError, json.JSONDecodeError) as e:
            print(f"Error reading file: {e}")
            return default_data

    return default_data


def write_data(file_path, data):
    with data_lock:
        with open(file_path, "w") as file:
            json.dump(data, file)


def poll_network_info(interval, file_path):
    network_interface = "net_in"
    previous_bytes_sent = 0
    previous_bytes_recv = 0

    while True:
        try:
            current_bytes_sent, current_bytes_recv = get_network_data(network_interface)
            system_uptime = get_system_uptime()
            data = read_data(network_file_path, "network")
            increment_sent = current_bytes_sent - previous_bytes_sent
            increment_recv = current_bytes_recv - previous_bytes_recv

            data["upload"] += increment_sent
            data["download"] += increment_recv
            data["uptime_seconds"] = system_uptime

            write_data(file_path, data)

            previous_bytes_sent = current_bytes_sent
            previous_bytes_recv = current_bytes_recv

        except ValueError as e:
            print(e)
            break

        time.sleep(interval)


def poll_system_info(interval, file_path):
    while True:
        start_time = time.time()
        ip_info, hostapd_info = get_system_info()
        data = read_data(system_file_path, "system")
        data["ip_info"] = ip_info
        data["hostapd_info"] = hostapd_info
        write_data(file_path, data)
        time.sleep(max(0, interval - (time.time() - start_time)))


if __name__ == "__main__":
    network_file_path = Path("network_data.json")
    system_file_path = Path("system_data.json")
    network_thread = threading.Thread(
        target=poll_network_info, args=(1, network_file_path)
    )
    system_thread = threading.Thread(
        target=poll_system_info, args=(5, system_file_path)
    )
    network_thread.start()
    system_thread.start()
