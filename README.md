# Apache Kafka Bazel Overlay

> If you want to understand more of how this technically works read [this blog post](https://fzakaria.com/2024/08/29/bazel-overlay-pattern.html).

This repo contains standalone Bazel BUILD configuration for part of the Apache Kafka project that could be shared by dependent projects using the Bazel build system.

This project is heavily inspired from [llvm-bazel](https://github.com/google/llvm-bazel) to bring [Bazel](https://bazel.build) build system to [Apache Kafka](https://kafka.apache.org/).

## How do I use it?

Start off by `git clone --recurse-submodules https://github.com/confluentinc/kafka-bazel`

This includes by default a git-submodule of Apache Kafka (third_party/kafka) that will track the latest on trunk; it can be changed to point to your local repository.

Build ⚒️. Profit. 💰

```console
> bazel build @kafka//...
INFO: Invocation ID: b97ba747-5d25-449b-bc20-757c5a89bbc9
INFO: Analyzed 4333 targets (102 packages loaded, 12244 targets configured).
INFO: Found 4333 targets...
INFO: Elapsed time: 16.142s, Critical Path: 13.12s
INFO: 2 processes: 1 internal, 1 worker.
INFO: Build completed successfully, 2 total actions
```

☝️ All the build targets will start with `@kafka//`.

## Status

* All build targets are buildable `@kafka//...` but not all test targets are passing as of yet.
* A minor [patch file](./apache_kafka.patch) must be applied to the Apache Kafka repository.