import socket

client_address = ("127.0.0.1", 2002)
server_address = ("127.0.0.1", 2004)
proxy_server_address = ("127.0.0.1", 2003)

client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
client_socket.bind(client_address)

client_socket.sendto(b"START", server_address)
messages = [i for i in range(100_000)]

for message in messages:
    client_socket.sendto(message.to_bytes(4, "big"), proxy_server_address)
