import time
import socket
import subprocess
import psutil
import os
import signal


def kill_process_by_name(name):
    matching_processes = []

    for proc in psutil.process_iter(["pid", "name"]):
        if name.lower() in proc.info["name"].lower():
            matching_processes.append(proc)

    for proc in matching_processes:
        try:
            proc.terminate()  # or proc.kill() for a forceful termination
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    _, alive = psutil.wait_procs(matching_processes, timeout=3)
    for proc in alive:
        try:
            proc.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass


def kill_process_by_port(port):
    try:
        result = subprocess.check_output(
            f"netstat -ano | findstr :{port}", shell=True
        ).decode()
        lines = result.strip().split("\n")
        if not lines:
            return

        for line in lines:
            parts = line.split()
            pid = parts[-1]
            os.kill(int(pid), signal.SIGTERM)
    except Exception:
        pass


def clear_socket(address, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((address, port))

    sock.settimeout(1)

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            # print( f"Clearing socket {address}:{port} - Received data: {len(data)} from {addr}")
        except socket.timeout:
            break
        except Exception:
            pass
    sock.close()


PROTOCOLS = ["rtp", "srt", "rist", "udp"]
SCENARIOS = ["Best", "Average", "Worst"]

for PROTOCOL in PROTOCOLS:
    for SCENARIO in SCENARIOS:
        print(f"Testing {PROTOCOL} with {SCENARIO} scenario")
        proxy = subprocess.Popen(
            [
                "uv",
                "run",
                ".\\src\\main.py",
                "--project",
                PROTOCOL,
                "--scenario",
                SCENARIO,
            ],
        )
        time.sleep(5)
        receiver = subprocess.Popen(
            [
                "src\\receiver.bat",
                PROTOCOL,
                f".\\Runs\\{PROTOCOL}\\{SCENARIO}\\out.mp4",
            ],
        )
        time.sleep(5)
        sender = subprocess.Popen(
            ["src\\sender.bat", PROTOCOL],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        code = receiver.wait()

        if code != 0:
            print("\a")
            sender.kill()
            receiver.kill()
            proxy.kill()
            raise Exception(f"Receiver exited with code {code}")

        try:
            sender.kill()
            sender.wait()
            print("Sender terminated")
        except Exception:
            pass

        try:
            proxy.kill()
            proxy.wait()
            print("Proxy terminated")
        except Exception:
            pass

        kill_process_by_name("ffmpeg")
        kill_process_by_port(2003)
        kill_process_by_port(2004)
        clear_socket("127.0.0.1", 2003)
        clear_socket("127.0.0.1", 2004)
