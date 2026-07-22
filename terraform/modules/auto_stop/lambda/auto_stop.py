import os

import boto3

ec2 = boto3.client("ec2")


def lambda_handler(event, context):
    tag_values = [os.environ["APP_TAG_NAME"], os.environ["NAT_TAG_NAME"]]

    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Name", "Values": tag_values},
            {"Name": "instance-state-name", "Values": ["running"]},
        ]
    )
    ids = [i["InstanceId"] for r in resp["Reservations"] for i in r["Instances"]]

    if ids:
        ec2.stop_instances(InstanceIds=ids)
        print(f"Stopped instances: {ids}")
    else:
        print("Nothing running - already stopped.")

    return {"stopped": ids}
