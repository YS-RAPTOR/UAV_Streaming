import socket
import time

server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
server_address = ("127.0.0.1", 2004)
server_socket.bind(server_address)

print(f"Starting listening server on {server_address[0]}:{server_address[1]}")

total_bytes_recieved = 0
start_time = None
duration = 0
messages_recieved = 0
total_messages = 10

while True:
    data, address = server_socket.recvfrom(4096)
    print(f"Received {len(data)} bytes from {address}")

    if start_time is None:
        start_time = time.time()

    total_bytes_recieved += len(data)
    messages_recieved += 1

    if messages_recieved >= total_messages:
        duration = time.time() - start_time
        break


print(f"Total bytes received: {total_bytes_recieved}")
print(f"Duration: {duration} seconds")
print(f"Throughput: {total_bytes_recieved / duration} bytes/second")
