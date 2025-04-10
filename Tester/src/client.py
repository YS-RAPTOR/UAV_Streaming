import socket
import struct
from time import time, sleep

client_address = ("127.0.0.1", 2002)
server_address = ("127.0.0.1", 2004)
proxy_server_address = ("127.0.0.1", 2003)

client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
client_socket.bind(client_address)

client_socket.sendto(b"START", server_address)
messages = [i for i in range(100_000)]

for _ in range(100_000):
    client_socket.sendto(struct.pack("!d", time()), proxy_server_address)
    sleep(0.001)
