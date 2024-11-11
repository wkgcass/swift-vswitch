# Sample

You can run sample programs on `macOS` and `Linux`.

You can run the sample program in a docker container if you do not have a `Linux` host:

```shell
docker pull swift:6.0.1-jammy
docker run --name=swift --privileged -it -v `pwd`:/swvs --workdir=/swvs swift:6.0.1-jammy /bin/bash
```

# sample-vs

A simple load balancer which demonstrates functionalities of the ipvs module.  
Supports `tcp/udp | v4/v6 | wrr`.

## Linux

Start the sample program with `tap` device.

```shell
# dest v4
swift run -c release sample-vs \
    --type=tap \
    --dev-name=tap0 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='192.168.111.1:8080'
# dest v6
swift run -c release sample-vs \
    --type=tap \
    --dev-name=tap0 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='[fd00::1]:8080'
```

> You can specify multiple dests separated by `,`.  
> Also you can specify the weight of each dest, with this syntax: `ip:port{weight}`.  
> e.g. `192.168.111.2:8080{5},192.168.111.2:9090{10}`.  
> The default weight is `10`.

Run the following shell script to initialize the tap device:

```shell
ip addr add 192.168.111.1/24 dev tap0
ip addr add fd00::1/120 dev tap0
ip link set tap0 up
```

Then you can use `curl`, `telnet`, `nc`, `wrk`, `iperf` to play with the lb.

```shell
# console 1
nc -l 8080

# console 2
nc 192.168.111.2 80
```

---

Start the sample program with `tun` device.

```shell
# dest v4
swift run -c release sample-vs \
    --type=tun \
    --dev-name=tun0 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='192.168.111.1:8080'
# dest v6
swift run -c release sample-vs \
    --type=tun \
    --dev-name=tun0 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='[fd00::1]:8080'
```

Run the following shell script to initialize the tun device:

```
ip addr add 192.168.111.1/24 dev tap0
ip addr add fd00::1/120 dev tap0
ip link set tap0 up
```

Then you can use `curl`, `telnet`, `nc`, `wrk`, `iperf` to play with the lb.

```shell
# console 1
nc -l 8080

# console 2
nc 192.168.111.2 80
```

## macOS

> Only `tun` is supported on macOS.

Start the sample program.

```shell
# dest v4
sudo swift run -c release sample-vs \
    --type=tun \
    --dev-name=utun11 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='192.168.111.1:8080'
# dest v6
sudo swift run -c release sample-vs \
    --type=tun \
    --dev-name=utun11 \
    --vip=192.168.111.2/24,fd00::2/120 \
    --port=80 \
    --dest='[fd00::1]:8080'
```

Run the following shell script to initialize the device:

```shell
/usr/bin/sudo /sbin/ifconfig utun11 inet 192.168.111.1 255.255.255.0 192.168.111.2
/usr/bin/sudo /sbin/ifconfig utun11 inet6 fd00::1/120
```

Then you can use `curl`, `telnet`, `nc`, `wrk`, `iperf` to play with the lb.

```shell
# console 1
nc -l 8080

# console 2
nc 192.168.111.2 80
```

# sample-taptunping

You can `ping` into the vswitch through a `tap` or `tun` device.

## Linux

Start the sample program with `tap` device and connect the `tap` device to a virtual netstack.

```shell
swift run -c release sample-taptunping \
    --type=tap \
    --dev-name=tap0 \
    --ipmask=192.168.111.2/24,fd00::2/120 \
    --net-type=stack
```

Start the sample program with `tap` device and connect the `tap` device to a virtual switch.  
Also a mimic host will also be connected to the virtual switch.

```shell
swift run -c release sample-taptunping \
    --type=tap \
    --dev-name=tap0 \
    --ipmask=192.168.111.2/24,fd00::2/120 \
    --net-type=mimic
```

Run the following shell script to initialize the tap device:

```shell
ip addr add 192.168.111.1/24 dev tap0
ip addr add fd00::1/120 dev tap0
ip link set tap0 up
```

Then `ping`:

```shell
ping 192.168.111.2
ping fd00::2
```

---

Start the sample program with `tun` device and connect it to a virtual net stack.

```shell
swift run -c release sample-taptunping \
    --type=tun \
    --dev-name=tun0 \
    --ipmask=192.168.111.2/24,fd00::2/120 \
    --net-type=stack
```

> A `tun` is a device without ethernet frame, so it cannot be connected to a switch.

Run the following shell script to initialize the tap device:

```shell
ip addr add 192.168.111.1/24 dev tun0
ip addr add fd00::1/120 dev tun0
ip link set tun0 up
```

Then `ping`:

```shell
ping 192.168.111.2
ping fd00::2
```

## macOS

> Only `tun` is supported on macOS.

Start the sample program.

```shell
sudo swift run -c release sample-taptunping \
    --type tun \
    --dev-name utun11 \
    --ipmask=192.168.111.2/24,fd00::2/120 \
    --net-type=stack
```

Run the following shell script to initialize the device:

```shell
/usr/bin/sudo /sbin/ifconfig utun11 inet 192.168.111.1 255.255.255.0 192.168.111.2
/usr/bin/sudo /sbin/ifconfig utun11 inet6 fd00::1/120
```

Then `ping`:

```shell
ping 192.168.111.2
ping6 fd00::2
```
