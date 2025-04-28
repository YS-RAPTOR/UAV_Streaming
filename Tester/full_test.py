import subprocess

PROTOCOLS = ["udp", "rtp", "srt", "rist"]
SCENARIOS = ["Best", "Average", "Worst", "Testing"]

DURATION = 5 * 60  # seconds

for PROTOCOL in PROTOCOLS:
    for SCENARIO in SCENARIOS:
        print(f"Testing {PROTOCOL} with {SCENARIO} scenario")
        # os.system(f"python3 Tester/src/main.py --protocol {PROTOCOL} --scenario {SCENARIO}")
        proxy = subprocess.Popen(
            [
                "uv",
                "run",
                "./src/main.py",
                "--project",
                PROTOCOL,
                "--scenario",
                SCENARIO,
            ]
        )

        receiver = subprocess.Popen(
            ["./src/receiver.bat", PROTOCOL, f"./Runs/{PROTOCOL}/{SCENARIO}/out.mp4"]
        )
        sender = subprocess.Popen(["./src/sender.bat", PROTOCOL])
        code = receiver.wait()
        print(f"Receiver exited with code {code}")

        try:
            sender.terminate()
        except Exception:
            pass

        try:
            proxy.terminate()
        except Exception:
            pass
