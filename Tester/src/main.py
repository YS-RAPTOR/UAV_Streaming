import time
import socket
import argparse
from pathlib import Path
from collections import deque
from random import Random
from typing import Deque, List, Literal
from common import (
    ConstantProvider,
    RandomExpovariate,
    RandomGauss,
    RandomGaussWithSpikes,
    Settings,
    Packet,
    Address,
)


class Application:
    def __init__(
        self,
        listen_address: Address,
        addresses: List[Address],
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

        self.started = False

    def run(self):
        while True:
            self.send_packets()
            self.settings.update(self.started)
            self.receive_packets()
            self.settings.update(self.started)
            self.add_to_latency_queue()
            self.settings.update(self.started)
            self.promote_packet_to_be_sent()
            self.settings.update(self.started)

    def corrupt_data(self, packet: Packet):
        i = self.rng.randint(0, len(packet.data) - 1)
        b = packet.data[i] ^ (1 << self.rng.randint(0, 7))
        packet.data = packet.data[:i] + bytes([b]) + packet.data[i + 1 :]

    def send_packets(self):
        while len(self.unsorted_packet_send_list) > 0:
            try:
                packet = self.unsorted_packet_send_list[-1]
                corruption_rate = self.settings.packet_corruption_rate
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
                self.started = True

                if address not in self.addresses:
                    self.addresses.append(address)

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

            packet_loss_rate = self.settings.packet_loss_rate
            rand = self.rng.random()

            if rand < packet_loss_rate:
                continue
            packet.time = time.time() + self.settings.latency

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
            packet.time = (len(packet.data) / self.settings.bandwidth) + time.time()

            self.packet_to_be_sent = packet


"""
Best
    Bandwidth: 15MB/s +- 2MB/s
    Latency: 10ms +- 5ms
    Packet Loss Rate: 0%
    Packet Corruption Rate: 0%
    No of Packet Corruptions: 0

Average
    Bandwidth: 10MB/s +- 2MB/s with spikes up to 5MB/s
    Latency: 60ms +- 10ms with spikes up to 90ms
    Packet Loss Rate: 2.5% +- 2.5% with spikes up to 7.5%
    Packet Corruption Rate: 1% +- 1% with spikes up to 3%
    No of Packet Corruptions: ExpoVariate(2)

Worst
    Bandwidth: 5MB/s +- 2MB/s
    Latency: 100ms +- 20ms
    Packet Loss Rate: 10% 
    Packet Corruption Rate: 5%
    No of Packet Corruptions: ExpoVariate(2)
"""

Scenario: Literal["Best", "Average", "Worst", "Testing"] = "Average"
Spike_Chance = 0.005
Spike_Duration = 30
Seed = 0
Update_Every = 0.5
Project_Name = "Test"


if __name__ == "__main__":
    main_rng = Random(Seed)

    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", type=str, default=None)
    parser.add_argument("--project", type=str, default=None)

    args = parser.parse_args()

    if args.scenario is None or args.project is None:
        raise ValueError("Please provide a scenario and project name")

    Project_Name = args.project
    Scenario = args.scenario

    if Project_Name == "Test":
        Run = Path(f"./Runs/Test-{time.time_ns()}")
    else:
        Run = Path(f"./Runs/{Project_Name}")

    Run.mkdir(parents=True, exist_ok=True)

    if Scenario == "Best":
        settings = Settings(
            folder=Run.joinpath(Scenario),
            update_every=Update_Every,
            bandwidth=RandomGauss(
                seed=main_rng.randint(0, 10**5),
                mean=15 * 1024 * 1024,
                stddev=1 * 1024 * 1024,
            ),
            latency=RandomGauss(
                seed=main_rng.randint(0, 10**5),
                mean=10 / 1000,
                stddev=2.5 / 1000,
            ),
            packet_loss_rate=ConstantProvider(0),
            packet_corruption_rate=ConstantProvider(0),
            no_of_packet_corruptions=ConstantProvider(0),
        )
    elif Scenario == "Average":
        settings = Settings(
            folder=Run.joinpath(Scenario),
            update_every=Update_Every,
            bandwidth=RandomGaussWithSpikes(
                seed=main_rng.randint(0, 10**5),
                mean=10 * 1024 * 1024,
                stddev=1 * 1024 * 1024,
                spike_multiplier=0.5,
                spike_chance=Spike_Chance,
                max_spike_duration=Spike_Duration,
            ),
            latency=RandomGaussWithSpikes(
                seed=main_rng.randint(0, 10**5),
                mean=60 / 1000,
                stddev=5 / 1000,
                spike_multiplier=1.5,
                spike_chance=Spike_Chance,
                max_spike_duration=Spike_Duration,
            ),
            packet_loss_rate=RandomGaussWithSpikes(
                seed=main_rng.randint(0, 10**5),
                mean=2.5 / 100,
                stddev=1.25 / 100,
                spike_multiplier=3,
                spike_chance=Spike_Chance,
                max_spike_duration=Spike_Duration,
            ),
            packet_corruption_rate=RandomGaussWithSpikes(
                seed=main_rng.randint(0, 10**5),
                mean=1 / 100,
                stddev=0.5 / 100,
                spike_multiplier=3,
                spike_chance=Spike_Chance,
                max_spike_duration=Spike_Duration,
            ),
            no_of_packet_corruptions=RandomExpovariate(
                seed=main_rng.randint(0, 10**5),
                lam=2,
                start_value=1,
            ),
        )
    elif Scenario == "Worst":
        settings = Settings(
            folder=Run.joinpath(Scenario),
            update_every=Update_Every,
            bandwidth=RandomGauss(
                seed=main_rng.randint(0, 10**5),
                mean=5 * 1024 * 1024,
                stddev=1 * 1024 * 1024,
            ),
            latency=RandomGauss(
                seed=main_rng.randint(0, 10**5),
                mean=100 / 1000,
                stddev=10 / 1000,
            ),
            packet_loss_rate=ConstantProvider(10 / 100),
            packet_corruption_rate=ConstantProvider(5 / 100),
            no_of_packet_corruptions=RandomExpovariate(
                seed=main_rng.randint(0, 10**5),
                lam=2,
                start_value=1,
            ),
        )
    elif Scenario == "Testing":
        settings = Settings(
            folder=Run.joinpath(Scenario),
            update_every=Update_Every,
            bandwidth=ConstantProvider(10**5),
            latency=ConstantProvider(1000 / 1000),
            packet_loss_rate=ConstantProvider(0),
            packet_corruption_rate=ConstantProvider(0),
            no_of_packet_corruptions=ConstantProvider(0),
        )
    else:
        raise ValueError("Invalid Scenario")

    print("Running Scenario:", Scenario)
    app = Application(
        listen_address=("127.0.0.1", 2003),
        addresses=[("127.0.0.1", 2004)],
        rng=main_rng,
        settings=settings,
    )
    app.run()
    settings.close()
