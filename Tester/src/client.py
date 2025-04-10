import socket

client_address = ("127.0.0.1", 2002)
server_address = ("127.0.0.1", 2003)

client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
client_socket.bind(client_address)

messages = ["HELLO".encode()] * 10

for message in messages:
    client_socket.sendto(message, server_address)
