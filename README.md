![logo](https://gitflic.ru/project/0mega3/prime/blob/raw?file=doc/logo/primelogo.png)

# Prime

An OTP application.
The prime server is implemented as a gen_server.

The server works like this:

- When starting up, the prime_server initializes and waits for requests.
- Users call us using gen_server:call (sync) or gen_server:cast (async)
that sends a request to generate uniformly distributed pseudorandom
numbers(PRNs) according to the uniform distribution function.
In addition, PRNs are generated at a frequency of 3000 numbers per second
(by default) and are queued in Redis (List data structure).

```math
F(x) = x, 2 =< x =< N
where
    N is the upper limit of PRNs
```

- As soon as the generator is started, the filter starts taking PRNs
from the queue, checking that numbers is prime and adding prime numbers
in Redis (Set data structure).

Parameters:

- N is the upper limit of pseudorandom numbers (aka PrnUpperLimit);
- RedisHost, RedisPort, RedisDB are connection parameters to Redis;
- QueueKey is the queue key used by the generator in Redis;
- ResultSetKey is the set key used by the filter in Redis.

# Prerequisites

The installation of prerequisites for [ArchLinux](https://archlinux.org/) is
shown.

- [Erlang/OTP](https://github.com/erlang/otp):

    ```console
    sudo pacman -S erlang
    ```

- [Rebar3 build tool](https://github.com/erlang/rebar3):

    ```console
    yay -S rebar3
    ```

- [Redis db](https://github.com/redis/redis):

    ```console
    sudo pacman -S redis
    ```

---

## Build

- If needed, remove the `_build` directory to remove all compilation
artifacts

    ```console
    cd /target/prime
    rm -rf _build
    ```

- Update the package index

    ```console
    rebar3 update
    ```

- Upgrade dependencies

    ```console
    rebar3 upgrade --all
    ```

- Compile the needed dependencies and the project’s apps’ `.app.src`
and `.erl` files

    ```console
    rebar3 compile
    ```

- If needed, build release tarball. Tarball target directory
`_build/prod/rel/prime/prime-0.1.0.tar.gz`

    ```console
    rebar3 as prod tar
    ```

---

## Usage

- Start Redis in the background by running

    ```console
    redis-server &
    ```

- Start an interactive shell and use Prime API

    For development use only

    ```console
    rebar3 shell
    ```

    For production use

    ```console
    mkdir prime
    mv prime-0.1.0.tar.gz prime/
    cd prime
    tar -zxvf prime-0.1.0.tar.gz
    bin/prime console
    ```

### Prime API

```erlang
{ok, Prime} = prime:start_link().
prime:generate(Prime).
prime:cancel(Prime).
prime:get_res(Prime).
prime:stop(Prime).
```

# Testing

The Redis Server should be started.

Run EUnit tests on project apps

```console
rebar3 eunit
```

## License

Prime was created by Denis Khorkin. It is licensed under the terms
of the BSD-3-Clause license.

## Credits

- Denis Khorkin
