import socket
import time

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server_address = ("127.0.0.1", 2004)
server_socket.bind(server_address)
server_socket.setblocking(False)

print(f"Starting listening server on {server_address[0]}:{server_address[1]}")

total_bytes_recieved = 0
start_time = None
duration = 0
messages_recieved = 0

numbers = set()


try:
    while True:
        try:
            data, address = server_socket.recvfrom(4096)
            print(f"Received {len(data)} bytes from {address}")

            if start_time is None:
                start_time = time.time()
                continue

            numbers.add(int.from_bytes(data, "big"))
        except BlockingIOError:
            pass
except KeyboardInterrupt:
    print("Calculating Packet Loss Rate...")

    missing = 0
    for n in range(100_000):
        if n not in numbers:
            missing += 1

    print(f"Missing {missing} packets")
    print(f"Recieved {len(numbers)} packets")
    print(f"Packet Loss Rate: {missing / 100_000 * 100}%")
