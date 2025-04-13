# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "matplotlib",
#     "pyqt6",
# ]
# ///
"""
Paretovariate Tested:
    Has too big of a chance for extremely big values
Expovariate Tested:
    Is much more manageable. lambda 2 for no of corruptions
"""

import common
import matplotlib.pyplot as plt  # type: ignore
import matplotlib  # type: ignore

matplotlib.use("QtAgg")

GET_INT = True
DISTRIBUTION = True
TIME = True

NO_OF_SAMPLES = 10_000

provider: common.Provider = common.RandomExpovariate(0, 2, 1)
data = []

alpha = 2

for i in range(NO_OF_SAMPLES):
    if GET_INT:
        data.append(provider.get_int())
    else:
        data.append(provider.get())


if GET_INT and DISTRIBUTION:
    counts = {}

    for point in data:
        if point in counts:
            counts[point] += 1
        else:
            counts[point] = 1

    # Sort the dictionary by key
    count_keys = sorted(list(counts.keys()))

    for count_key in count_keys:
        print(f"{count_key}: {counts[count_key]} | {counts[count_key] / NO_OF_SAMPLES}")

if TIME:
    plt.figure()
    plt.plot(data)
    plt.title("Time Series")
    pass

if DISTRIBUTION:
    plt.figure()
    plt.hist(data, bins=100, density=True)
    plt.title("Histogram")

if TIME or DISTRIBUTION:
    plt.show()
