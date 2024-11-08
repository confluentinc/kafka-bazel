#! /usr/bin/env python3

from dataclasses import dataclass
import json
import argparse
from datetime import datetime
from typing import Dict, Any
from google.cloud import bigquery
import subprocess
import os

@dataclass
class BuildEventProtocol:
    events: list[dict[str, Any]]

    def event(self, id: str) -> dict[str, Any] | None:
        return next(filter(lambda event: id in event["id"], self.events), None)

    def started(self) -> datetime:
        return datetime.fromtimestamp(
            int(self.event("started")["started"]["startTimeMillis"]) / 1000
        )

    def finished(self) -> datetime:
        return datetime.fromtimestamp(
            int(self.event("buildFinished")["finished"]["finishTimeMillis"]) / 1000
        )

    def status(self) -> str:
        return self.event("buildFinished")["finished"]["exitCode"]["name"]

    def num_targets(self) -> int:
        return len(
            list(filter(lambda event: "targetCompleted" in event["id"], self.events))
        )

    @staticmethod
    def from_json(value: str) -> "BuildEventProtocol":
        events = [json.loads(line) for line in value.strip().splitlines()]
        return BuildEventProtocol(events)


def parse_bazel_bep_from_json(bep: BuildEventProtocol) -> Dict[str, Any]:
    return {
        "build_status": bep.status(),
        "num_targets": bep.num_targets(),
        "start_time": bep.started(),
        "end_time": bep.finished(),
        "build_duration": (bep.finished() - bep.started()).total_seconds(),
    }

def get_current_commit() -> str:
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()
    return commit

def get_current_ref() -> str:
    if "SEMAPHORE_GIT_WORKING_BRANCH" in os.environ:
        return os.environ["SEMAPHORE_GIT_WORKING_BRANCH"]
    ref = subprocess.check_output(["git", "symbolic-ref", "--short", "HEAD"]).decode().strip()
    return ref

def get_third_party_kafka_commit() -> str:
    commit = subprocess.check_output(["git", "rev-parse", "HEAD:third_party/kafka"]).decode().strip()
    return commit

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse Bazel Build Event Protocol JSON and extract build metrics."
    )
    parser.add_argument(
        "bep_json_file",
        type=argparse.FileType("r"),
        help="Path to the JSON file containing BEP output.",
    )
    args = parser.parse_args()

    json_content = args.bep_json_file.read()
    bep = BuildEventProtocol.from_json(json_content)
    
    # Initialize BigQuery client
    client = bigquery.Client()
    row = {
        "confluent_commit": get_current_commit(),
        "confluent_commit_ref": get_current_ref(),
        "kafka_commit": get_third_party_kafka_commit(),
        "status": bep.status(),
        "targets": bep.num_targets(),
        "start_time": bep.started().timestamp(),
        "end_time": bep.finished().timestamp(),
    }

    print(row)
    
    # do the insert
    errors = client.insert_rows_json("cc-devel.fzakaria_playground.kafka_bazel_overlay", [row])

    print(errors)

if __name__ == "__main__":
    main()
