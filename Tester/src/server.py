import socket
import time
import struct

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server_address = ("127.0.0.1", 2004)
server_socket.bind(server_address)
server_socket.setblocking(False)

print(f"Starting listening server on {server_address[0]}:{server_address[1]}")

start_time = None
latency_bytes = []


try:
    while True:
        try:
            data, address = server_socket.recvfrom(4096)
            print(f"Received {len(data)} bytes from {address}")

            if start_time is None:
                start_time = time.time()
                continue

            latency_bytes.append((data, time.time()))
        except BlockingIOError:
            pass
except KeyboardInterrupt:
    latencies = [struct.unpack("!d", data)[0] - t for data, t in latency_bytes]
    print(f"Average latency: {sum(latencies) / len(latencies)}")
