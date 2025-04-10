import socket
import time
from collections import deque
from random import Random
from typing import Deque, List, Tuple
from common import ConstantProvider, Settings, Packet, Address


class Application:
    def __init__(
        self,
        listen_address: Address,
        addresses: Tuple[Address, Address],
        rng: Random,
        settings: Settings,
    ):
        self.listen_address = listen_address
        self.addresses = addresses
        self.rng = rng
        self.settings = settings

        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(self.listen_address)
        self.socket.setblocking(False)

        self.unsorted_packet_recieve_list: List[Packet] = []
        self.unsorted_packet_send_list: List[Packet] = []

        self.latency_queue: Deque[Packet] = deque()
        self.packet_to_be_sent: Packet | None = None

    def run(self):
        while True:
            self.send_packets()
            self.receive_packets()
            self.add_to_latency_queue()
            self.promote_packet_to_be_sent()

    def send_packets(self):
        while len(self.unsorted_packet_send_list) > 0:
            try:
                packet = self.unsorted_packet_send_list[-1]
                self.socket.sendto(packet.data, packet.send_address)
                self.unsorted_packet_send_list.pop()
            except BlockingIOError:
                break

    def receive_packets(self):
        while True:
            try:
                data, address = self.socket.recvfrom(4096)
                send_address = (
                    self.addresses[0]
                    if address == self.addresses[1]
                    else self.addresses[1]
                )
                self.unsorted_packet_recieve_list.append(Packet(data, send_address))
            except BlockingIOError:
                break

    def add_to_latency_queue(self):
        while len(self.unsorted_packet_recieve_list) > 0:
            length_of_packet_list = len(self.unsorted_packet_recieve_list)
            choice = self.rng.randint(0, length_of_packet_list - 1)
            if choice == length_of_packet_list - 1:
                packet = self.unsorted_packet_recieve_list.pop()
            else:
                packet = self.unsorted_packet_recieve_list[choice]
                self.unsorted_packet_recieve_list[choice] = (
                    self.unsorted_packet_recieve_list[-1]
                )
                self.unsorted_packet_recieve_list.pop()

            packet_loss_rate = self.settings.packet_loss_rate.get()
            rand = self.rng.random()

            if rand < packet_loss_rate:
                continue

            packet.time = time.time() + self.settings.latency.get()
            self.latency_queue.appendleft(packet)

    def promote_packet_to_be_sent(self):
        # Check if the packet_to_be_sent is set. If not set it.
        if self.packet_to_be_sent is not None:
            # Check if the packet_to_be_sent can be sent.
            if (
                self.packet_to_be_sent.time is not None
                and time.time() >= self.packet_to_be_sent.time
            ):
                # Send packet
                self.unsorted_packet_send_list.append(self.packet_to_be_sent)
                self.packet_to_be_sent = None
            else:
                return

        if len(self.latency_queue) == 0:
            return

        if (
            self.latency_queue[-1].time is not None
            and time.time() >= self.latency_queue[-1].time
        ):
            packet = self.latency_queue.pop()
            packet.time = (
                len(packet.data) / self.settings.bandwidth.get()
            ) + time.time()

            self.packet_to_be_sent = packet


if __name__ == "__main__":
    main_rng = Random(0)
    app = Application(
        listen_address=("127.0.0.1", 2003),
        addresses=(("127.0.0.1", 2002), ("127.0.0.1", 2004)),
        rng=main_rng,
        settings=Settings(
            bandwidth=ConstantProvider(10_000_000),
            latency=ConstantProvider(0),
            packet_loss_rate=ConstantProvider(0.5),
            packet_corruption_rate=ConstantProvider(0),
        ),
    )
    app.run()
