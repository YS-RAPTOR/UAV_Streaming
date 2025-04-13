import socket
import time
from collections import deque
from random import Random
from typing import Deque, List, Tuple
from common import ConstantProvider, RandomExpovariate, Settings, Packet, Address


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

    def corrupt_data(self, packet: Packet):
        i = self.rng.randint(0, len(packet.data) - 1)
        b = packet.data[i] ^ (1 << self.rng.randint(0, 7))
        packet.data = packet.data[:i] + bytes([b]) + packet.data[i + 1 :]

    def send_packets(self):
        while len(self.unsorted_packet_send_list) > 0:
            try:
                packet = self.unsorted_packet_send_list[-1]
                corruption_rate = self.settings.packet_corruption_rate.get()
                if self.rng.random() < corruption_rate:
                    no_of_corruptions = self.settings.no_of_packet_corruptions.get_int()
                    for _ in range(no_of_corruptions):
                        self.corrupt_data(packet)

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


"""
Best
    Bandwidth: 15MB/s +- 2MB/s
    Latency: 10ms +- 5ms
    Packet Loss Rate: 0%
    Packet Corruption Rate: 0%
    No of Packet Corruptions: ExpoVariate(2)

Average
    Bandwidth: 10MB/s +- 2MB/s with spikes for 1 second up to 5MB/s
    Latency: 60ms +- 10ms with spikes for 1 second up to 100ms
    Packet Loss Rate: 0% - 5% with spikes for 1 second up to 10%
    Packet Corruption Rate: 0% - 2% with spikes for 1 second up to 5%
    No of Packet Corruptions: ExpoVariate(2)

Worst
    Bandwidth: 5MB/s +- 2MB/s
    Latency: 100ms +- 20ms
    Packet Loss Rate: 10% 
    Packet Corruption Rate: 5%
    No of Packet Corruptions: ExpoVariate(2)
"""

if __name__ == "__main__":
    main_rng = Random(0)
    app = Application(
        listen_address=("127.0.0.1", 2003),
        addresses=(("127.0.0.1", 2002), ("127.0.0.1", 2004)),
        rng=main_rng,
        settings=Settings(
            bandwidth=ConstantProvider(10_000_000),
            latency=ConstantProvider(0),
            packet_loss_rate=ConstantProvider(0),
            packet_corruption_rate=ConstantProvider(0.5),
            no_of_packet_corruptions=RandomExpovariate(
                seed=main_rng.randint(0, 10**5),
                lam=2,
                start_value=1,
            ),
        ),
    )
    app.run()
