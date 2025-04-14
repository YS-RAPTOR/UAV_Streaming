import math
from time import time
from pathlib import Path
from random import Random
from typing import TextIO, Tuple
from dataclasses import dataclass
from abc import ABC, abstractmethod


class Provider(ABC):
    @abstractmethod
    def get(self) -> float:
        pass

    @abstractmethod
    def get_int(self) -> int:
        pass


class ConstantProvider(Provider):
    def __init__(self, value: float):
        self.value = value

    def get(self) -> float:
        return self.value

    def get_int(self) -> int:
        return int(self.value)


class RandomExpovariate(Provider):
    def __init__(self, seed: int, lam: int, start_value: int):
        self.rng = Random(seed)
        self.start_value = start_value
        self.lam = lam

    def get(self) -> float:
        return self.rng.expovariate(self.lam) + self.start_value

    def get_int(self) -> int:
        return math.floor(self.get())


class RandomGauss(Provider):
    def __init__(self, seed: int, mean: float, stddev: float):
        self.rng = Random(seed)
        self.mean = mean
        self.stddev = stddev

    def get(self) -> float:
        return max(self.rng.gauss(self.mean, self.stddev), 0)

    def get_int(self) -> int:
        return round(self.get())


class RandomGaussWithSpikes(Provider):
    def __init__(
        self,
        seed: int,
        mean: float,
        stddev: float,
        spike_chance: float,
        max_spike_duration: int,
        spike_multiplier: float,
    ):
        self.rng = Random(seed)
        self.mean = mean
        self.stddev = stddev

        self.spike_chance = spike_chance
        self.max_spike_duration = max_spike_duration
        self.spike_multiplier = spike_multiplier
        self.spike_time = 0

    def get(self) -> float:
        if self.rng.random() < self.spike_chance:
            self.spike_time += self.rng.randint(1, self.max_spike_duration)

        if self.spike_time > 0:
            self.spike_time -= 1
            return max(
                self.rng.gauss(self.mean, self.stddev) * self.spike_multiplier,
                0,
            )

        return max(self.rng.gauss(self.mean, self.stddev), 0)

    def get_int(self) -> int:
        return round(self.get())


class Settings:
    def __init__(
        self,
        folder: Path,
        update_every: float,
        bandwidth: Provider,
        latency: Provider,
        packet_loss_rate: Provider,
        packet_corruption_rate: Provider,
        no_of_packet_corruptions: Provider,
    ):
        if folder.exists():
            raise Exception("The Scenario folder already exists")
        folder.mkdir()

        self.start_time = time()
        self.update_every = update_every
        self.last_update = self.start_time
        self.file = open(folder.joinpath("data.csv"), "w")

        self.bandiwdth_provider = bandwidth
        self.latency_provider = latency
        self.packet_loss_rate_provider = packet_loss_rate
        self.packet_corruption_rate_provider = packet_corruption_rate
        self.no_of_packet_corruptions = no_of_packet_corruptions

        self.bandwidth = bandwidth.get()
        self.latency = latency.get()
        self.packet_loss_rate = packet_loss_rate.get()
        self.packet_corruption_rate = packet_corruption_rate.get()

        self.file.write(
            "time,bandwidth,latency,packet_loss_rate,packet_corruption_rate\n"
        )
        self.write()

    def update(self):
        if time() - self.last_update > self.update_every:
            self.last_update = time()
            self.bandwidth = self.bandiwdth_provider.get()
            self.latency = self.latency_provider.get()
            self.packet_loss_rate = self.packet_loss_rate_provider.get()
            self.packet_corruption_rate = self.packet_corruption_rate_provider.get()
            self.write()

    def write(self):
        self.file.write(
            f"{self.last_update - self.start_time},{self.bandwidth},{self.latency},{self.packet_loss_rate},{self.packet_corruption_rate}\n"
        )

    def close(self):
        self.file.close()


Address = Tuple[str, int]


@dataclass
class Packet:
    data: bytes
    send_address: Address
    time: float | None = None
