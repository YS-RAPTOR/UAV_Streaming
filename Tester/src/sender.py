import socket
from time import sleep

proxy_server_address = ("127.0.0.1", 2003)

client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

messages = ["HELLO".encode()] * 100_000
print(len(messages))

for message in messages:
    client_socket.sendto(message, proxy_server_address)
    sleep(0.0001)  # Simulate a small delay between sends
