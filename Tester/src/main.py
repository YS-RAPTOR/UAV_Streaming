import socket
import time
from random import Random
from typing import List, Tuple
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

        self.packet_to_be_sent: Packet | None = None

    def run(self):
        while True:
            while len(self.unsorted_packet_send_list) > 0:
                try:
                    packet = self.unsorted_packet_send_list[-1]
                    self.socket.sendto(packet.data, packet.send_address)
                    self.unsorted_packet_send_list.pop()
                except BlockingIOError:
                    break

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

            self.promote_packet_to_be_sent()

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

        length_of_packet_list = len(self.unsorted_packet_recieve_list)
        if length_of_packet_list == 0:
            return

        choice = self.rng.randint(0, length_of_packet_list - 1)
        if choice == length_of_packet_list - 1:
            packet = self.unsorted_packet_recieve_list.pop()
        else:
            packet = self.unsorted_packet_recieve_list[choice]
            self.unsorted_packet_recieve_list[choice] = (
                self.unsorted_packet_recieve_list[-1]
            )
            self.unsorted_packet_recieve_list.pop()

        packet.time = (len(packet.data) / self.settings.bandwidth.get()) + time.time()
        print(packet.time, time.time())

        self.packet_to_be_sent = packet


if __name__ == "__main__":
    main_rng = Random(0)
    app = Application(
        listen_address=("127.0.0.1", 2003),
        addresses=(("127.0.0.1", 2002), ("127.0.0.1", 2004)),
        rng=main_rng,
        settings=Settings(
            bandwidth=ConstantProvider(1),
            latency=ConstantProvider(0),
            packet_loss_rate=ConstantProvider(0),
            packet_corruption_rate=ConstantProvider(0),
        ),
    )
    app.run()
