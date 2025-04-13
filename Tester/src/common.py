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


class LoggingProvider(Provider):
    def __init__(
        self,
        provider: Provider,
        start_time: float,
        log_file: TextIO,
    ):
        self.start_time = start_time
        self.provider = provider
        self.log_file = log_file

    def get(self) -> float:
        value = self.provider.get()
        time_passed = time() - self.start_time
        self.log_file.write(f"{time_passed},{value}\n")
        return value

    def get_int(self) -> int:
        value = self.provider.get_int()
        time_passed = time() - self.start_time
        self.log_file.write(f"{time_passed},{value}\n")
        return value

    def close(self):
        self.log_file.close()


class Settings:
    def __init__(
        self,
        folder: Path,
        bandwidth: Provider,
        latency: Provider,
        packet_loss_rate: Provider,
        packet_corruption_rate: Provider,
        no_of_packet_corruptions: Provider,
    ):
        if folder.exists():
            raise Exception("The Scenario folder already exists")
        folder.mkdir()

        start_time = time()
        self.bandwidth: LoggingProvider = LoggingProvider(
            bandwidth,
            start_time,
            open(folder.joinpath("bandwidth.csv"), "w"),
        )
        self.latency: LoggingProvider = LoggingProvider(
            latency,
            start_time,
            open(folder.joinpath("latency.csv"), "w"),
        )
        self.packet_loss_rate: LoggingProvider = LoggingProvider(
            packet_loss_rate,
            start_time,
            open(folder.joinpath("packet_loss_rate.csv"), "w"),
        )
        self.packet_corruption_rate: LoggingProvider = LoggingProvider(
            packet_corruption_rate,
            start_time,
            open(folder.joinpath("packet_corruption_rate.csv"), "w"),
        )
        self.no_of_packet_corruptions = no_of_packet_corruptions

    def close(self):
        self.bandwidth.close()
        self.latency.close()
        self.packet_loss_rate.close()
        self.packet_corruption_rate.close()


Address = Tuple[str, int]


@dataclass
class Packet:
    data: bytes
    send_address: Address
    time: float | None = None
