FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    autotools-dev \
    automake \
    autoconf \
    libtool \
    pkg-config \
    libc6-dbg \
    python \
    python3 \
    software-properties-common \
    ca-certificates \
    curl \
    && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
    && apt-get update \
    && apt-get install -y gcc-10 g++-10 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/JuezUN/opt-cpp-backend.git /tmp/opt-cpp-backend

RUN cd /tmp/opt-cpp-backend/valgrind-3.11.0 \
    && ./autogen.sh \
    && ./configure --prefix=`pwd`/inst \
    && make -j2 \
    && make install

RUN python3 - <<'PY'
from pathlib import Path

p = Path("/tmp/opt-cpp-backend/run_cpp_backend.py")
text = p.read_text()

old_text = text

replacements = {
    "DIALECT = '-std=c++11'": "DIALECT = '-std=gnu++20'",
    'DIALECT = "-std=c++11"': 'DIALECT = "-std=gnu++20"',
    "DIALECT='-std=c++11'": "DIALECT='-std=gnu++20'",
    'DIALECT="-std=c++11"': 'DIALECT="-std=gnu++20"',
    "-std=c++11": "-std=gnu++20",
    "-std=gnu++11": "-std=gnu++20",
    "-std=c++0x": "-std=gnu++20",
    "-std=c11": "-std=gnu17",
}

for old, new in replacements.items():
    text = text.replace(old, new)

p.write_text(text)

if "-std=c++11" in text or "-std=gnu++11" in text or "-std=c++0x" in text:
    raise SystemExit("C++11 flag still exists in run_cpp_backend.py")

if "-std=gnu++20" not in text:
    raise SystemExit("GNU++20 flag was not inserted into run_cpp_backend.py")

print("Verified run_cpp_backend.py now uses GNU++20.")
PY

RUN grep -n "DIALECT" /tmp/opt-cpp-backend/run_cpp_backend.py \
    && g++ --version

RUN useradd netuser \
    && cd /tmp \
    && find opt-cpp-backend | xargs chown netuser
