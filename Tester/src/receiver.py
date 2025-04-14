import socket

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server_address = ("127.0.0.1", 2004)
server_socket.bind(server_address)

print(f"Starting listening server on {server_address[0]}:{server_address[1]}")

corruption = []
non_corrupted = 0
total = 0

while True:
    data, address = server_socket.recvfrom(4096)
    print(f"Received {len(data)} bytes from {address}")
    print(total)

    total += 1
    if data == b"HELLO":
        non_corrupted += 1
    else:
        corruption.append(data)

    if total >= 100_000:
        break

print(f"Total packets received: {total}")
print(f"Non-corrupted packets: {non_corrupted}")
print(f"Corrupted packets: {len(corruption)}")
print(f"Corruption Rate: {len(corruption) / total * 100:.2f}%")
