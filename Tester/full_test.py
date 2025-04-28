import time
import subprocess

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

        print("Receiver exited with code", code)
        if code != 0:
            print("\a")
            sender.kill()
            receiver.kill()
            proxy.kill()
            raise Exception(f"Receiver exited with code {code}")

        try:
            sender.terminate()
        except Exception:
            pass

        try:
            proxy.terminate()
        except Exception:
            pass
